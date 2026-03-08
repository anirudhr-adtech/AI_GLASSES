`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem
// Module: hamming_rom
// Description: 640-entry Hamming window coefficient ROM (Q1.15 format).
//              w(n) = 0.54 - 0.46 * cos(2*pi*n/639)
//////////////////////////////////////////////////////////////////////////////

module hamming_rom (
    input  wire        clk,
    input  wire [9:0]  addr_i,
    output reg  [15:0] data_o
);

    reg [15:0] rom [0:639];

    // Hamming window: w(n) = 0.54 - 0.46*cos(2*pi*n/639), n=0..639
    // Q1.15: multiply float by 32768, round to integer
    // We use an initial block with $rtoi and $cos
    integer i;
    initial begin
        for (i = 0; i < 640; i = i + 1) begin
            // 3.14159265358979 * 2 = 6.28318530717959
            // cos argument: 2*pi*i/639
            rom[i] = $rtoi((0.54 - 0.46 * $cos(6.28318530717959 * i / 639.0)) * 32768.0);
        end
    end

    always @(posedge clk) begin
        if (addr_i < 10'd640)
            data_o <= rom[addr_i];
        else
            data_o <= 16'd0;
    end

endmodule
