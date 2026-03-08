`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem — Testbench
// Module: tb_fft_addr_gen
//////////////////////////////////////////////////////////////////////////////

module tb_fft_addr_gen;

    reg         clk, rst_n;
    reg  [3:0]  stage;
    reg  [8:0]  butterfly;
    wire [9:0]  p_addr, q_addr;
    wire [8:0]  tw_addr;
    reg  [9:0]  bitrev_in;
    wire [9:0]  bitrev_out;

    integer pass_count = 0;
    integer fail_count = 0;

    fft_addr_gen uut (
        .clk           (clk),
        .rst_n         (rst_n),
        .stage_i       (stage),
        .butterfly_i   (butterfly),
        .p_addr_o      (p_addr),
        .q_addr_o      (q_addr),
        .tw_addr_o     (tw_addr),
        .bitrev_addr_i (bitrev_in),
        .bitrev_addr_o (bitrev_out)
    );

    always #5 clk = ~clk;

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
        clk       = 0;
        rst_n     = 0;
        stage     = 0;
        butterfly = 0;
        bitrev_in = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // Test 1: Stage 0, butterfly 0 -> p=0, q=1, tw=0
        stage     = 4'd0;
        butterfly = 9'd0;
        @(posedge clk); @(posedge clk);
        check_val("S0 B0 p", {6'd0, p_addr}, 0);
        check_val("S0 B0 q", {6'd0, q_addr}, 1);
        check_val("S0 B0 tw", {7'd0, tw_addr}, 0);

        // Test 2: Stage 0, butterfly 1 -> p=2, q=3, tw=0
        butterfly = 9'd1;
        @(posedge clk); @(posedge clk);
        check_val("S0 B1 p", {6'd0, p_addr}, 2);
        check_val("S0 B1 q", {6'd0, q_addr}, 3);

        // Test 3: Stage 1, butterfly 0 -> p=0, q=2
        stage     = 4'd1;
        butterfly = 9'd0;
        @(posedge clk); @(posedge clk);
        check_val("S1 B0 p", {6'd0, p_addr}, 0);
        check_val("S1 B0 q", {6'd0, q_addr}, 2);

        // Test 4: Stage 1, butterfly 1 -> p=1, q=3
        butterfly = 9'd1;
        @(posedge clk); @(posedge clk);
        check_val("S1 B1 p", {6'd0, p_addr}, 1);
        check_val("S1 B1 q", {6'd0, q_addr}, 3);

        // Test 5: Bit-reversal: 1 (0000000001) -> 512 (1000000000)
        bitrev_in = 10'd1;
        @(posedge clk); @(posedge clk);
        check_val("Bitrev 1->512", {6'd0, bitrev_out}, 512);

        // Test 6: Bit-reversal: 512 -> 1
        bitrev_in = 10'd512;
        @(posedge clk); @(posedge clk);
        check_val("Bitrev 512->1", {6'd0, bitrev_out}, 1);

        // Test 7: Bit-reversal: 0 -> 0
        bitrev_in = 10'd0;
        @(posedge clk); @(posedge clk);
        check_val("Bitrev 0->0", {6'd0, bitrev_out}, 0);

        // Test 8: Bit-reversal: 1023 -> 1023
        bitrev_in = 10'd1023;
        @(posedge clk); @(posedge clk);
        check_val("Bitrev 1023->1023", {6'd0, bitrev_out}, 1023);

        $display("=== tb_fft_addr_gen: %0d PASSED, %0d FAILED ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $finish;
    end

endmodule
