`timescale 1ns/1ps
//============================================================================
// Testbench: tb_npu_mac_array
// Basic verification of 8x8 MAC array in Conv2D and DW-Conv2D modes
//============================================================================

module tb_npu_mac_array;

    reg         clk;
    reg         rst_n;
    reg         en;
    reg         clear_acc;
    reg  [1:0]  mode;
    reg  [63:0] weight_data;
    reg  [63:0] act_data;
    wire [255:0] acc_out;
    wire         acc_valid;

    initial clk = 0;
    always #5 clk = ~clk;

    npu_mac_array #(
        .MAC_ROWS(8), .MAC_COLS(8),
        .DATA_WIDTH(8), .ACC_WIDTH(32)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .en         (en),
        .clear_acc  (clear_acc),
        .mode       (mode),
        .weight_data(weight_data),
        .act_data   (act_data),
        .acc_out    (acc_out),
        .acc_valid  (acc_valid)
    );

    integer i;
    integer pass_count, fail_count;

    initial begin
        pass_count = 0; fail_count = 0;
        rst_n = 0; en = 0; clear_acc = 0;
        mode = 0; weight_data = 0; act_data = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Test 1: Conv2D mode — all ones weights and activations
        $display("Test 1: Conv2D mode, weights=1, acts=1");
        mode = 2'd0;
        // Cycle 1: drive data with clear_acc=1
        clear_acc = 1; en = 1;
        weight_data = {8{8'sd1}};
        act_data    = {8{8'sd1}};
        @(posedge clk);
        // Cycle 2: deassert clear_acc, keep en for 1 more cycle
        clear_acc = 0;
        @(posedge clk);
        // Deassert en and wait for pipeline output
        en = 0;
        repeat (4) @(posedge clk);
        // Each MAC: 1*1=1, accumulated once. acc_out[col] should be 1
        $display("  acc_out[0] = %0d (expect 1)", $signed(acc_out[31:0]));
        if ($signed(acc_out[31:0]) == 1)
            pass_count = pass_count + 1;
        else
            fail_count = fail_count + 1;

        @(posedge clk);

        // Test 2: DW-Conv2D mode — only row 0 active
        $display("Test 2: DW-Conv2D mode");
        mode = 2'd1;
        // Cycle 1: drive data with clear_acc=1
        clear_acc = 1; en = 1;
        weight_data = {8{8'sd2}};
        act_data    = {8{8'sd3}};
        @(posedge clk);
        // Cycle 2: deassert clear_acc
        clear_acc = 0;
        @(posedge clk);
        // Deassert en and wait for pipeline output
        en = 0;
        repeat (4) @(posedge clk);
        // Row 0 MACs: 2*3=6, other rows disabled
        $display("  acc_out[0] = %0d (expect 6)", $signed(acc_out[31:0]));
        if ($signed(acc_out[31:0]) == 6)
            pass_count = pass_count + 1;
        else
            fail_count = fail_count + 1;

        repeat (3) @(posedge clk);
        $display("========================================");
        $display("tb_npu_mac_array: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        $finish;
    end

endmodule
