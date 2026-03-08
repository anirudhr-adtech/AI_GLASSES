`timescale 1ns/1ps
//============================================================================
// Module : tb_timer_clint
// Project : AI_GLASSES — RISC-V Subsystem
// Description : Self-checking testbench for timer_clint module
//============================================================================

module tb_timer_clint;

    // ----------------------------------------------------------------
    // Clock and reset
    // ----------------------------------------------------------------
    reg        clk;
    reg        rst_n;

    // AXI-Lite signals
    reg  [7:0]  s_axil_awaddr;
    reg         s_axil_awvalid;
    wire        s_axil_awready;
    reg  [31:0] s_axil_wdata;
    reg  [3:0]  s_axil_wstrb;
    reg         s_axil_wvalid;
    wire        s_axil_wready;
    wire [1:0]  s_axil_bresp;
    wire        s_axil_bvalid;
    reg         s_axil_bready;
    reg  [7:0]  s_axil_araddr;
    reg         s_axil_arvalid;
    wire        s_axil_arready;
    wire [31:0] s_axil_rdata;
    wire [1:0]  s_axil_rresp;
    wire        s_axil_rvalid;
    reg         s_axil_rready;
    wire        irq_timer_o;

    // Pass/fail counters
    integer pass_count;
    integer fail_count;

    // Read data capture
    reg [31:0] rd_data;

    // ----------------------------------------------------------------
    // DUT instantiation
    // ----------------------------------------------------------------
    timer_clint uut (
        .clk             (clk),
        .rst_n           (rst_n),
        .s_axil_awaddr   (s_axil_awaddr),
        .s_axil_awvalid  (s_axil_awvalid),
        .s_axil_awready  (s_axil_awready),
        .s_axil_wdata    (s_axil_wdata),
        .s_axil_wstrb    (s_axil_wstrb),
        .s_axil_wvalid   (s_axil_wvalid),
        .s_axil_wready   (s_axil_wready),
        .s_axil_bresp    (s_axil_bresp),
        .s_axil_bvalid   (s_axil_bvalid),
        .s_axil_bready   (s_axil_bready),
        .s_axil_araddr   (s_axil_araddr),
        .s_axil_arvalid  (s_axil_arvalid),
        .s_axil_arready  (s_axil_arready),
        .s_axil_rdata    (s_axil_rdata),
        .s_axil_rresp    (s_axil_rresp),
        .s_axil_rvalid   (s_axil_rvalid),
        .s_axil_rready   (s_axil_rready),
        .irq_timer_o     (irq_timer_o)
    );

    // ----------------------------------------------------------------
    // 100 MHz clock
    // ----------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // ----------------------------------------------------------------
    // AXI-Lite Write Task
    // ----------------------------------------------------------------
    task axil_write;
        input [7:0]  addr;
        input [31:0] data;
        input [3:0]  strb;
        integer wto;
        reg aw_done, w_done, b_done;
        begin
            @(posedge clk); #1;
            s_axil_awaddr  = addr;
            s_axil_awvalid = 1'b1;
            s_axil_wdata   = data;
            s_axil_wstrb   = strb;
            s_axil_wvalid  = 1'b1;
            s_axil_bready  = 1'b1;
            aw_done = 1'b0;
            w_done  = 1'b0;
            b_done  = 1'b0;
            wto = 0;

            begin : wr_loop
                forever begin
                    @(posedge clk);
                    if (s_axil_awready && s_axil_awvalid) aw_done = 1'b1;
                    if (s_axil_wready  && s_axil_wvalid)  w_done  = 1'b1;
                    if (s_axil_bvalid  && s_axil_bready)  b_done  = 1'b1;
                    #1;
                    if (aw_done) s_axil_awvalid = 1'b0;
                    if (w_done)  s_axil_wvalid  = 1'b0;
                    if (b_done) begin
                        s_axil_bready = 1'b0;
                        disable wr_loop;
                    end
                    wto = wto + 1;
                    if (wto > 100) disable wr_loop;
                end
            end
        end
    endtask

    // ----------------------------------------------------------------
    // AXI-Lite Read Task
    // ----------------------------------------------------------------
    task axil_read;
        input  [7:0]  addr;
        output [31:0] data;
        integer rto;
        reg ar_done, r_done;
        begin
            @(posedge clk); #1;
            s_axil_araddr  = addr;
            s_axil_arvalid = 1'b1;
            s_axil_rready  = 1'b1;
            ar_done = 1'b0;
            r_done  = 1'b0;
            rto = 0;

            begin : rd_loop
                forever begin
                    @(posedge clk);
                    if (s_axil_arready && s_axil_arvalid) ar_done = 1'b1;
                    if (s_axil_rvalid && s_axil_rready) begin
                        data = s_axil_rdata;
                        r_done = 1'b1;
                    end
                    #1;
                    if (ar_done) s_axil_arvalid = 1'b0;
                    if (r_done) begin
                        s_axil_rready = 1'b0;
                        disable rd_loop;
                    end
                    rto = rto + 1;
                    if (rto > 100) disable rd_loop;
                end
            end
        end
    endtask

    // ----------------------------------------------------------------
    // Check task
    // ----------------------------------------------------------------
    task check;
        input [255:0] test_name;
        input [31:0]  actual;
        input [31:0]  expected;
        begin
            if (actual === expected) begin
                $display("[PASS] %0s: got 0x%08x", test_name, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %0s: expected 0x%08x, got 0x%08x", test_name, expected, actual);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task check_bool;
        input [255:0] test_name;
        input          actual;
        input          expected;
        begin
            if (actual === expected) begin
                $display("[PASS] %0s: got %0b", test_name, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %0s: expected %0b, got %0b", test_name, expected, actual);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // ----------------------------------------------------------------
    // Main test sequence
    // ----------------------------------------------------------------
    initial begin
        $dumpfile("tb_timer_clint.vcd");
        $dumpvars(0, tb_timer_clint);

        pass_count = 0;
        fail_count = 0;

        // Init signals
        s_axil_awaddr  = 0;
        s_axil_awvalid = 0;
        s_axil_wdata   = 0;
        s_axil_wstrb   = 0;
        s_axil_wvalid  = 0;
        s_axil_bready  = 0;
        s_axil_araddr  = 0;
        s_axil_arvalid = 0;
        s_axil_rready  = 0;
        rst_n = 0;

        // Reset
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        $display("========================================");
        $display("  timer_clint Testbench");
        $display("========================================");

        // ----------------------------------------------------------
        // Test 1: mtime should be counting after reset
        // ----------------------------------------------------------
        repeat (10) @(posedge clk);
        axil_read(8'h00, rd_data);
        // mtime_lo should be > 0 after some clocks
        if (rd_data > 0) begin
            $display("[PASS] T1 mtime counting: mtime_lo = 0x%08x", rd_data);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] T1 mtime counting: mtime_lo = 0x%08x (expected > 0)", rd_data);
            fail_count = fail_count + 1;
        end

        // ----------------------------------------------------------
        // Test 2: Read mtimecmp default (0xFFFFFFFF for both halves)
        // ----------------------------------------------------------
        axil_read(8'h08, rd_data);
        check("T2 mtimecmp_lo reset", rd_data, 32'hFFFFFFFF);

        axil_read(8'h0C, rd_data);
        check("T2 mtimecmp_hi reset", rd_data, 32'hFFFFFFFF);

        // ----------------------------------------------------------
        // Test 3: IRQ should be low (mtime < mtimecmp at reset default)
        // ----------------------------------------------------------
        check_bool("T3 irq_timer low", irq_timer_o, 1'b0);

        // ----------------------------------------------------------
        // Test 4: Write mtimecmp low to a small value, trigger IRQ
        // ----------------------------------------------------------
        axil_write(8'h08, 32'h00000005, 4'hF);  // mtimecmp_lo = 5
        axil_write(8'h0C, 32'h00000000, 4'hF);  // mtimecmp_hi = 0

        // Wait a couple cycles for registered output
        repeat (4) @(posedge clk); #1;
        check_bool("T4 irq_timer high", irq_timer_o, 1'b1);

        // ----------------------------------------------------------
        // Test 5: Write mtimecmp to large value, IRQ should clear
        // ----------------------------------------------------------
        axil_write(8'h0C, 32'hFFFFFFFF, 4'hF);
        axil_write(8'h08, 32'hFFFFFFFF, 4'hF);
        repeat (4) @(posedge clk); #1;
        check_bool("T5 irq_timer clear", irq_timer_o, 1'b0);

        // ----------------------------------------------------------
        // Test 6: Prescaler — set prescaler=3, mtime increments every 4 cycles
        // ----------------------------------------------------------
        axil_write(8'h10, 32'h00000003, 4'hF); // prescaler=3
        // Read current mtime
        axil_read(8'h00, rd_data);
        begin : prescaler_test
            reg [31:0] mtime_before;
            reg [31:0] mtime_after;
            mtime_before = rd_data;
            // Wait 8 cycles => should increment by 2
            repeat (8) @(posedge clk);
            axil_read(8'h00, rd_data);
            mtime_after = rd_data;
            // With prescaler=3, mtime increments every 4 cycles
            // Allow some tolerance due to pipeline
            if ((mtime_after - mtime_before) >= 1 && (mtime_after - mtime_before) <= 3) begin
                $display("[PASS] T6 prescaler: delta = %0d", mtime_after - mtime_before);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] T6 prescaler: delta = %0d (expected 1-3)", mtime_after - mtime_before);
                fail_count = fail_count + 1;
            end
        end

        // ----------------------------------------------------------
        // Test 7: Read prescaler back
        // ----------------------------------------------------------
        axil_read(8'h10, rd_data);
        check("T7 prescaler readback", rd_data, 32'h00000003);

        // ----------------------------------------------------------
        // Test 8: mtime_hi should read 0 (counter hasn't wrapped)
        // ----------------------------------------------------------
        axil_read(8'h04, rd_data);
        check("T8 mtime_hi zero", rd_data, 32'h00000000);

        // ----------------------------------------------------------
        // Summary
        // ----------------------------------------------------------
        $display("========================================");
        $display("  Results: %0d passed, %0d failed", pass_count, fail_count);
        $display("========================================");
        if (fail_count == 0)
            $display("*** ALL TESTS PASSED ***");
        else
            $display("*** SOME TESTS FAILED ***");

        $finish;
    end

    // Timeout watchdog
    initial begin
        #100000;
        $display("[TIMEOUT] Simulation exceeded time limit");
        $finish;
    end

endmodule
