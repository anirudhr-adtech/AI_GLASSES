`timescale 1ns/1ps
// ============================================================================
// Module : npu_weight_buf
// Project : AI_GLASSES
// Description : 128KB dual-port BRAM wrapper for NPU weight storage.
//               Port A (DMA side) supports read and write.
//               Port B (MAC side) supports read only.
//               Synchronous read with 1-cycle latency for BRAM inference.
// ============================================================================

module npu_weight_buf #(
    parameter DEPTH      = 32768,
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 15
) (
    input  wire                    clk,

    // Port A — DMA write side (read/write)
    input  wire                    port_a_en,
    input  wire                    port_a_we,
    input  wire [ADDR_WIDTH-1:0]   port_a_addr,
    input  wire [DATA_WIDTH-1:0]   port_a_wdata,
    output reg  [DATA_WIDTH-1:0]   port_a_rdata,

    // Port B — MAC read side (read only)
    input  wire                    port_b_en,
    input  wire [ADDR_WIDTH-1:0]   port_b_addr,
    output reg  [DATA_WIDTH-1:0]   port_b_rdata
);

    // Memory array with Xilinx BRAM inference attribute
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Port A: synchronous read/write
    always @(posedge clk) begin
        if (port_a_en) begin
            if (port_a_we) begin
                mem[port_a_addr] <= port_a_wdata;
            end
            port_a_rdata <= mem[port_a_addr];
        end
    end

    // Port B: synchronous read only
    always @(posedge clk) begin
        if (port_b_en) begin
            port_b_rdata <= mem[port_b_addr];
        end
    end

endmodule
