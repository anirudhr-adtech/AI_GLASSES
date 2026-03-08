`timescale 1ns/1ps
//============================================================================
// Module : tb_sram_bank
// Project : AI_GLASSES — RISC-V Subsystem
// Description : Self-checking testbench for sram_bank (dual-port SRAM)
//============================================================================

module tb_sram_bank;

    // ----------------------------------------------------------------
    // Clock
    // ----------------------------------------------------------------
    reg clk;
    initial clk = 1'b0;
    always #5 clk = ~clk; // 100 MHz

    // ----------------------------------------------------------------
    // Pass/fail counters
    // ----------------------------------------------------------------
    integer pass_count;
    integer fail_count;

    // ----------------------------------------------------------------
    // DUT signals
    // ----------------------------------------------------------------
    localparam AW = 15;
    localparam DW = 32;

    reg  [AW-1:0]    a_addr;
    reg               a_en;
    wire [DW-1:0]     a_rdata;

    reg  [AW-1:0]    b_addr;
    reg               b_en;
    reg               b_we;
    reg  [DW/8-1:0]  b_wstrb;
    reg  [DW-1:0]    b_wdata;
    wire [DW-1:0]     b_rdata;

    // ----------------------------------------------------------------
    // DUT
    // ----------------------------------------------------------------
    sram_bank #(
        .ADDR_WIDTH(AW),
        .DATA_WIDTH(DW)
    ) u_dut (
        .clk     (clk),
        .a_addr  (a_addr),
        .a_en    (a_en),
        .a_rdata (a_rdata),
        .b_addr  (b_addr),
        .b_en    (b_en),
        .b_we    (b_we),
        .b_wstrb (b_wstrb),
        .b_wdata (b_wdata),
        .b_rdata (b_rdata)
    );

    // ----------------------------------------------------------------
    // Tasks
    // ----------------------------------------------------------------
    task check_val;
        input [DW-1:0] actual;
        input [DW-1:0] expected;
        input [8*40-1:0] msg;
        begin
            if (actual === expected) begin
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: %0s — exp=0x%08h got=0x%08h at %0t",
                         msg, expected, actual, $time);
            end
        end
    endtask

    task write_word;
        input [AW-1:0] addr;
        input [DW-1:0] data;
        input [3:0]    strb;
        begin
            @(posedge clk);
            b_addr  = addr;
            b_en    = 1'b1;
            b_we    = 1'b1;
            b_wstrb = strb;
            b_wdata = data;
            @(posedge clk);
            b_en    = 1'b0;
            b_we    = 1'b0;
        end
    endtask

    task read_port_a;
        input  [AW-1:0] addr;
        output [DW-1:0] data;
        begin
            @(posedge clk);
            a_addr = addr;
            a_en   = 1'b1;
            @(posedge clk);
            a_en   = 1'b0;
            data   = a_rdata;
        end
    endtask

    task read_port_b;
        input  [AW-1:0] addr;
        output [DW-1:0] data;
        begin
            @(posedge clk);
            b_addr = addr;
            b_en   = 1'b1;
            b_we   = 1'b0;
            @(posedge clk);
            b_en   = 1'b0;
            data   = b_rdata;
        end
    endtask

    task init_signals;
        begin
            a_addr  = {AW{1'b0}};
            a_en    = 1'b0;
            b_addr  = {AW{1'b0}};
            b_en    = 1'b0;
            b_we    = 1'b0;
            b_wstrb = 4'b0000;
            b_wdata = {DW{1'b0}};
        end
    endtask

    // ----------------------------------------------------------------
    // Test: basic write and read-back via Port B
    // ----------------------------------------------------------------
    task test_basic_write_read;
        reg [DW-1:0] rdata;
        begin
            $display("[TEST] Basic write/read via Port B");
            write_word(15'd0, 32'hCAFEBABE, 4'b1111);
            read_port_b(15'd0, rdata);
            check_val(rdata, 32'hCAFEBABE, "B write/read addr 0");

            write_word(15'd100, 32'h12345678, 4'b1111);
            read_port_b(15'd100, rdata);
            check_val(rdata, 32'h12345678, "B write/read addr 100");
        end
    endtask

    // ----------------------------------------------------------------
    // Test: read via Port A after writing via Port B
    // ----------------------------------------------------------------
    task test_cross_port_read;
        reg [DW-1:0] rdata;
        begin
            $display("[TEST] Cross-port: write B, read A");
            write_word(15'd200, 32'hDEADBEEF, 4'b1111);
            read_port_a(15'd200, rdata);
            check_val(rdata, 32'hDEADBEEF, "A read after B write");
        end
    endtask

    // ----------------------------------------------------------------
    // Test: byte-enable writes
    // ----------------------------------------------------------------
    task test_byte_enables;
        reg [DW-1:0] rdata;
        begin
            $display("[TEST] Byte-enable writes");
            // Write full word first
            write_word(15'd300, 32'hAABBCCDD, 4'b1111);

            // Overwrite only byte 0
            write_word(15'd300, 32'h000000FF, 4'b0001);
            read_port_b(15'd300, rdata);
            check_val(rdata, 32'hAABBCCFF, "byte0 strobe");

            // Overwrite only byte 1
            write_word(15'd300, 32'h0000EE00, 4'b0010);
            read_port_b(15'd300, rdata);
            check_val(rdata, 32'hAABBEEFF, "byte1 strobe");

            // Overwrite bytes 2 and 3
            write_word(15'd300, 32'h11220000, 4'b1100);
            read_port_b(15'd300, rdata);
            check_val(rdata, 32'h1122EEFF, "byte2_3 strobe");
        end
    endtask

    // ----------------------------------------------------------------
    // Test: simultaneous dual-port read
    // ----------------------------------------------------------------
    task test_dual_port_read;
        begin
            $display("[TEST] Simultaneous dual-port read");
            // Pre-write two locations
            write_word(15'd400, 32'h11111111, 4'b1111);
            write_word(15'd401, 32'h22222222, 4'b1111);

            // Read both ports simultaneously
            @(posedge clk);
            a_addr = 15'd400;
            a_en   = 1'b1;
            b_addr = 15'd401;
            b_en   = 1'b1;
            b_we   = 1'b0;
            @(posedge clk);
            a_en = 1'b0;
            b_en = 1'b0;
            check_val(a_rdata, 32'h11111111, "dual read port A");
            check_val(b_rdata, 32'h22222222, "dual read port B");
        end
    endtask

    // ----------------------------------------------------------------
    // Main
    // ----------------------------------------------------------------
    initial begin
        pass_count = 0;
        fail_count = 0;

        $display("============================================");
        $display("  TB: sram_bank");
        $display("============================================");

        init_signals;
        repeat (3) @(posedge clk);

        test_basic_write_read;
        test_cross_port_read;
        test_byte_enables;
        test_dual_port_read;

        repeat (5) @(posedge clk);

        $display("============================================");
        $display("  Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
        if (fail_count == 0)
            $display("  *** ALL TESTS PASSED ***");
        else
            $display("  *** SOME TESTS FAILED ***");
        $display("============================================");
        $finish;
    end

endmodule
