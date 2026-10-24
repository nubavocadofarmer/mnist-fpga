`timescale 1ns/1ps

module tb_dense_controller;
    logic clk = 0;
    always #5 clk = ~clk;
    logic reset = 1, start = 0;
    logic [12:0] in_size = 0, out_size = 0;
    logic [15:0] w_base = 0, w_addr;
    logic [6:0] b_base = 0, b_addr;
    logic [12:0] act_raddr, agu_out_idx, out_waddr;
    logic agu_valid, agu_first, agu_last, agu_done;
    logic agu_start, agu_enable, mac_en, load_bias, out_we, busy, done;
    logic [2:0] lane_sel;
    logic [4:0] shift = 0;
    logic relu_en = 0;
    logic signed [15:0] activation, y;
    logic [7:0][7:0] weights;
    logic [7:0][31:0] biases;

    logic signed [15:0] activation_mem [0:8191];
    logic [7:0][7:0] weight_mem [0:65535];
    logic [7:0][31:0] bias_mem [0:127];
    int expected [0:63];
    int active_inputs = 0, active_outputs = 0, write_count = 0;
    int read_count = 0, mac_count = 0, bias_count = 0;
    int n_layers = 0, n_results = 0;
    bit checking = 0;
    logic previous_valid = 0, previous_first = 0;

    dense_controller dut (.*);
    dense_agu agu (
        .clk(clk), .rst(reset), .start(agu_start), .enable(agu_enable),
        .in_size(in_size), .out_size(out_size), .w_base(w_base), .b_base(b_base),
        .act_raddr(act_raddr), .w_addr(w_addr), .b_addr(b_addr),
        .out_idx(agu_out_idx), .valid(agu_valid), .first(agu_first),
        .last(agu_last), .done(agu_done)
    );
    datapath data_dut (.*);

    // One-cycle synchronous reads match the activation buffer and parameter ROMs.
    always_ff @(posedge clk) begin
        activation <= activation_mem[act_raddr];
        weights <= weight_mem[w_addr];
        biases <= bias_mem[b_addr];
    end

    always @(posedge clk) begin
        if (reset) begin
            previous_valid = 0;
            previous_first = 0;
        end
        else if (checking) begin
            if (active_inputs == 0 && agu_start) $fatal(1, "Empty layer started the AGU");
            if (mac_en !== previous_valid || load_bias !== (previous_valid && previous_first))
                $fatal(1, "MAC controls are not aligned with memory responses");
            if (agu_valid && agu_enable) read_count++;
            if (mac_en) mac_count++;
            if (load_bias) bias_count++;
            if (out_we) begin
                if (agu_enable || mac_en) $fatal(1, "Compute advanced while serializing outputs");
                if (int'(out_waddr) != write_count || int'(out_waddr) >= active_outputs)
                    $fatal(1, "Output address %0d expected %0d of %0d", out_waddr, write_count, active_outputs);
                if (int'(lane_sel) != write_count%8) $fatal(1, "Incorrect lane selection");
                if (y !== 16'(expected[write_count]))
                    $fatal(1, "Inputs=%0d neuron=%0d result=%0d expected=%0d",
                           active_inputs, write_count, y, expected[write_count]);
                write_count++;
                n_results++;
            end
            if (done && write_count != active_outputs) $fatal(1, "Done asserted before final output write");
            previous_valid = agu_valid && agu_enable;
            previous_first = agu_first;
        end
    end

    task automatic run_layer(int inputs, int outputs, int shift_value, bit use_relu);
        int groups, value, sum, clocks;
        @(negedge clk);
        checking = 0;
        groups = inputs == 0 ? 0 : (outputs+7)/8;
        for (int i = 0; i < inputs; i++) activation_mem[i] = 16'((i*11)%31-15);
        for (int group_idx = 0; group_idx < groups; group_idx++) begin
            for (int lane = 0; lane < 8; lane++)
                bias_mem[group_idx][lane] = 32'((group_idx*8+lane)*137-500);
            for (int i = 0; i < inputs; i++)
                for (int lane = 0; lane < 8; lane++)
                    weight_mem[group_idx*inputs+i][lane] = 8'(((group_idx*8+lane)*7+i*3)%17-8);
        end
        for (int neuron = 0; neuron < outputs; neuron++) begin
            sum = neuron*137-500;
            for (int i = 0; i < inputs; i++) begin
                value = (neuron*7+i*3)%17-8;
                sum += int'(activation_mem[i])*value;
            end
            sum = sum >>> shift_value;
            if (sum > 32767) sum = 32767;
            if (sum < -32768) sum = -32768;
            if (use_relu && sum < 0) sum = 0;
            expected[neuron] = sum;
        end
        active_inputs = inputs;
        active_outputs = inputs == 0 ? 0 : outputs;
        write_count = 0; read_count = 0; mac_count = 0; bias_count = 0;
        previous_valid = 0; previous_first = 0;
        in_size = 13'(inputs);
        out_size = 13'(outputs);
        shift = 5'(shift_value);
        relu_en = use_relu;
        checking = 1;
        start = 1;
        @(negedge clk);
        start = 0;
        // The controller and AGU must use their latched layer size.
        out_size = 8191;
        clocks = 0;
        while (!done && clocks < 10000) begin
            @(negedge clk);
            clocks++;
        end
        if (!done) $fatal(1, "Layer timed out: inputs=%0d outputs=%0d", inputs, outputs);
        if (write_count != active_outputs || read_count != groups*inputs ||
            mac_count != groups*inputs || bias_count != groups)
            $fatal(1, "Wrong layer counts: writes=%0d reads=%0d MACs=%0d biases=%0d",
                       write_count, read_count, mac_count, bias_count);
        @(negedge clk);
        if (done || busy) $fatal(1, "Done did not pulse or controller did not return idle");
        checking = 0;
        n_layers++;
    endtask

    initial begin
        repeat (2) @(negedge clk);
        reset = 0;
        run_layer(3, 10, 0, 0);
        run_layer(1, 1, 0, 0);
        run_layer(1, 8, 0, 1);
        run_layer(1, 9, 1, 0);
        run_layer(2, 7, 2, 1);
        run_layer(784, 64, 0, 1);
        run_layer(64, 10, 7, 0);
        run_layer(3, 0, 0, 0);
        for (int inputs = 1; inputs <= 7; inputs++)
            for (int outputs = 1; outputs <= 17; outputs++)
                run_layer(inputs, outputs, outputs%5, 1'(outputs));
        $display("PASS: %0d layers and %0d output writes with synchronous memories, paused AGU, and datapath", n_layers, n_results);

        // Empty layers complete without consuming operands or writing stale sums.
        run_layer(0, 10, 0, 0);
        run_layer(0, 64, 7, 1);
        run_layer(0, 0, 0, 0);
        run_layer(3, 10, 0, 0);
        $display("PASS: zero-input layers complete without reads, MACs, or writes, then a normal layer runs");
        @(negedge clk);
        reset = 1;
        @(negedge clk);
        reset = 0;
        run_layer(3, 10, 0, 0);
        $display("PASS: reset and subsequent layer completion");
        $finish;
    end
endmodule
