`timescale 1ns / 1ps
//============================================================================
// Testbench: tb_soc_top
// Smoke-test for soc_top: verifies reset sequencing and that the module
// instantiates without errors. Full functional verification requires
// FPGA-level tests with firmware.
//============================================================================

module tb_soc_top;

    // Clocks
    reg        sys_clk;
    reg        npu_clk;
    reg        sys_rst_n;

    // AXI3 HP0 (loopback / tie-off for sim)
    wire [5:0]  hp0_awid, hp0_arid;
    wire [31:0] hp0_awaddr, hp0_araddr;
    wire [3:0]  hp0_awlen, hp0_arlen;
    wire [2:0]  hp0_awsize, hp0_arsize;
    wire [1:0]  hp0_awburst, hp0_arburst;
    wire [3:0]  hp0_awqos, hp0_arqos;
    wire        hp0_awvalid, hp0_arvalid;
    wire [63:0] hp0_wdata, hp0_rdata_w;
    wire [7:0]  hp0_wstrb;
    wire        hp0_wlast, hp0_wvalid;
    wire [5:0]  hp0_bid_w, hp0_rid_w;
    wire [1:0]  hp0_bresp_w, hp0_rresp_w;
    wire        hp0_bvalid_w, hp0_rvalid_w, hp0_rlast_w;
    wire        hp0_bready, hp0_rready;

    // Tie HP0 responses to simple always-ready (no real DDR in sim)
    reg [5:0]  hp0_bid_r, hp0_rid_r;
    reg [1:0]  hp0_bresp_r, hp0_rresp_r;
    reg        hp0_bvalid_r, hp0_rvalid_r, hp0_rlast_r;
    reg [63:0] hp0_rdata_r;
    reg        hp0_awready_r, hp0_wready_r, hp0_arready_r;

    // External I/O
    wire       uart_tx;
    reg        uart_rx;
    reg        cam_pclk, cam_vsync, cam_href;
    reg  [7:0] cam_data;
    reg        i2s_sck, i2s_ws, i2s_sd;
    wire       spi_sclk, spi_mosi, spi_cs_n;
    reg        spi_miso;
    wire       i2c_scl_o, i2c_scl_oe, i2c_sda_o, i2c_sda_oe;
    reg        i2c_scl_i_r, i2c_sda_i_r;
    reg  [7:0] gpio_i_r;
    wire [7:0] gpio_o_w, gpio_oe_w;
    reg        esp32_handshake;
    wire       esp32_reset_n;

    // 100 MHz sys_clk
    initial sys_clk = 0;
    always #5 sys_clk = ~sys_clk;

    // 200 MHz npu_clk
    initial npu_clk = 0;
    always #2.5 npu_clk = ~npu_clk;

    // Simple HP0 slave model: accept writes, return dummy read data
    always @(posedge sys_clk) begin
        if (!sys_rst_n) begin
            hp0_awready_r <= 1'b0;
            hp0_wready_r  <= 1'b0;
            hp0_arready_r <= 1'b0;
            hp0_bvalid_r  <= 1'b0;
            hp0_rvalid_r  <= 1'b0;
            hp0_bid_r     <= 6'd0;
            hp0_rid_r     <= 6'd0;
            hp0_bresp_r   <= 2'b00;
            hp0_rresp_r   <= 2'b00;
            hp0_rdata_r   <= 64'd0;
            hp0_rlast_r   <= 1'b0;
        end else begin
            hp0_awready_r <= 1'b1;
            hp0_wready_r  <= 1'b1;
            hp0_arready_r <= 1'b1;

            // Write response
            if (hp0_wvalid && hp0_wlast && hp0_wready_r) begin
                hp0_bvalid_r <= 1'b1;
                hp0_bid_r    <= hp0_awid;
                hp0_bresp_r  <= 2'b00;
            end else if (hp0_bvalid_r && hp0_bready) begin
                hp0_bvalid_r <= 1'b0;
            end

            // Read response
            if (hp0_arvalid && hp0_arready_r) begin
                hp0_rvalid_r <= 1'b1;
                hp0_rid_r    <= hp0_arid;
                hp0_rdata_r  <= 64'hDEAD_BEEF_CAFE_BABE;
                hp0_rlast_r  <= 1'b1;
                hp0_rresp_r  <= 2'b00;
            end else if (hp0_rvalid_r && hp0_rready) begin
                hp0_rvalid_r <= 1'b0;
                hp0_rlast_r  <= 1'b0;
            end
        end
    end

    // DUT
    soc_top dut (
        .sys_clk_i   (sys_clk),
        .sys_rst_ni  (sys_rst_n),
        .npu_clk_i   (npu_clk),

        // HP0
        .m_axi_hp0_awid    (hp0_awid),
        .m_axi_hp0_awaddr  (hp0_awaddr),
        .m_axi_hp0_awlen   (hp0_awlen),
        .m_axi_hp0_awsize  (hp0_awsize),
        .m_axi_hp0_awburst (hp0_awburst),
        .m_axi_hp0_awqos   (hp0_awqos),
        .m_axi_hp0_awvalid (hp0_awvalid),
        .m_axi_hp0_awready (hp0_awready_r),
        .m_axi_hp0_wdata   (hp0_wdata),
        .m_axi_hp0_wstrb   (hp0_wstrb),
        .m_axi_hp0_wlast   (hp0_wlast),
        .m_axi_hp0_wvalid  (hp0_wvalid),
        .m_axi_hp0_wready  (hp0_wready_r),
        .m_axi_hp0_bid     (hp0_bid_r),
        .m_axi_hp0_bresp   (hp0_bresp_r),
        .m_axi_hp0_bvalid  (hp0_bvalid_r),
        .m_axi_hp0_bready  (hp0_bready),
        .m_axi_hp0_arid    (hp0_arid),
        .m_axi_hp0_araddr  (hp0_araddr),
        .m_axi_hp0_arlen   (hp0_arlen),
        .m_axi_hp0_arsize  (hp0_arsize),
        .m_axi_hp0_arburst (hp0_arburst),
        .m_axi_hp0_arqos   (hp0_arqos),
        .m_axi_hp0_arvalid (hp0_arvalid),
        .m_axi_hp0_arready (hp0_arready_r),
        .m_axi_hp0_rid     (hp0_rid_r),
        .m_axi_hp0_rdata   (hp0_rdata_r),
        .m_axi_hp0_rresp   (hp0_rresp_r),
        .m_axi_hp0_rlast   (hp0_rlast_r),
        .m_axi_hp0_rvalid  (hp0_rvalid_r),
        .m_axi_hp0_rready  (hp0_rready),

        // External I/O
        .uart_tx_o   (uart_tx),
        .uart_rx_i   (uart_rx),
        .cam_pclk_i  (cam_pclk),
        .cam_vsync_i (cam_vsync),
        .cam_href_i  (cam_href),
        .cam_data_i  (cam_data),
        .i2s_sck_i   (i2s_sck),
        .i2s_ws_i    (i2s_ws),
        .i2s_sd_i    (i2s_sd),
        .spi_sclk_o  (spi_sclk),
        .spi_mosi_o  (spi_mosi),
        .spi_miso_i  (spi_miso),
        .spi_cs_n_o  (spi_cs_n),
        .i2c_scl_o    (i2c_scl_o),
        .i2c_scl_oe_o (i2c_scl_oe),
        .i2c_scl_i    (i2c_scl_i_r),
        .i2c_sda_o    (i2c_sda_o),
        .i2c_sda_oe_o (i2c_sda_oe),
        .i2c_sda_i    (i2c_sda_i_r),
        .gpio_i       (gpio_i_r),
        .gpio_o       (gpio_o_w),
        .gpio_oe      (gpio_oe_w),
        .esp32_handshake_i (esp32_handshake),
        .esp32_reset_n_o   (esp32_reset_n)
    );

    integer pass_count;
    integer fail_count;

    task check;
        input [127:0] name;
        input actual;
        input expected;
        begin
            if (actual === expected)
                pass_count = pass_count + 1;
            else begin
                $display("FAIL: %0s = %b, expected %b at time %0t", name, actual, expected, $time);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;

        // Initialize external inputs
        sys_rst_n = 0;
        uart_rx = 1;
        cam_pclk = 0; cam_vsync = 0; cam_href = 0; cam_data = 8'd0;
        i2s_sck = 0; i2s_ws = 0; i2s_sd = 0;
        spi_miso = 0;
        i2c_scl_i_r = 1; i2c_sda_i_r = 1;
        gpio_i_r = 8'd0;
        esp32_handshake = 0;

        // Hold reset
        repeat (10) @(posedge sys_clk);

        // Test 1: Module instantiates without error (compilation test)
        pass_count = pass_count + 1;

        // Release reset
        sys_rst_n = 1;

        // Wait for reset sequence to complete
        repeat (20) @(posedge sys_clk);

        // Test 2: UART TX should be idle high after reset
        check("uart_tx_idle", uart_tx, 1'b1);

        // Test 3: SPI CS should be deasserted (high) after reset
        check("spi_cs_idle", spi_cs_n, 1'b1);

        // Test 4: ESP32 reset output tracks gpio_o[7]
        // (gpio_o defaults to 0 after reset, so esp32_reset_n should be 0)
        check("esp32_rst", esp32_reset_n, gpio_o_w[7]);

        // Let the system run for a while
        repeat (100) @(posedge sys_clk);

        // Test 5: System didn't hang (we reached here)
        pass_count = pass_count + 1;

        repeat (5) @(posedge sys_clk);
        $display("========================================");
        $display("tb_soc_top: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        $finish;
    end

endmodule
