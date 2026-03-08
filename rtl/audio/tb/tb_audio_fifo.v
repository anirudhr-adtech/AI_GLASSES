`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem — Testbench
// Module: tb_audio_fifo
//////////////////////////////////////////////////////////////////////////////

module tb_audio_fifo;

    reg         clk, rst_n;
    reg         wr_en, rd_en;
    reg  [15:0] wr_data;
    wire [15:0] rd_data;
    wire        full, empty;
    wire [10:0] fill_level;
    wire        overrun;

    integer pass_count = 0;
    integer fail_count = 0;

    audio_fifo uut (
        .clk        (clk),
        .rst_n      (rst_n),
        .wr_en      (wr_en),
        .wr_data    (wr_data),
        .rd_en      (rd_en),
        .rd_data    (rd_data),
        .full       (full),
        .empty      (empty),
        .fill_level (fill_level),
        .overrun    (overrun)
    );

    always #5 clk = ~clk;

    task check_val;
        input [255:0] name;
        input [31:0]  actual;
        input [31:0]  expected;
        begin
            if (actual === expected) begin
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: %0s — got %0d, expected %0d", name, actual, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    integer i;

    initial begin
        clk     = 0;
        rst_n   = 0;
        wr_en   = 0;
        rd_en   = 0;
        wr_data = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Test 1: Empty after reset
        check_val("Empty after reset", {31'd0, empty}, 1);
        check_val("Fill level 0", {21'd0, fill_level}, 0);

        // Test 2: Write 10 values
        for (i = 0; i < 10; i = i + 1) begin
            @(posedge clk);
            wr_en   = 1;
            wr_data = i[15:0] + 16'h100;
        end
        @(posedge clk);
        wr_en = 0;
        @(posedge clk);

        check_val("Fill level 10", {21'd0, fill_level}, 10);
        check_val("Not empty", {31'd0, empty}, 0);

        // Test 3: Read back 10 values
        for (i = 0; i < 10; i = i + 1) begin
            @(posedge clk);
            rd_en = 1;
        end
        @(posedge clk);
        rd_en = 0;
        @(posedge clk);

        check_val("Empty after reading 10", {31'd0, empty}, 1);

        // Test 4: Fill to full (1024 entries)
        for (i = 0; i < 1024; i = i + 1) begin
            @(posedge clk);
            wr_en   = 1;
            wr_data = i[15:0];
        end
        @(posedge clk);
        wr_en = 0;
        @(posedge clk);

        check_val("Full", {31'd0, full}, 1);
        check_val("Fill level 1024", {21'd0, fill_level}, 1024);

        // Test 5: Overrun on write when full
        @(posedge clk);
        wr_en   = 1;
        wr_data = 16'hDEAD;
        @(posedge clk);
        wr_en = 0;
        @(posedge clk);

        check_val("Overrun sticky", {31'd0, overrun}, 1);

        // Test 6: Read first value should be 0
        @(posedge clk);
        rd_en = 1;
        @(posedge clk);
        rd_en = 0;
        @(posedge clk);
        check_val("First read = 0", {16'd0, rd_data}, 0);

        $display("=== tb_audio_fifo: %0d PASSED, %0d FAILED ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $finish;
    end

endmodule
