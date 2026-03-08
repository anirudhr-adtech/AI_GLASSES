`timescale 1ns/1ps
//============================================================================
// AI_GLASSES — DDR Subsystem (Simulation Model)
// Testbench: tb_backpressure_gen
//============================================================================

module tb_backpressure_gen;

    parameter PERIOD = 8;
    parameter SEED   = 42;

    reg        clk;
    reg        rst_n;
    reg  [1:0] mode_i;
    wire       ready_o;

    integer pass_count, fail_count;
    integer i, ready_cnt;

    backpressure_gen #(
        .MODE   (0),
        .PERIOD (PERIOD),
        .SEED   (SEED)
    ) dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .mode_i  (mode_i),
        .ready_o (ready_o)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        pass_count = 0;
        fail_count = 0;
        rst_n = 0; mode_i = 2'd0;

        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Test Mode 0: Always ready
        mode_i = 2'd0;
        ready_cnt = 0;
        repeat (32) begin
            @(posedge clk);
            if (ready_o) ready_cnt = ready_cnt + 1;
        end
        if (ready_cnt == 32) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Mode 0 should be always ready, got %0d/32", ready_cnt);
        end

        // Test Mode 1: Deassert 1 every PERIOD
        mode_i = 2'd1;
        ready_cnt = 0;
        repeat (PERIOD * 4) begin
            @(posedge clk);
            if (ready_o) ready_cnt = ready_cnt + 1;
        end
        // Should be (PERIOD-1)*4 = 28 ready out of 32
        if (ready_cnt >= (PERIOD - 1) * 3 && ready_cnt <= (PERIOD - 1) * 4 + 1) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Mode 1 ready count=%0d expected ~%0d", ready_cnt, (PERIOD-1)*4);
        end

        // Test Mode 2: Random (just check it's not stuck)
        mode_i = 2'd2;
        ready_cnt = 0;
        repeat (64) begin
            @(posedge clk);
            if (ready_o) ready_cnt = ready_cnt + 1;
        end
        if (ready_cnt > 0 && ready_cnt < 64) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Mode 2 random should have mix, got %0d/64", ready_cnt);
        end

        // Test Mode 3: Ready 1 of PERIOD
        mode_i = 2'd3;
        ready_cnt = 0;
        repeat (PERIOD * 4) begin
            @(posedge clk);
            if (ready_o) ready_cnt = ready_cnt + 1;
        end
        // Should be about 4 ready out of 32
        if (ready_cnt >= 3 && ready_cnt <= 5) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Mode 3 ready count=%0d expected ~4", ready_cnt);
        end

        // Test reset
        rst_n = 0;
        @(posedge clk);
        rst_n = 1;
        mode_i = 2'd0;
        @(posedge clk); @(posedge clk);
        if (ready_o) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: After reset mode 0 should be ready");
        end

        @(posedge clk);
        $display("========================================");
        $display("tb_backpressure_gen: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        if (fail_count == 0) $display("ALL TESTS PASSED");
        $finish;
    end

    initial begin
        $dumpfile("tb_backpressure_gen.vcd");
        $dumpvars(0, tb_backpressure_gen);
    end

endmodule
