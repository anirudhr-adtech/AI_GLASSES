`timescale 1ns/1ps
//============================================================================
// AI_GLASSES — DDR Subsystem (Simulation Model)
// Testbench: tb_latency_pipe
//============================================================================

module tb_latency_pipe;

    parameter LATENCY    = 4;  // Short for fast sim
    parameter DATA_WIDTH = 128;
    parameter ID_WIDTH   = 6;

    reg                    clk;
    reg                    rst_n;
    reg                    in_valid;
    reg  [DATA_WIDTH-1:0]  in_data;
    reg  [ID_WIDTH-1:0]    in_id;
    reg                    in_last;
    wire                   out_valid;
    wire [DATA_WIDTH-1:0]  out_data;
    wire [ID_WIDTH-1:0]    out_id;
    wire                   out_last;
    reg                    out_ready;

    integer pass_count, fail_count;
    integer cycle_count;

    latency_pipe #(
        .LATENCY    (LATENCY),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (in_valid),
        .in_data   (in_data),
        .in_id     (in_id),
        .in_last   (in_last),
        .out_valid (out_valid),
        .out_data  (out_data),
        .out_id    (out_id),
        .out_last  (out_last),
        .out_ready (out_ready)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task check_output;
        input [DATA_WIDTH-1:0] exp_data;
        input [ID_WIDTH-1:0]   exp_id;
        input                  exp_last;
        input                  exp_valid;
        input [255:0]          msg;
        begin
            if (out_valid !== exp_valid) begin
                fail_count = fail_count + 1;
                $display("FAIL: %0s valid=%b expected=%b", msg, out_valid, exp_valid);
            end else if (exp_valid && (out_data !== exp_data || out_id !== exp_id || out_last !== exp_last)) begin
                fail_count = fail_count + 1;
                $display("FAIL: %0s data=%h id=%h last=%b", msg, out_data, out_id, out_last);
            end else begin
                pass_count = pass_count + 1;
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        rst_n = 0; in_valid = 0; in_data = 0; in_id = 0; in_last = 0; out_ready = 1;

        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Test 1: Single entry, verify it appears after LATENCY cycles
        in_valid = 1;
        in_data = 128'hAAAA_BBBB_CCCC_DDDD_1111_2222_3333_4444;
        in_id = 6'd5;
        in_last = 1;
        @(posedge clk);
        in_valid = 0; in_data = 0; in_id = 0; in_last = 0;

        // Wait LATENCY-1 more cycles (first cycle was the input)
        repeat (LATENCY - 1) begin
            @(posedge clk);
            check_output(128'd0, 6'd0, 1'b0, 1'b0, "Should not be valid yet");
        end

        // Now output should be valid
        @(posedge clk);
        check_output(128'hAAAA_BBBB_CCCC_DDDD_1111_2222_3333_4444, 6'd5, 1'b1, 1'b1, "Latency output");

        // Test 2: Back-to-back entries
        repeat (2) @(posedge clk);

        in_valid = 1; in_data = 128'h1; in_id = 6'd1; in_last = 0;
        @(posedge clk);
        in_data = 128'h2; in_id = 6'd2; in_last = 0;
        @(posedge clk);
        in_data = 128'h3; in_id = 6'd3; in_last = 1;
        @(posedge clk);
        in_valid = 0;

        repeat (LATENCY - 1) @(posedge clk);
        @(posedge clk);
        check_output(128'h1, 6'd1, 1'b0, 1'b1, "B2B entry 1");
        @(posedge clk);
        check_output(128'h2, 6'd2, 1'b0, 1'b1, "B2B entry 2");
        @(posedge clk);
        check_output(128'h3, 6'd3, 1'b1, 1'b1, "B2B entry 3 last");

        // Test 3: Reset clears pipeline
        repeat (2) @(posedge clk);
        in_valid = 1; in_data = 128'hFF; in_id = 6'd10; in_last = 1;
        @(posedge clk);
        in_valid = 0;
        @(posedge clk);
        rst_n = 0;
        @(posedge clk);
        rst_n = 1;
        repeat (LATENCY + 2) begin
            @(posedge clk);
            check_output(128'd0, 6'd0, 1'b0, 1'b0, "After reset should be invalid");
        end

        @(posedge clk);
        $display("========================================");
        $display("tb_latency_pipe: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        if (fail_count == 0) $display("ALL TESTS PASSED");
        $finish;
    end

    initial begin
        $dumpfile("tb_latency_pipe.vcd");
        $dumpvars(0, tb_latency_pipe);
    end

endmodule
