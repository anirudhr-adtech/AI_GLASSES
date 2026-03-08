`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Camera Subsystem
// Module: yuv2rgb
// Description: BT.601 YUV422 to RGB888 color converter (2-cycle pipeline)
//////////////////////////////////////////////////////////////////////////////

module yuv2rgb (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [7:0]  y_i,
    input  wire [7:0]  u_i,
    input  wire [7:0]  v_i,
    output reg         out_valid,
    output reg  [7:0]  r_o,
    output reg  [7:0]  g_o,
    output reg  [7:0]  b_o
);

    // BT.601 fixed-point Q8.8 coefficients:
    // R = Y + 1.402*(V-128)   -> coeff 359
    // G = Y - 0.344*(U-128) - 0.714*(V-128)  -> coeffs 88, 183
    // B = Y + 1.772*(U-128)   -> coeff 454
    localparam signed [9:0] COEFF_RV = 10'sd359;   // 1.402 * 256
    localparam signed [9:0] COEFF_GU = -10'sd88;   // -0.344 * 256
    localparam signed [9:0] COEFF_GV = -10'sd183;  // -0.714 * 256
    localparam signed [9:0] COEFF_BU = 10'sd454;   // 1.772 * 256

    // Stage 1: multiply
    reg signed [18:0] mul_rv;   // COEFF_RV * (V-128)
    reg signed [18:0] mul_gu;   // COEFF_GU * (U-128)
    reg signed [18:0] mul_gv;   // COEFF_GV * (V-128)
    reg signed [18:0] mul_bu;   // COEFF_BU * (U-128)
    reg signed [9:0]  y_s1;
    reg                valid_s1;

    // Stage 1
    always @(posedge clk) begin
        if (!rst_n) begin
            mul_rv   <= 19'sd0;
            mul_gu   <= 19'sd0;
            mul_gv   <= 19'sd0;
            mul_bu   <= 19'sd0;
            y_s1     <= 10'sd0;
            valid_s1 <= 1'b0;
        end else begin
            valid_s1 <= in_valid;
            y_s1     <= {2'b00, y_i};
            mul_rv   <= COEFF_RV * ($signed({1'b0, v_i}) - 10'sd128);
            mul_gu   <= COEFF_GU * ($signed({1'b0, u_i}) - 10'sd128);
            mul_gv   <= COEFF_GV * ($signed({1'b0, v_i}) - 10'sd128);
            mul_bu   <= COEFF_BU * ($signed({1'b0, u_i}) - 10'sd128);
        end
    end

    // Stage 2: add + clamp
    wire signed [18:0] r_sum = {y_s1, 8'd0} + mul_rv;
    wire signed [18:0] g_sum = {y_s1, 8'd0} + mul_gu + mul_gv;
    wire signed [18:0] b_sum = {y_s1, 8'd0} + mul_bu;

    // Clamp to [0, 255] after >>8
    wire signed [10:0] r_shift = r_sum[18:8];
    wire signed [10:0] g_shift = g_sum[18:8];
    wire signed [10:0] b_shift = b_sum[18:8];

    function [7:0] clamp;
        input signed [10:0] val;
        begin
            if (val < 0)
                clamp = 8'd0;
            else if (val > 255)
                clamp = 8'd255;
            else
                clamp = val[7:0];
        end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            r_o       <= 8'd0;
            g_o       <= 8'd0;
            b_o       <= 8'd0;
            out_valid <= 1'b0;
        end else begin
            out_valid <= valid_s1;
            r_o       <= clamp(r_shift);
            g_o       <= clamp(g_shift);
            b_o       <= clamp(b_shift);
        end
    end

endmodule
