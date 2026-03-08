`timescale 1ns/1ps
//============================================================================
// Module : uart_rx
// Project : AI_GLASSES — RISC-V Subsystem
// Description : UART 8N1 receiver FSM with 16x oversampling.
//               Samples in middle of bit period. Reports framing errors.
//============================================================================
module uart_rx (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx_in,
    input  wire       baud_tick_16x,
    output reg  [7:0] rx_data,
    output reg        rx_valid,
    output reg        rx_error
);

    // FSM states
    localparam [1:0] S_IDLE  = 2'b00,
                     S_START = 2'b01,
                     S_DATA  = 2'b10,
                     S_STOP  = 2'b11;

    reg [1:0] state;
    reg [3:0] tick_cnt;   // 0..15 counter for 16x oversampling
    reg [2:0] bit_idx;
    reg [7:0] shift_reg;

    always @(posedge clk) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            tick_cnt  <= 4'd0;
            bit_idx   <= 3'd0;
            shift_reg <= 8'd0;
            rx_data   <= 8'd0;
            rx_valid  <= 1'b0;
            rx_error  <= 1'b0;
        end else begin
            rx_valid <= 1'b0;  // default: clear pulse
            rx_error <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (~rx_in) begin
                        // Falling edge detected — possible start bit
                        state    <= S_START;
                        tick_cnt <= 4'd0;
                    end
                end

                S_START: begin
                    if (baud_tick_16x) begin
                        if (tick_cnt == 4'd7) begin
                            // Middle of start bit — verify still low
                            if (~rx_in) begin
                                state    <= S_DATA;
                                tick_cnt <= 4'd0;
                                bit_idx  <= 3'd0;
                            end else begin
                                // False start, go back to idle
                                state <= S_IDLE;
                            end
                        end else begin
                            tick_cnt <= tick_cnt + 4'd1;
                        end
                    end
                end

                S_DATA: begin
                    if (baud_tick_16x) begin
                        if (tick_cnt == 4'd15) begin
                            // Middle of data bit — sample
                            shift_reg <= {rx_in, shift_reg[7:1]};  // LSB first
                            tick_cnt  <= 4'd0;
                            if (bit_idx == 3'd7) begin
                                state <= S_STOP;
                            end else begin
                                bit_idx <= bit_idx + 3'd1;
                            end
                        end else begin
                            tick_cnt <= tick_cnt + 4'd1;
                        end
                    end
                end

                S_STOP: begin
                    if (baud_tick_16x) begin
                        if (tick_cnt == 4'd15) begin
                            // Middle of stop bit — check framing
                            rx_data <= shift_reg;
                            if (rx_in) begin
                                rx_valid <= 1'b1;
                            end else begin
                                rx_error <= 1'b1;  // framing error
                            end
                            state <= S_IDLE;
                        end else begin
                            tick_cnt <= tick_cnt + 4'd1;
                        end
                    end
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
