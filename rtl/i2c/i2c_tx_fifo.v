`timescale 1ns / 1ps
//============================================================================
// i2c_tx_fifo.v
// AI_GLASSES — I2C Master
// 16-byte TX FIFO with synchronous read/write.
//============================================================================

module i2c_tx_fifo (
    input  wire        clk,
    input  wire        rst_n,

    // Write interface
    input  wire [7:0]  wr_data_i,
    input  wire        wr_en_i,

    // Read interface
    output reg  [7:0]  rd_data_o,
    input  wire        rd_en_i,

    // Status
    output reg         full_o,
    output reg         empty_o,
    output reg  [4:0]  count_o
);

    reg [7:0] mem [0:15];
    reg [3:0] wr_ptr;
    reg [3:0] rd_ptr;
    reg [4:0] count;

    wire do_write = wr_en_i & ~full_o;
    wire do_read  = rd_en_i & ~empty_o;

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr  <= 4'd0;
            rd_ptr  <= 4'd0;
            count   <= 5'd0;
            full_o  <= 1'b0;
            empty_o <= 1'b1;
            count_o <= 5'd0;
            rd_data_o <= 8'd0;
        end else begin
            if (do_write) begin
                mem[wr_ptr] <= wr_data_i;
                wr_ptr <= wr_ptr + 4'd1;
            end

            if (do_read) begin
                rd_data_o <= mem[rd_ptr];
                rd_ptr <= rd_ptr + 4'd1;
            end

            case ({do_write, do_read})
                2'b10:   count <= count + 5'd1;
                2'b01:   count <= count - 5'd1;
                default: count <= count;
            endcase

            // Register status outputs
            if (do_write && !do_read)
                count_o <= count + 5'd1;
            else if (!do_write && do_read)
                count_o <= count - 5'd1;
            else
                count_o <= count;

            full_o  <= (do_write && !do_read) ? (count == 5'd15) :
                       (!do_write && do_read) ? 1'b0 : (count == 5'd16);
            empty_o <= (!do_write && do_read) ? (count == 5'd1) :
                       (do_write && !do_read) ? 1'b0 : (count == 5'd0);
        end
    end

endmodule
