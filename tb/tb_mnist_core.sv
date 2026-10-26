`timescale 1ns/1ps

module tb_mnist_core #(
    parameter int N_IMAGES = 10,
    parameter string VECTOR_DIR = "mem/vectors/10"
);
    logic clk = 0;
    always #5 clk = ~clk;
    logic reset = 1, start = 0, image_we = 0;
    logic [9:0] image_waddr = 0;
    logic signed [15:0] image_wdata = 0;
    logic image_ready, busy, done;
    logic [3:0] digit;
    logic signed [15:0] max_score;

    logic [15:0] images [0:N_IMAGES*784-1];
    logic [15:0] hidden [0:N_IMAGES*64-1];
    logic [15:0] scores [0:N_IMAGES*10-1];
    logic [7:0] digits [0:N_IMAGES-1];
    int image_idx = 0, hidden_count = 0, score_count = 0;
    int n_predictions = 0, n_values = 0, last_latency = 0;
    bit checking = 0;

    mnist_core dut (.*);

    always @(posedge clk) begin
        if (!reset && checking && dut.dense_we) begin
            if (!busy || image_ready) $fatal(1, "Invalid controls during computation");
            if (dut.layer_two) begin
                if (score_count >= 10 || int'(dut.dense_waddr) != score_count ||
                    !dut.a_we || dut.b_we)
                    $fatal(1, "Invalid score write or buffer selection");
                if (dut.dense_wdata !== $signed(scores[image_idx*10+score_count]))
                    $fatal(1, "Image %0d score[%0d]=%0d expected=%0d", image_idx,
                           score_count, dut.dense_wdata, $signed(scores[image_idx*10+score_count]));
                score_count++;
            end
            else begin
                if (hidden_count >= 64 || int'(dut.dense_waddr) != hidden_count ||
                    !dut.b_we || dut.a_we)
                    $fatal(1, "Invalid hidden write or buffer selection");
                if (dut.dense_wdata !== $signed(hidden[image_idx*64+hidden_count]))
                    $fatal(1, "Image %0d hidden[%0d]=%0d expected=%0d", image_idx,
                           hidden_count, dut.dense_wdata, $signed(hidden[image_idx*64+hidden_count]));
                hidden_count++;
            end
            n_values++;
        end
    end

    task automatic load_image();
        @(negedge clk);
        if (!image_ready || busy || done) $fatal(1, "Core not ready for image");
        image_we = 1;
        for (int pixel = 0; pixel < 784; pixel++) begin
            image_waddr = 10'(pixel);
            image_wdata = $signed(images[image_idx*784+pixel]);
            @(negedge clk);
        end
        image_we = 0;
        // An out-of-range host address must not write the image buffer.
        image_we = 1;
        image_waddr = 10'd1023;
        #1;
        if (dut.a_we) $fatal(1, "Accepted an out-of-range image address");
        @(negedge clk);
        image_we = 0;
    endtask

    task automatic run_prediction(bit overlap_last_pixel = 0);
        int clocks, expected_score;
        logic [3:0] old_digit;
        logic signed [15:0] old_score;
        hidden_count = 0;
        score_count = 0;
        checking = 1;
        old_digit = digit;
        old_score = max_score;
        expected_score = int'($signed(scores[image_idx*10]));
        for (int i = 1; i < 10; i++) begin
            if (int'($signed(scores[image_idx*10+i])) > expected_score)
                expected_score = int'($signed(scores[image_idx*10+i]));
        end

        @(negedge clk);
        if (overlap_last_pixel) begin
            image_we = 1;
            image_waddr = 10'd783;
            image_wdata = ~$signed(images[image_idx*784+783]);
            @(negedge clk);
        end
        start = 1;
        if (overlap_last_pixel) begin
            image_we = 1;
            image_waddr = 10'd783;
            image_wdata = $signed(images[image_idx*784+783]);
        end
        @(negedge clk);
        start = 0;
        clocks = 0;
        while (!done && clocks < 10000) begin
            if (!busy || image_ready) $fatal(1, "Core became idle before completion");
            if (digit !== old_digit || max_score !== old_score)
                $fatal(1, "Published result changed before done");
            // Busy starts and host writes must not disturb either layer or argmax.
            start = clocks == 20 || clocks == 6360 || dut.argmax_start;
            image_we = 1;
            image_waddr = 0;
            image_wdata = 16'sh8000;
            @(negedge clk);
            clocks++;
        end
        image_we = 0;
        start = 0;
        if (!done || busy || image_ready || hidden_count != 64 || score_count != 10)
            $fatal(1, "Incomplete inference: hidden=%0d scores=%0d clocks=%0d", hidden_count, score_count, clocks);
        if (digit !== digits[image_idx][3:0] || int'(max_score) != expected_score)
            $fatal(1, "Image %0d: digit=%0d score=%0d expected digit=%0d score=%0d",
                   image_idx, digit, max_score, digits[image_idx], expected_score);
        if (last_latency != 0 && clocks != last_latency)
            $fatal(1, "Inference latency changed from %0d to %0d", last_latency, clocks);
        last_latency = clocks;
        n_predictions++;
        checking = 0;
        repeat (3) begin
            @(negedge clk);
            if (done || busy || !image_ready || digit !== digits[image_idx][3:0] ||
                int'(max_score) != expected_score)
                $fatal(1, "Completion pulse or held result incorrect");
        end
    endtask

    task automatic check_reset();
        reset = 1;
        image_we = 1;
        start = 1;
        @(negedge clk);
        if (busy || done || image_ready || digit !== 0 || max_score !== 0 || dut.a_we || dut.b_we)
            $fatal(1, "Reset did not clear outputs and suppress writes");
        reset = 0;
        start = 0;
        image_we = 0;
        @(negedge clk);
        if (!image_ready || busy || done) $fatal(1, "Reset did not return core to idle");
    endtask

    initial begin
        $readmemh({VECTOR_DIR, "/images.mem"}, images);
        $readmemh({VECTOR_DIR, "/hidden.mem"}, hidden);
        $readmemh({VECTOR_DIR, "/scores.mem"}, scores);
        $readmemh({VECTOR_DIR, "/expected_digits.mem"}, digits);
        repeat (2) @(negedge clk);
        check_reset();
        for (image_idx = 0; image_idx < N_IMAGES; image_idx++) begin
            load_image();
            run_prediction(image_idx == 0);
        end
        $display("PASS: %0d complete predictions, %0d golden hidden/score values, %0d inference clocks",
                 n_predictions, n_values, last_latency);

        image_idx = 0;
        for (int stage = 0; stage < 3; stage++) begin
            load_image();
            start = 1;
            @(negedge clk);
            start = 0;
            if (stage == 0) repeat (20) @(negedge clk);
            if (stage == 1) begin
                wait (dut.layer_two && dut.dense_start);
                repeat (10) @(negedge clk);
            end
            if (stage == 2) begin
                wait (dut.argmax_start);
                repeat (5) @(negedge clk);
            end
            check_reset();
            load_image();
            run_prediction();
        end
        $display("PASS: reset during either layer and argmax; %0d completed predictions total", n_predictions);
        $display("PASS: busy requests ignored, image address bounds, last-pixel/start overlap, held results, one-cycle done");
        $finish;
    end

    initial begin
        #(100000 * (N_IMAGES + 10));
        $fatal(1, "MNIST core test timed out");
    end
endmodule
