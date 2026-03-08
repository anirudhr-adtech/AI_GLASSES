`timescale 1ns/1ps
//============================================================================
// Module : tb_irq_controller
// Project : AI_GLASSES — RISC-V Subsystem
// Description : Self-checking testbench for irq_controller module
//============================================================================

module tb_irq_controller;

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
    reg  [7:0]  irq_sources_i;
    wire        irq_external_o;

    // Pass/fail counters
    integer pass_count;
    integer fail_count;

    // Read data capture
    reg [31:0] rd_data;

    // ----------------------------------------------------------------
    // DUT instantiation
    // ----------------------------------------------------------------
    irq_controller uut (
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
        .irq_sources_i   (irq_sources_i),
        .irq_external_o  (irq_external_o)
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
        begin
            @(posedge clk);
            s_axil_awaddr  <= addr;
            s_axil_awvalid <= 1'b1;
            s_axil_wdata   <= data;
            s_axil_wstrb   <= strb;
            s_axil_wvalid  <= 1'b1;
            s_axil_bready  <= 1'b1;

            @(posedge clk);
            while (!s_axil_awready) @(posedge clk);
            s_axil_awvalid <= 1'b0;
            while (!s_axil_wready) @(posedge clk);
            s_axil_wvalid <= 1'b0;

            while (!s_axil_bvalid) @(posedge clk);
            @(posedge clk);
            s_axil_bready <= 1'b0;
        end
    endtask

    // ----------------------------------------------------------------
    // AXI-Lite Read Task
    // ----------------------------------------------------------------
    task axil_read;
        input  [7:0]  addr;
        output [31:0] data;
        begin
            @(posedge clk);
            s_axil_araddr  <= addr;
            s_axil_arvalid <= 1'b1;
            s_axil_rready  <= 1'b1;

            @(posedge clk);
            while (!s_axil_arready) @(posedge clk);
            s_axil_arvalid <= 1'b0;

            while (!s_axil_rvalid) @(posedge clk);
            data = s_axil_rdata;
            @(posedge clk);
            s_axil_rready <= 1'b0;
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
        $dumpfile("tb_irq_controller.vcd");
        $dumpvars(0, tb_irq_controller);

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
        irq_sources_i  = 8'h00;
        rst_n = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        $display("========================================");
        $display("  irq_controller Testbench");
        $display("========================================");

        // ----------------------------------------------------------
        // Test 1: Default register values
        // ----------------------------------------------------------
        axil_read(8'h04, rd_data); // IRQ_ENABLE
        check("T1 IRQ_ENABLE reset", rd_data, 32'h00000000);

        axil_read(8'h0C, rd_data); // IRQ_TYPE
        check("T1 IRQ_TYPE reset", rd_data, 32'h000000FC);

        axil_read(8'h14, rd_data); // IRQ_HIGHEST
        check("T1 IRQ_HIGHEST none", rd_data, 32'h000000FF);

        check_bool("T1 irq_external low", irq_external_o, 1'b0);

        // ----------------------------------------------------------
        // Test 2: Level-sensitive interrupt (bits [1:0] are level type)
        // ----------------------------------------------------------
        // Enable source 0
        axil_write(8'h04, 32'h00000001, 4'hF); // IRQ_ENABLE = bit 0

        // Assert level source 0
        irq_sources_i = 8'h01;
        repeat (3) @(posedge clk); // allow registered outputs to update

        axil_read(8'h00, rd_data); // IRQ_PENDING
        check("T2 pending level", rd_data[0], 1'b1);

        axil_read(8'h10, rd_data); // IRQ_STATUS
        check("T2 status level", rd_data[0], 1'b1);

        check_bool("T2 irq_external high", irq_external_o, 1'b1);

        axil_read(8'h14, rd_data); // IRQ_HIGHEST
        check("T2 highest=0", rd_data, 32'h00000000);

        // De-assert level source => pending should clear
        irq_sources_i = 8'h00;
        repeat (3) @(posedge clk);

        axil_read(8'h00, rd_data);
        check("T2 pending clear", rd_data[0], 1'b0);
        check_bool("T2 irq_external low", irq_external_o, 1'b0);

        // ----------------------------------------------------------
        // Test 3: Edge-sensitive interrupt (bit 2 is edge type by default)
        // ----------------------------------------------------------
        // Enable source 2
        axil_write(8'h04, 32'h00000004, 4'hF); // IRQ_ENABLE = bit 2

        // Pulse source 2 (rising edge)
        irq_sources_i = 8'h04;
        repeat (2) @(posedge clk);
        irq_sources_i = 8'h00;
        repeat (3) @(posedge clk);

        axil_read(8'h00, rd_data); // IRQ_PENDING
        check("T3 edge pending set", rd_data[2], 1'b1);

        check_bool("T3 irq_external high", irq_external_o, 1'b1);

        axil_read(8'h14, rd_data); // IRQ_HIGHEST
        check("T3 highest=2", rd_data, 32'h00000002);

        // Clear edge pending via IRQ_CLEAR
        axil_write(8'h08, 32'h00000004, 4'hF); // write-1-to-clear bit 2
        repeat (3) @(posedge clk);

        axil_read(8'h00, rd_data);
        check("T3 edge cleared", rd_data[2], 1'b0);
        check_bool("T3 irq_external low", irq_external_o, 1'b0);

        // ----------------------------------------------------------
        // Test 4: Priority encoding — multiple sources active
        // ----------------------------------------------------------
        // Enable sources 0,1,3
        axil_write(8'h04, 32'h0000000B, 4'hF); // bits 0,1,3

        // Set source 1 (level) and source 3 (edge)
        irq_sources_i = 8'h0A; // bits 1 and 3
        repeat (3) @(posedge clk);

        axil_read(8'h14, rd_data);
        check("T4 highest=1 (priority)", rd_data, 32'h00000001);

        irq_sources_i = 8'h00;
        repeat (2) @(posedge clk);

        // ----------------------------------------------------------
        // Test 5: IRQ_TYPE reconfiguration — change bit 2 to level
        // ----------------------------------------------------------
        axil_write(8'h0C, 32'h000000F8, 4'hF); // bit 2 now level
        axil_write(8'h04, 32'h00000004, 4'hF); // enable bit 2

        irq_sources_i = 8'h04;
        repeat (3) @(posedge clk);

        axil_read(8'h00, rd_data);
        check("T5 type change level", rd_data[2], 1'b1);

        irq_sources_i = 8'h00;
        repeat (3) @(posedge clk);

        axil_read(8'h00, rd_data);
        check("T5 level deassert", rd_data[2], 1'b0);

        // ----------------------------------------------------------
        // Test 6: Disabled source should not appear in status
        // ----------------------------------------------------------
        axil_write(8'h04, 32'h00000000, 4'hF); // disable all
        irq_sources_i = 8'hFF;
        repeat (3) @(posedge clk);

        axil_read(8'h10, rd_data); // IRQ_STATUS
        check("T6 disabled status", rd_data, 32'h00000000);
        check_bool("T6 irq_external low", irq_external_o, 1'b0);

        irq_sources_i = 8'h00;
        repeat (2) @(posedge clk);

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
        #200000;
        $display("[TIMEOUT] Simulation exceeded time limit");
        $finish;
    end

endmodule
