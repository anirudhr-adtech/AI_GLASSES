`timescale 1ns/1ps
// Blackbox stub for sram_bank — 128KB dual-port SRAM (ASIC synthesis only)
// Real SRAM macro from SCL memory compiler substituted in PnR.

(* blackbox *)
module sram_bank #(
    parameter ADDR_WIDTH = 15,
    parameter DATA_WIDTH = 32
) (
    input  wire                       clk,
    input  wire [ADDR_WIDTH-1:0]      a_addr,
    input  wire                       a_en,
    output wire [DATA_WIDTH-1:0]      a_rdata,
    input  wire [ADDR_WIDTH-1:0]      b_addr,
    input  wire                       b_en,
    input  wire                       b_we,
    input  wire [DATA_WIDTH/8-1:0]    b_wstrb,
    input  wire [DATA_WIDTH-1:0]      b_wdata,
    output wire [DATA_WIDTH-1:0]      b_rdata
);
endmodule
