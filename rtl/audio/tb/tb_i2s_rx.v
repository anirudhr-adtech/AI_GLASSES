`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem — Testbench
// Module: tb_i2s_rx
//////////////////////////////////////////////////////////////////////////////

module tb_i2s_rx;

    reg  clk, rst_n;
    reg  i2s_sck, i2s_ws, i2s_sd;
    wire [15:0] sample;
    wire        sample_valid;

    integer pass_count = 0;
    integer fail_count = 0;

    i2s_rx uut (
        .clk            (clk),
        .rst_n          (rst_n),
        .i2s_sck_i      (i2s_sck),
        .i2s_ws_i       (i2s_ws),
        .i2s_sd_i       (i2s_sd),
        .sample_o       (sample),
        .sample_valid_o (sample_valid)
    );

    // 100 MHz system clock
    always #5 clk = ~clk;

    // I2S bit clock ~3.125 MHz (32 sys clocks per SCK period)
    localparam SCK_HALF = 160; // ns (half period)

    task send_i2s_frame;
        input [15:0] left_data;
        input [15:0] right_data;
        integer i;
        begin
            // WS low = left channel
            i2s_ws = 0;
            #(SCK_HALF);
            for (i = 15; i >= 0; i = i - 1) begin
                i2s_sd  = left_data[i];
                i2s_sck = 0;
                #(SCK_HALF);
                i2s_sck = 1;
                #(SCK_HALF);
            end
            // WS high = right channel (skipped)
            i2s_ws = 1;
            for (i = 15; i >= 0; i = i - 1) begin
                i2s_sd  = right_data[i];
                i2s_sck = 0;
                #(SCK_HALF);
                i2s_sck = 1;
                #(SCK_HALF);
            end
        end
    endtask

    reg [15:0] captured_sample;
    reg        got_sample;

    always @(posedge clk) begin
        if (sample_valid) begin
            captured_sample <= sample;
            got_sample      <= 1'b1;
        end
    end

    initial begin
        clk     = 0;
        rst_n   = 0;
        i2s_sck = 0;
        i2s_ws  = 1;
        i2s_sd  = 0;
        got_sample = 0;
        captured_sample = 0;

        repeat (10) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        // Test 1: Send left=0xA5A5, right=0x1234 (right should be ignored)
        got_sample = 0;
        send_i2s_frame(16'hA5A5, 16'h1234);
        repeat (20) @(posedge clk);

        if (got_sample && captured_sample == 16'hA5A5) begin
            pass_count = pass_count + 1;
            $display("PASS: Left sample = 0x%04X", captured_sample);
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Expected 0xA5A5, got 0x%04X (valid=%b)", captured_sample, got_sample);
        end

        // Test 2: Send left=0x1234
        got_sample = 0;
        send_i2s_frame(16'h1234, 16'hFFFF);
        repeat (20) @(posedge clk);

        if (got_sample && captured_sample == 16'h1234) begin
            pass_count = pass_count + 1;
            $display("PASS: Left sample = 0x%04X", captured_sample);
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Expected 0x1234, got 0x%04X (valid=%b)", captured_sample, got_sample);
        end

        // Test 3: Send left=0x0000
        got_sample = 0;
        send_i2s_frame(16'h0000, 16'hBEEF);
        repeat (20) @(posedge clk);

        if (got_sample && captured_sample == 16'h0000) begin
            pass_count = pass_count + 1;
            $display("PASS: Left sample = 0x%04X", captured_sample);
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Expected 0x0000, got 0x%04X (valid=%b)", captured_sample, got_sample);
        end

        // Test 4: Send left=0xFFFF
        got_sample = 0;
        send_i2s_frame(16'hFFFF, 16'h0000);
        repeat (20) @(posedge clk);

        if (got_sample && captured_sample == 16'hFFFF) begin
            pass_count = pass_count + 1;
            $display("PASS: Left sample = 0x%04X", captured_sample);
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Expected 0xFFFF, got 0x%04X (valid=%b)", captured_sample, got_sample);
        end

        $display("=== tb_i2s_rx: %0d PASSED, %0d FAILED ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $finish;
    end

endmodule
