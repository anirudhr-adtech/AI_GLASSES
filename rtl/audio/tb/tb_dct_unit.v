`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem — Testbench
// Module: tb_dct_unit
// Description: Self-checking testbench for dct_unit.
//////////////////////////////////////////////////////////////////////////////

module tb_dct_unit;

    reg        clk;
    reg        rst_n;
    reg        start;
    reg [15:0] log_data;
    reg [5:0]  log_idx;
    reg        log_valid;
    wire       done;
    wire [15:0] mfcc_data;
    wire [3:0]  mfcc_idx;
    wire       mfcc_valid;

    dct_unit uut (
        .clk          (clk),
        .rst_n        (rst_n),
        .start_i      (start),
        .log_data_i   (log_data),
        .log_idx_i    (log_idx),
        .log_valid_i  (log_valid),
        .done_o       (done),
        .mfcc_data_o  (mfcc_data),
        .mfcc_idx_o   (mfcc_idx),
        .mfcc_valid_o (mfcc_valid)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer errors;
    integer i;
    reg [15:0] mfcc_results [0:9];
    reg [3:0]  out_count;

    initial begin
        $display("=== tb_dct_unit: START ===");
        errors = 0;
        rst_n = 0;
        start = 0;
        log_data = 0;
        log_idx = 0;
        log_valid = 0;
        out_count = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (3) @(posedge clk);

        // Test 1: Unit impulse at m=0 -> DCT should produce cosine basis
        start = 1;
        @(posedge clk);
        start = 0;

        // Feed 40 log-mel values: impulse at m=0
        for (i = 0; i < 40; i = i + 1) begin
            @(posedge clk);
            log_data  = (i == 0) ? 16'h0100 : 16'h0000; // 1.0 in Q8.8
            log_idx   = i[5:0];
            log_valid = 1;
            @(posedge clk);
            log_valid = 0;
        end

        // Collect outputs (while-loop timeout pattern)
        begin : collect_blk
            integer collect_countdown;
            collect_countdown = 10000;
            while (!done && collect_countdown > 0) begin
                @(posedge clk);
                collect_countdown = collect_countdown - 1;
                if (mfcc_valid) begin
                    mfcc_results[mfcc_idx] = mfcc_data;
                    out_count = out_count + 1;
                end
            end
            if (collect_countdown == 0) begin
                $display("FAIL: Timeout");
                errors = errors + 1;
            end
        end

        // Should have 10 outputs
        if (out_count != 4'd10) begin
            $display("FAIL: Expected 10 MFCC outputs, got %0d", out_count);
            errors = errors + 1;
        end

        // Print results
        for (i = 0; i < 10; i = i + 1) begin
            $display("  MFCC[%0d] = 0x%04X (%0d)", i, mfcc_results[i], $signed(mfcc_results[i]));
        end

        // MFCC[0] should be positive (sum of cos(0) = 1.0 * input[0])
        if ($signed(mfcc_results[0]) <= 0) begin
            $display("FAIL: MFCC[0] should be > 0 for unit impulse at m=0");
            errors = errors + 1;
        end

        // Test 2: Constant input -> only c=0 should be non-zero
        out_count = 0;
        repeat (3) @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        for (i = 0; i < 40; i = i + 1) begin
            @(posedge clk);
            log_data  = 16'h0100; // 1.0 in Q8.8 for all
            log_idx   = i[5:0];
            log_valid = 1;
            @(posedge clk);
            log_valid = 0;
        end

        // Collect outputs test 2 (while-loop timeout pattern)
        begin : collect2_blk
            integer collect2_countdown;
            collect2_countdown = 10000;
            while (!done && collect2_countdown > 0) begin
                @(posedge clk);
                collect2_countdown = collect2_countdown - 1;
                if (mfcc_valid) begin
                    mfcc_results[mfcc_idx] = mfcc_data;
                    out_count = out_count + 1;
                end
            end
        end

        // For constant input, MFCC[0] should be large, others ~0
        $display("  Constant input test:");
        for (i = 0; i < 10; i = i + 1) begin
            $display("  MFCC[%0d] = %0d", i, $signed(mfcc_results[i]));
        end

        if ($signed(mfcc_results[0]) <= 0) begin
            $display("FAIL: MFCC[0] should be positive for constant input");
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("=== tb_dct_unit: PASSED ===");
            $display("ALL TESTS PASSED");
        end else
            $display("=== tb_dct_unit: FAILED (%0d errors) ===", errors);

        $finish;
    end

endmodule
