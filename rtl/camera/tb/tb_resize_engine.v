`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Camera Subsystem
// Testbench: tb_resize_engine
//////////////////////////////////////////////////////////////////////////////

module tb_resize_engine;

    reg        clk;
    reg        rst_n;
    reg        start;
    reg [23:0] scale_x, scale_y;
    reg [9:0]  src_w, src_h, dst_w, dst_h;
    reg [23:0] in_pixel;
    reg        in_valid;
    wire       in_ready;
    wire [23:0] out_pixel;
    wire       out_valid;
    wire       done;

    integer err_count;
    integer out_cnt;
    integer timeout_cnt;

    resize_engine uut (
        .clk          (clk),
        .rst_n        (rst_n),
        .start_i      (start),
        .scale_x_i    (scale_x),
        .scale_y_i    (scale_y),
        .src_width_i  (src_w),
        .src_height_i (src_h),
        .dst_width_i  (dst_w),
        .dst_height_i (dst_h),
        .in_pixel_i   (in_pixel),
        .in_valid_i   (in_valid),
        .in_ready_o   (in_ready),
        .out_pixel_o  (out_pixel),
        .out_valid_o  (out_valid),
        .done_o       (done)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Pixel source: provide pixels when ready
    reg [9:0] src_col;

    always @(posedge clk) begin
        if (!rst_n) begin
            in_valid <= 0;
            in_pixel <= 0;
            src_col  <= 0;
        end else begin
            if (in_ready) begin
                in_valid <= 1;
                // Generate a simple gradient
                in_pixel <= {src_col[7:0], src_col[7:0], src_col[7:0]};
                src_col  <= src_col + 1;
            end else begin
                in_valid <= 0;
            end
        end
    end

    initial begin
        err_count = 0;
        out_cnt   = 0;
        rst_n     = 0;
        start     = 0;
        // 1:1 scale (no resize) — scale = 1.0 in Q8.16 = 0x010000
        scale_x   = 24'h01_0000;
        scale_y   = 24'h01_0000;
        src_w     = 10'd8;
        src_h     = 10'd4;
        dst_w     = 10'd8;
        dst_h     = 10'd4;

        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // Start resize
        start = 1;
        @(posedge clk);
        start = 0;

        // Wait for done or timeout
        timeout_cnt = 0;
        while (!done && timeout_cnt < 5000) begin
            @(posedge clk);
            timeout_cnt = timeout_cnt + 1;
        end

        if (timeout_cnt >= 5000) begin
            $display("FAIL: resize_engine timed out");
            err_count = err_count + 1;
        end else begin
            $display("INFO: resize_engine completed in %0d cycles", timeout_cnt);
        end

        repeat (10) @(posedge clk);

        // Summary
        if (err_count == 0)
            $display("PASS: tb_resize_engine — resize completed (out_pixels=%0d)", out_cnt);
        else
            $display("FAIL: tb_resize_engine — %0d errors", err_count);

        $finish;
    end

    // Count output pixels
    always @(posedge clk) begin
        if (out_valid)
            out_cnt = out_cnt + 1;
    end

endmodule
