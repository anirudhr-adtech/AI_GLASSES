`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Camera Subsystem
// Module: frame_buf_ctrl
// Description: Double-buffer pointer management for DDR frame buffers
//////////////////////////////////////////////////////////////////////////////

module frame_buf_ctrl (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] buf_a_addr_i,
    input  wire [31:0] buf_b_addr_i,
    input  wire        active_buf_i,  // 0 = A write / B read, 1 = B write / A read
    input  wire        swap_i,        // Pulse to toggle active buffer
    output reg  [31:0] wr_addr_o,
    output reg  [31:0] rd_addr_o
);

    reg active_buf;

    // Compute next active_buf combinationally so mux and register
    // update coherently on the same clock edge.
    wire active_buf_next = swap_i ? ~active_buf : active_buf;

    always @(posedge clk) begin
        if (!rst_n) begin
            active_buf <= 1'b0;
            wr_addr_o  <= 32'd0;
            rd_addr_o  <= 32'd0;
        end else begin
            active_buf <= active_buf_next;

            // Mux write/read addresses based on active buffer
            // active_buf 0: write to A, read from B
            // active_buf 1: write to B, read from A
            if (!active_buf_next) begin
                wr_addr_o <= buf_a_addr_i;
                rd_addr_o <= buf_b_addr_i;
            end else begin
                wr_addr_o <= buf_b_addr_i;
                rd_addr_o <= buf_a_addr_i;
            end
        end
    end

endmodule
