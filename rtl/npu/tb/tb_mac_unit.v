`timescale 1ns/1ps
//============================================================================
// Testbench: tb_mac_unit
// Verifies single MAC cell: INT8 x INT8 -> INT32 accumulate
//============================================================================

module tb_mac_unit;

    reg        clk;
    reg        rst_n;
    reg        en;
    reg        clear_acc;
    reg  [7:0] weight_i;
    reg  [7:0] act_i;
    wire [31:0] acc_o;

    // Clock generation: 100 MHz (10ns period)
    initial clk = 0;
    always #5 clk = ~clk;

    // DUT
    mac_unit #(
        .DATA_WIDTH(8),
        .ACC_WIDTH(32)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .en        (en),
        .clear_acc (clear_acc),
        .weight_i  (weight_i),
        .act_i     (act_i),
        .acc_o     (acc_o)
    );

    integer pass_count;
    integer fail_count;

    task check_acc;
        input [31:0] expected;
        begin
            if (acc_o === expected)
                pass_count = pass_count + 1;
            else begin
                $display("FAIL: acc_o = %0d, expected %0d at time %0t", $signed(acc_o), $signed(expected), $time);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        rst_n = 0;
        en = 0;
        clear_acc = 0;
        weight_i = 0;
        act_i = 0;

        // Reset
        repeat (5) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Test 1: Clear accumulator, compute 3 * 4 = 12
        clear_acc = 1; en = 1;
        weight_i = 8'sd3; act_i = 8'sd4;
        @(posedge clk);
        clear_acc = 0;
        // Wait 2 cycles (pipeline latency)
        @(posedge clk);
        @(posedge clk);
        check_acc(32'sd12);

        // Test 2: Accumulate 5 * 6 = 30, total = 12+30 = 42
        weight_i = 8'sd5; act_i = 8'sd6;
        @(posedge clk);
        @(posedge clk);
        check_acc(32'sd42);

        // Test 3: Negative numbers: (-3) * 7 = -21, total = 42+(-21) = 21
        weight_i = -8'sd3; act_i = 8'sd7;
        @(posedge clk);
        @(posedge clk);
        check_acc(32'sd21);

        // Test 4: Clear and new computation
        clear_acc = 1;
        weight_i = 8'sd10; act_i = 8'sd10;
        @(posedge clk);
        clear_acc = 0;
        @(posedge clk);
        @(posedge clk);
        check_acc(32'sd100);

        // Results
        en = 0;
        repeat (3) @(posedge clk);
        $display("========================================");
        $display("tb_mac_unit: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        $finish;
    end

endmodule
