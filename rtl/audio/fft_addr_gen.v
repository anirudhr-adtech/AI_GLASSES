`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem
// Module: fft_addr_gen
// Description: Bit-reversal permutation + stage address generator for
//              1024-point radix-2 DIT FFT.
//////////////////////////////////////////////////////////////////////////////

module fft_addr_gen (
    input  wire        clk,
    input  wire        rst_n,
    // Stage and butterfly index
    input  wire [3:0]  stage_i,
    input  wire [8:0]  butterfly_i,
    // Butterfly addresses
    output reg  [9:0]  p_addr_o,
    output reg  [9:0]  q_addr_o,
    // Twiddle address
    output reg  [8:0]  tw_addr_o,
    // Bit-reversal
    input  wire [9:0]  bitrev_addr_i,
    output reg  [9:0]  bitrev_addr_o
);

    // Bit-reverse function for 10-bit address
    function [9:0] bitrev10;
        input [9:0] addr;
        integer j;
        begin
            for (j = 0; j < 10; j = j + 1)
                bitrev10[j] = addr[9-j];
        end
    endfunction

    // Combinational address generation
    wire [9:0] k = {1'b0, butterfly_i};
    wire [3:0] s = stage_i;

    // p = (k >> s) << (s+1) | (k & ((1 << s) - 1))
    // q = p + (1 << s)
    // tw = (k & ((1 << s) - 1)) << (9 - s)

    wire [9:0] upper_bits;
    wire [9:0] lower_mask;
    wire [9:0] lower_bits;
    wire [9:0] p_comb;
    wire [9:0] q_comb;
    wire [8:0] tw_comb;

    assign lower_mask = (10'd1 << s) - 10'd1;
    assign upper_bits = (k >> s) << (s + 1);
    assign lower_bits = k & lower_mask;
    assign p_comb     = upper_bits | lower_bits;
    assign q_comb     = p_comb + (10'd1 << s);
    assign tw_comb    = lower_bits << (4'd9 - s);

    always @(posedge clk) begin
        if (!rst_n) begin
            p_addr_o      <= 10'd0;
            q_addr_o      <= 10'd0;
            tw_addr_o     <= 9'd0;
            bitrev_addr_o <= 10'd0;
        end else begin
            p_addr_o      <= p_comb;
            q_addr_o      <= q_comb;
            tw_addr_o     <= tw_comb;
            bitrev_addr_o <= bitrev10(bitrev_addr_i);
        end
    end

endmodule
