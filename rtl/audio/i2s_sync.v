`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem
// Module: i2s_sync
// Description: 2-FF synchronizer for I2S signals (SCK, WS, SD) from I2S
//              domain to sys_clk domain, with edge detectors.
//////////////////////////////////////////////////////////////////////////////

module i2s_sync (
    input  wire clk,
    input  wire rst_n,
    // Raw I2S inputs
    input  wire i2s_sck_i,
    input  wire i2s_ws_i,
    input  wire i2s_sd_i,
    // Synchronized outputs
    output wire sck_sync_o,
    output wire ws_sync_o,
    output wire sd_sync_o,
    // Edge detectors
    output reg  sck_rise_o,
    output reg  sck_fall_o,
    output reg  ws_rise_o,
    output reg  ws_fall_o
);

    // 2-FF synchronizer chains
    reg sck_meta, sck_sync;
    reg ws_meta,  ws_sync;
    reg sd_meta,  sd_sync;

    // Previous values for edge detection
    reg sck_prev;
    reg ws_prev;

    assign sck_sync_o = sck_sync;
    assign ws_sync_o  = ws_sync;
    assign sd_sync_o  = sd_sync;

    // Synchronizer FFs
    always @(posedge clk) begin
        if (!rst_n) begin
            sck_meta <= 1'b0;
            sck_sync <= 1'b0;
            ws_meta  <= 1'b0;
            ws_sync  <= 1'b0;
            sd_meta  <= 1'b0;
            sd_sync  <= 1'b0;
        end else begin
            sck_meta <= i2s_sck_i;
            sck_sync <= sck_meta;
            ws_meta  <= i2s_ws_i;
            ws_sync  <= ws_meta;
            sd_meta  <= i2s_sd_i;
            sd_sync  <= sd_meta;
        end
    end

    // Edge detection
    always @(posedge clk) begin
        if (!rst_n) begin
            sck_prev   <= 1'b0;
            ws_prev    <= 1'b0;
            sck_rise_o <= 1'b0;
            sck_fall_o <= 1'b0;
            ws_rise_o  <= 1'b0;
            ws_fall_o  <= 1'b0;
        end else begin
            sck_prev   <= sck_sync;
            ws_prev    <= ws_sync;
            sck_rise_o <= (~sck_prev) & sck_sync;
            sck_fall_o <= sck_prev & (~sck_sync);
            ws_rise_o  <= (~ws_prev) & ws_sync;
            ws_fall_o  <= ws_prev & (~ws_sync);
        end
    end

endmodule
