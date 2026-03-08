`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Camera Subsystem
// Testbench: tb_gray_counter
//////////////////////////////////////////////////////////////////////////////

module tb_gray_counter;

    parameter WIDTH = 4;  // Smaller for faster sim

    reg               clk;
    reg               rst_n;
    reg               inc;
    wire [WIDTH:0]    gray_count_o;
    wire [WIDTH:0]    bin_count_o;

    integer err_count;
    integer i;

    gray_counter #(.WIDTH(WIDTH)) uut (
        .clk          (clk),
        .rst_n        (rst_n),
        .inc          (inc),
        .gray_count_o (gray_count_o),
        .bin_count_o  (bin_count_o)
    );

    // Clock: 10ns period
    initial clk = 0;
    always #5 clk = ~clk;

    // Gray-to-binary helper for checking
    function [WIDTH:0] gray2bin;
        input [WIDTH:0] gray;
        integer j;
        begin
            gray2bin[WIDTH] = gray[WIDTH];
            for (j = WIDTH-1; j >= 0; j = j - 1)
                gray2bin[j] = gray2bin[j+1] ^ gray[j];
        end
    endfunction

    initial begin
        err_count = 0;
        rst_n = 0;
        inc   = 0;

        // Reset
        @(posedge clk); @(posedge clk);
        #1; rst_n = 1;
        @(posedge clk); #1;

        // Check reset values
        if (bin_count_o !== 0) begin
            $display("FAIL: bin_count not 0 after reset");
            err_count = err_count + 1;
        end
        if (gray_count_o !== 0) begin
            $display("FAIL: gray_count not 0 after reset");
            err_count = err_count + 1;
        end

        // Count through full range: assert inc for exactly 16 clocks
        inc = 1;
        repeat (1 << WIDTH) begin
            @(posedge clk);
        end
        #1; inc = 0;
        @(posedge clk); #1;

        // Verify final count
        if (bin_count_o !== (1 << WIDTH)) begin
            $display("FAIL: bin_count = %0d, expected %0d", bin_count_o, (1 << WIDTH));
            err_count = err_count + 1;
        end

        // Verify gray code is valid (adjacent values differ by 1 bit)
        // Reset and re-count, checking each step
        rst_n = 0;
        @(posedge clk); @(posedge clk);
        #1; rst_n = 1;
        @(posedge clk); #1;

        begin : gray_check
            reg [WIDTH:0] prev_gray;
            reg [WIDTH:0] xor_val;
            integer bit_cnt;
            integer k;

            prev_gray = gray_count_o;
            for (i = 0; i < (1 << WIDTH); i = i + 1) begin
                inc = 1;
                @(posedge clk); #1;
                // Check only 1 bit changed
                xor_val = prev_gray ^ gray_count_o;
                bit_cnt = 0;
                for (k = 0; k <= WIDTH; k = k + 1)
                    bit_cnt = bit_cnt + xor_val[k];
                if (bit_cnt !== 1) begin
                    $display("FAIL: at step %0d, gray changed by %0d bits (prev=%b, cur=%b)",
                             i, bit_cnt, prev_gray, gray_count_o);
                    err_count = err_count + 1;
                end
                // Also check gray2bin matches binary
                if (gray2bin(gray_count_o) !== bin_count_o) begin
                    $display("FAIL: gray2bin mismatch at step %0d", i);
                    err_count = err_count + 1;
                end
                prev_gray = gray_count_o;
            end
        end

        // Summary
        if (err_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("FAIL: tb_gray_counter — %0d errors", err_count);

        $finish;
    end

endmodule
