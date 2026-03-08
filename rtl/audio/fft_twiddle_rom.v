`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem
// Module: fft_twiddle_rom
// Description: 512-entry complex twiddle factor ROM (Q1.15 format).
//              W_N^k = cos(2*pi*k/N) - j*sin(2*pi*k/N), k=0..511, N=1024
//////////////////////////////////////////////////////////////////////////////

module fft_twiddle_rom (
    input  wire        clk,
    input  wire [8:0]  addr_i,
    output reg  [15:0] re_o,
    output reg  [15:0] im_o
);

    reg [15:0] rom_re [0:511];
    reg [15:0] rom_im [0:511];

    integer i;
    integer tmp_re, tmp_im;
    initial begin
        for (i = 0; i < 512; i = i + 1) begin
            // cos(2*pi*k/1024) in Q1.15, clamped to [-32768, 32767]
            tmp_re = $rtoi($cos(6.28318530717959 * i / 1024.0) * 32768.0);
            if (tmp_re > 32767)  tmp_re = 32767;
            if (tmp_re < -32768) tmp_re = -32768;
            rom_re[i] = tmp_re[15:0];
            // -sin(2*pi*k/1024) in Q1.15, clamped
            tmp_im = $rtoi(-$sin(6.28318530717959 * i / 1024.0) * 32768.0);
            if (tmp_im > 32767)  tmp_im = 32767;
            if (tmp_im < -32768) tmp_im = -32768;
            rom_im[i] = tmp_im[15:0];
        end
    end

    always @(posedge clk) begin
        re_o <= rom_re[addr_i];
        im_o <= rom_im[addr_i];
    end

endmodule
