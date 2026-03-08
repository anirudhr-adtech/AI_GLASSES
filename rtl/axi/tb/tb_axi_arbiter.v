`timescale 1ns/1ps
//============================================================================
// Testbench: tb_axi_arbiter
// Project:   AI_GLASSES — AXI Interconnect
// Description: Self-checking testbench for axi_arbiter
//============================================================================

module tb_axi_arbiter;

    parameter NUM_MASTERS = 5;
    parameter STALL_LIMIT = 32;

    reg                         clk, rst_n;
    reg  [NUM_MASTERS-1:0]      req_i;
    reg  [2*NUM_MASTERS-1:0]    tier_i;
    reg                         lock_i;
    reg                         done_i;
    wire [NUM_MASTERS-1:0]      grant_o;
    wire [16*NUM_MASTERS-1:0]   stall_count_o;

    integer pass_count, fail_count, test_num;

    axi_arbiter #(
        .NUM_MASTERS(NUM_MASTERS),
        .STALL_LIMIT(STALL_LIMIT)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .req_i(req_i), .tier_i(tier_i),
        .lock_i(lock_i), .done_i(done_i),
        .grant_o(grant_o), .stall_count_o(stall_count_o)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task check_grant;
        input [NUM_MASTERS-1:0] exp_grant;
        input [79:0] test_name;
        begin
            test_num = test_num + 1;
            if (grant_o === exp_grant) begin
                pass_count = pass_count + 1;
                $display("PASS test %0d: %0s grant=0x%02h", test_num, test_name, grant_o);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL test %0d: %0s exp=0x%02h got=0x%02h", test_num, test_name, exp_grant, grant_o);
            end
        end
    endtask

    task complete_burst;
        begin
            req_i = 0;
            lock_i = 0;
            done_i = 1;
            @(posedge clk);
            done_i = 0;
            @(posedge clk);
        end
    endtask

    initial begin
        $display("=== tb_axi_arbiter START ===");
        pass_count = 0; fail_count = 0; test_num = 0;
        rst_n = 0; req_i = 0; lock_i = 0; done_i = 0;
        // Tier config: M0=T2, M1=T2, M2=T0, M3=T1, M4=T2
        tier_i = {2'd2, 2'd1, 2'd0, 2'd2, 2'd2};
        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Test 1: Single master request (M0)
        req_i = 5'b00001;
        @(posedge clk); @(posedge clk);
        check_grant(5'b00001, "Single M0   ");
        lock_i = 1;
        @(posedge clk);
        complete_burst;

        // Test 2: Tier 0 beats Tier 2 (M2 vs M0)
        req_i = 5'b00101; // M0 + M2
        @(posedge clk); @(posedge clk);
        check_grant(5'b00100, "T0 beats T2 ");
        lock_i = 1;
        @(posedge clk);
        complete_burst;

        // Test 3: Tier 0 beats Tier 1 (M2 vs M3)
        req_i = 5'b01100; // M2 + M3
        @(posedge clk); @(posedge clk);
        check_grant(5'b00100, "T0 beats T1 ");
        lock_i = 1;
        @(posedge clk);
        complete_burst;

        // Test 4: Tier 1 beats Tier 2 (M3 vs M0)
        req_i = 5'b01001; // M0 + M3
        @(posedge clk); @(posedge clk);
        check_grant(5'b01000, "T1 beats T2 ");
        lock_i = 1;
        @(posedge clk);
        complete_burst;

        // Test 5: Lock prevents preemption
        req_i = 5'b00001; // M0
        @(posedge clk); @(posedge clk);
        lock_i = 1;
        req_i = 5'b00101; // M2 also requests (higher priority)
        @(posedge clk); @(posedge clk);
        // M0 should still hold grant (locked)
        check_grant(5'b00001, "Lock hold   ");
        complete_burst;

        // Test 6: After lock release, higher tier wins
        req_i = 5'b00101;
        @(posedge clk); @(posedge clk);
        check_grant(5'b00100, "After unlock");
        lock_i = 1;
        @(posedge clk);
        complete_burst;

        // Test 7: No requests -> no grant
        req_i = 5'b00000;
        @(posedge clk); @(posedge clk);
        check_grant(5'b00000, "No requests ");

        $display("=== tb_axi_arbiter DONE ===");
        $display("PASSED: %0d  FAILED: %0d", pass_count, fail_count);
        if (fail_count == 0) $display("*** ALL TESTS PASSED ***");
        else $display("*** SOME TESTS FAILED ***");
        $finish;
    end

endmodule
