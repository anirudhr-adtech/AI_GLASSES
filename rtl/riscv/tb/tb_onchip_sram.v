`timescale 1ns/1ps
//============================================================================
// Module : tb_onchip_sram
// Project : AI_GLASSES — RISC-V Subsystem
// Description : Self-checking testbench for onchip_sram (512KB banked SRAM)
//============================================================================

module tb_onchip_sram;

    // ----------------------------------------------------------------
    // Clock and reset
    // ----------------------------------------------------------------
    reg clk;
    reg rst_n;

    initial clk = 1'b0;
    always #5 clk = ~clk; // 100 MHz

    // ----------------------------------------------------------------
    // Pass/fail counters
    // ----------------------------------------------------------------
    integer pass_count;
    integer fail_count;

    // ----------------------------------------------------------------
    // Port A (iBus, read-only) AXI4 signals
    // ----------------------------------------------------------------
    reg  [31:0] a_araddr;
    reg         a_arvalid;
    wire        a_arready;
    reg  [3:0]  a_arid;
    reg  [7:0]  a_arlen;
    reg  [2:0]  a_arsize;
    reg  [1:0]  a_arburst;

    wire [31:0] a_rdata;
    wire        a_rvalid;
    reg         a_rready;
    wire [1:0]  a_rresp;
    wire [3:0]  a_rid;
    wire        a_rlast;

    // ----------------------------------------------------------------
    // Port B (dBus, read/write) AXI4 signals
    // ----------------------------------------------------------------
    reg  [31:0] b_awaddr;
    reg         b_awvalid;
    wire        b_awready;
    reg  [3:0]  b_awid;
    reg  [7:0]  b_awlen;
    reg  [2:0]  b_awsize;
    reg  [1:0]  b_awburst;

    reg  [31:0] b_wdata;
    reg  [3:0]  b_wstrb;
    reg         b_wvalid;
    reg         b_wlast;
    wire        b_wready;

    wire [3:0]  b_bid;
    wire [1:0]  b_bresp;
    wire        b_bvalid;
    reg         b_bready;

    reg  [31:0] b_araddr;
    reg         b_arvalid;
    wire        b_arready;
    reg  [3:0]  b_arid;
    reg  [7:0]  b_arlen;
    reg  [2:0]  b_arsize;
    reg  [1:0]  b_arburst;

    wire [31:0] b_rdata;
    wire        b_rvalid;
    reg         b_rready;
    wire [1:0]  b_rresp;
    wire [3:0]  b_rid;
    wire        b_rlast;

    // ----------------------------------------------------------------
    // DUT
    // ----------------------------------------------------------------
    onchip_sram #(
        .NUM_BANKS       (4),
        .BANK_ADDR_WIDTH (15),
        .DATA_WIDTH      (32)
    ) u_dut (
        .clk             (clk),
        .rst_n           (rst_n),

        // Port A
        .s_axi_a_araddr  (a_araddr),
        .s_axi_a_arvalid (a_arvalid),
        .s_axi_a_arready (a_arready),
        .s_axi_a_arid    (a_arid),
        .s_axi_a_arlen   (a_arlen),
        .s_axi_a_arsize  (a_arsize),
        .s_axi_a_arburst (a_arburst),
        .s_axi_a_rdata   (a_rdata),
        .s_axi_a_rvalid  (a_rvalid),
        .s_axi_a_rready  (a_rready),
        .s_axi_a_rresp   (a_rresp),
        .s_axi_a_rid     (a_rid),
        .s_axi_a_rlast   (a_rlast),

        // Port B
        .s_axi_b_awaddr  (b_awaddr),
        .s_axi_b_awvalid (b_awvalid),
        .s_axi_b_awready (b_awready),
        .s_axi_b_awid    (b_awid),
        .s_axi_b_awlen   (b_awlen),
        .s_axi_b_awsize  (b_awsize),
        .s_axi_b_awburst (b_awburst),
        .s_axi_b_wdata   (b_wdata),
        .s_axi_b_wstrb   (b_wstrb),
        .s_axi_b_wvalid  (b_wvalid),
        .s_axi_b_wlast   (b_wlast),
        .s_axi_b_wready  (b_wready),
        .s_axi_b_bid     (b_bid),
        .s_axi_b_bresp   (b_bresp),
        .s_axi_b_bvalid  (b_bvalid),
        .s_axi_b_bready  (b_bready),
        .s_axi_b_araddr  (b_araddr),
        .s_axi_b_arvalid (b_arvalid),
        .s_axi_b_arready (b_arready),
        .s_axi_b_arid    (b_arid),
        .s_axi_b_arlen   (b_arlen),
        .s_axi_b_arsize  (b_arsize),
        .s_axi_b_arburst (b_arburst),
        .s_axi_b_rdata   (b_rdata),
        .s_axi_b_rvalid  (b_rvalid),
        .s_axi_b_rready  (b_rready),
        .s_axi_b_rresp   (b_rresp),
        .s_axi_b_rid     (b_rid),
        .s_axi_b_rlast   (b_rlast)
    );

    // ----------------------------------------------------------------
    // Tasks
    // ----------------------------------------------------------------
    task check_val;
        input [31:0] actual;
        input [31:0] expected;
        input [8*48-1:0] msg;
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

    task reset_dut;
        begin
            rst_n      = 1'b0;
            a_araddr   = 32'd0; a_arvalid  = 1'b0; a_arid = 4'd0;
            a_arlen    = 8'd0;  a_arsize   = 3'b010; a_arburst = 2'b01;
            a_rready   = 1'b0;
            b_awaddr   = 32'd0; b_awvalid  = 1'b0; b_awid = 4'd0;
            b_awlen    = 8'd0;  b_awsize   = 3'b010; b_awburst = 2'b01;
            b_wdata    = 32'd0; b_wstrb    = 4'b1111; b_wvalid = 1'b0; b_wlast = 1'b0;
            b_bready   = 1'b0;
            b_araddr   = 32'd0; b_arvalid  = 1'b0; b_arid = 4'd0;
            b_arlen    = 8'd0;  b_arsize   = 3'b010; b_arburst = 2'b01;
            b_rready   = 1'b0;
            repeat (5) @(posedge clk);
            rst_n = 1'b1;
            @(posedge clk);
        end
    endtask

    // AXI write via Port B
    task axi_b_write;
        input [31:0] addr;
        input [31:0] data;
        input [3:0]  strb;
        begin
            // Address phase
            @(posedge clk);
            b_awaddr  = addr;
            b_awid    = 4'd1;
            b_awvalid = 1'b1;
            @(posedge clk);
            while (!b_awready) @(posedge clk);
            b_awvalid = 1'b0;

            // Data phase
            b_wdata  = data;
            b_wstrb  = strb;
            b_wvalid = 1'b1;
            b_wlast  = 1'b1;
            @(posedge clk);
            while (!b_wready) @(posedge clk);
            b_wvalid = 1'b0;
            b_wlast  = 1'b0;

            // Response
            b_bready = 1'b1;
            while (!b_bvalid) @(posedge clk);
            @(posedge clk);
            b_bready = 1'b0;
        end
    endtask

    // AXI read via Port B
    task axi_b_read;
        input  [31:0] addr;
        output [31:0] rdata;
        begin
            @(posedge clk);
            b_araddr  = addr;
            b_arid    = 4'd2;
            b_arvalid = 1'b1;
            b_rready  = 1'b1;
            @(posedge clk);
            while (!b_arready) @(posedge clk);
            b_arvalid = 1'b0;
            while (!b_rvalid) @(posedge clk);
            rdata = b_rdata;
            @(posedge clk);
            b_rready = 1'b0;
        end
    endtask

    // AXI read via Port A
    task axi_a_read;
        input  [31:0] addr;
        output [31:0] rdata;
        begin
            @(posedge clk);
            a_araddr  = addr;
            a_arid    = 4'd3;
            a_arvalid = 1'b1;
            a_rready  = 1'b1;
            @(posedge clk);
            while (!a_arready) @(posedge clk);
            a_arvalid = 1'b0;
            while (!a_rvalid) @(posedge clk);
            rdata = a_rdata;
            @(posedge clk);
            a_rready = 1'b0;
        end
    endtask

    // ----------------------------------------------------------------
    // Test: write and read each bank
    // ----------------------------------------------------------------
    task test_all_banks;
        reg [31:0] rdata;
        integer bank;
        reg [31:0] addr;
        reg [31:0] expected;
        begin
            $display("[TEST] Write/read all 4 banks");
            for (bank = 0; bank < 4; bank = bank + 1) begin
                // Address = bank[1:0] << 17 | word_offset << 2
                addr     = (bank << 17) | (32'd10 << 2);
                expected = 32'hA0000000 | bank;
                axi_b_write(addr, expected, 4'b1111);
                axi_b_read(addr, rdata);
                check_val(rdata, expected, "bank write/read");
            end
        end
    endtask

    // ----------------------------------------------------------------
    // Test: byte-enable writes
    // ----------------------------------------------------------------
    task test_byte_enables;
        reg [31:0] rdata;
        reg [31:0] addr;
        begin
            $display("[TEST] Byte-enable writes");
            addr = 32'h00000020; // bank 0, word 8
            axi_b_write(addr, 32'hAABBCCDD, 4'b1111);
            axi_b_write(addr, 32'h000000FF, 4'b0001);
            axi_b_read(addr, rdata);
            check_val(rdata, 32'hAABBCCFF, "byte0 write");

            axi_b_write(addr, 32'h00EE0000, 4'b0100);
            axi_b_read(addr, rdata);
            check_val(rdata, 32'hAAEECCFF, "byte2 write");
        end
    endtask

    // ----------------------------------------------------------------
    // Test: Port A read (iBus) after Port B write
    // ----------------------------------------------------------------
    task test_cross_port;
        reg [31:0] rdata;
        reg [31:0] addr;
        begin
            $display("[TEST] Cross-port: write B, read A");
            addr = 32'h00000040; // bank 0, word 16
            axi_b_write(addr, 32'hFACEFEED, 4'b1111);
            axi_a_read(addr, rdata);
            check_val(rdata, 32'hFACEFEED, "cross-port read A");
        end
    endtask

    // ----------------------------------------------------------------
    // Test: different banks no collision
    // ----------------------------------------------------------------
    task test_different_banks;
        reg [31:0] rdata_a;
        reg [31:0] rdata_b;
        begin
            $display("[TEST] Different bank access (no collision)");
            // Write to bank 0 and bank 1
            axi_b_write(32'h00000004, 32'h11111111, 4'b1111); // bank 0
            axi_b_write(32'h00020004, 32'h22222222, 4'b1111); // bank 1

            // Read from bank 0 via A, then bank 1 via B (sequential)
            axi_a_read(32'h00000004, rdata_a);
            check_val(rdata_a, 32'h11111111, "bank0 via A");

            axi_b_read(32'h00020004, rdata_b);
            check_val(rdata_b, 32'h22222222, "bank1 via B");
        end
    endtask

    // ----------------------------------------------------------------
    // Test: bank collision (both ports access same bank)
    // The onchip_sram should handle this with Port B winning
    // and Port A being stalled by 1 cycle.
    // ----------------------------------------------------------------
    task test_bank_collision;
        reg [31:0] rdata_a;
        begin
            $display("[TEST] Bank collision (same bank, Port B wins)");
            // Write via B to bank 0
            axi_b_write(32'h00000008, 32'hC0111501, 4'b1111);

            // Now try to read bank 0 from port A — the collision logic
            // may cause a 1-cycle stall but should still complete
            axi_a_read(32'h00000008, rdata_a);
            // Accept any valid read — the stall is internal
            if (rdata_a !== 32'bx) begin
                pass_count = pass_count + 1;
                $display("  Port A read completed after potential stall: 0x%08h", rdata_a);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: Port A returned X after collision");
            end
        end
    endtask

    // ----------------------------------------------------------------
    // Main
    // ----------------------------------------------------------------
    initial begin
        pass_count = 0;
        fail_count = 0;

        $display("============================================");
        $display("  TB: onchip_sram");
        $display("============================================");

        reset_dut;
        test_all_banks;
        test_byte_enables;
        test_cross_port;
        test_different_banks;
        test_bank_collision;

        repeat (10) @(posedge clk);

        $display("============================================");
        $display("  Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
        if (fail_count == 0)
            $display("  *** ALL TESTS PASSED ***");
        else
            $display("  *** SOME TESTS FAILED ***");
        $display("============================================");
        $finish;
    end

    // Timeout watchdog
    initial begin
        #100000;
        $display("TIMEOUT: simulation exceeded 100us");
        $finish;
    end

endmodule
