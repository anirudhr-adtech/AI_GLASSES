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
        @(posedge clk); #1;
        load = 0;

        // Check MOSI = MSB
        check("MOSI = MSB after load", mosi == 1'b1); // 0xA5 MSB = 1

        // Shift 8 bits, feed MISO = 0x3C (00111100) MSB-first
        // 0xA5 = 10100101. After load, mosi=bit7=1 (already checked above).
        // Each shift_en posedge: RTL does tx_shift <= {tx_shift[6:0],0}, mosi <= tx_shift[6]
        //   and rx_shift <= {rx_shift[6:0], miso_i}
        captured_mosi = 8'd0;
        captured_mosi[7] = mosi; // MSB captured from load
        for (i = 7; i >= 0; i = i - 1) begin
            miso = (8'h3C >> i) & 1'b1;  // feed MSB first
            shift_en = 1;
            @(posedge clk); #1;
            // After this posedge, mosi shows NEXT tx bit
            if (i > 0) captured_mosi[i-1] = mosi;
            shift_en = 0;
            if (i > 0) begin
                @(posedge clk); #1;
            end
        end

        // bit_done pulses on the clock where bit_cnt==7 && shift_en
        // We just sampled #1 after that posedge, so bit_done should be 1
        check("bit_done asserted", bit_done == 1'b1);
        check("RX data correct (0x3C)", rx_data == 8'h3C);
        check("TX shifted out (0xA5)", captured_mosi == 8'hA5);

        @(posedge clk);
        $display("========================================");
        if (fail_count == 0) begin
            $display("SPI SHIFT REG TB: ALL %0d TESTS PASSED", pass_count);
            $display("ALL TESTS PASSED");
        end else
            $display("SPI SHIFT REG TB: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        $finish;
    end

endmodule
