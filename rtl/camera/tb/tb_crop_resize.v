`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Camera Subsystem
// Testbench: tb_crop_resize
// Description: Self-checking testbench for crop resize (bilinear wrapper)
//////////////////////////////////////////////////////////////////////////////

module tb_crop_resize;

    localparam CLK_PERIOD = 10;

    reg         clk;
    reg         rst_n;
    reg         start;
    reg  [23:0] scale_x, scale_y;
    reg  [9:0]  src_width, src_height;
    reg  [9:0]  dst_width, dst_height;
    reg  [23:0] in_pixel;
    reg         in_valid;
    wire        in_ready;
    wire [23:0] out_pixel;
    wire        out_valid;
    wire        done;

    integer test_num, pass_count, fail_count;
    integer out_pixel_count;

    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    crop_resize u_dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .start_i      (start),
        .scale_x_i    (scale_x),
        .scale_y_i    (scale_y),
        .src_width_i  (src_width),
        .src_height_i (src_height),
        .dst_width_i  (dst_width),
        .dst_height_i (dst_height),
        .in_pixel_i   (in_pixel),
        .in_valid_i   (in_valid),
        .in_ready_o   (in_ready),
        .out_pixel_o  (out_pixel),
        .out_valid_o  (out_valid),
        .done_o       (done)
    );

    task reset_dut;
        begin
            rst_n    = 1'b0;
            start    = 1'b0;
            in_pixel = 24'd0;
            in_valid = 1'b0;
            scale_x  = 24'd0;
            scale_y  = 24'd0;
            src_width  = 10'd0;
            src_height = 10'd0;
            dst_width  = 10'd0;
            dst_height = 10'd0;
            repeat (5) @(posedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task check(input [255:0] name, input cond);
        begin
            test_num = test_num + 1;
            if (cond) begin
                $display("[PASS] Test %0d: %0s", test_num, name);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] Test %0d: %0s", test_num, name);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Count output pixels
    always @(posedge clk) begin
        if (!rst_n)
            out_pixel_count <= 0;
        else if (out_valid)
            out_pixel_count <= out_pixel_count + 1;
    end

    initial begin
        $display("============================================================");
        $display("  TB: crop_resize — Bilinear Resize Wrapper");
        $display("============================================================");

        test_num   = 0;
        pass_count = 0;
        fail_count = 0;
        out_pixel_count = 0;

        reset_dut;

        // Test 1: Reset state
        check("done deasserted after reset", done == 1'b0);
        check("out_valid deasserted after reset", out_valid == 1'b0);

        // Test 2: 1:1 passthrough (4x4 -> 4x4)
        src_width  = 10'd4;
        src_height = 10'd4;
        dst_width  = 10'd4;
        dst_height = 10'd4;
        scale_x    = 24'h010000; // 1.0 Q8.16
        scale_y    = 24'h010000;
        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        // Feed 16 pixels (4x4)
        begin : feed_px
            integer i, timeout;
            for (i = 0; i < 16; i = i + 1) begin
                @(posedge clk);
                timeout = 0;
                while (!in_ready && timeout < 500) begin
                    @(posedge clk);
                    timeout = timeout + 1;
                end
                in_pixel = {8'd100, 8'd150, 8'd200}; // constant color
                in_valid = 1'b1;
                @(posedge clk);
                in_valid = 1'b0;
            end
        end

        // Wait for output
        repeat (100) @(posedge clk);

        check("1:1 resize produces output", out_pixel_count > 0 || done);

        // Test 3: Downscale (8x8 -> 4x4)
        reset_dut;
        out_pixel_count = 0;

        src_width  = 10'd8;
        src_height = 10'd8;
        dst_width  = 10'd4;
        dst_height = 10'd4;
        scale_x    = 24'h020000; // 2.0
        scale_y    = 24'h020000;
        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        // Feed dst_height * src_width pixels (one source line per output row)
        begin : feed_px2
            integer j, timeout2;
            for (j = 0; j < 32; j = j + 1) begin
                @(posedge clk);
                timeout2 = 0;
                while (!in_ready && timeout2 < 500) begin
                    @(posedge clk);
                    timeout2 = timeout2 + 1;
                end
                in_pixel = {j[7:0], j[7:0], j[7:0]};
                in_valid = 1'b1;
                @(posedge clk);
                in_valid = 1'b0;
            end
        end

        repeat (200) @(posedge clk);
        check("Downscale 2x produces some output", out_pixel_count > 0 || done);

        // Summary
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

    initial begin
        #300000;
        $display("[TIMEOUT]");
        $finish;
    end

endmodule
