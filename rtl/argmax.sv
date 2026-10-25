`timescale 1ns/1ps

module argmax (
    input  logic               clk,
    input  logic               reset,
    input  logic               start,
    output logic [12:0]        act_raddr,
    input  logic signed [15:0] act_rdata,
    output logic [3:0]         digit,
    output logic signed [15:0] max_score,
    output logic               busy,
    output logic               done
);
    typedef enum logic [1:0] {
        IDLE,
        READ,
        COMPARE,
        DONE
    } state_t;

    state_t state, next_state;
    logic [3:0] index;

    assign act_raddr = {9'b0, index};

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            index <= '0;
            digit <= '0;
            max_score <= '0;
        end
        else begin
            state <= next_state;

            if (state == IDLE && start) begin
                index <= '0;
                digit <= '0;
                max_score <= 16'sh8000;
            end
            else if (state == COMPARE) begin
                // Strict comparison keeps the first index when scores tie.
                if (index == 0 || act_rdata > max_score) begin
                    max_score <= act_rdata;
                    digit <= index;
                end
                if (index != 4'd9)
                    index <= index + 4'd1;
            end
        end
    end

    always_comb begin
        next_state = state;

        case (state)
            IDLE: begin
                if (start)
                    next_state = READ;
            end
            READ: begin
                next_state = COMPARE;
            end
            COMPARE: begin
                if (index == 4'd9)
                    next_state = DONE;
                else
                    next_state = READ;
            end
            DONE: begin
                next_state = IDLE;
            end
            default: begin
                next_state = IDLE;
            end
        endcase
    end

    always_comb begin
        busy = 1'b0;
        done = 1'b0;

        if (!reset) begin
            case (state)
                READ, COMPARE: busy = 1'b1;
                DONE: done = 1'b1;
                default: begin
                end
            endcase
        end
    end
endmodule
