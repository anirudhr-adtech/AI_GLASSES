`timescale 1ns/1ps
//============================================================================
// Module : axi_addr_decoder
// Project : AI_GLASSES — RISC-V Subsystem
// Description : Combinational address decoder for AXI4 crossbar with
//               registered output for clean timing. Decodes 4 slave
//               regions based on upper address nibble.
//============================================================================

module riscv_axi_addr_decoder #(
    parameter ADDR_WIDTH = 32
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire [ADDR_WIDTH-1:0] addr_i,
    output wire [1:0]            slave_sel_o
);

    reg [1:0] slave_sel_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            slave_sel_r <= 2'd0;
        end else begin
            case (addr_i[31:28])
                4'h0:           slave_sel_r <= 2'd0;  // S0: Boot ROM  0x0xxx_xxxx
                4'h1:           slave_sel_r <= 2'd1;  // S1: SRAM      0x1xxx_xxxx
                4'h2, 4'h3, 4'h4:
                                slave_sel_r <= 2'd2;  // S2: Periph    0x2xxx-0x4xxx
                default:        slave_sel_r <= 2'd3;  // S3: DDR       0x8xxx+
            endcase
        end
    end

    assign slave_sel_o = slave_sel_r;

endmodule
