`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem — Testbench
// Module: tb_i2s_sync
//////////////////////////////////////////////////////////////////////////////

module tb_i2s_sync;

    reg  clk, rst_n;
    reg  i2s_sck, i2s_ws, i2s_sd;
    wire sck_sync, ws_sync, sd_sync;
    wire sck_rise, sck_fall, ws_rise, ws_fall;

    integer pass_count = 0;
    integer fail_count = 0;

    i2s_sync uut (
        .clk        (clk),
        .rst_n      (rst_n),
        .i2s_sck_i  (i2s_sck),
        .i2s_ws_i   (i2s_ws),
        .i2s_sd_i   (i2s_sd),
        .sck_sync_o (sck_sync),
        .ws_sync_o  (ws_sync),
        .sd_sync_o  (sd_sync),
        .sck_rise_o (sck_rise),
        .sck_fall_o (sck_fall),
        .ws_rise_o  (ws_rise),
        .ws_fall_o  (ws_fall)
    );

    // 100 MHz clock
    always #5 clk = ~clk;

    task check;
        input [255:0] name;
        input actual;
        input expected;
        begin
            if (actual === expected) begin
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: %0s — got %b, expected %b at time %0t", name, actual, expected, $time);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        clk     = 0;
        rst_n   = 0;
        i2s_sck = 0;
        i2s_ws  = 0;
        i2s_sd  = 0;

        // Reset
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // Test 1: Signals sync through 2 FFs (3-cycle latency: 2 sync + 1 edge)
        @(posedge clk);
        i2s_sck = 1;
        repeat (4) @(posedge clk);
        check("SCK sync high", sck_sync, 1'b1);

        // Test 2: SCK rising edge detected
        // Edge was already detected, check it was pulsed
        // Reset SCK and try again
        i2s_sck = 0;
        repeat (4) @(posedge clk);
        check("SCK sync low", sck_sync, 1'b0);

        // Now raise SCK and look for rising edge
        i2s_sck = 1;
        repeat (3) @(posedge clk);
        // After 3 clocks the edge detector should have fired
        // Check sck_rise was high (it's a 1-cycle pulse)
        // We need to sample it at the right time
        check("SCK rise detected", sck_rise, 1'b1);

        // Test 3: SCK falling edge
        @(posedge clk);
        i2s_sck = 0;
        repeat (3) @(posedge clk);
        check("SCK fall detected", sck_fall, 1'b1);

        // Test 4: WS rising edge
        i2s_ws = 1;
        repeat (3) @(posedge clk);
        check("WS rise detected", ws_rise, 1'b1);

        // Test 5: WS falling edge
        @(posedge clk);
        i2s_ws = 0;
        repeat (3) @(posedge clk);
        check("WS fall detected", ws_fall, 1'b1);

        // Test 6: SD sync
        i2s_sd = 1;
        repeat (3) @(posedge clk);
        check("SD sync high", sd_sync, 1'b1);

        i2s_sd = 0;
        repeat (3) @(posedge clk);
        check("SD sync low", sd_sync, 1'b0);

        // Summary
        $display("=== tb_i2s_sync: %0d PASSED, %0d FAILED ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $finish;
    end

endmodule
