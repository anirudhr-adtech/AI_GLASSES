`timescale 1ns/1ps
//============================================================================
// Testbench : tb_rst_sync
// Description : Self-checking testbench for rst_sync (2-FF reset synchronizer)
//============================================================================
module tb_rst_sync;

    reg  clk;
    reg  rst_n_async;
    wire rst_n_sync;

    integer pass_count;
    integer fail_count;

    // Clock generation: 100 MHz = 10 ns period
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // DUT
    rst_sync u_rst_sync (
        .clk         (clk),
        .rst_n_async (rst_n_async),
        .rst_n_sync  (rst_n_sync)
    );

    task check_sync;
        input expected;
        input [63:0] test_id;
        begin
            if (rst_n_sync === expected) begin
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL test %0d: rst_n_sync=%b, expected=%b at time %0t",
                         test_id, rst_n_sync, expected, $time);
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        rst_n_async = 1'b0;

        // Test 1: After reset assertion, rst_n_sync should be 0
        @(posedge clk); #1;
        check_sync(1'b0, 1);

        // Test 2: Still held in reset after another cycle
        @(posedge clk); #1;
        check_sync(1'b0, 2);

        // Test 3: Deassert async reset — first cycle, ff1=1 but ff2 still 0
        rst_n_async = 1'b1;
        @(posedge clk); #1;
        check_sync(1'b0, 3);

        // Test 4: Second cycle after deassertion — ff2 should be 1
        @(posedge clk); #1;
        check_sync(1'b1, 4);

        // Test 5: Stays deasserted (sync output stays 1)
        @(posedge clk); #1;
        check_sync(1'b1, 5);

        // Test 6: Re-assert reset asynchronously (between clock edges)
        #2;
        rst_n_async = 1'b0;
        #1;
        check_sync(1'b0, 6);  // Should go low immediately (async assertion)

        // Test 7: Deassert again and wait 2 cycles for sync deassertion
        rst_n_async = 1'b1;
        @(posedge clk); #1;
        check_sync(1'b0, 7);  // 1 cycle — still low
        @(posedge clk); #1;
        check_sync(1'b1, 8);  // 2 cycles — now high

        // Summary
        $display("---------------------------------------");
        $display("Tests: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        $display("---------------------------------------");
        $finish;
    end

endmodule
