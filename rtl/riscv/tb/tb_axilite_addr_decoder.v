`timescale 1ns/1ps
//============================================================================
// Testbench : tb_axilite_addr_decoder
// Project   : AI_GLASSES — RISC-V Subsystem
// Description : Self-checking testbench for axilite_addr_decoder
//============================================================================

module tb_axilite_addr_decoder;

    reg        clk;
    reg        rst_n;
    reg [31:0] addr_i;
    wire [3:0] slave_sel_o;
    wire       decode_error_o;

    integer pass_cnt, fail_cnt;

    riscv_axilite_addr_decoder #(
        .ADDR_WIDTH(32),
        .NUM_SLAVES(8)
    ) uut (
        .clk           (clk),
        .rst_n         (rst_n),
        .addr_i        (addr_i),
        .slave_sel_o   (slave_sel_o),
        .decode_error_o(decode_error_o)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task check;
        input [31:0] address;
        input [2:0]  exp_sel;
        input        exp_err;
        begin
            addr_i = address;
            @(posedge clk);
            @(posedge clk); // registered
            if (exp_err) begin
                if (decode_error_o !== 1'b1) begin
                    $display("FAIL: addr=0x%08h expected decode_error=1 got=%0d", address, decode_error_o);
                    fail_cnt = fail_cnt + 1;
                end else begin
                    $display("PASS: addr=0x%08h -> decode_error", address);
                    pass_cnt = pass_cnt + 1;
                end
            end else begin
                if (slave_sel_o !== exp_sel || decode_error_o !== 1'b0) begin
                    $display("FAIL: addr=0x%08h expected sel=%0d err=0 got sel=%0d err=%0d",
                             address, exp_sel, slave_sel_o, decode_error_o);
                    fail_cnt = fail_cnt + 1;
                end else begin
                    $display("PASS: addr=0x%08h -> slave=%0d", address, slave_sel_o);
                    pass_cnt = pass_cnt + 1;
                end
            end
        end
    endtask

    initial begin
        pass_cnt = 0;
        fail_cnt = 0;
        rst_n    = 0;
        addr_i   = 32'd0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Slave 0: UART 0x2000_0000
        check(32'h2000_0000, 3'd0, 1'b0);
        check(32'h2000_00FF, 3'd0, 1'b0);

        // Slave 1: Timer 0x2000_0100
        check(32'h2000_0100, 3'd1, 1'b0);

        // Slave 2: IRQ Ctrl 0x2000_0200
        check(32'h2000_0200, 3'd2, 1'b0);

        // Slave 3: GPIO 0x2000_0300
        check(32'h2000_0300, 3'd3, 1'b0);

        // Slave 4: Camera 0x2000_0400
        check(32'h2000_0400, 3'd4, 1'b0);

        // Slave 5: Audio 0x2000_0500
        check(32'h2000_0500, 3'd5, 1'b0);

        // Slave 6: I2C 0x2000_0600
        check(32'h2000_0600, 3'd6, 1'b0);

        // Slave 7: SPI 0x2000_0700
        check(32'h2000_0700, 3'd7, 1'b0);

        // Out of range: 0x2000_0800 -> error
        check(32'h2000_0800, 3'd0, 1'b1);

        // Completely wrong region: 0x3000_0000 -> error
        check(32'h3000_0000, 3'd0, 1'b1);

        // 0x1000_0000 -> error
        check(32'h1000_0000, 3'd0, 1'b1);

        $display("");
        $display("========================================");
        $display("  Results: %0d passed, %0d failed", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  SOME TESTS FAILED");
        $display("========================================");
        $finish;
    end

endmodule
