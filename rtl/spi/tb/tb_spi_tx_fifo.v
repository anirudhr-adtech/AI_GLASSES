`timescale 1ns / 1ps
//============================================================================
// tb_spi_tx_fifo.v — Self-checking testbench for spi_tx_fifo
//============================================================================

module tb_spi_tx_fifo;

    reg        clk, rst_n;
    reg  [7:0] wr_data;
    reg        wr_en, rd_en;
    wire [7:0] rd_data;
    wire       full, empty;
    wire [4:0] count;

    spi_tx_fifo uut (
        .clk       (clk),
        .rst_n     (rst_n),
        .wr_data_i (wr_data),
        .wr_en_i   (wr_en),
        .rd_data_o (rd_data),
        .rd_en_i   (rd_en),
        .full_o    (full),
        .empty_o   (empty),
        .count_o   (count)
    );

    integer pass_count = 0;
    integer fail_count = 0;
    integer i;

    task check;
        input [255:0] msg;
        input         cond;
    begin
        if (cond) pass_count = pass_count + 1;
        else begin
            fail_count = fail_count + 1;
            $display("FAIL: %0s at time %0t", msg, $time);
        end
    end
    endtask

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        rst_n = 0; wr_en = 0; rd_en = 0; wr_data = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        check("empty after reset", empty == 1'b1);

        // Write and read 4 bytes
        for (i = 0; i < 4; i = i + 1) begin
            wr_data = 8'h10 + i[7:0];
            wr_en = 1;
            @(posedge clk);
        end
        wr_en = 0;
        @(posedge clk); @(posedge clk);
        check("not empty after writes", empty == 1'b0);

        for (i = 0; i < 4; i = i + 1) begin
            // FWFT: rd_data is valid before rd_en; check then advance
            check("read data matches", rd_data == (8'h10 + i[7:0]));
            @(posedge clk); #1;
            rd_en = 1;
            @(posedge clk); #1;
            rd_en = 0;
        end
        @(posedge clk); @(posedge clk);
        check("empty after read all", empty == 1'b1);

        // Fill completely
        for (i = 0; i < 16; i = i + 1) begin
            wr_data = i[7:0];
            wr_en = 1;
            @(posedge clk);
        end
        wr_en = 0;
        @(posedge clk); @(posedge clk);
        check("full after 16 writes", full == 1'b1);

        $display("========================================");
        if (fail_count == 0)
            $display("SPI TX FIFO TB: ALL %0d TESTS PASSED", pass_count);
        else
            $display("SPI TX FIFO TB: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        $finish;
    end

endmodule
