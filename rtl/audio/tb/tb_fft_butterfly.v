`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem — Testbench
// Module: tb_fft_butterfly
//////////////////////////////////////////////////////////////////////////////

module tb_fft_butterfly;

    reg         clk, rst_n, en;
    reg  signed [15:0] a_re, a_im, b_re, b_im, w_re, w_im;
    wire signed [15:0] p_re, p_im, q_re, q_im;
    wire               valid;

    integer pass_count = 0;
    integer fail_count = 0;

    fft_butterfly uut (
        .clk     (clk),
        .rst_n   (rst_n),
        .en      (en),
        .a_re    (a_re),
        .a_im    (a_im),
        .b_re    (b_re),
        .b_im    (b_im),
        .w_re    (w_re),
        .w_im    (w_im),
        .p_re    (p_re),
        .p_im    (p_im),
        .q_re    (q_re),
        .q_im    (q_im),
        .valid_o (valid)
    );

    always #5 clk = ~clk;

    task check_near;
        input [255:0] name;
        input signed [15:0] actual;
        input signed [15:0] expected;
        input [15:0] tolerance;
        begin
            if (actual >= expected - $signed({1'b0, tolerance}) &&
                actual <= expected + $signed({1'b0, tolerance})) begin
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: %0s — got %0d, expected %0d (+/-%0d)", name, actual, expected, tolerance);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        clk   = 0;
        rst_n = 0;
        en    = 0;
        a_re  = 0; a_im = 0;
        b_re  = 0; b_im = 0;
        w_re  = 0; w_im = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // Test 1: W = 1+0j (w_re=32767, w_im=0), A=1000+0j, B=500+0j
        // W*B = 500+0j, P = (1000+500)/2 = 750, Q = (1000-500)/2 = 250
        @(posedge clk);
        a_re = 16'd1000; a_im = 16'd0;
        b_re = 16'd500;  b_im = 16'd0;
        w_re = 16'd32767; w_im = 16'd0;
        en   = 1;
        @(posedge clk);
        en = 0;

        // Wait for 2-cycle pipeline
        @(posedge clk);
        @(posedge clk);

        if (valid) begin
            check_near("T1 p_re", p_re, 16'd750, 16'd5);
            check_near("T1 p_im", p_im, 16'd0, 16'd2);
            check_near("T1 q_re", q_re, 16'd250, 16'd5);
            check_near("T1 q_im", q_im, 16'd0, 16'd2);
        end else begin
            $display("FAIL: T1 valid not asserted");
            fail_count = fail_count + 4;
        end

        // Test 2: W = 0-1j (w_re=0, w_im=-32768), A=100+200j, B=300+400j
        // W*B = (0*300 - (-32768)*400)/32768 + j(0*400 + (-32768)*300)/32768
        //     = 400 + j(-300) = 400 - 300j
        // P = (A + W*B)/2 = (100+400 + (200-300)j)/2 = 250 - 50j
        // Q = (A - W*B)/2 = (100-400 + (200+300)j)/2 = -150 + 250j
        @(posedge clk);
        a_re = 16'd100;  a_im = 16'd200;
        b_re = 16'd300;  b_im = 16'd400;
        w_re = 16'd0;    w_im = -16'd32768;
        en   = 1;
        @(posedge clk);
        en = 0;
        @(posedge clk);
        @(posedge clk);

        if (valid) begin
            check_near("T2 p_re", p_re, 16'd250, 16'd10);
            check_near("T2 q_re", q_re, -16'd150, 16'd10);
        end else begin
            $display("FAIL: T2 valid not asserted");
            fail_count = fail_count + 2;
        end

        // Test 3: Zero inputs
        @(posedge clk);
        a_re = 0; a_im = 0; b_re = 0; b_im = 0;
        w_re = 16'd32767; w_im = 0;
        en = 1;
        @(posedge clk);
        en = 0;
        @(posedge clk);
        @(posedge clk);

        if (valid) begin
            check_near("T3 p_re zero", p_re, 16'd0, 16'd1);
            check_near("T3 q_re zero", q_re, 16'd0, 16'd1);
        end else begin
            $display("FAIL: T3 valid not asserted");
            fail_count = fail_count + 2;
        end

        $display("=== tb_fft_butterfly: %0d PASSED, %0d FAILED ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $finish;
    end

endmodule
