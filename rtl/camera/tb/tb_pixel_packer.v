`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Camera Subsystem
// Testbench: tb_pixel_packer
//////////////////////////////////////////////////////////////////////////////

module tb_pixel_packer;

    reg         clk;
    reg         rst_n;
    reg  [23:0] in_pixel;
    reg         in_valid;
    wire [127:0] out_data;
    wire        out_valid;
    reg         out_ready;

    integer err_count;

    pixel_packer uut (
        .clk         (clk),
        .rst_n       (rst_n),
        .in_pixel_i  (in_pixel),
        .in_valid_i  (in_valid),
        .out_data_o  (out_data),
        .out_valid_o (out_valid),
        .out_ready_i (out_ready)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        err_count = 0;
        rst_n     = 0;
        in_pixel  = 0;
        in_valid  = 0;
        out_ready = 1;

        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Send 4 pixels: should produce one 128-bit word
        // Pixel 0: R=0xAA, G=0xBB, B=0xCC
        @(posedge clk); in_valid = 1; in_pixel = 24'hAABBCC;
        // Pixel 1: R=0x11, G=0x22, B=0x33
        @(posedge clk); in_pixel = 24'h112233;
        // Pixel 2: R=0x44, G=0x55, B=0x66
        @(posedge clk); in_pixel = 24'h445566;
        // Pixel 3: R=0x77, G=0x88, B=0x99
        @(posedge clk); in_pixel = 24'h778899;
        @(posedge clk); in_valid = 0;

        // Wait for output
        repeat (2) @(posedge clk);
        #1;

        // Verify output word packing
        // [31:0]=pixel0_RGBX, [63:32]=pixel1_RGBX, [95:64]=pixel2_RGBX, [127:96]=pixel3_RGBX
        if (out_data[31:0] !== 32'hAABBCC00) begin
            $display("FAIL: pixel[0] = %h, expected AABBCC00", out_data[31:0]);
            err_count = err_count + 1;
        end
        if (out_data[63:32] !== 32'h11223300) begin
            $display("FAIL: pixel[1] = %h, expected 11223300", out_data[63:32]);
            err_count = err_count + 1;
        end
        if (out_data[95:64] !== 32'h44556600) begin
            $display("FAIL: pixel[2] = %h, expected 44556600", out_data[95:64]);
            err_count = err_count + 1;
        end
        if (out_data[127:96] !== 32'h77889900) begin
            $display("FAIL: pixel[3] = %h, expected 77889900", out_data[127:96]);
            err_count = err_count + 1;
        end

        // Send another 4 pixels to test continuous operation
        @(posedge clk); in_valid = 1; in_pixel = 24'hFF0000;
        @(posedge clk); in_pixel = 24'h00FF00;
        @(posedge clk); in_pixel = 24'h0000FF;
        @(posedge clk); in_pixel = 24'hFFFFFF;
        @(posedge clk); in_valid = 0;

        repeat (2) @(posedge clk);

        // Test backpressure: out_ready = 0
        out_ready = 0;
        @(posedge clk); in_valid = 1; in_pixel = 24'h123456;
        @(posedge clk); in_pixel = 24'h789ABC;
        @(posedge clk); in_pixel = 24'hDEF012;
        @(posedge clk); in_pixel = 24'h345678;
        @(posedge clk); in_valid = 0;

        repeat (4) @(posedge clk);
        out_ready = 1;
        repeat (4) @(posedge clk);

        // Summary
        if (err_count == 0)
            $display("PASS: tb_pixel_packer — all tests passed");
        else
            $display("FAIL: tb_pixel_packer — %0d errors", err_count);

        $finish;
    end

endmodule
