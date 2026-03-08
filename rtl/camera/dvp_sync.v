`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Camera Subsystem
// Module: dvp_sync
// Description: 2-FF input synchronizer for DVP camera signals to sys_clk
//////////////////////////////////////////////////////////////////////////////

module dvp_sync (
    input  wire        clk,
    input  wire        rst_n,
    // Raw DVP inputs
    input  wire        pclk_i,
    input  wire        vsync_i,
    input  wire        href_i,
    input  wire [7:0]  data_i,
    // Synchronized outputs
    output reg         pclk_sync_o,
    output reg         vsync_sync_o,
    output reg         href_sync_o,
    output reg  [7:0]  data_sync_o,
    // Edge detectors
    output reg         pclk_rise_o,
    output reg         pclk_fall_o,
    output reg         vsync_rise_o
);

    // Stage 1 registers
    reg        pclk_s1;
    reg        vsync_s1;
    reg        href_s1;
    reg [7:0]  data_s1;

    // Previous synchronized values for edge detection
    reg        pclk_prev;
    reg        vsync_prev;

    // 2-FF synchronizer
    always @(posedge clk) begin
        if (!rst_n) begin
            pclk_s1     <= 1'b0;
            vsync_s1    <= 1'b0;
            href_s1     <= 1'b0;
            data_s1     <= 8'd0;
            pclk_sync_o <= 1'b0;
            vsync_sync_o <= 1'b0;
            href_sync_o <= 1'b0;
            data_sync_o <= 8'd0;
        end else begin
            // Stage 1
            pclk_s1  <= pclk_i;
            vsync_s1 <= vsync_i;
            href_s1  <= href_i;
            data_s1  <= data_i;
            // Stage 2 (synchronized output)
            pclk_sync_o  <= pclk_s1;
            vsync_sync_o <= vsync_s1;
            href_sync_o  <= href_s1;
            data_sync_o  <= data_s1;
        end
    end

    // Edge detection (registered for clean output)
    always @(posedge clk) begin
        if (!rst_n) begin
            pclk_prev    <= 1'b0;
            vsync_prev   <= 1'b0;
            pclk_rise_o  <= 1'b0;
            pclk_fall_o  <= 1'b0;
            vsync_rise_o <= 1'b0;
        end else begin
            pclk_prev    <= pclk_sync_o;
            vsync_prev   <= vsync_sync_o;
            pclk_rise_o  <= pclk_sync_o & ~pclk_prev;
            pclk_fall_o  <= ~pclk_sync_o & pclk_prev;
            vsync_rise_o <= vsync_sync_o & ~vsync_prev;
        end
    end

endmodule
