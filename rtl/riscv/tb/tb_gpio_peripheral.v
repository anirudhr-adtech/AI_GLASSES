`timescale 1ns/1ps
//============================================================================
// Module : tb_gpio_peripheral
// Project : AI_GLASSES — RISC-V Subsystem
// Description : Self-checking testbench for gpio_peripheral
//============================================================================

module tb_gpio_peripheral;

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

    reg  [7:0]  gpio_i;
    wire [7:0]  gpio_o;
    wire [7:0]  gpio_oe;
    wire        irq_gpio;

    // ----------------------------------------------------------------
    // Pass/fail counters
    // ----------------------------------------------------------------
    integer pass_count;
    integer fail_count;

    // ----------------------------------------------------------------
    // DUT
    // ----------------------------------------------------------------
    gpio_peripheral #(
        .GPIO_WIDTH(8)
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
        .gpio_i          (gpio_i),
        .gpio_o          (gpio_o),
        .gpio_oe         (gpio_oe),
        .irq_gpio        (irq_gpio)
    );

    // ----------------------------------------------------------------
    // AXI-Lite write task
    // ----------------------------------------------------------------
    task axil_write;
        input [7:0]  addr;
        input [31:0] data;
        begin
            @(posedge clk);
            s_axil_awaddr  = addr;
            s_axil_awvalid = 1'b1;
            s_axil_wdata   = data;
            s_axil_wstrb   = 4'hF;
            s_axil_wvalid  = 1'b1;
            s_axil_bready  = 1'b1;
            @(posedge clk);
            while (!(s_axil_awready && s_axil_wready)) @(posedge clk);
            s_axil_awvalid = 1'b0;
            s_axil_wvalid  = 1'b0;
            while (!s_axil_bvalid) @(posedge clk);
            @(posedge clk);
            s_axil_bready = 1'b0;
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
            s_axil_araddr  = addr;
            s_axil_arvalid = 1'b1;
            s_axil_rready  = 1'b1;
            @(posedge clk);
            while (!s_axil_arready) @(posedge clk);
            s_axil_arvalid = 1'b0;
            while (!s_axil_rvalid) @(posedge clk);
            axil_read_data = s_axil_rdata;
            @(posedge clk);
            s_axil_rready = 1'b0;
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
        $dumpfile("tb_gpio_peripheral.vcd");
        $dumpvars(0, tb_gpio_peripheral);

        pass_count = 0;
        fail_count = 0;

        // Init signals
        rst_n          = 1'b0;
        gpio_i         = 8'h00;
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
        // Test 1: Default register values
        // -----------------------------------------------------------
        $display("\n--- Test 1: Default register values ---");
        axil_read(8'h00); // GPIO_DIR
        check("GPIO_DIR default", axil_read_data, 32'h00);
        axil_read(8'h04); // GPIO_OUT
        check("GPIO_OUT default", axil_read_data, 32'h00);
        axil_read(8'h0C); // GPIO_IRQ_EN
        check("GPIO_IRQ_EN default", axil_read_data, 32'h00);

        // -----------------------------------------------------------
        // Test 2: Write/read GPIO_DIR and GPIO_OUT
        // -----------------------------------------------------------
        $display("\n--- Test 2: GPIO_DIR and GPIO_OUT ---");
        axil_write(8'h00, 32'h000000FF); // All outputs
        axil_read(8'h00);
        check("GPIO_DIR readback", axil_read_data[7:0], 8'hFF);

        axil_write(8'h04, 32'h000000A5);
        axil_read(8'h04);
        check("GPIO_OUT readback", axil_read_data[7:0], 8'hA5);

        // Check output pins (1 cycle latency for registered output)
        repeat (2) @(posedge clk);
        check("gpio_o pin value", {24'd0, gpio_o}, 32'h000000A5);
        check("gpio_oe pin value", {24'd0, gpio_oe}, 32'h000000FF);

        // -----------------------------------------------------------
        // Test 3: GPIO_IN (read input pins through synchronizer)
        // -----------------------------------------------------------
        $display("\n--- Test 3: GPIO_IN read ---");
        axil_write(8'h00, 32'h00000000); // All inputs
        gpio_i = 8'h3C;
        // Wait for 2-FF sync + 1 cycle margin
        repeat (5) @(posedge clk);
        axil_read(8'h08);
        check("GPIO_IN read", axil_read_data[7:0], 8'h3C);

        // -----------------------------------------------------------
        // Test 4: Rising edge interrupt detection
        // -----------------------------------------------------------
        $display("\n--- Test 4: Rising edge IRQ ---");
        gpio_i = 8'h00;
        repeat (5) @(posedge clk);

        // Enable IRQ on pin 0
        axil_write(8'h0C, 32'h00000001);

        // Trigger rising edge on pin 0
        gpio_i = 8'h01;
        // Wait for sync + edge detect
        repeat (5) @(posedge clk);

        // Read IRQ_PEND
        axil_read(8'h10);
        check("IRQ_PEND pin 0 set", axil_read_data[0], 1'b1);

        // Check irq_gpio output
        repeat (2) @(posedge clk);
        check("irq_gpio asserted", {31'd0, irq_gpio}, 32'd1);

        // -----------------------------------------------------------
        // Test 5: W1C on IRQ_PEND
        // -----------------------------------------------------------
        $display("\n--- Test 5: W1C IRQ_PEND ---");
        axil_write(8'h10, 32'h00000001); // Write 1 to clear pin 0
        repeat (3) @(posedge clk);
        axil_read(8'h10);
        check("IRQ_PEND cleared after W1C", axil_read_data[0], 1'b0);

        // Check irq_gpio de-asserted
        repeat (2) @(posedge clk);
        check("irq_gpio de-asserted", {31'd0, irq_gpio}, 32'd0);

        // -----------------------------------------------------------
        // Test 6: IRQ not triggered when IRQ_EN is 0
        // -----------------------------------------------------------
        $display("\n--- Test 6: IRQ masked when disabled ---");
        axil_write(8'h0C, 32'h00000000); // Disable all IRQs
        gpio_i = 8'h00;
        repeat (5) @(posedge clk);
        gpio_i = 8'h02; // Rising edge on pin 1
        repeat (5) @(posedge clk);
        // IRQ_PEND should still capture the edge
        axil_read(8'h10);
        check("IRQ_PEND pin 1 set (even disabled)", axil_read_data[1], 1'b1);
        // But irq_gpio should NOT be asserted
        repeat (2) @(posedge clk);
        check("irq_gpio not asserted (masked)", {31'd0, irq_gpio}, 32'd0);

        // -----------------------------------------------------------
        // Test 7: Write to RO register (GPIO_IN) should be ignored
        // -----------------------------------------------------------
        $display("\n--- Test 7: Write to RO GPIO_IN ---");
        axil_write(8'h08, 32'hDEADBEEF);
        axil_read(8'h08);
        // Should still read the synchronized gpio_i (0x02 from above)
        check("GPIO_IN not modified by write", axil_read_data[7:0], 8'h02);

        // -----------------------------------------------------------
        // Summary
        // -----------------------------------------------------------
        repeat (10) @(posedge clk);
        $display("\n============================================");
        $display("  GPIO Peripheral Testbench Summary");
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
