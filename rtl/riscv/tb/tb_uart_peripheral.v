`timescale 1ns/1ps
//============================================================================
// Module : tb_uart_peripheral
// Project : AI_GLASSES — RISC-V Subsystem
// Description : Self-checking testbench for uart_peripheral
//============================================================================

module tb_uart_peripheral;

    // ----------------------------------------------------------------
    // Clock and reset
    // ----------------------------------------------------------------
    reg        clk;
    reg        rst_n;

    initial clk = 1'b0;
    always #5 clk = ~clk; // 100 MHz

    // ----------------------------------------------------------------
    // AXI-Lite signals
    // ----------------------------------------------------------------
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

    wire        uart_tx_o;
    reg         uart_rx_i;
    wire        irq_tx_empty;
    wire        irq_rx_ready;

    // ----------------------------------------------------------------
    // Pass/fail counters
    // ----------------------------------------------------------------
    integer pass_count;
    integer fail_count;

    // ----------------------------------------------------------------
    // DUT
    // ----------------------------------------------------------------
    uart_peripheral #(
        .FIFO_DEPTH(4)
    ) u_dut (
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
        .uart_tx_o       (uart_tx_o),
        .uart_rx_i       (uart_rx_i),
        .irq_tx_empty    (irq_tx_empty),
        .irq_rx_ready    (irq_rx_ready)
    );

    // ----------------------------------------------------------------
    // AXI-Lite write task
    // ----------------------------------------------------------------
    task axil_write;
        input [7:0]  addr;
        input [31:0] data;
        begin
            @(posedge clk);
            s_axil_awaddr  <= addr;
            s_axil_awvalid <= 1'b1;
            s_axil_wdata   <= data;
            s_axil_wstrb   <= 4'hF;
            s_axil_wvalid  <= 1'b1;
            s_axil_bready  <= 1'b1;
            // Wait for handshake
            @(posedge clk);
            while (!(s_axil_awready && s_axil_wready)) @(posedge clk);
            s_axil_awvalid <= 1'b0;
            s_axil_wvalid  <= 1'b0;
            // Wait for write response
            while (!s_axil_bvalid) @(posedge clk);
            @(posedge clk);
            s_axil_bready <= 1'b0;
        end
    endtask

    // ----------------------------------------------------------------
    // AXI-Lite read task
    // ----------------------------------------------------------------
    reg [31:0] axil_read_data;

    task axil_read;
        input [7:0] addr;
        begin
            @(posedge clk);
            s_axil_araddr  <= addr;
            s_axil_arvalid <= 1'b1;
            s_axil_rready  <= 1'b1;
            @(posedge clk);
            while (!s_axil_arready) @(posedge clk);
            s_axil_arvalid <= 1'b0;
            while (!s_axil_rvalid) @(posedge clk);
            axil_read_data <= s_axil_rdata;
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

    // ----------------------------------------------------------------
    // Stimulus
    // ----------------------------------------------------------------
    initial begin
        $dumpfile("tb_uart_peripheral.vcd");
        $dumpvars(0, tb_uart_peripheral);

        pass_count = 0;
        fail_count = 0;

        // Init signals
        rst_n          = 1'b0;
        uart_rx_i      = 1'b1; // idle high
        s_axil_awaddr  = 8'd0;
        s_axil_awvalid = 1'b0;
        s_axil_wdata   = 32'd0;
        s_axil_wstrb   = 4'h0;
        s_axil_wvalid  = 1'b0;
        s_axil_bready  = 1'b0;
        s_axil_araddr  = 8'd0;
        s_axil_arvalid = 1'b0;
        s_axil_rready  = 1'b0;

        // Reset
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        // -----------------------------------------------------------
        // Test 1: Read default STATUS (TX empty=1, RX empty=1)
        // -----------------------------------------------------------
        $display("\n--- Test 1: Default STATUS register ---");
        axil_read(8'h08);
        // Expect: TX full=0, TX empty=1, RX full=0, RX empty=1 => bits[3:0] = 4'b1010 = 0xA
        check("STATUS default", axil_read_data[3:0], 4'hA);

        // -----------------------------------------------------------
        // Test 2: Write and read BAUDDIV
        // -----------------------------------------------------------
        $display("\n--- Test 2: BAUDDIV register ---");
        axil_write(8'h0C, 32'd107); // 115200 baud @ 12.5 MHz-ish
        axil_read(8'h0C);
        check("BAUDDIV readback", axil_read_data, 32'd107);

        // -----------------------------------------------------------
        // Test 3: Write and read IRQ_ENABLE
        // -----------------------------------------------------------
        $display("\n--- Test 3: IRQ_ENABLE register ---");
        axil_write(8'h10, 32'h0000_0003);
        axil_read(8'h10);
        check("IRQ_ENABLE readback", axil_read_data, 32'h0000_0003);

        // -----------------------------------------------------------
        // Test 4: TX empty IRQ should be asserted (FIFO empty + IRQ en)
        // -----------------------------------------------------------
        $display("\n--- Test 4: TX empty interrupt ---");
        repeat (5) @(posedge clk);
        check("irq_tx_empty asserted", {31'd0, irq_tx_empty}, 32'd1);

        // -----------------------------------------------------------
        // Test 5: Write TXDATA (push byte to TX FIFO)
        // -----------------------------------------------------------
        $display("\n--- Test 5: TXDATA write ---");
        axil_write(8'h00, 32'h0000_0055); // write 0x55 to TX FIFO
        repeat (5) @(posedge clk);
        // STATUS: TX empty should now be 0
        axil_read(8'h08);
        check("STATUS TX not empty after write", axil_read_data[1], 1'b0);

        // -----------------------------------------------------------
        // Test 6: RXDATA read when empty (bit 31 should be set)
        // -----------------------------------------------------------
        $display("\n--- Test 6: RXDATA empty flag ---");
        axil_read(8'h04);
        check("RXDATA empty flag", axil_read_data[31], 1'b1);

        // -----------------------------------------------------------
        // Test 7: Write to RO register (STATUS) should be ignored
        // -----------------------------------------------------------
        $display("\n--- Test 7: Write to RO register ---");
        axil_write(8'h08, 32'hDEADBEEF);
        axil_read(8'h08);
        check("STATUS not modified by write", axil_read_data[31:6], 26'd0);

        // -----------------------------------------------------------
        // Summary
        // -----------------------------------------------------------
        repeat (10) @(posedge clk);
        $display("\n============================================");
        $display("  UART Peripheral Testbench Summary");
        $display("  PASSED: %0d", pass_count);
        $display("  FAILED: %0d", fail_count);
        if (fail_count == 0)
            $display("  RESULT: ALL TESTS PASSED");
        else
            $display("  RESULT: SOME TESTS FAILED");
        $display("============================================\n");
        $finish;
    end

    // Timeout watchdog
    initial begin
        #500000;
        $display("[TIMEOUT] Simulation did not complete in time");
        $finish;
    end

endmodule
