`timescale 1ns / 1ps
//============================================================================
// tb_spi_shift_reg.v — Self-checking testbench for spi_shift_reg
//============================================================================

module tb_spi_shift_reg;

    reg        clk, rst_n;
    reg        load, shift_en;
    reg  [7:0] tx_data;
    wire [7:0] rx_data;
    wire       mosi;
    reg        miso;
    wire       bit_done;

    spi_shift_reg uut (
        .clk        (clk),
        .rst_n      (rst_n),
        .load       (load),
        .shift_en   (shift_en),
        .tx_data_i  (tx_data),
        .rx_data_o  (rx_data),
        .mosi_o     (mosi),
        .miso_i     (miso),
        .bit_done_o (bit_done)
    );

    integer pass_count = 0;
    integer fail_count = 0;
    integer i;
    reg [7:0] captured_mosi;

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
        rst_n = 0; load = 0; shift_en = 0; tx_data = 0; miso = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Load 0xA5
        tx_data = 8'hA5;
        load = 1;
        @(posedge clk);
        load = 0;

        // Check MOSI = MSB
        check("MOSI = MSB after load", mosi == 1'b1); // 0xA5 MSB = 1

        // Shift 8 bits, feed MISO = 0x3C (00111100)
        captured_mosi = 8'd0;
        for (i = 7; i >= 0; i = i - 1) begin
            miso = (8'h3C >> i) & 1'b1;
            captured_mosi = {captured_mosi[6:0], mosi};
            shift_en = 1;
            @(posedge clk);
            shift_en = 0;
            @(posedge clk);
        end

        check("bit_done asserted", bit_done == 1'b1);
        check("RX data correct (0x3C)", rx_data == 8'h3C);
        // MOSI should have shifted out 0xA5
        check("TX shifted out (0xA5)", captured_mosi == 8'hA5);

        @(posedge clk);
        $display("========================================");
        if (fail_count == 0)
            $display("SPI SHIFT REG TB: ALL %0d TESTS PASSED", pass_count);
        else
            $display("SPI SHIFT REG TB: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        $finish;
    end

endmodule
