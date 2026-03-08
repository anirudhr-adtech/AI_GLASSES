`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem — Testbench
// Module: tb_fft_twiddle_rom
//////////////////////////////////////////////////////////////////////////////

module tb_fft_twiddle_rom;

    reg         clk;
    reg  [8:0]  addr;
    wire [15:0] re, im;

    integer pass_count = 0;
    integer fail_count = 0;

    fft_twiddle_rom uut (
        .clk    (clk),
        .addr_i (addr),
        .re_o   (re),
        .im_o   (im)
    );

    always #5 clk = ~clk;

    task check_range;
        input [255:0] name;
        input signed [15:0] actual;
        input signed [15:0] lo;
        input signed [15:0] hi;
        begin
            if (actual >= lo && actual <= hi) begin
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: %0s — got %0d, expected [%0d, %0d]", name, actual, lo, hi);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        clk  = 0;
        addr = 0;

        repeat (3) @(posedge clk);

        // Test 1: W_1024^0 = cos(0) - j*sin(0) = 1 + 0j
        // Re ~ 32767, Im ~ 0
        addr = 9'd0;
        @(posedge clk); @(posedge clk);
        check_range("W^0 re ~32767", $signed(re), 16'd32700, 16'd32767);
        check_range("W^0 im ~0", $signed(im), -16'd50, 16'd50);

        // Test 2: W_1024^256 = cos(pi/2) - j*sin(pi/2) = 0 - 1j
        // Re ~ 0, Im ~ -32768
        addr = 9'd256;
        @(posedge clk); @(posedge clk);
        check_range("W^256 re ~0", $signed(re), -16'd50, 16'd50);
        check_range("W^256 im ~-32768", $signed(im), -16'd32768, -16'd32700);

        // Test 3: W_1024^128 = cos(pi/4) - j*sin(pi/4) ~ 0.7071 - j*0.7071
        // 0.7071 * 32768 ~ 23170
        addr = 9'd128;
        @(posedge clk); @(posedge clk);
        check_range("W^128 re ~23170", $signed(re), 16'd23100, 16'd23250);
        check_range("W^128 im ~-23170", $signed(im), -16'd23250, -16'd23100);

        // Test 4: W_1024^512 doesn't exist (max is 511), check addr 511
        // cos(2*pi*511/1024) ~ cos(pi - pi/1024) ~ -0.9999
        addr = 9'd511;
        @(posedge clk); @(posedge clk);
        check_range("W^511 re near -1", $signed(re), -16'd32768, -16'd32700);

        $display("=== tb_fft_twiddle_rom: %0d PASSED, %0d FAILED ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $finish;
    end

endmodule
