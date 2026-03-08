`timescale 1ns / 1ps
//============================================================================
// tb_i2c_shift_reg.v — Self-checking testbench for i2c_shift_reg
//============================================================================

module tb_i2c_shift_reg;

    reg        clk, rst_n;
    reg        load, shift_en;
    reg  [7:0] tx_data;
    wire [7:0] rx_data;
    wire       sda_o, sda_oe;
    reg        sda_i;
    wire       bit_done;

    i2c_shift_reg uut (
        .clk        (clk),
        .rst_n      (rst_n),
        .load       (load),
        .shift_en   (shift_en),
        .tx_data_i  (tx_data),
        .rx_data_o  (rx_data),
        .sda_o      (sda_o),
        .sda_oe_o   (sda_oe),
        .sda_i      (sda_i),
        .bit_done_o (bit_done)
    );

    integer pass_count = 0;
    integer fail_count = 0;

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

    reg [7:0] rx_pattern;
    integer i;

    initial begin
        rst_n = 0; load = 0; shift_en = 0; tx_data = 0; sda_i = 1;
        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Load 0xA5 = 10100101
        tx_data = 8'hA5;
        load = 1;
        @(posedge clk);
        load = 0;

        // After load, MSB (1) should be driven: sda_oe=0 (release=1)
        check("MSB=1 releases SDA", sda_oe == 1'b0);

        // Shift out all 8 bits while shifting in a known pattern (0x3C)
        rx_pattern = 8'h3C; // 00111100
        for (i = 7; i >= 0; i = i - 1) begin
            sda_i = rx_pattern[i];
            shift_en = 1;
            @(posedge clk);
            shift_en = 0;
            @(posedge clk);
        end

        check("bit_done asserted after 8 shifts", bit_done == 1'b1);
        @(posedge clk);
        check("RX data correct", rx_data == 8'h3C);

        // Load 0x00 — all zeros, SDA should be pulled low for all bits
        tx_data = 8'h00;
        load = 1;
        @(posedge clk);
        load = 0;
        check("MSB=0 pulls SDA low", sda_oe == 1'b1);

        @(posedge clk);
        $display("========================================");
        if (fail_count == 0)
            $display("I2C SHIFT REG TB: ALL %0d TESTS PASSED", pass_count);
        else
            $display("I2C SHIFT REG TB: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        $finish;
    end

endmodule
