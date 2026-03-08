`timescale 1ns/1ps
//============================================================================
// Testbench: tb_npu_activation
// Verifies ReLU, ReLU6, and bypass activation functions
//============================================================================

module tb_npu_activation;

    reg        clk;
    reg        rst_n;
    reg        en;
    reg  [1:0] act_type;
    reg  [7:0] data_i;
    reg        valid_i;
    wire [7:0] data_o;
    wire       valid_o;

    initial clk = 0;
    always #5 clk = ~clk;

    npu_activation dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .en      (en),
        .act_type(act_type),
        .data_i  (data_i),
        .valid_i (valid_i),
        .data_o  (data_o),
        .valid_o (valid_o)
    );

    integer pass_count, fail_count;

    task check_output;
        input [7:0] expected;
        input [63:0] test_name;
        begin
            @(posedge clk); // wait for registered output
            if ($signed(data_o) === $signed(expected) && valid_o)
                pass_count = pass_count + 1;
            else begin
                fail_count = fail_count + 1;
                $display("FAIL %0s: got %0d, expected %0d", test_name, $signed(data_o), $signed(expected));
            end
        end
    endtask

    initial begin
        pass_count = 0; fail_count = 0;
        rst_n = 0; en = 0; valid_i = 0;
        act_type = 0; data_i = 0;

        repeat (5) @(posedge clk);
        rst_n = 1; en = 1;
        @(posedge clk);

        // Bypass mode (act_type=0)
        act_type = 2'd0;
        data_i = 8'sd42; valid_i = 1; @(posedge clk);
        check_output(8'sd42, "bypass_pos");

        data_i = -8'sd10; @(posedge clk);
        check_output(-8'sd10, "bypass_neg");

        // ReLU mode (act_type=1)
        act_type = 2'd1;
        data_i = 8'sd50; @(posedge clk);
        check_output(8'sd50, "relu_pos");

        data_i = -8'sd30; @(posedge clk);
        check_output(8'd0, "relu_neg");

        // ReLU6 mode (act_type=2)
        act_type = 2'd2;
        data_i = 8'sd3; @(posedge clk);
        check_output(8'sd3, "relu6_mid");

        data_i = 8'sd100; @(posedge clk);
        check_output(8'sd6, "relu6_clamp");

        data_i = -8'sd5; @(posedge clk);
        check_output(8'd0, "relu6_neg");

        valid_i = 0;
        repeat (3) @(posedge clk);
        $display("========================================");
        $display("tb_npu_activation: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        $finish;
    end

endmodule
