`timescale 1ns / 1ps

module tb_dense_agu;
    logic complete1, complete8;
    agu_check #(.LANES(1)) single_lane(.complete(complete1));
    agu_check #(.LANES(8)) eight_lanes(.complete(complete8));
    initial begin
        wait (complete1 && complete8);
        $display("PASS: dense AGU with one and eight lanes, including pause/resume");
        $finish;
    end
    initial begin
        #2000000;
        $fatal(1, "AGU test timed out");
    end
endmodule

module agu_check #(parameter int LANES = 8)(output logic complete = 0);
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst = 1, start = 0, enable = 1;
    logic [12:0] in_size = 0, out_size = 0, act_raddr, out_idx;
    logic [15:0] w_base = 0, w_addr;
    logic [6:0] b_base = 0, b_addr;
    logic valid, first, last, done;
    int checked_steps = 0, paused_clocks = 0;
    dense_agu #(.LANES(LANES)) dut(.*);

    task automatic pause_current();
        logic [12:0] saved_act, saved_out;
        logic [15:0] saved_weight;
        logic [6:0] saved_bias;
        saved_act = act_raddr;
        saved_out = out_idx;
        saved_weight = w_addr;
        saved_bias = b_addr;
        enable = 0;
        #1;
        if (valid !== 0 || first !== 0 || last !== 0)
            $fatal(1, "LANES=%0d: paused step indicators are not zero", LANES);
        repeat (3) begin
            @(negedge clk);
            if (act_raddr !== saved_act || out_idx !== saved_out || w_addr !== saved_weight ||
                b_addr !== saved_bias || valid !== 0 || first !== 0 || last !== 0 || done !== 0)
                $fatal(1, "LANES=%0d: address or control changed during pause", LANES);
            paused_clocks++;
        end
        enable = 1;
        #1;
    endtask

    task automatic run_layer(int ins, int outs, int wb, int bb, bit pauses = 0);
        int steps, groups;
        @(negedge clk);
        in_size = 13'(ins);
        out_size = 13'(outs);
        w_base = 16'(wb);
        b_base = 7'(bb);
        start = 1;
        @(negedge clk);
        start = 0;
        groups = (outs + LANES - 1) / LANES;
        steps = 0;
        for (int group_idx = 0; group_idx < groups; group_idx++) begin
            for (int input_idx = 0; input_idx < ins; input_idx++) begin
                if (pauses && (input_idx == 0 || input_idx == ins/2 || input_idx == ins-1))
                    pause_current();
                if (valid !== 1 || int'(act_raddr) != input_idx || int'(out_idx) != group_idx * LANES ||
                    int'(w_addr) != wb + steps || int'(b_addr) != bb + group_idx ||
                    first !== (input_idx == 0) || last !== (input_idx == ins - 1) || done !== 0)
                    $fatal(1, "LANES=%0d group=%0d input=%0d address/control mismatch", LANES, group_idx, input_idx);
                steps++;
                checked_steps++;
                @(negedge clk);
            end
        end
        if (done !== 1 || valid !== 0) $fatal(1, "Completion mismatch");
        enable = 0;
        @(negedge clk);
        if (done !== 0) $fatal(1, "Done did not clear");
        enable = 1;
    endtask

    initial begin
        repeat (2) @(negedge clk);
        rst = 0;
        if (valid !== 0 || first !== 0 || last !== 0 || w_addr !== 0 || b_addr !== 0)
            $fatal(1, "Reset outputs incorrect");
        run_layer(784, 64, 0, 0);
        run_layer(64, 10, LANES == 8 ? 6272 : 50176, LANES == 8 ? 8 : 64);
        run_layer(3, 10, 100, 5);
        run_layer(1, 1, 23, 2);
        run_layer(1, 128, 0, 0);
        run_layer(784, 64, 0, 0, 1);
        run_layer(64, 10, LANES == 8 ? 6272 : 50176, LANES == 8 ? 8 : 64, 1);
        run_layer(3, 10, 100, 5, 1);
        run_layer(1, 1, 23, 2, 1);
        run_layer(0, 10, 0, 0);
        run_layer(3, 0, 0, 0);

        // Start takes priority over enable, but paused requests remain invalid.
        @(negedge clk);
        enable = 0;
        in_size = 3;
        out_size = 9;
        w_base = 20;
        b_base = 2;
        start = 1;
        @(negedge clk);
        start = 0;
        #1;
        if (valid !== 0 || first !== 0 || last !== 0 || done !== 0 ||
            act_raddr !== 0 || out_idx !== 0 || w_addr !== 20 || b_addr !== 2)
            $fatal(1, "Start while paused failed");
        pause_current();
        if (valid !== 1 || first !== 1 || act_raddr !== 0 || w_addr !== 20)
            $fatal(1, "Resume after paused start skipped the first request");

        @(negedge clk);
        enable = 0;
        rst = 1;
        @(negedge clk);
        rst = 0;
        #1;
        if (valid !== 0 || first !== 0 || last !== 0 || done !== 0 ||
            act_raddr !== 0 || out_idx !== 0 || w_addr !== 0 || b_addr !== 0)
            $fatal(1, "Reset while paused failed");
        enable = 1;
        #1;
        if (valid !== 0) $fatal(1, "Reset work unexpectedly resumed");
        run_layer(3, 10, 100, 5, 1);
        $display("PASS: LANES=%0d, %0d checked requests, %0d paused clocks", LANES, checked_steps, paused_clocks);
        complete = 1;
    end
endmodule
