`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem — Testbench
// Module: tb_log_compress
// Description: Self-checking testbench for log_compress.
//////////////////////////////////////////////////////////////////////////////

module tb_log_compress;

    reg        clk;
    reg        rst_n;
    reg        start;
    reg [31:0] mel_data;
    reg [5:0]  mel_idx;
    reg        mel_valid;
    wire       done;
    wire [15:0] log_data;
    wire [5:0]  log_idx;
    wire       log_valid;

    log_compress uut (
        .clk         (clk),
        .rst_n       (rst_n),
        .start_i     (start),
        .mel_data_i  (mel_data),
        .mel_idx_i   (mel_idx),
        .mel_valid_i (mel_valid),
        .done_o      (done),
        .log_data_o  (log_data),
        .log_idx_o   (log_idx),
        .log_valid_o (log_valid)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer errors;
    integer i;
    reg [15:0] results [0:39];
    reg [5:0]  out_count;
    reg        done_seen;

    // Global timeout guard
    initial begin
        #500000;
        $display("FAIL: Global timeout reached");
        $finish;
    end

    // Concurrent output collector: capture log_valid outputs at all times
    // Also capture done pulse
    always @(posedge clk) begin
        #1;
        if (log_valid) begin
            results[log_idx] = log_data;
            out_count = out_count + 1;
        end
        if (done)
            done_seen = 1;
    end

    // Task to feed mel values - wait for RTL to be ready (in S_CAPTURE)
    task feed_mel;
        input [5:0]  idx;
        input [31:0] val;
        begin
            @(posedge clk);
            mel_data  = val;
            mel_idx   = idx;
            mel_valid = 1;
            @(posedge clk);
            mel_valid = 0;
            // Wait enough cycles for the pipeline (NORM->LUT->COMPUTE->OUTPUT = 4+ cycles)
            repeat(8) @(posedge clk);
        end
    endtask

    initial begin
        $display("=== tb_log_compress: START ===");
        errors = 0;
        rst_n = 0;
        start = 0;
        mel_data = 0;
        mel_idx = 0;
        mel_valid = 0;
        out_count = 0;
        done_seen = 0;

        // Initialize results array
        for (i = 0; i < 40; i = i + 1)
            results[i] = 16'd0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (3) @(posedge clk);

        // Start the log_compress module
        start = 1;
        @(posedge clk); #1;
        start = 0;
        @(posedge clk); // Let FSM move to S_CAPTURE

        // Feed 40 mel values: first is 0, rest are known
        feed_mel(6'd0, 32'd0);         // log(0) = 0
        feed_mel(6'd1, 32'd1);         // log(1) = 0
        feed_mel(6'd2, 32'd256);       // log(256) ~ 5.5 * 256 = 1415
        feed_mel(6'd3, 32'd65536);     // log(65536) ~ 11.09 * 256 = 2839
        feed_mel(6'd4, 32'd1000000);   // log(1e6) ~ 13.8 * 256 = 3533

        // Fill remaining with constant
        for (i = 5; i < 40; i = i + 1) begin
            feed_mel(i[5:0], 32'd1024);
        end

        // Wait for done signal (may have already been captured by always block)
        if (!done_seen) begin : done_wait_blk
            integer done_countdown;
            done_countdown = 5000;
            while (!done_seen && done_countdown > 0) begin
                @(posedge clk); #1;
                done_countdown = done_countdown - 1;
            end
            if (done_countdown == 0) begin
                $display("FAIL: Timeout waiting for done");
                errors = errors + 1;
            end
        end

        // Allow last output to be captured
        repeat (3) @(posedge clk); #1;

        // Check outputs
        if (out_count != 6'd40) begin
            $display("FAIL: Expected 40 outputs, got %0d", out_count);
            errors = errors + 1;
        end

        // log(0) should be 0
        if (results[0] != 16'd0) begin
            $display("FAIL: log(0) = 0x%04X, expected 0x0000", results[0]);
            errors = errors + 1;
        end

        // log values should be monotonically increasing for increasing inputs
        // results[2] (log 256) < results[3] (log 65536) < results[4] (log 1e6)
        if ($signed(results[2]) >= $signed(results[3])) begin
            $display("FAIL: log(256)=%0d should be < log(65536)=%0d",
                     $signed(results[2]), $signed(results[3]));
            errors = errors + 1;
        end
        if ($signed(results[3]) >= $signed(results[4])) begin
            $display("FAIL: log(65536)=%0d should be < log(1e6)=%0d",
                     $signed(results[3]), $signed(results[4]));
            errors = errors + 1;
        end

        $display("  log(0)     = 0x%04X (%0d)", results[0], $signed(results[0]));
        $display("  log(1)     = 0x%04X (%0d)", results[1], $signed(results[1]));
        $display("  log(256)   = 0x%04X (%0d)", results[2], $signed(results[2]));
        $display("  log(65536) = 0x%04X (%0d)", results[3], $signed(results[3]));
        $display("  log(1e6)   = 0x%04X (%0d)", results[4], $signed(results[4]));

        if (errors == 0) begin
            $display("=== tb_log_compress: PASSED ===");
            $display("ALL TESTS PASSED");
        end else
            $display("=== tb_log_compress: FAILED (%0d errors) ===", errors);

        $finish;
    end

endmodule
