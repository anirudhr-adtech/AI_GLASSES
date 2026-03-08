`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem
// Module: fft_butterfly
// Description: Single radix-2 DIT butterfly unit with 2-cycle pipeline.
//              X'[p] = A + W*B,  X'[q] = A - W*B
//              Right-shift by 1 per stage for block floating-point scaling.
//////////////////////////////////////////////////////////////////////////////

module fft_butterfly (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    // Input operands (Q1.15 fixed-point)
    input  wire signed [15:0] a_re,
    input  wire signed [15:0] a_im,
    input  wire signed [15:0] b_re,
    input  wire signed [15:0] b_im,
    // Twiddle factor (Q1.15)
    input  wire signed [15:0] w_re,
    input  wire signed [15:0] w_im,
    // Output
    output reg  signed [15:0] p_re,
    output reg  signed [15:0] p_im,
    output reg  signed [15:0] q_re,
    output reg  signed [15:0] q_im,
    output reg                valid_o
);

    // Stage 1: 4 multiplies (DSP48 inference)
    reg signed [31:0] wr_br, wi_bi, wr_bi, wi_br;
    reg signed [15:0] a_re_d1, a_im_d1;
    reg               en_d1;

    // Stage 2: adds + butterfly sums
    reg signed [16:0] wb_re, wb_im;  // W*B real and imag parts

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_br   <= 32'd0;
            wi_bi   <= 32'd0;
            wr_bi   <= 32'd0;
            wi_br   <= 32'd0;
            a_re_d1 <= 16'd0;
            a_im_d1 <= 16'd0;
            en_d1   <= 1'b0;
        end else begin
            en_d1 <= en;
            if (en) begin
                // W*B = (Wr*Br - Wi*Bi) + j(Wr*Bi + Wi*Br)
                wr_br   <= w_re * b_re;
                wi_bi   <= w_im * b_im;
                wr_bi   <= w_re * b_im;
                wi_br   <= w_im * b_re;
                a_re_d1 <= a_re;
                a_im_d1 <= a_im;
            end
        end
    end

    // Stage 2: butterfly sums with >>1 scaling
    wire signed [16:0] wb_re_w = (wr_br - wi_bi) >>> 15;  // Q1.15 * Q1.15 -> Q2.30, take Q1.15
    wire signed [16:0] wb_im_w = (wr_bi + wi_br) >>> 15;

    // Saturate to 16-bit
    wire signed [16:0] p_re_sum = $signed({a_re_d1[15], a_re_d1}) + wb_re_w;
    wire signed [16:0] p_im_sum = $signed({a_im_d1[15], a_im_d1}) + wb_im_w;
    wire signed [16:0] q_re_sum = $signed({a_re_d1[15], a_re_d1}) - wb_re_w;
    wire signed [16:0] q_im_sum = $signed({a_im_d1[15], a_im_d1}) - wb_im_w;

    always @(posedge clk) begin
        if (!rst_n) begin
            p_re    <= 16'd0;
            p_im    <= 16'd0;
            q_re    <= 16'd0;
            q_im    <= 16'd0;
            valid_o <= 1'b0;
        end else begin
            valid_o <= en_d1;
            if (en_d1) begin
                // >>1 scaling per stage
                p_re <= p_re_sum[16:1];
                p_im <= p_im_sum[16:1];
                q_re <= q_re_sum[16:1];
                q_im <= q_im_sum[16:1];
            end
        end
    end

endmodule
