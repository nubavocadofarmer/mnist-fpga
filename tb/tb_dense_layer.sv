`timescale 1ns/1ps

module tb_dense_layer;
    logic clk = 0;
    always #5 clk = ~clk;
    logic reset = 1, start = 0;
    logic [12:0] in_size = 0, out_size = 0;
    logic [15:0] w_base = 0;
    logic [6:0] b_base = 0;
    logic [4:0] shift = 0;
    logic relu_en = 0;
    logic [12:0] act_raddr, out_waddr;
    logic signed [15:0] act_rdata, out_wdata;
    logic out_we, busy, done;

    logic source_b = 0, loading = 0;
    logic [12:0] load_addr = 0;
    logic signed [15:0] load_data = 0;
    logic a_we, b_we;
    logic [12:0] a_waddr;
    logic signed [15:0] a_wdata, a_rdata, b_rdata;

    logic [15:0] image_vectors [0:7839];
    logic [15:0] hidden_vectors [0:639];
    logic [15:0] score_vectors [0:99];
    logic [7:0] digit_vectors [0:9];
    int image_idx = 0, write_count = 0, expected_outputs = 0;
    int n_layers = 0, n_values = 0, n_digits = 0;
    int best_digit = 0, best_score = -32768;
    bit checking = 0;

    dense_layer dut (.*);

    assign act_rdata = source_b ? b_rdata : a_rdata;
    assign a_we = loading || (source_b && out_we);
    assign a_waddr = loading ? load_addr : out_waddr;
    assign a_wdata = loading ? load_data : out_wdata;
    assign b_we = !source_b && out_we;

    act_buf buffer_a (
        .clk(clk), .we(a_we), .waddr(a_waddr), .wdata(a_wdata),
        .raddr(act_raddr), .rdata(a_rdata)
    );
    act_buf buffer_b (
        .clk(clk), .we(b_we), .waddr(out_waddr), .wdata(out_wdata),
        .raddr(act_raddr), .rdata(b_rdata)
    );

    always @(posedge clk) begin
        if (!reset && out_we) begin
            if (!checking || loading || !busy) $fatal(1, "Unexpected destination write");
            if (int'(out_waddr) != write_count || write_count >= expected_outputs)
                $fatal(1, "Image %0d: invalid destination address %0d", image_idx, out_waddr);
            if (!source_b && out_wdata !== $signed(hidden_vectors[image_idx*64+write_count]))
                $fatal(1, "Image %0d hidden[%0d]=%0d expected=%0d", image_idx, write_count,
                       out_wdata, $signed(hidden_vectors[image_idx*64+write_count]));
            if (source_b && out_wdata !== $signed(score_vectors[image_idx*10+write_count]))
                $fatal(1, "Image %0d score[%0d]=%0d expected=%0d", image_idx, write_count,
                       out_wdata, $signed(score_vectors[image_idx*10+write_count]));
            if (source_b && (write_count == 0 || int'(out_wdata) > best_score)) begin
                best_score = int'(out_wdata);
                best_digit = write_count;
            end
            write_count++;
            n_values++;
        end
    end

    task automatic run_layer(bit second_layer);
        int clocks;
        @(negedge clk);
        source_b = second_layer;
        in_size = second_layer ? 13'd64 : 13'd784;
        out_size = second_layer ? 13'd10 : 13'd64;
        w_base = second_layer ? 16'd6272 : 16'd0;
        b_base = second_layer ? 7'd8 : 7'd0;
        shift = second_layer ? 5'd7 : 5'd0;
        relu_en = !second_layer;
        expected_outputs = int'(out_size);
        write_count = 0;
        best_score = -32768;
        best_digit = 0;
        checking = 1;
        start = 1;
        @(negedge clk);
        start = 0;
        // Requantization controls must remain latched throughout the layer.
        shift = 31;
        relu_en = second_layer;
        clocks = 0;
        while (!done && clocks < 10000) begin
            @(negedge clk);
            clocks++;
        end
        if (!done || write_count != expected_outputs)
            $fatal(1, "Layer incomplete: done=%b writes=%0d expected=%0d", done, write_count, expected_outputs);
        if (second_layer) begin
            if (best_digit != int'(digit_vectors[image_idx]))
                $fatal(1, "Image %0d: predicted=%0d expected=%0d", image_idx, best_digit, digit_vectors[image_idx]);
            n_digits++;
        end
        @(negedge clk);
        if (done || busy) $fatal(1, "Layer completion did not return idle");
        checking = 0;
        n_layers++;
    endtask

    initial begin
        $readmemh("mem/vectors/10/images.mem", image_vectors);
        $readmemh("mem/vectors/10/hidden.mem", hidden_vectors);
        $readmemh("mem/vectors/10/scores.mem", score_vectors);
        $readmemh("mem/vectors/10/expected_digits.mem", digit_vectors);
        repeat (2) @(negedge clk);
        reset = 0;
        for (image_idx = 0; image_idx < 10; image_idx++) begin
            @(negedge clk);
            loading = 1;
            source_b = 0;
            for (int pixel = 0; pixel < 784; pixel++) begin
                load_addr = 13'(pixel);
                load_data = $signed(image_vectors[image_idx*784+pixel]);
                @(negedge clk);
            end
            loading = 0;
            run_layer(0);
            run_layer(1);
        end
        $display("PASS: %0d real-weight dense layers, %0d golden output values, %0d predicted digits", n_layers, n_values, n_digits);

        // Empty inputs must finish without writing old accumulator values.
        @(negedge clk);
        in_size = 0;
        out_size = 10;
        start = 1;
        @(negedge clk);
        start = 0;
        if (!done || out_we) $fatal(1, "Zero-input layer did not complete without writes");
        @(negedge clk);
        if (done || busy) $fatal(1, "Empty layer did not return idle");
        $display("PASS: latched requantization controls, ping-pong buffers, final partial group, and zero-input completion");
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "Dense-layer test timed out");
    end
endmodule
