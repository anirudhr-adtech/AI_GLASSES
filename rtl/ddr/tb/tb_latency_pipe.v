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
        .out_valid    (out_valid),
        .out_data     (out_data),
        .out_id       (out_id),
        .out_last     (out_last),
        .out_ready    (out_ready),
        .pipe_empty_o ()
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

    // Pipeline latency: data enters pipe_data[0] on the capturing posedge,
    // then shifts through stages 1..LATENCY-1. Output appears LATENCY cycles
    // after the input posedge (pipe[0]→pipe[1]→...→pipe[LATENCY-1]).
    // With Verilator --timing + #1, the combinational out_valid reflects the
    // NBA-updated pipe_valid[LATENCY-1] on the same posedge it transitions.
    localparam EFF_LATENCY = LATENCY;

    initial begin
        pass_count = 0;
        fail_count = 0;
        rst_n = 0; in_valid = 0; in_data = 0; in_id = 0; in_last = 0; out_ready = 1;

        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Test 1: Single entry — find actual latency empirically
        in_valid = 1;
        in_data = 128'hAAAA_BBBB_CCCC_DDDD_1111_2222_3333_4444;
        in_id = 6'd5;
        in_last = 1;
        @(posedge clk);  // Input captured at this edge
        in_valid = 0; in_data = 0; in_id = 0; in_last = 0;

        // Wait for output to become valid (up to LATENCY+2 cycles)
        cycle_count = 0;
        begin : wait_valid
            integer i;
            for (i = 0; i < LATENCY + 2; i = i + 1) begin
                @(posedge clk); #1;
                cycle_count = cycle_count + 1;
                if (out_valid) begin
                    // Verify data
                    if (out_data == 128'hAAAA_BBBB_CCCC_DDDD_1111_2222_3333_4444 &&
                        out_id == 6'd5 && out_last == 1'b1) begin
                        pass_count = pass_count + 1;
                    end else begin
                        fail_count = fail_count + 1;
                        $display("FAIL: Latency output data mismatch");
                    end
                    i = LATENCY + 2; // break
                end
            end
        end
        if (!out_valid) begin
            fail_count = fail_count + 1;
            $display("FAIL: Output never became valid");
        end

        // Test 2: Back-to-back entries
        repeat (2) @(posedge clk);

        in_valid = 1; in_data = 128'h1; in_id = 6'd1; in_last = 0;
        @(posedge clk);  // Entry 1 captured (edge B)
        in_data = 128'h2; in_id = 6'd2; in_last = 0;
        @(posedge clk);  // Entry 2 captured (edge B+1)
        in_data = 128'h3; in_id = 6'd3; in_last = 1;
        @(posedge clk);  // Entry 3 captured (edge B+2)
        in_valid = 0;

        // Use negedge sampling to avoid NBA race at posedge.
        // Entry 1 enters pipe[0] at B, reaches pipe[3] at B+3.
        // At negedge of B+3, pipe[3] should have entry 1.
        begin : b2b_check
            integer wait_cnt;
            // Wait for out_valid at negedge
            for (wait_cnt = 0; wait_cnt < LATENCY + 4; wait_cnt = wait_cnt + 1) begin
                @(negedge clk);
                if (out_valid) wait_cnt = LATENCY + 4;
            end
            // Check entry 1
            if (out_valid && out_data == 128'h1 && out_id == 6'd1 && out_last == 1'b0)
                pass_count = pass_count + 1;
            else begin
                fail_count = fail_count + 1;
                $display("FAIL: B2B entry 1 data=%h id=%h last=%b v=%b", out_data, out_id, out_last, out_valid);
            end
            // Entry 2
            @(negedge clk);
            if (out_valid && out_data == 128'h2 && out_id == 6'd2 && out_last == 1'b0)
                pass_count = pass_count + 1;
            else begin
                fail_count = fail_count + 1;
                $display("FAIL: B2B entry 2 data=%h id=%h last=%b v=%b", out_data, out_id, out_last, out_valid);
            end
            // Entry 3
            @(negedge clk);
            if (out_valid && out_data == 128'h3 && out_id == 6'd3 && out_last == 1'b1)
                pass_count = pass_count + 1;
            else begin
                fail_count = fail_count + 1;
                $display("FAIL: B2B entry 3 data=%h id=%h last=%b v=%b", out_data, out_id, out_last, out_valid);
            end
        end

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
            @(posedge clk); #1;
            check_output(128'd0, 6'd0, 1'b0, 1'b0, "After reset should be invalid");
        end

        @(posedge clk);
        $display("========================================");
        $display("tb_latency_pipe: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        if (fail_count == 0) $display("ALL TESTS PASSED");
        $finish;
    end

    // Timeout watchdog
    initial begin
        #10000;
        $display("TIMEOUT: Simulation exceeded 10us");
        $finish;
    end

    initial begin
        $dumpfile("tb_latency_pipe.vcd");
        $dumpvars(0, tb_latency_pipe);
    end

endmodule
