`timescale 1ns/1ps

module mnist_core #(
    parameter string WEIGHT_FILE = "mem/weights_x8.mem",
    parameter string BIAS_FILE = "mem/biases_x8.mem"
)(
    input  logic               clk,
    input  logic               reset,
    input  logic               image_we,
    input  logic [9:0]         image_waddr,
    input  logic signed [15:0] image_wdata,
    output logic               image_ready,
    input  logic               start,
    output logic               busy,
    output logic               done,
    output logic [3:0]         digit,
    output logic signed [15:0] max_score
);
    typedef enum logic [2:0] {
        IDLE,
        START_L1,
        RUN_L1,
        START_L2,
        RUN_L2,
        START_ARGMAX,
        RUN_ARGMAX,
        DONE
    } state_t;

    state_t state, next_state;

    logic layer_two, dense_start, dense_done;
    logic unused_dense_busy;
    logic [12:0] in_size, out_size;
    logic [15:0] w_base;
    logic [6:0] b_base;
    logic [4:0] shift;
    logic relu_en;
    logic [12:0] dense_raddr, dense_waddr;
    logic signed [15:0] dense_rdata, dense_wdata;
    logic dense_we;

    logic a_we, b_we;
    logic [12:0] a_waddr, a_raddr, b_raddr;
    logic signed [15:0] a_wdata, a_rdata, b_rdata;

    logic argmax_start, argmax_done;
    logic unused_argmax_busy;
    logic [12:0] argmax_raddr;
    logic [3:0] argmax_digit;
    logic signed [15:0] argmax_score;

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            digit <= '0;
            max_score <= '0;
        end
        else begin
            state <= next_state;
            if (state == RUN_ARGMAX && argmax_done) begin
                digit <= argmax_digit;
                max_score <= argmax_score;
            end
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (start) next_state = START_L1;
            end
            START_L1: next_state = RUN_L1;
            RUN_L1: begin
                if (dense_done) next_state = START_L2;
            end
            START_L2: next_state = RUN_L2;
            RUN_L2: begin
                if (dense_done) next_state = START_ARGMAX;
            end
            START_ARGMAX: next_state = RUN_ARGMAX;
            RUN_ARGMAX: begin
                if (argmax_done) next_state = DONE;
            end
            DONE: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    assign image_ready = !reset && state == IDLE;
    assign busy = !reset && state != IDLE && state != DONE;
    assign done = !reset && state == DONE;
    assign layer_two = state == START_L2 || state == RUN_L2;
    assign dense_start = !reset && (state == START_L1 || state == START_L2);
    assign argmax_start = !reset && state == START_ARGMAX;

    assign in_size = layer_two ? 13'd64 : 13'd784;
    assign out_size = layer_two ? 13'd10 : 13'd64;
    assign w_base = layer_two ? 16'd6272 : 16'd0;
    assign b_base = layer_two ? 7'd8 : 7'd0;
    assign shift = layer_two ? 5'd7 : 5'd0;
    assign relu_en = !layer_two;
    assign dense_rdata = layer_two ? b_rdata : a_rdata;

    always_comb begin
        a_we = 1'b0;
        b_we = 1'b0;
        a_waddr = dense_waddr;
        a_wdata = dense_wdata;
        a_raddr = '0;
        b_raddr = '0;

        if (state == START_L1 || state == RUN_L1)
            a_raddr = dense_raddr;
        if (layer_two)
            b_raddr = dense_raddr;
        if (state == START_ARGMAX || state == RUN_ARGMAX)
            a_raddr = argmax_raddr;

        if (!reset) begin
            if (image_ready && image_we && image_waddr < 10'd784) begin
                a_we = 1'b1;
                a_waddr = {3'b0, image_waddr};
                a_wdata = image_wdata;
            end
            else if (state == RUN_L2)
                a_we = dense_we;

            if (state == RUN_L1)
                b_we = dense_we;
        end
    end

    act_buf buffer_a (
        .clk(clk),
        .we(a_we),
        .waddr(a_waddr),
        .wdata(a_wdata),
        .raddr(a_raddr),
        .rdata(a_rdata)
    );

    act_buf buffer_b (
        .clk(clk),
        .we(b_we),
        .waddr(dense_waddr),
        .wdata(dense_wdata),
        .raddr(b_raddr),
        .rdata(b_rdata)
    );

    dense_layer #(
        .WEIGHT_FILE(WEIGHT_FILE),
        .BIAS_FILE(BIAS_FILE)
    ) u_dense (
        .clk(clk),
        .reset(reset),
        .start(dense_start),
        .in_size(in_size),
        .out_size(out_size),
        .w_base(w_base),
        .b_base(b_base),
        .shift(shift),
        .relu_en(relu_en),
        .act_raddr(dense_raddr),
        .act_rdata(dense_rdata),
        .out_we(dense_we),
        .out_waddr(dense_waddr),
        .out_wdata(dense_wdata),
        .busy(unused_dense_busy),
        .done(dense_done)
    );

    argmax u_argmax (
        .clk(clk),
        .reset(reset),
        .start(argmax_start),
        .act_raddr(argmax_raddr),
        .act_rdata(a_rdata),
        .digit(argmax_digit),
        .max_score(argmax_score),
        .busy(unused_argmax_busy),
        .done(argmax_done)
    );
endmodule
