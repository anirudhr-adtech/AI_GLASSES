`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Camera Subsystem
// Module: line_buffer
// Description: Dual-line BRAM buffer for bilinear vertical interpolation
//////////////////////////////////////////////////////////////////////////////

module line_buffer #(
    parameter MAX_WIDTH = 640
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        wr_en,
    input  wire        wr_line_sel,   // 0 = line A, 1 = line B
    input  wire [9:0]  wr_addr,
    input  wire [23:0] wr_data,
    input  wire        rd_line_sel,   // 0 = line A, 1 = line B
    input  wire [9:0]  rd_addr,
    output reg  [23:0] rd_data
);

    // Two BRAM blocks for dual-line storage
    (* ram_style = "block" *)
    reg [23:0] line_a [0:MAX_WIDTH-1];

    (* ram_style = "block" *)
    reg [23:0] line_b [0:MAX_WIDTH-1];

    // Write logic
    always @(posedge clk) begin
        if (wr_en) begin
            if (!wr_line_sel)
                line_a[wr_addr] <= wr_data;
            else
                line_b[wr_addr] <= wr_data;
        end
    end

    // Read logic (registered output)
    always @(posedge clk) begin
        if (!rst_n)
            rd_data <= 24'd0;
        else begin
            if (!rd_line_sel)
                rd_data <= line_a[rd_addr];
            else
                rd_data <= line_b[rd_addr];
        end
    end

endmodule
