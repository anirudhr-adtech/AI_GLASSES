`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem — Testbench
// Module: tb_power_spectrum
//////////////////////////////////////////////////////////////////////////////

module tb_power_spectrum;

    reg         clk, rst_n;
    reg         start;
    wire [15:0] fft_re_i, fft_im_i;
    wire [9:0]  fft_addr;
    wire        fft_rd_en;
    wire        done;
    wire [31:0] pwr_data;
    wire [9:0]  pwr_addr;
    wire        pwr_valid;

    integer pass_count = 0;
    integer fail_count = 0;

    power_spectrum uut (
        .clk         (clk),
        .rst_n       (rst_n),
        .start_i     (start),
        .fft_re_i    (fft_re_i),
        .fft_im_i    (fft_im_i),
        .fft_addr_o  (fft_addr),
        .fft_rd_en_o (fft_rd_en),
        .done_o      (done),
        .pwr_data_o  (pwr_data),
        .pwr_addr_o  (pwr_addr),
        .pwr_valid_o (pwr_valid)
    );

    always #5 clk = ~clk;

    // Model FFT output memory: Re = addr*10, Im = addr*5
    reg [15:0] fft_re_mem [0:1023];
    reg [15:0] fft_im_mem [0:1023];
    reg [15:0] fft_re_reg, fft_im_reg;

    assign fft_re_i = fft_re_reg;
    assign fft_im_i = fft_im_reg;

    integer j;
    initial begin
        for (j = 0; j < 1024; j = j + 1) begin
            fft_re_mem[j] = (j < 513) ? j[15:0] * 10 : 16'd0;
            fft_im_mem[j] = (j < 513) ? j[15:0] * 5  : 16'd0;
        end
    end

    always @(posedge clk) begin
        if (fft_rd_en) begin
            fft_re_reg <= fft_re_mem[fft_addr];
            fft_im_reg <= fft_im_mem[fft_addr];
        end
    end

    integer out_count;
    reg [31:0] pwr_bin0, pwr_bin1, pwr_bin10;

    initial begin
        clk   = 0;
        rst_n = 0;
        start = 0;
        fft_re_reg = 0;
        fft_im_reg = 0;
        out_count = 0;
        pwr_bin0  = 0;
        pwr_bin1  = 0;
        pwr_bin10 = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // Start
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        // Collect outputs
        begin : collect_block
            fork
                begin : timeout_branch
                    repeat (5000) @(posedge clk);
                    $display("FAIL: Timeout");
                    fail_count = fail_count + 1;
                    disable wait_done_branch;
                end
                begin : wait_done_branch
                    while (!done) begin
                        @(posedge clk);
                        if (pwr_valid) begin
                            out_count = out_count + 1;
                            if (pwr_addr == 10'd0) pwr_bin0  = pwr_data;
                            if (pwr_addr == 10'd1) pwr_bin1  = pwr_data;
                            if (pwr_addr == 10'd10) pwr_bin10 = pwr_data;
                        end
                    end
                    disable timeout_branch;
                end
            join
        end

        // Test 1: Should output 513 bins
        if (out_count == 513) begin
            pass_count = pass_count + 1;
            $display("PASS: Output count = %0d", out_count);
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Output count = %0d, expected 513", out_count);
        end

        // Test 2: Bin 0 power = 0^2 + 0^2 = 0
        if (pwr_bin0 == 32'd0) begin
            pass_count = pass_count + 1;
            $display("PASS: Bin 0 power = 0");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Bin 0 power = %0d, expected 0", pwr_bin0);
        end

        // Test 3: Bin 1 power = (10)^2 + (5)^2 = 125
        if (pwr_bin1 == 32'd125) begin
            pass_count = pass_count + 1;
            $display("PASS: Bin 1 power = 125");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Bin 1 power = %0d, expected 125", pwr_bin1);
        end

        // Test 4: Bin 10 power = (100)^2 + (50)^2 = 12500
        if (pwr_bin10 == 32'd12500) begin
            pass_count = pass_count + 1;
            $display("PASS: Bin 10 power = 12500");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Bin 10 power = %0d, expected 12500", pwr_bin10);
        end

        $display("=== tb_power_spectrum: %0d PASSED, %0d FAILED ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $finish;
    end

endmodule
