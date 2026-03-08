`timescale 1ns / 1ps
//============================================================================
// tb_spi_rx_fifo.v — Self-checking testbench for spi_rx_fifo
//============================================================================

module tb_spi_rx_fifo;

    reg        clk, rst_n;
    reg  [7:0] wr_data;
    reg        wr_en, rd_en;
    wire [7:0] rd_data;
    wire       full, empty;
    wire [4:0] count;

    spi_rx_fifo uut (
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
        check("not full after reset", full == 1'b0);

        // Write 8 entries
        for (i = 0; i < 8; i = i + 1) begin
            wr_data = 8'hC0 + i[7:0];
            wr_en = 1;
            @(posedge clk);
        end
        wr_en = 0;
        @(posedge clk); @(posedge clk);
        check("not empty", empty == 1'b0);

        // Read back (FWFT: check data before asserting rd_en)
        for (i = 0; i < 8; i = i + 1) begin
            check("rx data matches", rd_data == (8'hC0 + i[7:0]));
            @(posedge clk); #1;
            rd_en = 1;
            @(posedge clk); #1;
            rd_en = 0;
        end
        @(posedge clk); @(posedge clk);
        check("empty after reads", empty == 1'b1);

        $display("========================================");
        if (fail_count == 0)
            $display("SPI RX FIFO TB: ALL %0d TESTS PASSED", pass_count);
        else
            $display("SPI RX FIFO TB: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        $finish;
    end

endmodule
