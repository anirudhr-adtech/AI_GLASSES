`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Camera Subsystem
// Module: gray_counter
// Description: Gray-code counter for async FIFO pointers
//////////////////////////////////////////////////////////////////////////////

module gray_counter #(
    parameter WIDTH = 10
)(
    input  wire                clk,
    input  wire                rst_n,
    input  wire                inc,
    output reg  [WIDTH:0]      gray_count_o,
    output reg  [WIDTH:0]      bin_count_o
);

    wire [WIDTH:0] bin_next;
    wire [WIDTH:0] gray_next;

    // Binary increment
    assign bin_next  = bin_count_o + {{WIDTH{1'b0}}, inc};

    // Binary-to-Gray conversion: gray = bin ^ (bin >> 1)
    assign gray_next = bin_next ^ (bin_next >> 1);

    always @(posedge clk) begin
        if (!rst_n) begin
            bin_count_o  <= {(WIDTH+1){1'b0}};
            gray_count_o <= {(WIDTH+1){1'b0}};
        end else begin
            bin_count_o  <= bin_next;
            gray_count_o <= gray_next;
        end
    end

endmodule
