`timescale 1ns / 1ps
//============================================================================
// Testbench: tb_clk_rst_mgr
// Verifies reset synchronisation and sequenced deassert timing.
//============================================================================

module tb_clk_rst_mgr;

    reg  clk;
    reg  npu_clk;
    reg  sys_rst_n;
    wire periph_rst_n;
    wire cpu_rst_n;
    wire npu_rst_n;

    // 100 MHz sys_clk (10 ns period)
    initial clk = 0;
    always #5 clk = ~clk;

    // 200 MHz npu_clk (5 ns period)
    initial npu_clk = 0;
    always #2.5 npu_clk = ~npu_clk;

    clk_rst_mgr dut (
        .clk_i         (clk),
        .npu_clk_i     (npu_clk),
        .sys_rst_ni    (sys_rst_n),
        .periph_rst_no (periph_rst_n),
        .cpu_rst_no    (cpu_rst_n),
        .npu_rst_no    (npu_rst_n)
    );

    integer pass_count;
    integer fail_count;

    task check;
        input [63:0] name;
        input actual;
        input expected;
        begin
            if (actual === expected)
                pass_count = pass_count + 1;
            else begin
                $display("FAIL: %0s = %b, expected %b at time %0t", name, actual, expected, $time);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        sys_rst_n = 0;

        // Hold reset for 50 ns
        #50;

        // Test 1: All resets should be asserted during reset
        check("periph_rst_n", periph_rst_n, 1'b0);
        check("cpu_rst_n",    cpu_rst_n,    1'b0);
        check("npu_rst_n",    npu_rst_n,    1'b0);

        // Release reset
        @(posedge clk);
        sys_rst_n = 1;

        // Wait 3 sys_clk cycles — periph should deassert (counter reaches 2+)
        repeat (5) @(posedge clk);
        @(posedge clk); // extra cycle to avoid NBA stale-value issue
        check("periph_rst_n_early", periph_rst_n, 1'b1);
        check("cpu_rst_n_early",    cpu_rst_n,    1'b0);

        // Wait until counter reaches 10+ — cpu should deassert
        repeat (8) @(posedge clk);
        @(posedge clk); // extra cycle to avoid NBA stale-value issue
        check("cpu_rst_n_late", cpu_rst_n, 1'b1);

        // Wait for NPU reset to propagate (2 npu_clk cycles + margin)
        repeat (5) @(posedge clk);
        check("npu_rst_n_late", npu_rst_n, 1'b1);

        // Test re-assertion: pulse sys_rst_n low
        @(posedge clk);
        sys_rst_n = 0;
        #30;
        check("periph_rst_n_reassert", periph_rst_n, 1'b0);
        check("cpu_rst_n_reassert",    cpu_rst_n,    1'b0);

        // Release again and verify recovery
        @(posedge clk);
        sys_rst_n = 1;
        repeat (15) @(posedge clk);
        check("periph_rst_n_recover", periph_rst_n, 1'b1);
        check("cpu_rst_n_recover",    cpu_rst_n,    1'b1);

        repeat (5) @(posedge clk);
        $display("========================================");
        $display("tb_clk_rst_mgr: %0d PASSED, %0d FAILED", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        $display("========================================");
        $finish;
    end

endmodule
