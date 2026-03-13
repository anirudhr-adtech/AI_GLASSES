`timescale 1ns/1ps
// ============================================================================
// Blackbox stub for npu_weight_buf — used during ASIC synthesis only.
// Real SRAM macro (128KB dual-port) will be substituted during PnR.
// ============================================================================

(* blackbox *)
module npu_weight_buf #(
    parameter DEPTH      = 32768,
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 15
) (
    input  wire                    clk,

    // Port A — DMA write side (read/write)
    input  wire                    port_a_en,
    input  wire                    port_a_we,
    input  wire [ADDR_WIDTH-1:0]  port_a_addr,
    input  wire [DATA_WIDTH-1:0]  port_a_wdata,
    output wire [DATA_WIDTH-1:0]  port_a_rdata,

    // Port B — MAC read side (read only)
    input  wire                    port_b_en,
    input  wire [ADDR_WIDTH-1:0]  port_b_addr,
    output wire [DATA_WIDTH-1:0]  port_b_rdata
);
endmodule
