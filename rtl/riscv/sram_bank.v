`timescale 1ns/1ps
//============================================================================
// Module : sram_bank
// Project : AI_GLASSES — RISC-V Subsystem
// Description : Single dual-port SRAM bank (Port A read-only, Port B R/W)
//============================================================================

module sram_bank #(
    parameter ADDR_WIDTH = 15,
    parameter DATA_WIDTH = 32
)(
    input  wire                       clk,

    // Port A — read-only
    input  wire [ADDR_WIDTH-1:0]      a_addr,
    input  wire                       a_en,
    output reg  [DATA_WIDTH-1:0]      a_rdata,

    // Port B — read/write
    input  wire [ADDR_WIDTH-1:0]      b_addr,
    input  wire                       b_en,
    input  wire                       b_we,
    input  wire [DATA_WIDTH/8-1:0]    b_wstrb,
    input  wire [DATA_WIDTH-1:0]      b_wdata,
    output reg  [DATA_WIDTH-1:0]      b_rdata
);

    // ----------------------------------------------------------------
    // Memory array
    // ----------------------------------------------------------------
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem [0:(1<<ADDR_WIDTH)-1];

    // ----------------------------------------------------------------
    // Port A — registered read
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (a_en) begin
            a_rdata <= mem[a_addr];
        end
    end

    // ----------------------------------------------------------------
    // Port B — byte-enable write + registered read
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (b_en) begin
            if (b_we) begin
                if (b_wstrb[0]) mem[b_addr][7:0]   <= b_wdata[7:0];
                if (b_wstrb[1]) mem[b_addr][15:8]  <= b_wdata[15:8];
                if (b_wstrb[2]) mem[b_addr][23:16] <= b_wdata[23:16];
                if (b_wstrb[3]) mem[b_addr][31:24] <= b_wdata[31:24];
            end
            b_rdata <= mem[b_addr];
        end
    end

endmodule
