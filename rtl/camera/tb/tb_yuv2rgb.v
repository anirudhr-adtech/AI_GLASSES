`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Camera Subsystem
// Testbench: tb_yuv2rgb
//////////////////////////////////////////////////////////////////////////////

module tb_yuv2rgb;

    reg        clk;
    reg        rst_n;
    reg        in_valid;
    reg  [7:0] y_i, u_i, v_i;
    wire       out_valid;
    wire [7:0] r_o, g_o, b_o;

    integer err_count;

    yuv2rgb uut (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (in_valid),
        .y_i       (y_i),
        .u_i       (u_i),
        .v_i       (v_i),
        .out_valid (out_valid),
        .r_o       (r_o),
        .g_o       (g_o),
        .b_o       (b_o)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Tolerance check
    function integer abs_diff;
        input [7:0] a;
        input [7:0] b;
        begin
            if (a > b) abs_diff = a - b;
            else abs_diff = b - a;
        end
    endfunction

    task check_rgb;
        input [7:0] exp_r, exp_g, exp_b;
        input integer tol;
        integer timeout;
        begin
            // Wait for out_valid with timeout guard
            timeout = 0;
            @(posedge clk);
            while (!out_valid && timeout < 100) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 100) begin
                $display("FAIL: Timeout waiting for out_valid");
                err_count = err_count + 1;
            end
            #1;
            if (abs_diff(r_o, exp_r) > tol) begin
                $display("FAIL: R=%0d, expected ~%0d (tol=%0d)", r_o, exp_r, tol);
                err_count = err_count + 1;
            end
            if (abs_diff(g_o, exp_g) > tol) begin
                $display("FAIL: G=%0d, expected ~%0d (tol=%0d)", g_o, exp_g, tol);
                err_count = err_count + 1;
            end
            if (abs_diff(b_o, exp_b) > tol) begin
                $display("FAIL: B=%0d, expected ~%0d (tol=%0d)", b_o, exp_b, tol);
                err_count = err_count + 1;
            end
            $display("  YUV->RGB: R=%0d G=%0d B=%0d", r_o, g_o, b_o);
        end
    endtask

    initial begin
        err_count = 0;
        rst_n     = 0;
        in_valid  = 0;
        y_i       = 0;
        u_i       = 0;
        v_i       = 0;

        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Test 1: White (Y=255, U=128, V=128 -> R=255, G=255, B=255)
        $display("Test 1: White");
        in_valid = 1; y_i = 255; u_i = 128; v_i = 128;
        @(posedge clk);
        #1;
        in_valid = 0;
        check_rgb(255, 255, 255, 3);

        // Test 2: Black (Y=0, U=128, V=128 -> R=0, G=0, B=0)
        $display("Test 2: Black");
        in_valid = 1; y_i = 0; u_i = 128; v_i = 128;
        @(posedge clk);
        #1;
        in_valid = 0;
        check_rgb(0, 0, 0, 3);

        // Test 3: Pure Red (Y=82, U=90, V=240 -> R~255, G~0, B~0)
        $display("Test 3: Red");
        in_valid = 1; y_i = 82; u_i = 90; v_i = 240;
        @(posedge clk);
        #1;
        in_valid = 0;
        check_rgb(239, 0, 0, 20);

        // Test 4: Pure Green (Y=145, U=54, V=34 -> R~0, G~255, B~0)
        $display("Test 4: Green");
        in_valid = 1; y_i = 145; u_i = 54; v_i = 34;
        @(posedge clk);
        #1;
        in_valid = 0;
        check_rgb(0, 255, 0, 20);

        // Test 5: Pure Blue (Y=41, U=240, V=110 -> R~0, G~0, B~255)
        $display("Test 5: Blue");
        in_valid = 1; y_i = 41; u_i = 240; v_i = 110;
        @(posedge clk);
        #1;
        in_valid = 0;
        check_rgb(0, 0, 243, 20);

        // Summary
        $display("========================================");
        if (err_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("FAIL: tb_yuv2rgb — %0d errors", err_count);
        $display("========================================");

        $finish;
    end

    // Global timeout
    initial begin
        #50000;
        $display("[TIMEOUT] tb_yuv2rgb");
        $finish;
    end

endmodule
