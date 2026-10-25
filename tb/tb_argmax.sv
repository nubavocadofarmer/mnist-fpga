`timescale 1ns/1ps

module tb_argmax;
    logic clk = 0;
    always #5 clk = ~clk;
    logic reset = 1, start = 0;
    logic [12:0] act_raddr;
    logic signed [15:0] act_rdata, max_score;
    logic [3:0] digit;
    logic busy, done;
    logic we = 0;
    logic [12:0] waddr = 0;
    logic signed [15:0] wdata = 0;

    logic signed [15:0] scores [0:9];
    logic [15:0] golden_scores [0:99];
    logic [7:0] golden_digits [0:9];
    int n_cases = 0;

    argmax dut (.*);
    act_buf buffer (
        .clk(clk), .we(we), .waddr(waddr), .wdata(wdata),
        .raddr(act_raddr), .rdata(act_rdata)
    );

    task automatic load_scores();
        @(negedge clk);
        we = 1;
        for (int i = 0; i < 10; i++) begin
            waddr = 13'(i);
            wdata = scores[i];
            @(negedge clk);
        end
        we = 0;
    endtask

    task automatic check_scan(bit extra_start = 0);
        int expected_digit, expected_score, clocks;
        expected_digit = 0;
        expected_score = int'(scores[0]);
        for (int i = 1; i < 10; i++) begin
            if (int'(scores[i]) > expected_score) begin
                expected_score = int'(scores[i]);
                expected_digit = i;
            end
        end

        @(negedge clk);
        start = 1;
        @(negedge clk);
        start = 0;
        if (!busy || done) $fatal(1, "Start did not begin a scan");
        clocks = 0;
        while (!done && clocks < 30) begin
            if (!busy || act_raddr > 13'd9) $fatal(1, "Invalid scan controls");
            start = extra_start && clocks == 4;
            @(negedge clk);
            clocks++;
        end
        start = 0;
        if (!done || busy || clocks != 20)
            $fatal(1, "Completion timing mismatch: done=%b busy=%b clocks=%0d", done, busy, clocks);
        if (int'(digit) != expected_digit || int'(max_score) != expected_score)
            $fatal(1, "Case %0d: digit=%0d score=%0d expected digit=%0d score=%0d",
                   n_cases, digit, max_score, expected_digit, expected_score);
        repeat (3) begin
            @(negedge clk);
            if (done || busy || int'(digit) != expected_digit || int'(max_score) != expected_score)
                $fatal(1, "Result was not held or done was not a one-cycle pulse");
        end
        n_cases++;
    endtask

    initial begin
        $readmemh("mem/vectors/10/scores.mem", golden_scores);
        $readmemh("mem/vectors/10/expected_digits.mem", golden_digits);
        repeat (2) @(negedge clk);
        reset = 0;
        if (busy || done || digit !== 0 || max_score !== 0 || act_raddr !== 0)
            $fatal(1, "Reset outputs incorrect");

        for (int winner = 0; winner < 10; winner++) begin
            for (int i = 0; i < 10; i++) scores[i] = -16'sd100;
            scores[winner] = -16'sd1;
            load_scores();
            check_scan();
        end
        for (int i = 0; i < 10; i++) scores[i] = 16'sh8000;
        load_scores();
        check_scan();
        for (int i = 0; i < 10; i++) scores[i] = 0;
        load_scores();
        check_scan();
        for (int i = 0; i < 10; i++) scores[i] = 16'sh8000;
        scores[3] = 16'sh7fff;
        scores[8] = 16'sh7fff;
        load_scores();
        check_scan(1);
        if (digit !== 4'd3) $fatal(1, "Tie did not keep the lower index");
        $display("PASS: all ten winning positions, negative scores, INT16 limits, ties, and ignored busy start");

        for (int image = 0; image < 10; image++) begin
            for (int i = 0; i < 10; i++) scores[i] = $signed(golden_scores[image*10+i]);
            load_scores();
            check_scan();
            if (digit !== golden_digits[image][3:0]) $fatal(1, "Golden MNIST digit mismatch");
        end
        $display("PASS: ten MNIST score vectors match golden predicted digits");

        repeat (1000) begin
            for (int i = 0; i < 10; i++) scores[i] = 16'($urandom);
            load_scores();
            check_scan();
        end

        // Abort a scan, then confirm a new scan can complete.
        @(negedge clk);
        start = 1;
        @(negedge clk);
        start = 0;
        repeat (4) @(negedge clk);
        reset = 1;
        @(negedge clk);
        if (busy || done || digit !== 0 || max_score !== 0 || act_raddr !== 0)
            $fatal(1, "Reset did not abort the active scan");
        reset = 0;
        check_scan();
        $display("PASS: %0d scans including 1000 randomized vectors, reset recovery, and stable result readout", n_cases);
        $finish;
    end

    initial begin
        #1000000;
        $fatal(1, "Argmax test timed out");
    end
endmodule
