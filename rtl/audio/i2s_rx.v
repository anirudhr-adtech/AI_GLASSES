`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem
// Module: i2s_rx
// Description: I2S slave receiver. Deserializes 16-bit left-channel PCM
//              samples (mono for wake-word detection).
//////////////////////////////////////////////////////////////////////////////

module i2s_rx (
    input  wire        clk,
    input  wire        rst_n,
    // I2S interface
    input  wire        i2s_sck_i,
    input  wire        i2s_ws_i,
    input  wire        i2s_sd_i,
    // Sample output
    output reg  [15:0] sample_o,
    output reg         sample_valid_o
);

    // Synchronized signals from i2s_sync
    wire sck_sync, ws_sync, sd_sync;
    wire sck_rise, sck_fall, ws_rise, ws_fall;

    i2s_sync u_sync (
        .clk        (clk),
        .rst_n      (rst_n),
        .i2s_sck_i  (i2s_sck_i),
        .i2s_ws_i   (i2s_ws_i),
        .i2s_sd_i   (i2s_sd_i),
        .sck_sync_o (sck_sync),
        .ws_sync_o  (ws_sync),
        .sd_sync_o  (sd_sync),
        .sck_rise_o (sck_rise),
        .sck_fall_o (sck_fall),
        .ws_rise_o  (ws_rise),
        .ws_fall_o  (ws_fall)
    );

    // FSM states
    localparam S_IDLE         = 2'd0;
    localparam S_CAPTURE_LEFT = 2'd1;
    localparam S_SKIP_RIGHT   = 2'd2;

    reg [1:0]  state;
    reg [3:0]  bit_cnt;
    reg [15:0] shift_reg;

    always @(posedge clk) begin
        if (!rst_n) begin
            state          <= S_IDLE;
            bit_cnt        <= 4'd0;
            shift_reg      <= 16'd0;
            sample_o       <= 16'd0;
            sample_valid_o <= 1'b0;
        end else begin
            sample_valid_o <= 1'b0;

            case (state)
                S_IDLE: begin
                    // WS falling edge = start of left channel
                    if (ws_fall) begin
                        state   <= S_CAPTURE_LEFT;
                        bit_cnt <= 4'd0;
                    end
                end

                S_CAPTURE_LEFT: begin
                    if (sck_rise) begin
                        // Shift in MSB-first
                        shift_reg <= {shift_reg[14:0], sd_sync};
                        if (bit_cnt == 4'd15) begin
                            sample_o       <= {shift_reg[14:0], sd_sync};
                            sample_valid_o <= 1'b1;
                            state          <= S_SKIP_RIGHT;
                        end
                        bit_cnt <= bit_cnt + 4'd1;
                    end
                end

                S_SKIP_RIGHT: begin
                    // Wait for WS falling edge (next left channel)
                    if (ws_fall) begin
                        state   <= S_CAPTURE_LEFT;
                        bit_cnt <= 4'd0;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
