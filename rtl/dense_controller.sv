`timescale 1ns/1ps

module dense_controller (
    input logic clk, reset, start,
    input logic [12:0] in_size,
    input logic [12:0] out_size,
    input logic agu_valid, agu_first, agu_last,
    input logic [12:0] agu_out_idx,
    output logic agu_start, agu_enable, mac_en, load_bias,
    output logic [2:0] lane_sel,
    output logic out_we,
    output logic [12:0] out_waddr,
    output logic busy, done
);
    typedef enum logic [2:0] {IDLE, COMPUTE, FLUSH, WRITE, DONE} state_t;
    state_t state, next_state;
    logic [12:0] out_size_r, group_idx;
    logic [2:0] lane_idx;
    logic valid_d, first_d, last_d;

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            out_size_r <= '0;
            group_idx <= '0;
            lane_idx <= '0;
            valid_d <= 1'b0;
            first_d <= 1'b0;
            last_d <= 1'b0;
        end
        else begin
            state <= next_state;
            valid_d <= agu_valid && agu_enable;
            first_d <= agu_valid && agu_enable && agu_first;
            last_d <= agu_valid && agu_enable && agu_last;
            if (state == IDLE && start) out_size_r <= out_size;
            if (agu_valid && agu_enable && agu_first) group_idx <= agu_out_idx;
            if (state != WRITE) lane_idx <= '0;
            else if (out_we && lane_idx != 3'd7) lane_idx <= lane_idx + 3'd1;
        end
    end

    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (start) begin
                    if (in_size == 0 || out_size == 0) next_state = DONE;
                    else next_state = COMPUTE;
                end
            end
            COMPUTE: begin
                if (agu_valid && agu_enable && agu_last) next_state = FLUSH;
            end
            FLUSH: begin
                if (valid_d && last_d) next_state = WRITE;
            end
            WRITE: begin
                if (out_we) begin
                    if (lane_idx == 3'd7 || int'(group_idx) + int'(lane_idx) + 1 >= int'(out_size_r)) begin
                        if (int'(group_idx) + 8 >= int'(out_size_r)) next_state = DONE;
                        else next_state = COMPUTE;
                    end
                end
            end
            DONE: next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    always_comb begin
        agu_start = 1'b0;
        agu_enable = 1'b0;
        mac_en = 1'b0;
        load_bias = 1'b0;
        lane_sel = '0;
        out_we = 1'b0;
        out_waddr = '0;
        busy = 1'b0;
        done = 1'b0;
        if (!reset) begin
            case (state)
                IDLE: begin
                    if (start && in_size != 0 && out_size != 0) agu_start = 1'b1;
                end
                COMPUTE, FLUSH: begin
                    busy = 1'b1;
                    if (state == COMPUTE) agu_enable = 1'b1;
                    mac_en = valid_d;
                    load_bias = valid_d && first_d;
                end
                WRITE: begin
                    busy = 1'b1;
                    lane_sel = lane_idx;
                    out_waddr = group_idx + {10'b0, lane_idx};
                    if (int'(group_idx) + int'(lane_idx) < int'(out_size_r)) out_we = 1'b1;
                end
                DONE: done = 1'b1;
                default: begin
                end
            endcase
        end
    end
endmodule
