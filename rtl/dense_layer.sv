`timescale 1ns/1ps

module dense_layer #(
    parameter string WEIGHT_FILE = "mem/weights_x8.mem",
    parameter string BIAS_FILE = "mem/biases_x8.mem"
)(
    input  logic               clk,
    input  logic               reset,
    input  logic               start,
    input  logic [12:0]        in_size,
    input  logic [12:0]        out_size,
    input  logic [15:0]        w_base,
    input  logic [6:0]         b_base,
    input  logic [4:0]         shift,
    input  logic               relu_en,

    output logic [12:0]        act_raddr,
    input  logic signed [15:0] act_rdata,
    output logic               out_we,
    output logic [12:0]        out_waddr,
    output logic signed [15:0] out_wdata,
    output logic               busy,
    output logic               done
);
    logic agu_start, agu_enable;
    logic agu_valid, agu_first, agu_last;
    logic [12:0] agu_out_idx;
    logic [15:0] w_addr;
    logic [6:0] b_addr;
    logic unused_agu_done;

    logic mac_en, load_bias;
    logic [2:0] lane_sel;
    logic [7:0][7:0] weights;
    logic [7:0][31:0] biases;
    logic [12:0] weight_rom_addr;
    logic [3:0] bias_rom_addr;
    logic [4:0] shift_r;
    logic relu_en_r;

    // Layer settings are held for the entire computation and result readout.
    always_ff @(posedge clk) begin
        if (reset) begin
            shift_r <= '0;
            relu_en_r <= 1'b0;
        end
        else if (start && !busy && !done) begin
            shift_r <= shift;
            relu_en_r <= relu_en;
        end
    end

    dense_agu u_agu (
        .clk(clk),
        .rst(reset),
        .start(agu_start),
        .enable(agu_enable),
        .in_size(in_size),
        .out_size(out_size),
        .w_base(w_base),
        .b_base(b_base),
        .act_raddr(act_raddr),
        .w_addr(w_addr),
        .b_addr(b_addr),
        .out_idx(agu_out_idx),
        .valid(agu_valid),
        .first(agu_first),
        .last(agu_last),
        .done(unused_agu_done)
    );

    dense_controller u_controller (
        .clk(clk),
        .reset(reset),
        .start(start),
        .in_size(in_size),
        .out_size(out_size),
        .agu_valid(agu_valid),
        .agu_first(agu_first),
        .agu_last(agu_last),
        .agu_out_idx(agu_out_idx),
        .agu_start(agu_start),
        .agu_enable(agu_enable),
        .mac_en(mac_en),
        .load_bias(load_bias),
        .lane_sel(lane_sel),
        .out_we(out_we),
        .out_waddr(out_waddr),
        .busy(busy),
        .done(done)
    );

    // The AGU increments after its final read. Park idle out-of-range reads at zero.
    assign weight_rom_addr = w_addr < 16'd6400 ? w_addr[12:0] : 13'd0;
    assign bias_rom_addr = b_addr < 7'd10 ? b_addr[3:0] : 4'd0;

    rom #(
        .LANES(8),
        .LANE_W(8),
        .DEPTH(6400),
        .AW(13),
        .MEM_FILE(WEIGHT_FILE)
    ) u_weight_rom (
        .clk(clk),
        .addr(weight_rom_addr),
        .data(weights)
    );

    rom #(
        .LANES(8),
        .LANE_W(32),
        .DEPTH(10),
        .AW(4),
        .MEM_FILE(BIAS_FILE)
    ) u_bias_rom (
        .clk(clk),
        .addr(bias_rom_addr),
        .data(biases)
    );

    datapath u_datapath (
        .clk(clk),
        .reset(reset),
        .mac_en(mac_en),
        .load_bias(load_bias),
        .activation(act_rdata),
        .weights(weights),
        .biases(biases),
        .lane_sel(lane_sel),
        .shift(shift_r),
        .relu_en(relu_en_r),
        .y(out_wdata)
    );

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (!reset && agu_valid) begin
            assert (w_addr < 16'd6400) else $fatal(1, "Weight address exceeds the packed ROM");
            assert (b_addr < 7'd10) else $fatal(1, "Bias address exceeds the packed ROM");
        end
    end
`endif
endmodule
