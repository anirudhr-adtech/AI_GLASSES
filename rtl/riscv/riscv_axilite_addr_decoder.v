`timescale 1ns/1ps
//============================================================================
// Module : axilite_addr_decoder
// Project : AI_GLASSES — RISC-V Subsystem
// Description : Address decoder for AXI-Lite peripheral fabric. Decodes
//               8 peripheral slaves using bits [15:8] within the
//               0x2000_0000 region. Reports decode_error for unmapped.
//============================================================================

module riscv_axilite_addr_decoder #(
    parameter ADDR_WIDTH = 32,
    parameter NUM_SLAVES = 9
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire [ADDR_WIDTH-1:0] addr_i,
    output wire [3:0]            slave_sel_o,
    output wire                  decode_error_o
);

    reg [3:0] slave_sel_r;
    reg       decode_error_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            slave_sel_r    <= 4'd0;
            decode_error_r <= 1'b0;
        end else begin
            // Default: decode error
            decode_error_r <= 1'b0;
            slave_sel_r    <= 4'd0;

            // Check if address is in the peripheral range 0x2000_0000 - 0x2000_08FF
            if (addr_i[31:16] == 16'h2000 && addr_i[15:8] < NUM_SLAVES[7:0]) begin
                slave_sel_r <= {1'b0, addr_i[11:8]};
            end else begin
                decode_error_r <= 1'b1;
            end
        end
    end

    assign slave_sel_o    = slave_sel_r;
    assign decode_error_o = decode_error_r;

endmodule
