`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem
// Module: audio_fifo
// Description: 1024x16-bit synchronous circular FIFO with overrun detection.
//////////////////////////////////////////////////////////////////////////////

module audio_fifo #(
    parameter DEPTH = 1024,
    parameter WIDTH = 16
)(
    input  wire                clk,
    input  wire                rst_n,
    input  wire                wr_en,
    input  wire [WIDTH-1:0]    wr_data,
    input  wire                rd_en,
    output reg  [WIDTH-1:0]    rd_data,
    output wire                full,
    output wire                empty,
    output wire [10:0]         fill_level,
    output reg                 overrun
);

    localparam ADDR_W = $clog2(DEPTH);

    (* ram_style = "block" *)
    reg [WIDTH-1:0] mem [0:DEPTH-1];

    reg [ADDR_W:0] wr_ptr;
    reg [ADDR_W:0] rd_ptr;

    wire [ADDR_W:0] count;
    assign count      = wr_ptr - rd_ptr;
    assign fill_level = count[10:0];
    assign full       = (count == DEPTH);
    assign empty      = (count == {(ADDR_W+1){1'b0}});

    // Write logic
    always @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr  <= {(ADDR_W+1){1'b0}};
            overrun <= 1'b0;
        end else begin
            if (wr_en) begin
                if (full) begin
                    overrun <= 1'b1;
                end else begin
                    mem[wr_ptr[ADDR_W-1:0]] <= wr_data;
                    wr_ptr <= wr_ptr + 1'b1;
                end
            end
        end
    end

    // Read logic
    always @(posedge clk) begin
        if (!rst_n) begin
            rd_ptr  <= {(ADDR_W+1){1'b0}};
            rd_data <= {WIDTH{1'b0}};
        end else begin
            if (rd_en && !empty) begin
                rd_data <= mem[rd_ptr[ADDR_W-1:0]];
                rd_ptr  <= rd_ptr + 1'b1;
            end
        end
    end

endmodule
