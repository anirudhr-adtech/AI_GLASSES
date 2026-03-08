`timescale 1ns / 1ps
//============================================================================
// spi_clk_gen.v
// AI_GLASSES — SPI Master
// SPI clock divider with CPOL/CPHA support.
// spi_clk = sys_clk / (2 * (div + 1)). div=4 -> 10MHz at 100MHz sys_clk.
//============================================================================

module spi_clk_gen (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [7:0]  div_i,
    input  wire        cpol_i,
    input  wire        cpha_i,
    input  wire        sclk_en,

    output reg         sclk_o,
    output reg         sample_edge_o,
    output reg         shift_edge_o
);

    reg [7:0] cnt;
    reg       sclk_int;

    // CPOL: idle polarity. CPHA: 0 = sample on first edge, 1 = sample on second edge
    // Combine: CPOL^CPHA determines which edge is sample vs shift
    // Mode 0 (CPOL=0,CPHA=0): sample on rising, shift on falling
    // Mode 1 (CPOL=0,CPHA=1): sample on falling, shift on rising
    // Mode 2 (CPOL=1,CPHA=0): sample on falling, shift on rising
    // Mode 3 (CPOL=1,CPHA=1): sample on rising, shift on falling

    wire sample_on_rise = ~(cpol_i ^ cpha_i);

    always @(posedge clk) begin
        if (!rst_n) begin
            cnt           <= 8'd0;
            sclk_int      <= 1'b0;
            sclk_o        <= 1'b0;
            sample_edge_o <= 1'b0;
            shift_edge_o  <= 1'b0;
        end else begin
            sample_edge_o <= 1'b0;
            shift_edge_o  <= 1'b0;

            if (!sclk_en) begin
                cnt      <= 8'd0;
                sclk_int <= 1'b0;
                sclk_o   <= cpol_i; // idle level
            end else begin
                if (cnt == div_i) begin
                    cnt      <= 8'd0;
                    sclk_int <= ~sclk_int;
                    sclk_o   <= cpol_i ^ (~sclk_int); // XOR with CPOL for output

                    if (~sclk_int) begin
                        // Rising edge of internal clock
                        if (sample_on_rise)
                            sample_edge_o <= 1'b1;
                        else
                            shift_edge_o <= 1'b1;
                    end else begin
                        // Falling edge of internal clock
                        if (sample_on_rise)
                            shift_edge_o <= 1'b1;
                        else
                            sample_edge_o <= 1'b1;
                    end
                end else begin
                    cnt <= cnt + 8'd1;
                end
            end
        end
    end

endmodule
