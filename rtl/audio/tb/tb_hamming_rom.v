`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem — Testbench
// Module: tb_hamming_rom
//////////////////////////////////////////////////////////////////////////////

module tb_hamming_rom;

    reg         clk;
    reg  [9:0]  addr;
    wire [15:0] data;

    integer pass_count = 0;
    integer fail_count = 0;

    hamming_rom uut (
        .clk    (clk),
        .addr_i (addr),
        .data_o (data)
    );

    always #5 clk = ~clk;

    task check_range;
        input [255:0] name;
        input [15:0]  actual;
        input [15:0]  lo;
        input [15:0]  hi;
        begin
            if (actual >= lo && actual <= hi) begin
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: %0s — got %0d, expected [%0d, %0d]", name, actual, lo, hi);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task check_val;
        input [255:0] name;
        input [15:0]  actual;
        input [15:0]  expected;
        begin
            if (actual === expected) begin
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: %0s — got %0d, expected %0d", name, actual, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        clk  = 0;
        addr = 0;

        // Wait for ROM init
        repeat (3) @(posedge clk);

        // Test 1: Address 0 — w(0) = 0.54 - 0.46 = 0.08 -> 0.08*32768 ~ 2621
        addr = 10'd0;
        @(posedge clk); @(posedge clk);
        check_range("w(0) ~2621", data, 16'd2500, 16'd2750);

        // Test 2: Mid-point n=319 — w(319) ~ 0.9986 -> ~32722
        addr = 10'd319;
        @(posedge clk); @(posedge clk);
        check_range("w(319) near peak", data, 16'd32000, 16'd32768);

        // Test 3: Address 639 — w(639) = 0.08 ~ 2621 (symmetric)
        addr = 10'd639;
        @(posedge clk); @(posedge clk);
        check_range("w(639) ~2621", data, 16'd2500, 16'd2750);

        // Test 4: Symmetry: w(100) should ~ w(539)
        addr = 10'd100;
        @(posedge clk); @(posedge clk);
        begin : sym_test
            reg [15:0] val_100;
            val_100 = data;
            addr = 10'd539;
            @(posedge clk); @(posedge clk);
            // Allow +/- 2 for rounding
            if (data >= val_100 - 2 && data <= val_100 + 2) begin
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: Symmetry w(100)=%0d vs w(539)=%0d", val_100, data);
                fail_count = fail_count + 1;
            end
        end

        // Test 5: Out-of-range address returns 0
        addr = 10'd700;
        @(posedge clk); @(posedge clk);
        check_val("Out of range = 0", data, 16'd0);

        $display("=== tb_hamming_rom: %0d PASSED, %0d FAILED ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $finish;
    end

endmodule
