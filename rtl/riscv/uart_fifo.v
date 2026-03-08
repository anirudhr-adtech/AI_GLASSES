`timescale 1ns/1ps
//============================================================================
// Module : uart_fifo
// Project : AI_GLASSES — RISC-V Subsystem
// Description : Synchronous FIFO with parameterized depth and width.
//               Pointer-based implementation with full/empty/count outputs.
//============================================================================
module uart_fifo #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 16,
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    wr_en,
    input  wire                    rd_en,
    input  wire [DATA_WIDTH-1:0]   din,
    output reg  [DATA_WIDTH-1:0]   dout,
    output reg                     full,
    output reg                     empty,
    output reg  [ADDR_WIDTH:0]     count
);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [ADDR_WIDTH-1:0] wr_ptr;
    reg [ADDR_WIDTH-1:0] rd_ptr;
    reg [ADDR_WIDTH:0]   cnt;

    // Combinational next-state
    reg [ADDR_WIDTH-1:0] wr_ptr_next;
    reg [ADDR_WIDTH-1:0] rd_ptr_next;
    reg [ADDR_WIDTH:0]   cnt_next;

    wire do_write;
    wire do_read;

    assign do_write = wr_en & ~cnt[ADDR_WIDTH];   // write when not full
    assign do_read  = rd_en & (cnt != {(ADDR_WIDTH+1){1'b0}});  // read when not empty

    always @(*) begin
        wr_ptr_next = wr_ptr;
        rd_ptr_next = rd_ptr;
        cnt_next    = cnt;

        case ({do_write, do_read})
            2'b10: begin
                wr_ptr_next = (wr_ptr == DEPTH - 1) ? {ADDR_WIDTH{1'b0}} : wr_ptr + 1'b1;
                cnt_next    = cnt + 1'b1;
            end
            2'b01: begin
                rd_ptr_next = (rd_ptr == DEPTH - 1) ? {ADDR_WIDTH{1'b0}} : rd_ptr + 1'b1;
                cnt_next    = cnt - 1'b1;
            end
            2'b11: begin
                wr_ptr_next = (wr_ptr == DEPTH - 1) ? {ADDR_WIDTH{1'b0}} : wr_ptr + 1'b1;
                rd_ptr_next = (rd_ptr == DEPTH - 1) ? {ADDR_WIDTH{1'b0}} : rd_ptr + 1'b1;
                cnt_next    = cnt; // simultaneous read+write, count unchanged
            end
            default: begin
                // no operation
            end
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr <= {ADDR_WIDTH{1'b0}};
            rd_ptr <= {ADDR_WIDTH{1'b0}};
            cnt    <= {(ADDR_WIDTH+1){1'b0}};
            full   <= 1'b0;
            empty  <= 1'b1;
            count  <= {(ADDR_WIDTH+1){1'b0}};
            dout   <= {DATA_WIDTH{1'b0}};
        end else begin
            wr_ptr <= wr_ptr_next;
            rd_ptr <= rd_ptr_next;
            cnt    <= cnt_next;
            full   <= (cnt_next == DEPTH);
            empty  <= (cnt_next == {(ADDR_WIDTH+1){1'b0}});
            count  <= cnt_next;

            if (do_write)
                mem[wr_ptr] <= din;

            if (do_read)
                dout <= mem[rd_ptr];
        end
    end

endmodule
