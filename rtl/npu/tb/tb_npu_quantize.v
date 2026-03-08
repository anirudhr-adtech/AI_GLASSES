`timescale 1ns/1ps
//============================================================================
// Testbench: tb_npu_quantize
// Verifies INT32 -> INT8 quantization pipeline
//============================================================================

module tb_npu_quantize;

    reg         clk;
    reg         rst_n;
    reg         en;
    reg  [31:0] data_i;
    reg         valid_i;
    reg  [7:0]  shift_i;
    reg  [15:0] scale_i;
    wire [7:0]  data_o;
    wire        valid_o;

    initial clk = 0;
    always #5 clk = ~clk;

    npu_quantize dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .en     (en),
        .data_i (data_i),
        .valid_i(valid_i),
        .shift_i(shift_i),
        .scale_i(scale_i),
        .data_o (data_o),
        .valid_o(valid_o)
    );

    integer pass_count, fail_count;

    initial begin
        pass_count = 0; fail_count = 0;
        rst_n = 0; en = 0; valid_i = 0;
        data_i = 0; shift_i = 0; scale_i = 16'd1;

        repeat (5) @(posedge clk);
        rst_n = 1; en = 1;
        @(posedge clk);

        // Test 1: Simple passthrough (shift=0, scale=1)
        // Input 50 -> output 50
        data_i = 32'sd50; valid_i = 1; shift_i = 0; scale_i = 16'd1;
        @(posedge clk);
        valid_i = 0;
        // Wait 3 cycles for pipeline
        repeat (2) @(posedge clk);
        if (valid_o && $signed(data_o) == 50) pass_count = pass_count + 1;
        else begin fail_count = fail_count + 1; $display("FAIL Test1: data_o=%0d", $signed(data_o)); end

        // Test 2: Shift right by 4: 256 >> 4 = 16, * 1 = 16
        @(posedge clk);
        data_i = 32'sd256; valid_i = 1; shift_i = 8'd4; scale_i = 16'd1;
        @(posedge clk);
        valid_i = 0;
        repeat (2) @(posedge clk);
        if (valid_o && $signed(data_o) == 16) pass_count = pass_count + 1;
        else begin fail_count = fail_count + 1; $display("FAIL Test2: data_o=%0d", $signed(data_o)); end

        // Test 3: Clamp positive — large value should clamp to 127
        @(posedge clk);
        data_i = 32'sd10000; valid_i = 1; shift_i = 0; scale_i = 16'd1;
        @(posedge clk);
        valid_i = 0;
        repeat (2) @(posedge clk);
        if (valid_o && $signed(data_o) == 127) pass_count = pass_count + 1;
        else begin fail_count = fail_count + 1; $display("FAIL Test3: data_o=%0d", $signed(data_o)); end

        // Test 4: Clamp negative — large negative should clamp to -128
        @(posedge clk);
        data_i = -32'sd10000; valid_i = 1; shift_i = 0; scale_i = 16'd1;
        @(posedge clk);
        valid_i = 0;
        repeat (2) @(posedge clk);
        if (valid_o && $signed(data_o) == -128) pass_count = pass_count + 1;
        else begin fail_count = fail_count + 1; $display("FAIL Test4: data_o=%0d", $signed(data_o)); end

        repeat (3) @(posedge clk);
        $display("========================================");
        $display("tb_npu_quantize: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        if (fail_count == 0) $display("ALL TESTS PASSED");
        $finish;
    end

endmodule
