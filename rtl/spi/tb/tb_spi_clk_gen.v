`timescale 1ns / 1ps
//============================================================================
// tb_spi_clk_gen.v — Self-checking testbench for spi_clk_gen
//============================================================================

module tb_spi_clk_gen;

    reg        clk, rst_n;
    reg  [7:0] div;
    reg        cpol, cpha, sclk_en;
    wire       sclk_o, sample_edge, shift_edge;

    spi_clk_gen uut (
        .clk           (clk),
        .rst_n         (rst_n),
        .div_i         (div),
        .cpol_i        (cpol),
        .cpha_i        (cpha),
        .sclk_en       (sclk_en),
        .sclk_o        (sclk_o),
        .sample_edge_o (sample_edge),
        .shift_edge_o  (shift_edge)
    );

    integer pass_count = 0;
    integer fail_count = 0;
    integer sample_cnt, shift_cnt;

    task check;
        input [255:0] msg;
        input         cond;
    begin
        if (cond) pass_count = pass_count + 1;
        else begin
            fail_count = fail_count + 1;
            $display("FAIL: %0s at time %0t", msg, $time);
        end
    end
    endtask

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        rst_n = 0; div = 8'd4; cpol = 0; cpha = 0; sclk_en = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // CPOL=0: idle low
        check("SCLK idle low (CPOL=0)", sclk_o == 1'b0);

        // Enable and count edges (Mode 0: CPOL=0, CPHA=0)
        sclk_en = 1;
        sample_cnt = 0;
        shift_cnt = 0;
        repeat (200) begin
            @(posedge clk);
            if (sample_edge) sample_cnt = sample_cnt + 1;
            if (shift_edge) shift_cnt = shift_cnt + 1;
        end
        check("Mode 0: sample edges generated", sample_cnt > 0);
        check("Mode 0: shift edges generated", shift_cnt > 0);

        sclk_en = 0;
        @(posedge clk); @(posedge clk);

        // Test Mode 3 (CPOL=1, CPHA=1)
        cpol = 1; cpha = 1;
        @(posedge clk);
        check("SCLK idle high (CPOL=1)", sclk_o == 1'b1);

        sclk_en = 1;
        sample_cnt = 0;
        shift_cnt = 0;
        repeat (200) begin
            @(posedge clk);
            if (sample_edge) sample_cnt = sample_cnt + 1;
            if (shift_edge) shift_cnt = shift_cnt + 1;
        end
        check("Mode 3: sample edges generated", sample_cnt > 0);
        check("Mode 3: shift edges generated", shift_cnt > 0);

        sclk_en = 0;
        @(posedge clk);

        $display("========================================");
        if (fail_count == 0)
            $display("SPI CLK GEN TB: ALL %0d TESTS PASSED", pass_count);
        else
            $display("SPI CLK GEN TB: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        $finish;
    end

endmodule
