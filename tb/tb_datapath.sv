`timescale 1ns/1ps

module tb_datapath;
    logic clk = 0;
    logic reset = 0, mac_en = 0, load_bias = 0;
    logic signed [15:0] activation = 0;
    logic [7:0][7:0] weights = 0;
    logic [7:0][31:0] biases = 0;
    logic [2:0] lane_sel = 0;
    logic [4:0] shift = 0;
    logic relu_en = 0;
    logic signed [15:0] y;

    int signed expected_acc [0:7];
    int n_cycles = 0, n_reads = 0;

    datapath dut (.*);

    task automatic check_lanes();
        int signed expected_y;
        for (int lane = 0; lane < 8; lane++) begin
            lane_sel = 3'(lane);
            #1;
            expected_y = expected_acc[lane] >>> shift;
            if (expected_y > 32767) expected_y = 32767;
            if (expected_y < -32768) expected_y = -32768;
            if (relu_en && expected_y < 0) expected_y = 0;
            if (dut.accumulators[lane] !== expected_acc[lane])
                $fatal(1, "Cycle %0d lane %0d: acc=%0d expected=%0d",
                       n_cycles, lane, dut.accumulators[lane], expected_acc[lane]);
            if (y !== 16'(expected_y))
                $fatal(1, "Cycle %0d lane %0d shift=%0d relu=%b: y=%0d expected=%0d",
                       n_cycles, lane, shift, relu_en, y, expected_y);
            n_reads++;
        end
    endtask

    task automatic tick();
        longint signed product, sum;
        clk = 0;
        #5;
        for (int lane = 0; lane < 8; lane++) begin
            if (reset) expected_acc[lane] = 0;
            else if (mac_en) begin
                product = longint'(activation) * longint'($signed(weights[lane]));
                sum = (load_bias ? longint'($signed(biases[lane])) : longint'(expected_acc[lane])) + product;
                expected_acc[lane] = int'(sum);
            end
        end
        clk = 1;
        #1;
        n_cycles++;
        check_lanes();
        clk = 0;
        #4;
    endtask

    initial begin
        reset = 1;
        mac_en = 1;
        load_bias = 1;
        tick();
        reset = 0;
        activation = -13;
        for (int lane = 0; lane < 8; lane++) begin
            weights[lane] = 8'(lane-4);
            biases[lane] = 32'(100*lane-300);
        end
        tick();
        load_bias = 0;
        activation = 17;
        tick();
        mac_en = 0;
        load_bias = 1;
        activation = -32768;
        weights = '1;
        biases = '1;
        tick();
        $display("PASS: unique lane wiring, bias plus first product, accumulation, reset priority, and disabled hold");

        mac_en = 1;
        load_bias = 1;
        weights = 0;
        biases[0] = 32'sd32767;
        biases[1] = 32'sd32768;
        biases[2] = -32'sd32768;
        biases[3] = -32'sd32769;
        biases[4] = -32'sd3;
        biases[5] = 32'sh7fffffff;
        biases[6] = 32'sh80000000;
        biases[7] = 32'sd65535;
        tick();
        mac_en = 0;
        for (int relu = 0; relu < 2; relu++) begin
            relu_en = 1'(relu);
            for (int shift_value = 0; shift_value < 32; shift_value++) begin
                shift = 5'(shift_value);
                check_lanes();
            end
        end
        $display("PASS: all shifts, signed negative shifts, saturation boundaries, ReLU, and combinational lane selection");

        mac_en = 1;
        load_bias = 1;
        activation = 32767;
        weights = {8{8'h7f}};
        biases = {8{32'h7fffffff}};
        tick();
        activation = -32768;
        weights = {8{8'h7f}};
        biases = {8{32'h80000000}};
        tick();
        $display("PASS: positive and negative accumulator wraparound");

        repeat (1000) begin
            reset = $urandom_range(0, 99) == 0;
            mac_en = $urandom_range(0, 4) != 0;
            load_bias = $urandom_range(0, 3) == 0;
            activation = 16'($urandom);
            shift = 5'($urandom);
            relu_en = 1'($urandom);
            for (int lane = 0; lane < 8; lane++) begin
                weights[lane] = 8'($urandom);
                biases[lane] = $urandom;
            end
            tick();
        end
        $display("PASS: %0d clock checks and %0d lane/readout checks", n_cycles, n_reads);
        $finish;
    end
endmodule
