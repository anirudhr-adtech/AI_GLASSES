`timescale 1ns/1ps
//============================================================================
// Module : tb_boot_rom
// Project : AI_GLASSES — RISC-V Subsystem
// Description : Self-checking testbench for boot_rom (4KB AXI4 ROM)
//============================================================================

module tb_boot_rom;

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
    // AXI4 signals
    // ----------------------------------------------------------------
    // Read address
    reg  [31:0] s_axi_araddr;
    reg         s_axi_arvalid;
    wire        s_axi_arready;
    reg  [3:0]  s_axi_arid;
    reg  [7:0]  s_axi_arlen;
    reg  [2:0]  s_axi_arsize;
    reg  [1:0]  s_axi_arburst;

    // Read data
    wire [31:0] s_axi_rdata;
    wire        s_axi_rvalid;
    reg         s_axi_rready;
    wire [1:0]  s_axi_rresp;
    wire [3:0]  s_axi_rid;
    wire        s_axi_rlast;

    // Write address
    reg  [31:0] s_axi_awaddr;
    reg         s_axi_awvalid;
    wire        s_axi_awready;
    reg  [3:0]  s_axi_awid;
    reg  [7:0]  s_axi_awlen;
    reg  [2:0]  s_axi_awsize;
    reg  [1:0]  s_axi_awburst;

    // Write data
    reg  [31:0] s_axi_wdata;
    reg  [3:0]  s_axi_wstrb;
    reg         s_axi_wvalid;
    reg         s_axi_wlast;
    wire        s_axi_wready;

    // Write response
    wire [3:0]  s_axi_bid;
    wire [1:0]  s_axi_bresp;
    wire        s_axi_bvalid;
    reg         s_axi_bready;

    // ----------------------------------------------------------------
    // Initialize ROM content directly (bypass hex file for testing)
    // ----------------------------------------------------------------
    boot_rom #(
        .ADDR_WIDTH (12),
        .DATA_WIDTH (32),
        .DEPTH      (1024),
        .INIT_FILE  ("tb_boot_rom.hex")
    ) u_dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .s_axi_araddr    (s_axi_araddr),
        .s_axi_arvalid   (s_axi_arvalid),
        .s_axi_arready   (s_axi_arready),
        .s_axi_arid      (s_axi_arid),
        .s_axi_arlen     (s_axi_arlen),
        .s_axi_arsize    (s_axi_arsize),
        .s_axi_arburst   (s_axi_arburst),
        .s_axi_rdata     (s_axi_rdata),
        .s_axi_rvalid    (s_axi_rvalid),
        .s_axi_rready    (s_axi_rready),
        .s_axi_rresp     (s_axi_rresp),
        .s_axi_rid       (s_axi_rid),
        .s_axi_rlast     (s_axi_rlast),
        .s_axi_awaddr    (s_axi_awaddr),
        .s_axi_awvalid   (s_axi_awvalid),
        .s_axi_awready   (s_axi_awready),
        .s_axi_awid      (s_axi_awid),
        .s_axi_awlen     (s_axi_awlen),
        .s_axi_awsize    (s_axi_awsize),
        .s_axi_awburst   (s_axi_awburst),
        .s_axi_wdata     (s_axi_wdata),
        .s_axi_wstrb     (s_axi_wstrb),
        .s_axi_wvalid    (s_axi_wvalid),
        .s_axi_wlast     (s_axi_wlast),
        .s_axi_wready    (s_axi_wready),
        .s_axi_bid       (s_axi_bid),
        .s_axi_bresp     (s_axi_bresp),
        .s_axi_bvalid    (s_axi_bvalid),
        .s_axi_bready    (s_axi_bready)
    );

    // ----------------------------------------------------------------
    // Pre-load ROM memory for testing
    // ----------------------------------------------------------------
    integer k;
    initial begin
        // Write known pattern: mem[i] = i * 4 + 0xDEAD0000
        for (k = 0; k < 1024; k = k + 1) begin
            u_dut.mem[k] = 32'hDEAD0000 + (k * 4);
        end
    end

    // ----------------------------------------------------------------
    // Tasks
    // ----------------------------------------------------------------
    task reset_dut;
        begin
            rst_n          = 1'b0;
            s_axi_araddr   = 32'd0;
            s_axi_arvalid  = 1'b0;
            s_axi_arid     = 4'd0;
            s_axi_arlen    = 8'd0;
            s_axi_arsize   = 3'b010;
            s_axi_arburst  = 2'b01;
            s_axi_rready   = 1'b0;
            s_axi_awaddr   = 32'd0;
            s_axi_awvalid  = 1'b0;
            s_axi_awid     = 4'd0;
            s_axi_awlen    = 8'd0;
            s_axi_awsize   = 3'b010;
            s_axi_awburst  = 2'b01;
            s_axi_wdata    = 32'd0;
            s_axi_wstrb    = 4'b1111;
            s_axi_wvalid   = 1'b0;
            s_axi_wlast    = 1'b0;
            s_axi_bready   = 1'b0;
            repeat (5) @(posedge clk);
            rst_n = 1'b1;
            @(posedge clk);
        end
    endtask

    task axi_read;
        input [31:0] addr;
        input [3:0]  id;
        output [31:0] rdata;
        begin
            @(posedge clk);
            s_axi_araddr  = addr;
            s_axi_arid    = id;
            s_axi_arvalid = 1'b1;
            s_axi_arlen   = 8'd0;
            s_axi_rready  = 1'b1;
            // Wait for arready
            @(posedge clk);
            while (!s_axi_arready) @(posedge clk);
            s_axi_arvalid = 1'b0;
            // Wait for rvalid
            while (!s_axi_rvalid) @(posedge clk);
            rdata = s_axi_rdata;
            @(posedge clk);
            s_axi_rready = 1'b0;
        end
    endtask

    task check_read;
        input [31:0] addr;
        input [3:0]  id;
        input [31:0] expected;
        input [8*40-1:0] msg;
        reg [31:0] rdata;
        begin
            axi_read(addr, id, rdata);
            if (rdata === expected) begin
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: %0s — addr=0x%08h exp=0x%08h got=0x%08h",
                         msg, addr, expected, rdata);
            end
        end
    endtask

    // ----------------------------------------------------------------
    // Test: read from multiple addresses
    // ----------------------------------------------------------------
    task test_sequential_reads;
        integer i;
        reg [31:0] expected;
        begin
            $display("[TEST] Sequential reads");
            for (i = 0; i < 8; i = i + 1) begin
                expected = 32'hDEAD0000 + (i * 4);
                check_read(i * 4, 4'd1, expected, "seq_read");
            end
        end
    endtask

    // ----------------------------------------------------------------
    // Test: read from non-zero offsets
    // ----------------------------------------------------------------
    task test_random_reads;
        begin
            $display("[TEST] Random address reads");
            check_read(32'h00000100, 4'd2, 32'hDEAD0000 + (64 * 4), "rand_read_0x100");
            check_read(32'h00000FFC, 4'd3, 32'hDEAD0000 + (1023 * 4), "rand_read_0xFFC");
            check_read(32'h00000000, 4'd4, 32'hDEAD0000, "rand_read_0x000");
        end
    endtask

    // ----------------------------------------------------------------
    // Test: write is silently ignored
    // ----------------------------------------------------------------
    task test_write_ignored;
        reg [31:0] rdata_before;
        reg [31:0] rdata_after;
        begin
            $display("[TEST] Write silently ignored");
            // Read original value
            axi_read(32'h00000000, 4'd5, rdata_before);

            // Issue a write
            @(posedge clk);
            s_axi_awaddr  = 32'h00000000;
            s_axi_awid    = 4'd6;
            s_axi_awvalid = 1'b1;
            s_axi_awlen   = 8'd0;
            @(posedge clk);
            while (!s_axi_awready) @(posedge clk);
            s_axi_awvalid = 1'b0;

            s_axi_wdata  = 32'hBAADF00D;
            s_axi_wstrb  = 4'b1111;
            s_axi_wvalid = 1'b1;
            s_axi_wlast  = 1'b1;
            @(posedge clk);
            while (!s_axi_wready) @(posedge clk);
            s_axi_wvalid = 1'b0;
            s_axi_wlast  = 1'b0;

            s_axi_bready = 1'b1;
            while (!s_axi_bvalid) @(posedge clk);
            @(posedge clk);
            s_axi_bready = 1'b0;

            // Read back — should be unchanged
            axi_read(32'h00000000, 4'd7, rdata_after);
            if (rdata_after === rdata_before) begin
                pass_count = pass_count + 1;
                $display("  Write correctly ignored");
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: Write modified ROM! before=0x%08h after=0x%08h",
                         rdata_before, rdata_after);
            end
        end
    endtask

    // ----------------------------------------------------------------
    // Test: rlast and rresp
    // ----------------------------------------------------------------
    task test_rlast_rresp;
        reg [31:0] dummy;
        begin
            $display("[TEST] rlast and rresp signals");
            @(posedge clk);
            s_axi_araddr  = 32'h00000008;
            s_axi_arid    = 4'd8;
            s_axi_arvalid = 1'b1;
            s_axi_rready  = 1'b1;
            @(posedge clk);
            while (!s_axi_arready) @(posedge clk);
            s_axi_arvalid = 1'b0;
            while (!s_axi_rvalid) @(posedge clk);

            if (s_axi_rlast === 1'b1) begin
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: rlast not asserted");
            end
            if (s_axi_rresp === 2'b00) begin
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: rresp not OKAY");
            end
            if (s_axi_rid === 4'd8) begin
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: rid mismatch, expected 8 got %0d", s_axi_rid);
            end
            @(posedge clk);
            s_axi_rready = 1'b0;
        end
    endtask

    // ----------------------------------------------------------------
    // Main
    // ----------------------------------------------------------------
    initial begin
        pass_count = 0;
        fail_count = 0;

        $display("============================================");
        $display("  TB: boot_rom");
        $display("============================================");

        reset_dut;
        test_sequential_reads;
        test_random_reads;
        test_write_ignored;
        test_rlast_rresp;

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
