`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem — Testbench
// Module: tb_audio_window
//////////////////////////////////////////////////////////////////////////////

module tb_audio_window;

    reg         clk, rst_n;
    reg         start;
    wire        fifo_rd_en;
    reg  [15:0] fifo_rd_data;
    wire        done;
    wire [15:0] out_data;
    wire        out_valid;
    wire [9:0]  out_addr;

    integer pass_count = 0;
    integer fail_count = 0;

    audio_window uut (
        .clk            (clk),
        .rst_n          (rst_n),
        .start_i        (start),
        .fifo_rd_en_o   (fifo_rd_en),
        .fifo_rd_data_i (fifo_rd_data),
        .done_o         (done),
        .out_data_o     (out_data),
        .out_valid_o    (out_valid),
        .out_addr_o     (out_addr)
    );

    always #5 clk = ~clk;

    // Model FIFO: always return constant value 16'h4000 (= 0.5 in Q1.15)
    always @(posedge clk) begin
        if (fifo_rd_en)
            fifo_rd_data <= 16'h4000;
    end

    integer out_count;
    integer zero_count;
    reg [9:0] last_addr;

    initial begin
        clk     = 0;
        rst_n   = 0;
        start   = 0;
        fifo_rd_data = 16'd0;
        out_count  = 0;
        zero_count = 0;
        last_addr  = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // Start windowing
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        // Wait for outputs (while-loop timeout pattern)
        begin : wait_block
            integer aw_countdown;
            aw_countdown = 20000;
            while (!done && aw_countdown > 0) begin
                @(posedge clk);
                aw_countdown = aw_countdown - 1;
                if (out_valid) begin
                    out_count = out_count + 1;
                    last_addr = out_addr;
                    if (out_data == 16'd0)
                        zero_count = zero_count + 1;
                end
            end
            if (aw_countdown == 0) begin
                $display("FAIL: Timeout waiting for done");
                fail_count = fail_count + 1;
            end
        end

        // Test 1: Should output 1024 samples total
        if (out_count == 1024) begin
            pass_count = pass_count + 1;
            $display("PASS: Output count = %0d", out_count);
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Output count = %0d, expected 1024", out_count);
        end

        // Test 2: Last 384 samples should be zeros (zero-padding)
        if (zero_count >= 384) begin
            pass_count = pass_count + 1;
            $display("PASS: Zero-pad count >= 384 (%0d)", zero_count);
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Zero-pad count = %0d, expected >= 384", zero_count);
        end

        // Test 3: Last address should be 1023
        if (last_addr == 10'd1023) begin
            pass_count = pass_count + 1;
            $display("PASS: Last address = %0d", last_addr);
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Last address = %0d, expected 1023", last_addr);
        end

        $display("=== tb_audio_window: %0d PASSED, %0d FAILED ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $finish;
    end

endmodule
