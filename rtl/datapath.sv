`timescale 1ns/1ps

module datapath (
    input  logic                    clk,
    input  logic                    reset,
    input  logic                    mac_en,
    input  logic                    load_bias,
    input  logic signed [15:0]       activation,
    input  logic [7:0][7:0]          weights,
    input  logic [7:0][31:0]         biases,
    input  logic [2:0]              lane_sel,
    input  logic [4:0]              shift,
    input  logic                    relu_en,
    output logic signed [15:0]       y
);
    logic signed [31:0] accumulators [0:7];
    logic signed [31:0] selected_acc;
    mac mac_0 (
    .clk(clk),
    .reset(reset),
    .load_bias(load_bias),
    .accumulation_enable(mac_en),
    .activation(activation),
    .weight($signed(weights[0])),
    .bias($signed(biases[0])),
    .accumulator(accumulators[0])
);
    mac mac_1 (
    .clk(clk),
    .reset(reset),
    .load_bias(load_bias),
    .accumulation_enable(mac_en),
    .activation(activation),
    .weight($signed(weights[1])),
    .bias($signed(biases[1])),
    .accumulator(accumulators[1])
);
    mac mac_2 (
    .clk(clk),
    .reset(reset),
    .load_bias(load_bias),
    .accumulation_enable(mac_en),
    .activation(activation),
    .weight($signed(weights[2])),
    .bias($signed(biases[2])),
    .accumulator(accumulators[2])
);
    mac mac_3 (
    .clk(clk),
    .reset(reset),
    .load_bias(load_bias),
    .accumulation_enable(mac_en),
    .activation(activation),
    .weight($signed(weights[3])),
    .bias($signed(biases[3])),
    .accumulator(accumulators[3])
);
    mac mac_4 (
    .clk(clk),
    .reset(reset),
    .load_bias(load_bias),
    .accumulation_enable(mac_en),
    .activation(activation),
    .weight($signed(weights[4])),
    .bias($signed(biases[4])),
    .accumulator(accumulators[4])
);
    mac mac_5 (
    .clk(clk),
    .reset(reset),
    .load_bias(load_bias),
    .accumulation_enable(mac_en),
    .activation(activation),
    .weight($signed(weights[5])),
    .bias($signed(biases[5])),
    .accumulator(accumulators[5])
);
    mac mac_6 (
    .clk(clk),
    .reset(reset),
    .load_bias(load_bias),
    .accumulation_enable(mac_en),
    .activation(activation),
    .weight($signed(weights[6])),
    .bias($signed(biases[6])),
    .accumulator(accumulators[6])
);
    mac mac_7 (
    .clk(clk),
    .reset(reset),
    .load_bias(load_bias),
    .accumulation_enable(mac_en),
    .activation(activation),
    .weight($signed(weights[7])),
    .bias($signed(biases[7])),
    .accumulator(accumulators[7])
);

    assign selected_acc = accumulators[lane_sel];

    requant_relu requant_0 (
    .acc(selected_acc),
    .relu_en(relu_en),
    .shift(shift),
    .y(y)
);

endmodule
