`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Camera Subsystem
// Testbench: tb_isp_lite
// Description: Self-checking testbench for ISP-lite pipeline wrapper
//////////////////////////////////////////////////////////////////////////////

module tb_isp_lite;

    // ----------------------------------------------------------------
    // Parameters
    // ----------------------------------------------------------------
    localparam CLK_PERIOD = 10; // 100 MHz

    // ----------------------------------------------------------------
    // DUT signals
    // ----------------------------------------------------------------
    reg         clk;
    reg         rst_n;
    reg         start;
    reg         bypass;
    reg  [23:0] scale_x, scale_y;
    reg  [9:0]  src_width, src_height;
    reg  [9:0]  dst_width, dst_height;
    reg  [15:0] in_pixel;
    reg         in_valid;
    wire        in_ready;
    wire [127:0] out_data;
    wire        out_valid;
    reg         out_ready;
    wire        done;

    // ----------------------------------------------------------------
    // Test tracking
    // ----------------------------------------------------------------
    integer test_num;
    integer pass_count;
    integer fail_count;
    integer pixel_count;

    // ----------------------------------------------------------------
    // Clock generation
    // ----------------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ----------------------------------------------------------------
    // DUT instantiation
    // ----------------------------------------------------------------
    isp_lite u_dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .start_i      (start),
        .bypass_i     (bypass),
        .scale_x_i    (scale_x),
        .scale_y_i    (scale_y),
        .src_width_i  (src_width),
        .src_height_i (src_height),
        .dst_width_i  (dst_width),
        .dst_height_i (dst_height),
        .in_pixel_i   (in_pixel),
        .in_valid_i   (in_valid),
        .in_ready_o   (in_ready),
        .out_data_o   (out_data),
        .out_valid_o  (out_valid),
        .out_ready_i  (out_ready),
        .done_o       (done)
    );

    // ----------------------------------------------------------------
    // Tasks
    // ----------------------------------------------------------------
    task reset_dut;
        begin
            rst_n    <= 1'b0;
            start    <= 1'b0;
            bypass   <= 1'b0;
            in_pixel <= 16'd0;
            in_valid <= 1'b0;
            out_ready <= 1'b1;
            repeat (5) @(posedge clk);
            rst_n <= 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task check(input [255:0] test_name, input condition);
        begin
            test_num = test_num + 1;
            if (condition) begin
                $display("[PASS] Test %0d: %0s", test_num, test_name);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] Test %0d: %0s", test_num, test_name);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // ----------------------------------------------------------------
    // Main test
    // ----------------------------------------------------------------
    initial begin
        $display("============================================================");
        $display("  TB: isp_lite — ISP Pipeline Wrapper");
        $display("============================================================");

        test_num   = 0;
        pass_count = 0;
        fail_count = 0;

        reset_dut;

        // Test 1: Reset state
        check("done deasserted after reset", done == 1'b0);
        check("out_valid deasserted after reset", out_valid == 1'b0);

        // Test 2: Start pipeline (normal mode)
        src_width  <= 10'd8;
        src_height <= 10'd4;
        dst_width  <= 10'd4;
        dst_height <= 10'd2;
        scale_x    <= 24'h020000; // 2.0 in Q8.16
        scale_y    <= 24'h020000;
        bypass     <= 1'b0;
        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        // Feed some YUV422 pixels
        pixel_count = 0;
        repeat (32) begin
            @(posedge clk);
            in_pixel <= {8'hA0, 8'h80}; // Y=A0, U=80
            in_valid <= 1'b1;
            pixel_count = pixel_count + 1;
        end
        in_valid <= 1'b0;

        // Wait for some output
        repeat (50) @(posedge clk);

        check("Pipeline started (not in IDLE)", u_dut.state != 2'd0 || done == 1'b1);

        // Test 3: Bypass mode
        reset_dut;
        src_width  <= 10'd4;
        src_height <= 10'd2;
        dst_width  <= 10'd4;
        dst_height <= 10'd2;
        scale_x    <= 24'h010000; // 1.0
        scale_y    <= 24'h010000;
        bypass     <= 1'b1;
        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        // Feed pixels in bypass mode
        repeat (8) begin
            @(posedge clk);
            in_pixel <= 16'hFF80; // Y=FF, U=80
            in_valid <= 1'b1;
        end
        in_valid <= 1'b0;
        repeat (20) @(posedge clk);

        check("Bypass mode: pipeline active", u_dut.pipeline_active == 1'b1 || done == 1'b1);

        // ----------------------------------------------------------------
        // Summary
        // ----------------------------------------------------------------
        $display("============================================================");
        $display("  Results: %0d passed, %0d failed out of %0d tests",
                 pass_count, fail_count, test_num);
        $display("============================================================");
        if (fail_count == 0)
            $display("  >>> ALL TESTS PASSED <<<");
        else
            $display("  >>> SOME TESTS FAILED <<<");
        $finish;
    end

    // Timeout
    initial begin
        #100000;
        $display("[TIMEOUT] Simulation exceeded time limit");
        $finish;
    end

endmodule
