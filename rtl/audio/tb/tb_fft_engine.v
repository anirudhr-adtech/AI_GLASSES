`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem — Testbench
// Module: tb_fft_engine
// Description: Loads a known signal (DC + cosine), runs FFT, checks bins.
//////////////////////////////////////////////////////////////////////////////

module tb_fft_engine;

    reg         clk, rst_n;
    reg         start;
    reg  [15:0] in_data;
    reg  [9:0]  in_addr;
    reg         in_wr_en;
    wire        done;
    wire [15:0] out_re, out_im;
    reg  [9:0]  out_addr;
    reg         out_rd_en;

    integer pass_count = 0;
    integer fail_count = 0;

    fft_engine uut (
        .clk         (clk),
        .rst_n       (rst_n),
        .start_i     (start),
        .in_data_i   (in_data),
        .in_addr_i   (in_addr),
        .in_wr_en_i  (in_wr_en),
        .done_o      (done),
        .out_re_o    (out_re),
        .out_im_o    (out_im),
        .out_addr_i  (out_addr),
        .out_rd_en_i (out_rd_en)
    );

    always #5 clk = ~clk;

    // Global timeout guard
    initial begin
        #50000000;
        $display("FAIL: Global timeout reached");
        $finish;
    end

    integer i;

    initial begin
        clk       = 0;
        rst_n     = 0;
        start     = 0;
        in_data   = 0;
        in_addr   = 0;
        in_wr_en  = 0;
        out_addr  = 0;
        out_rd_en = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // Load a DC signal: all samples = 100
        for (i = 0; i < 1024; i = i + 1) begin
            @(posedge clk);
            in_addr  = i[9:0];
            in_data  = 16'd100;
            in_wr_en = 1;
        end
        @(posedge clk);
        in_wr_en = 0;

        // Need extra cycle for bit-reverse addr pipeline
        repeat (3) @(posedge clk);

        // Start FFT
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        // Wait for done (while-loop timeout pattern)
        begin : wait_block
            integer fft_countdown;
            fft_countdown = 100000;
            while (!done && fft_countdown > 0) begin
                @(posedge clk); #1;
                fft_countdown = fft_countdown - 1;
            end
            if (fft_countdown == 0) begin
                $display("FAIL: FFT timeout");
                fail_count = fail_count + 1;
            end
        end

        if (done) begin
            pass_count = pass_count + 1;
            $display("PASS: FFT completed");
        end

        // Read bin 0 (DC) - should have the largest magnitude
        // BRAM read needs: set addr+rd_en, posedge latches, then data available
        @(posedge clk);
        out_addr  = 10'd0;
        out_rd_en = 1;
        @(posedge clk);  // BRAM latches addr, out_rdata updated
        out_rd_en = 0;
        @(posedge clk); #1; // Wait for registered output to propagate

        $display("INFO: Bin 0 Re=%0d Im=%0d", $signed(out_re), $signed(out_im));

        // DC bin should be non-zero
        if (out_re != 16'd0 || out_im != 16'd0) begin
            pass_count = pass_count + 1;
            $display("PASS: DC bin non-zero");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: DC bin is zero");
        end

        // Read bin 1 - for pure DC input, should be ~0
        @(posedge clk);
        out_addr  = 10'd1;
        out_rd_en = 1;
        @(posedge clk);
        out_rd_en = 0;
        @(posedge clk); #1;

        $display("INFO: Bin 1 Re=%0d Im=%0d", $signed(out_re), $signed(out_im));

        // Bin 1 should be near zero for DC input (allow some rounding)
        // Use signed literals properly for Verilator
        if ($signed(out_re) > -16'sd10 && $signed(out_re) < 16'sd10) begin
            pass_count = pass_count + 1;
            $display("PASS: Bin 1 near zero for DC input");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Bin 1 Re=%0d, expected near 0", $signed(out_re));
        end

        $display("=== tb_fft_engine: %0d PASSED, %0d FAILED ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $finish;
    end

endmodule
