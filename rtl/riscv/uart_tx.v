`timescale 1ns/1ps
//============================================================================
// Module : uart_tx
// Project : AI_GLASSES — RISC-V Subsystem
// Description : UART 8N1 transmitter FSM. Shifts out LSB first.
//               Baud timing driven externally via baud_tick input.
//============================================================================
module uart_tx (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tx_start,
    input  wire [7:0] tx_data,
    input  wire       baud_tick,
    output reg        tx_busy,
    output reg        tx_done,
    output reg        tx_out
);

    // FSM states
    localparam [1:0] S_IDLE  = 2'b00,
                     S_START = 2'b01,
                     S_DATA  = 2'b10,
                     S_STOP  = 2'b11;

    reg [1:0] state;
    reg [2:0] bit_idx;
    reg [7:0] shift_reg;

    always @(posedge clk) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            bit_idx   <= 3'd0;
            shift_reg <= 8'd0;
            tx_busy   <= 1'b0;
            tx_done   <= 1'b0;
            tx_out    <= 1'b1;  // idle HIGH
        end else begin
            tx_done <= 1'b0;  // default: clear pulse

            case (state)
                S_IDLE: begin
                    tx_out <= 1'b1;
                    if (tx_start) begin
                        state     <= S_START;
                        shift_reg <= tx_data;
                        tx_busy   <= 1'b1;
                    end
                end

                S_START: begin
                    if (baud_tick) begin
                        tx_out  <= 1'b0;  // start bit
                        state   <= S_DATA;
                        bit_idx <= 3'd0;
                    end
                end

                S_DATA: begin
                    if (baud_tick) begin
                        tx_out    <= shift_reg[0];
                        shift_reg <= {1'b0, shift_reg[7:1]};
                        if (bit_idx == 3'd7) begin
                            state <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 3'd1;
                        end
                    end
                end

                S_STOP: begin
                    if (baud_tick) begin
                        tx_out  <= 1'b1;  // stop bit
                        tx_done <= 1'b1;
                        tx_busy <= 1'b0;
                        state   <= S_IDLE;
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
