`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Camera Subsystem
// Module: pixel_fifo
// Description: Async FIFO with gray-coded pointers (PCLK → sys_clk)
//////////////////////////////////////////////////////////////////////////////

module pixel_fifo #(
    parameter DEPTH = 1024,
    parameter WIDTH = 16
)(
    // Write side (PCLK domain)
    input  wire              wr_clk,
    input  wire              wr_rst_n,
    input  wire              wr_en,
    input  wire [WIDTH-1:0]  wr_data,
    output reg               wr_full,
    // Read side (sys_clk domain)
    input  wire              rd_clk,
    input  wire              rd_rst_n,
    input  wire              rd_en,
    output reg  [WIDTH-1:0]  rd_data,
    output reg               rd_empty,
    // Status
    output reg               overflow_o
);

    localparam ADDR_W = $clog2(DEPTH);  // 10 for DEPTH=1024

    // Memory
    (* ram_style = "block" *)
    reg [WIDTH-1:0] mem [0:DEPTH-1];

    // Write-side gray counter
    wire [ADDR_W:0] wr_gray;
    wire [ADDR_W:0] wr_bin;

    // Read-side gray counter
    wire [ADDR_W:0] rd_gray;
    wire [ADDR_W:0] rd_bin;

    // Synchronized pointers
    reg [ADDR_W:0] wr_gray_rd_s1, wr_gray_rd_s2;  // wr gray synced to rd domain
    reg [ADDR_W:0] rd_gray_wr_s1, rd_gray_wr_s2;  // rd gray synced to wr domain

    // Write enable gated by not full
    wire wr_inc = wr_en & ~wr_full;
    wire rd_inc = rd_en & ~rd_empty;

    // Gray counters
    gray_counter #(.WIDTH(ADDR_W)) u_wr_cnt (
        .clk          (wr_clk),
        .rst_n        (wr_rst_n),
        .inc          (wr_inc),
        .gray_count_o (wr_gray),
        .bin_count_o  (wr_bin)
    );

    gray_counter #(.WIDTH(ADDR_W)) u_rd_cnt (
        .clk          (rd_clk),
        .rst_n        (rd_rst_n),
        .inc          (rd_inc),
        .gray_count_o (rd_gray),
        .bin_count_o  (rd_bin)
    );

    // Synchronize write pointer to read domain
    always @(posedge rd_clk) begin
        if (!rd_rst_n) begin
            wr_gray_rd_s1 <= {(ADDR_W+1){1'b0}};
            wr_gray_rd_s2 <= {(ADDR_W+1){1'b0}};
        end else begin
            wr_gray_rd_s1 <= wr_gray;
            wr_gray_rd_s2 <= wr_gray_rd_s1;
        end
    end

    // Synchronize read pointer to write domain
    always @(posedge wr_clk) begin
        if (!wr_rst_n) begin
            rd_gray_wr_s1 <= {(ADDR_W+1){1'b0}};
            rd_gray_wr_s2 <= {(ADDR_W+1){1'b0}};
        end else begin
            rd_gray_wr_s1 <= rd_gray;
            rd_gray_wr_s2 <= rd_gray_wr_s1;
        end
    end

    // Full flag (write domain): full when wr_gray matches rd_gray with MSBs inverted
    always @(posedge wr_clk) begin
        if (!wr_rst_n)
            wr_full <= 1'b0;
        else
            wr_full <= (wr_gray == {~rd_gray_wr_s2[ADDR_W:ADDR_W-1],
                                     rd_gray_wr_s2[ADDR_W-2:0]});
    end

    // Empty flag (read domain)
    always @(posedge rd_clk) begin
        if (!rd_rst_n)
            rd_empty <= 1'b1;
        else
            rd_empty <= (rd_gray == wr_gray_rd_s2);
    end

    // Memory write
    always @(posedge wr_clk) begin
        if (wr_inc)
            mem[wr_bin[ADDR_W-1:0]] <= wr_data;
    end

    // Memory read (registered)
    always @(posedge rd_clk) begin
        if (!rd_rst_n)
            rd_data <= {WIDTH{1'b0}};
        else if (rd_inc)
            rd_data <= mem[rd_bin[ADDR_W-1:0]];
    end

    // Overflow detection (write domain)
    always @(posedge wr_clk) begin
        if (!wr_rst_n)
            overflow_o <= 1'b0;
        else if (wr_en & wr_full)
            overflow_o <= 1'b1;
    end

endmodule
