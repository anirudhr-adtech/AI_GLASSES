`timescale 1ns / 1ps
//============================================================================
// tb_i2c_tx_fifo.v — Self-checking testbench for i2c_tx_fifo
//============================================================================

module tb_i2c_tx_fifo;

    reg        clk, rst_n;
    reg  [7:0] wr_data;
    reg        wr_en, rd_en;
    wire [7:0] rd_data;
    wire       full, empty;
    wire [4:0] count;

    i2c_tx_fifo uut (
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

        // Check empty after reset
        check("empty after reset", empty == 1'b1);
        check("not full after reset", full == 1'b0);

        // Write 16 bytes (fill FIFO)
        for (i = 0; i < 16; i = i + 1) begin
            @(posedge clk);
            wr_data = i[7:0];
            wr_en = 1;
        end
        @(posedge clk);
        wr_en = 0;
        @(posedge clk); @(posedge clk);
        check("full after 16 writes", full == 1'b1);
        check("not empty when full", empty == 1'b0);

        // Try write when full (should be ignored)
        wr_data = 8'hFF;
        wr_en = 1;
        @(posedge clk);
        wr_en = 0;
        @(posedge clk);
        check("still full after overflow attempt", full == 1'b1);

        // Read all 16 bytes and verify order (FWFT: data valid before rd_en)
        for (i = 0; i < 16; i = i + 1) begin
            check("read data matches", rd_data == i[7:0]);
            rd_en = 1;
            @(posedge clk);
            rd_en = 0;
            @(posedge clk);
        end
        @(posedge clk); @(posedge clk);
        check("empty after reading all", empty == 1'b1);

        // Simultaneous read/write
        wr_data = 8'hAB;
        wr_en = 1;
        @(posedge clk);
        wr_en = 0;
        @(posedge clk);
        // FWFT: data available before rd_en
        check("simultaneous rw data", rd_data == 8'hAB);
        rd_en = 1;
        @(posedge clk);
        rd_en = 0;
        @(posedge clk);

        @(posedge clk);
        $display("========================================");
        if (fail_count == 0)
            $display("I2C TX FIFO TB: ALL %0d TESTS PASSED", pass_count);
        else
            $display("I2C TX FIFO TB: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        $finish;
    end

endmodule
