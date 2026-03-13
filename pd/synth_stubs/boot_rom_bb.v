`timescale 1ns/1ps
// Blackbox stub for boot_rom — 4KB ROM with AXI4 slave (ASIC synthesis only)
// Real ROM macro substituted in PnR. No $readmemh needed for synthesis.

(* blackbox *)
module boot_rom #(
    parameter ADDR_WIDTH = 12,
    parameter DATA_WIDTH = 32,
    parameter DEPTH      = 1024,
    parameter INIT_FILE  = "boot_rom.hex"
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    input  wire [3:0]  s_axi_arid,
    input  wire [7:0]  s_axi_arlen,
    input  wire [2:0]  s_axi_arsize,
    input  wire [1:0]  s_axi_arburst,
    output wire [31:0] s_axi_rdata,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,
    output wire [1:0]  s_axi_rresp,
    output wire [3:0]  s_axi_rid,
    output wire        s_axi_rlast,
    input  wire [31:0] s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [3:0]  s_axi_awid,
    input  wire [7:0]  s_axi_awlen,
    input  wire [2:0]  s_axi_awsize,
    input  wire [1:0]  s_axi_awburst,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    input  wire        s_axi_wlast,
    output wire        s_axi_wready,
    output wire [3:0]  s_axi_bid,
    output wire [1:0]  s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready
);
endmodule
