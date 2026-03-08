`timescale 1ns/1ps
//============================================================================
// Testbench : tb_axi_addr_decoder
// Project   : AI_GLASSES — RISC-V Subsystem
// Description : Self-checking testbench for axi_addr_decoder
//============================================================================

module tb_axi_addr_decoder;

    reg        clk;
    reg        rst_n;
    reg [31:0] addr_i;
    wire [1:0] slave_sel_o;

    integer pass_cnt, fail_cnt;

    riscv_axi_addr_decoder #(.ADDR_WIDTH(32)) uut (
        .clk        (clk),
        .rst_n      (rst_n),
        .addr_i     (addr_i),
        .slave_sel_o(slave_sel_o)
    );

    // 100 MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    task check_decode;
        input [31:0] address;
        input [1:0]  expected;
        begin
            addr_i = address;
            @(posedge clk); // latch
            @(posedge clk); // registered output available
            if (slave_sel_o !== expected) begin
                $display("FAIL: addr=0x%08h expected=%0d got=%0d", address, expected, slave_sel_o);
                fail_cnt = fail_cnt + 1;
            end else begin
                $display("PASS: addr=0x%08h -> slave=%0d", address, slave_sel_o);
                pass_cnt = pass_cnt + 1;
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

        // S0: Boot ROM 0x0xxx_xxxx
        check_decode(32'h0000_0000, 2'd0);
        check_decode(32'h0000_1000, 2'd0);
        check_decode(32'h0FFF_FFFF, 2'd0);

        // S1: SRAM 0x1xxx_xxxx
        check_decode(32'h1000_0000, 2'd1);
        check_decode(32'h1ABC_DEF0, 2'd1);

        // S2: Periph 0x2xxx - 0x4xxx
        check_decode(32'h2000_0000, 2'd2);
        check_decode(32'h3000_0000, 2'd2);
        check_decode(32'h4000_0000, 2'd2);
        check_decode(32'h4FFF_FFFF, 2'd2);

        // S3: DDR 0x8xxx+
        check_decode(32'h8000_0000, 2'd3);
        check_decode(32'hA000_0000, 2'd3);
        check_decode(32'hFFFF_FFFF, 2'd3);
        check_decode(32'h5000_0000, 2'd3);  // 0x5 not in 0-4, so DDR default

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
