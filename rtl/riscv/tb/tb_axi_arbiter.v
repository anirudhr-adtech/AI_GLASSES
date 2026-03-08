`timescale 1ns/1ps
//============================================================================
// Testbench : tb_axi_arbiter
// Project   : AI_GLASSES — RISC-V Subsystem
// Description : Self-checking testbench for axi_arbiter
//============================================================================

module tb_axi_arbiter;

    reg        clk;
    reg        rst_n;
    reg  [2:0] req_i;
    reg        done_i;
    wire [2:0] grant_o;
    wire [1:0] last_o;

    integer pass_cnt, fail_cnt;

    riscv_axi_arbiter #(
        .NUM_MASTERS  (3),
        .STARVE_LIMIT (16)
    ) uut (
        .clk     (clk),
        .rst_n   (rst_n),
        .req_i   (req_i),
        .done_i  (done_i),
        .grant_o (grant_o),
        .last_o  (last_o)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task check_grant;
        input [2:0] expected_grant;
        input [7:0] test_name_len; // unused, for readability
        begin
            @(posedge clk);
            @(posedge clk); // allow FSM to respond
            if (grant_o !== expected_grant) begin
                $display("FAIL: expected grant=%b got=%b", expected_grant, grant_o);
                fail_cnt = fail_cnt + 1;
            end else begin
                $display("PASS: grant=%b last=%0d", grant_o, last_o);
                pass_cnt = pass_cnt + 1;
            end
        end
    endtask

    task complete_txn;
        begin
            done_i = 1;
            @(posedge clk);
            done_i = 0;
            @(posedge clk);
        end
    endtask

    initial begin
        pass_cnt = 0;
        fail_cnt = 0;
        rst_n    = 0;
        req_i    = 3'b000;
        done_i   = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Test 1: Single M0 request
        $display("Test 1: Single M0 request");
        req_i = 3'b001;
        check_grant(3'b001, 0);
        req_i = 3'b000;
        complete_txn;

        // Test 2: Single M1 request
        $display("Test 2: Single M1 request");
        req_i = 3'b010;
        check_grant(3'b010, 0);
        req_i = 3'b000;
        complete_txn;

        // Test 3: Single M2 request
        $display("Test 3: Single M2 request");
        req_i = 3'b100;
        check_grant(3'b100, 0);
        req_i = 3'b000;
        complete_txn;

        // Test 4: DMA priority override — M0+M2, M2 should win
        $display("Test 4: DMA priority M0+M2");
        req_i = 3'b101;
        check_grant(3'b100, 0);
        req_i = 3'b000;
        complete_txn;

        // Test 5: All three request — round-robin
        $display("Test 5: All three request — round-robin");
        req_i = 3'b111;
        @(posedge clk); @(posedge clk);
        $display("  First grant=%b last=%0d", grant_o, last_o);
        if (grant_o != 3'b000) pass_cnt = pass_cnt + 1;
        else fail_cnt = fail_cnt + 1;
        complete_txn;

        // Continue round-robin
        req_i = 3'b111;
        @(posedge clk); @(posedge clk);
        $display("  Second grant=%b last=%0d", grant_o, last_o);
        if (grant_o != 3'b000) pass_cnt = pass_cnt + 1;
        else fail_cnt = fail_cnt + 1;
        complete_txn;

        req_i = 3'b111;
        @(posedge clk); @(posedge clk);
        $display("  Third grant=%b last=%0d", grant_o, last_o);
        if (grant_o != 3'b000) pass_cnt = pass_cnt + 1;
        else fail_cnt = fail_cnt + 1;
        req_i = 3'b000;
        complete_txn;

        // Test 6: Grant hold — grant should persist until done
        $display("Test 6: Grant hold until done");
        req_i = 3'b001;
        @(posedge clk); @(posedge clk);
        // grant should be asserted
        repeat (5) begin
            @(posedge clk);
            if (grant_o != 3'b001) begin
                $display("FAIL: Grant not held");
                fail_cnt = fail_cnt + 1;
            end
        end
        $display("PASS: Grant held for 5 cycles");
        pass_cnt = pass_cnt + 1;
        req_i = 3'b000;
        complete_txn;

        // Test 7: No requests — no grant
        $display("Test 7: No requests");
        req_i = 3'b000;
        @(posedge clk); @(posedge clk);
        if (grant_o == 3'b000) begin
            $display("PASS: No grant when no request");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL: Grant without request");
            fail_cnt = fail_cnt + 1;
        end

        $display("");
        $display("========================================");
        $display("  Results: %0d passed, %0d failed", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  SOME TESTS FAILED");
        $display("========================================");
        $finish;
    end

endmodule
