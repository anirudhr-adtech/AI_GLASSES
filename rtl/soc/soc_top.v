`timescale 1ns / 1ps
//============================================================================
// Module : soc_top
// Project : AI_GLASSES — SoC Top-Level
// Description : Full SoC integration wrapper for the AI Smart Glasses
//               Phase 0 FPGA prototype (Zybo Z7-20).
//               Instantiates: clk_rst_mgr, riscv_subsys_top, npu_top,
//               audio_subsys_top, cam_subsys_top, axi_crossbar (DDR arb),
//               ddr_wrapper, spi_master, i2c_master.
//
//               Architecture:
//               - riscv_subsys_top contains CPU, internal crossbar (3M×4S),
//                 boot ROM, SRAM, UART, GPIO, timer, IRQ, AXI-Lite fabric
//                 (9 slots). Its m_axi_ddr carries merged CPU+NPU DDR traffic.
//               - SoC-level axi_crossbar (5M×5S) arbitrates DDR access for
//                 riscv (M0), NPU DMA (M2), Camera DMA (M3), Audio DMA (M4).
//               - ddr_wrapper converts AXI4 128-bit → AXI3 64-bit for HP0.
//============================================================================

module soc_top (
    // ================================================================
    // Zynq PS interface (via Block Design)
    // ================================================================
    input  wire        sys_clk_i,          // 100 MHz from Zynq FCLK_CLK0
    input  wire        sys_rst_ni,         // Active-low from Zynq FCLK_RESET0_N
    input  wire        npu_clk_i,          // 200 MHz from FCLK_CLK1 (tie to sys_clk if single-domain)

    // AXI3 master to Zynq S_AXI_HP0 (64-bit)
    output wire [5:0]  m_axi_hp0_awid,
    output wire [31:0] m_axi_hp0_awaddr,
    output wire [3:0]  m_axi_hp0_awlen,
    output wire [2:0]  m_axi_hp0_awsize,
    output wire [1:0]  m_axi_hp0_awburst,
    output wire [3:0]  m_axi_hp0_awqos,
    output wire        m_axi_hp0_awvalid,
    input  wire        m_axi_hp0_awready,
    output wire [63:0] m_axi_hp0_wdata,
    output wire [7:0]  m_axi_hp0_wstrb,
    output wire        m_axi_hp0_wlast,
    output wire        m_axi_hp0_wvalid,
    input  wire        m_axi_hp0_wready,
    input  wire [5:0]  m_axi_hp0_bid,
    input  wire [1:0]  m_axi_hp0_bresp,
    input  wire        m_axi_hp0_bvalid,
    output wire        m_axi_hp0_bready,
    output wire [5:0]  m_axi_hp0_arid,
    output wire [31:0] m_axi_hp0_araddr,
    output wire [3:0]  m_axi_hp0_arlen,
    output wire [2:0]  m_axi_hp0_arsize,
    output wire [1:0]  m_axi_hp0_arburst,
    output wire [3:0]  m_axi_hp0_arqos,
    output wire        m_axi_hp0_arvalid,
    input  wire        m_axi_hp0_arready,
    input  wire [5:0]  m_axi_hp0_rid,
    input  wire [63:0] m_axi_hp0_rdata,
    input  wire [1:0]  m_axi_hp0_rresp,
    input  wire        m_axi_hp0_rlast,
    input  wire        m_axi_hp0_rvalid,
    output wire        m_axi_hp0_rready,

    // ================================================================
    // External I/O (FPGA Pins / PMOD)
    // ================================================================
    // UART (USB-UART bridge)
    output wire        uart_tx_o,
    input  wire        uart_rx_i,

    // Camera DVP (OV7670)
    input  wire        cam_pclk_i,
    input  wire        cam_vsync_i,
    input  wire        cam_href_i,
    input  wire [7:0]  cam_data_i,

    // I2S Audio
    input  wire        i2s_sck_i,
    input  wire        i2s_ws_i,
    input  wire        i2s_sd_i,

    // SPI (ESP32-C3)
    output wire        spi_sclk_o,
    output wire        spi_mosi_o,
    input  wire        spi_miso_i,
    output wire        spi_cs_n_o,

    // I2C (IMU sensor / camera SCCB)
    output wire        i2c_scl_o,
    output wire        i2c_scl_oe_o,
    input  wire        i2c_scl_i,
    output wire        i2c_sda_o,
    output wire        i2c_sda_oe_o,
    input  wire        i2c_sda_i,

    // GPIO
    input  wire [7:0]  gpio_i,
    output wire [7:0]  gpio_o,
    output wire [7:0]  gpio_oe,

    // ESP32 control
    input  wire        esp32_handshake_i,
    output wire        esp32_reset_n_o
);

    // ================================================================
    // 1. Clock and Reset Manager
    // ================================================================
    wire periph_rst_n;
    wire cpu_rst_n;
    wire npu_rst_n;

    clk_rst_mgr u_clk_rst (
        .clk_i         (sys_clk_i),
        .npu_clk_i     (npu_clk_i),
        .sys_rst_ni    (sys_rst_ni),
        .periph_rst_no (periph_rst_n),
        .cpu_rst_no    (cpu_rst_n),
        .npu_rst_no    (npu_rst_n)
    );

    // ================================================================
    // 2. Internal wires: riscv ↔ crossbar ↔ DDR
    // ================================================================

    // --- riscv DDR master (32-bit) ---
    wire [31:0] rv_ddr_awaddr,  rv_ddr_araddr;
    wire        rv_ddr_awvalid, rv_ddr_arvalid;
    wire        rv_ddr_awready, rv_ddr_arready;
    wire [3:0]  rv_ddr_awid,    rv_ddr_arid;
    wire [7:0]  rv_ddr_awlen,   rv_ddr_arlen;
    wire [2:0]  rv_ddr_awsize,  rv_ddr_arsize;
    wire [1:0]  rv_ddr_awburst, rv_ddr_arburst;
    wire [31:0] rv_ddr_wdata;
    wire [3:0]  rv_ddr_wstrb;
    wire        rv_ddr_wvalid,  rv_ddr_wlast,  rv_ddr_wready;
    wire [3:0]  rv_ddr_bid,     rv_ddr_rid;
    wire [1:0]  rv_ddr_bresp,   rv_ddr_rresp;
    wire        rv_ddr_bvalid,  rv_ddr_bready;
    wire [31:0] rv_ddr_rdata;
    wire        rv_ddr_rvalid,  rv_ddr_rready,  rv_ddr_rlast;

    // --- NPU AXI-Lite (from riscv slot 8) ---
    wire [7:0]  npu_axil_awaddr,  npu_axil_araddr;
    wire        npu_axil_awvalid, npu_axil_arvalid;
    wire        npu_axil_awready, npu_axil_arready;
    wire [31:0] npu_axil_wdata;
    wire [3:0]  npu_axil_wstrb;
    wire        npu_axil_wvalid,  npu_axil_wready;
    wire [1:0]  npu_axil_bresp,   npu_axil_rresp;
    wire        npu_axil_bvalid,  npu_axil_bready;
    wire [31:0] npu_axil_rdata;
    wire        npu_axil_rvalid,  npu_axil_rready;

    // --- NPU DMA master (128-bit) ---
    wire [3:0]   npu_dma_awid,    npu_dma_arid;
    wire [31:0]  npu_dma_awaddr,  npu_dma_araddr;
    wire [7:0]   npu_dma_awlen,   npu_dma_arlen;
    wire [2:0]   npu_dma_awsize,  npu_dma_arsize;
    wire [1:0]   npu_dma_awburst, npu_dma_arburst;
    wire         npu_dma_awvalid, npu_dma_arvalid;
    wire         npu_dma_awready, npu_dma_arready;
    wire [127:0] npu_dma_wdata;
    wire [15:0]  npu_dma_wstrb;
    wire         npu_dma_wlast,   npu_dma_wvalid, npu_dma_wready;
    wire [3:0]   npu_dma_bid,     npu_dma_rid;
    wire [1:0]   npu_dma_bresp,   npu_dma_rresp;
    wire         npu_dma_bvalid,  npu_dma_bready;
    wire [127:0] npu_dma_rdata;
    wire         npu_dma_rlast,   npu_dma_rvalid, npu_dma_rready;
    wire         irq_npu_done;

    // --- Camera AXI-Lite + DMA ---
    wire [7:0]   cam_axil_awaddr,  cam_axil_araddr;
    wire         cam_axil_awvalid, cam_axil_arvalid;
    wire         cam_axil_awready, cam_axil_arready;
    wire [31:0]  cam_axil_wdata;
    wire [3:0]   cam_axil_wstrb;
    wire         cam_axil_wvalid,  cam_axil_wready;
    wire [1:0]   cam_axil_bresp,   cam_axil_rresp;
    wire         cam_axil_bvalid,  cam_axil_bready;
    wire [31:0]  cam_axil_rdata;
    wire         cam_axil_rvalid,  cam_axil_rready;

    wire [3:0]   cam_dma_awid,    cam_dma_arid;
    wire [31:0]  cam_dma_awaddr,  cam_dma_araddr;
    wire [7:0]   cam_dma_awlen,   cam_dma_arlen;
    wire [2:0]   cam_dma_awsize,  cam_dma_arsize;
    wire [1:0]   cam_dma_awburst, cam_dma_arburst;
    wire         cam_dma_awvalid, cam_dma_arvalid;
    wire         cam_dma_awready, cam_dma_arready;
    wire [127:0] cam_dma_wdata;
    wire [15:0]  cam_dma_wstrb;
    wire         cam_dma_wlast,   cam_dma_wvalid, cam_dma_wready;
    wire [3:0]   cam_dma_bid,     cam_dma_rid;
    wire [1:0]   cam_dma_bresp,   cam_dma_rresp;
    wire         cam_dma_bvalid,  cam_dma_bready;
    wire [127:0] cam_dma_rdata;
    wire         cam_dma_rlast,   cam_dma_rvalid, cam_dma_rready;
    wire         irq_camera_ready;

    // --- Audio AXI-Lite + DMA (write-only, 32-bit) ---
    wire [7:0]   aud_axil_awaddr,  aud_axil_araddr;
    wire         aud_axil_awvalid, aud_axil_arvalid;
    wire         aud_axil_awready, aud_axil_arready;
    wire [31:0]  aud_axil_wdata;
    wire [3:0]   aud_axil_wstrb;
    wire         aud_axil_wvalid,  aud_axil_wready;
    wire [1:0]   aud_axil_bresp,   aud_axil_rresp;
    wire         aud_axil_bvalid,  aud_axil_bready;
    wire [31:0]  aud_axil_rdata;
    wire         aud_axil_rvalid,  aud_axil_rready;

    wire [3:0]   aud_dma_awid;
    wire [31:0]  aud_dma_awaddr;
    wire [7:0]   aud_dma_awlen;
    wire [2:0]   aud_dma_awsize;
    wire [1:0]   aud_dma_awburst;
    wire         aud_dma_awvalid, aud_dma_awready;
    wire [31:0]  aud_dma_wdata;
    wire [3:0]   aud_dma_wstrb;
    wire         aud_dma_wlast,  aud_dma_wvalid, aud_dma_wready;
    wire [3:0]   aud_dma_bid;
    wire [1:0]   aud_dma_bresp;
    wire         aud_dma_bvalid, aud_dma_bready;
    wire         irq_audio_ready;

    // --- I2C / SPI AXI-Lite ---
    wire [7:0]  i2c_axil_awaddr,  i2c_axil_araddr;
    wire        i2c_axil_awvalid, i2c_axil_arvalid;
    wire        i2c_axil_awready, i2c_axil_arready;
    wire [31:0] i2c_axil_wdata;
    wire [3:0]  i2c_axil_wstrb;
    wire        i2c_axil_wvalid,  i2c_axil_wready;
    wire [1:0]  i2c_axil_bresp,   i2c_axil_rresp;
    wire        i2c_axil_bvalid,  i2c_axil_bready;
    wire [31:0] i2c_axil_rdata;
    wire        i2c_axil_rvalid,  i2c_axil_rready;
    wire        irq_i2c_done;

    wire [7:0]  spi_axil_awaddr,  spi_axil_araddr;
    wire        spi_axil_awvalid, spi_axil_arvalid;
    wire        spi_axil_awready, spi_axil_arready;
    wire [31:0] spi_axil_wdata;
    wire [3:0]  spi_axil_wstrb;
    wire        spi_axil_wvalid,  spi_axil_wready;
    wire [1:0]  spi_axil_bresp,   spi_axil_rresp;
    wire        spi_axil_bvalid,  spi_axil_bready;
    wire [31:0] spi_axil_rdata;
    wire        spi_axil_rvalid,  spi_axil_rready;

    // --- Crossbar S3 → DDR wrapper (128-bit AXI4) ---
    wire [5:0]   xbar_ddr_awid,    xbar_ddr_arid;
    wire [31:0]  xbar_ddr_awaddr,  xbar_ddr_araddr;
    wire [7:0]   xbar_ddr_awlen,   xbar_ddr_arlen;
    wire [2:0]   xbar_ddr_awsize,  xbar_ddr_arsize;
    wire [1:0]   xbar_ddr_awburst, xbar_ddr_arburst;
    wire         xbar_ddr_awvalid, xbar_ddr_arvalid;
    wire         xbar_ddr_awready, xbar_ddr_arready;
    wire [127:0] xbar_ddr_wdata;
    wire [15:0]  xbar_ddr_wstrb;
    wire         xbar_ddr_wlast,   xbar_ddr_wvalid, xbar_ddr_wready;
    wire [5:0]   xbar_ddr_bid,     xbar_ddr_rid;
    wire [1:0]   xbar_ddr_bresp,   xbar_ddr_rresp;
    wire         xbar_ddr_bvalid,  xbar_ddr_bready;
    wire [127:0] xbar_ddr_rdata;
    wire         xbar_ddr_rlast,   xbar_ddr_rvalid, xbar_ddr_rready;

    // ================================================================
    // 3. RISC-V Subsystem
    // ================================================================
    riscv_subsys_top u_riscv (
        .clk_i   (sys_clk_i),
        .rst_ni  (periph_rst_n),

        // DDR master
        .m_axi_ddr_awaddr  (rv_ddr_awaddr),
        .m_axi_ddr_awvalid (rv_ddr_awvalid),
        .m_axi_ddr_awready (rv_ddr_awready),
        .m_axi_ddr_awid    (rv_ddr_awid),
        .m_axi_ddr_awlen   (rv_ddr_awlen),
        .m_axi_ddr_awsize  (rv_ddr_awsize),
        .m_axi_ddr_awburst (rv_ddr_awburst),
        .m_axi_ddr_wdata   (rv_ddr_wdata),
        .m_axi_ddr_wstrb   (rv_ddr_wstrb),
        .m_axi_ddr_wvalid  (rv_ddr_wvalid),
        .m_axi_ddr_wlast   (rv_ddr_wlast),
        .m_axi_ddr_wready  (rv_ddr_wready),
        .m_axi_ddr_bid     (rv_ddr_bid),
        .m_axi_ddr_bresp   (rv_ddr_bresp),
        .m_axi_ddr_bvalid  (rv_ddr_bvalid),
        .m_axi_ddr_bready  (rv_ddr_bready),
        .m_axi_ddr_araddr  (rv_ddr_araddr),
        .m_axi_ddr_arvalid (rv_ddr_arvalid),
        .m_axi_ddr_arready (rv_ddr_arready),
        .m_axi_ddr_arid    (rv_ddr_arid),
        .m_axi_ddr_arlen   (rv_ddr_arlen),
        .m_axi_ddr_arsize  (rv_ddr_arsize),
        .m_axi_ddr_arburst (rv_ddr_arburst),
        .m_axi_ddr_rdata   (rv_ddr_rdata),
        .m_axi_ddr_rvalid  (rv_ddr_rvalid),
        .m_axi_ddr_rready  (rv_ddr_rready),
        .m_axi_ddr_rresp   (rv_ddr_rresp),
        .m_axi_ddr_rid     (rv_ddr_rid),
        .m_axi_ddr_rlast   (rv_ddr_rlast),

        // NPU DMA slave — tie off (NPU DMA routed directly to crossbar)
        .s_axi_npu_data_awaddr  (32'd0),
        .s_axi_npu_data_awvalid (1'b0),
        .s_axi_npu_data_awid    (4'd0),
        .s_axi_npu_data_awlen   (8'd0),
        .s_axi_npu_data_awsize  (3'd0),
        .s_axi_npu_data_awburst (2'd0),
        .s_axi_npu_data_wdata   (32'd0),
        .s_axi_npu_data_wstrb   (4'd0),
        .s_axi_npu_data_wvalid  (1'b0),
        .s_axi_npu_data_wlast   (1'b0),
        .s_axi_npu_data_bready  (1'b0),
        .s_axi_npu_data_araddr  (32'd0),
        .s_axi_npu_data_arvalid (1'b0),
        .s_axi_npu_data_arid    (4'd0),
        .s_axi_npu_data_arlen   (8'd0),
        .s_axi_npu_data_arsize  (3'd0),
        .s_axi_npu_data_arburst (2'd0),
        .s_axi_npu_data_rready  (1'b0),

        // AXI-Lite to external peripherals
        .m_axil_camera_ctrl_awaddr  (cam_axil_awaddr),
        .m_axil_camera_ctrl_awvalid (cam_axil_awvalid),
        .m_axil_camera_ctrl_awready (cam_axil_awready),
        .m_axil_camera_ctrl_wdata   (cam_axil_wdata),
        .m_axil_camera_ctrl_wstrb   (cam_axil_wstrb),
        .m_axil_camera_ctrl_wvalid  (cam_axil_wvalid),
        .m_axil_camera_ctrl_wready  (cam_axil_wready),
        .m_axil_camera_ctrl_bresp   (cam_axil_bresp),
        .m_axil_camera_ctrl_bvalid  (cam_axil_bvalid),
        .m_axil_camera_ctrl_bready  (cam_axil_bready),
        .m_axil_camera_ctrl_araddr  (cam_axil_araddr),
        .m_axil_camera_ctrl_arvalid (cam_axil_arvalid),
        .m_axil_camera_ctrl_arready (cam_axil_arready),
        .m_axil_camera_ctrl_rdata   (cam_axil_rdata),
        .m_axil_camera_ctrl_rresp   (cam_axil_rresp),
        .m_axil_camera_ctrl_rvalid  (cam_axil_rvalid),
        .m_axil_camera_ctrl_rready  (cam_axil_rready),

        .m_axil_audio_ctrl_awaddr   (aud_axil_awaddr),
        .m_axil_audio_ctrl_awvalid  (aud_axil_awvalid),
        .m_axil_audio_ctrl_awready  (aud_axil_awready),
        .m_axil_audio_ctrl_wdata    (aud_axil_wdata),
        .m_axil_audio_ctrl_wstrb    (aud_axil_wstrb),
        .m_axil_audio_ctrl_wvalid   (aud_axil_wvalid),
        .m_axil_audio_ctrl_wready   (aud_axil_wready),
        .m_axil_audio_ctrl_bresp    (aud_axil_bresp),
        .m_axil_audio_ctrl_bvalid   (aud_axil_bvalid),
        .m_axil_audio_ctrl_bready   (aud_axil_bready),
        .m_axil_audio_ctrl_araddr   (aud_axil_araddr),
        .m_axil_audio_ctrl_arvalid  (aud_axil_arvalid),
        .m_axil_audio_ctrl_arready  (aud_axil_arready),
        .m_axil_audio_ctrl_rdata    (aud_axil_rdata),
        .m_axil_audio_ctrl_rresp    (aud_axil_rresp),
        .m_axil_audio_ctrl_rvalid   (aud_axil_rvalid),
        .m_axil_audio_ctrl_rready   (aud_axil_rready),

        .m_axil_i2c_ctrl_awaddr     (i2c_axil_awaddr),
        .m_axil_i2c_ctrl_awvalid    (i2c_axil_awvalid),
        .m_axil_i2c_ctrl_awready    (i2c_axil_awready),
        .m_axil_i2c_ctrl_wdata      (i2c_axil_wdata),
        .m_axil_i2c_ctrl_wstrb      (i2c_axil_wstrb),
        .m_axil_i2c_ctrl_wvalid     (i2c_axil_wvalid),
        .m_axil_i2c_ctrl_wready     (i2c_axil_wready),
        .m_axil_i2c_ctrl_bresp      (i2c_axil_bresp),
        .m_axil_i2c_ctrl_bvalid     (i2c_axil_bvalid),
        .m_axil_i2c_ctrl_bready     (i2c_axil_bready),
        .m_axil_i2c_ctrl_araddr     (i2c_axil_araddr),
        .m_axil_i2c_ctrl_arvalid    (i2c_axil_arvalid),
        .m_axil_i2c_ctrl_arready    (i2c_axil_arready),
        .m_axil_i2c_ctrl_rdata      (i2c_axil_rdata),
        .m_axil_i2c_ctrl_rresp      (i2c_axil_rresp),
        .m_axil_i2c_ctrl_rvalid     (i2c_axil_rvalid),
        .m_axil_i2c_ctrl_rready     (i2c_axil_rready),

        .m_axil_spi_ctrl_awaddr     (spi_axil_awaddr),
        .m_axil_spi_ctrl_awvalid    (spi_axil_awvalid),
        .m_axil_spi_ctrl_awready    (spi_axil_awready),
        .m_axil_spi_ctrl_wdata      (spi_axil_wdata),
        .m_axil_spi_ctrl_wstrb      (spi_axil_wstrb),
        .m_axil_spi_ctrl_wvalid     (spi_axil_wvalid),
        .m_axil_spi_ctrl_wready     (spi_axil_wready),
        .m_axil_spi_ctrl_bresp      (spi_axil_bresp),
        .m_axil_spi_ctrl_bvalid     (spi_axil_bvalid),
        .m_axil_spi_ctrl_bready     (spi_axil_bready),
        .m_axil_spi_ctrl_araddr     (spi_axil_araddr),
        .m_axil_spi_ctrl_arvalid    (spi_axil_arvalid),
        .m_axil_spi_ctrl_arready    (spi_axil_arready),
        .m_axil_spi_ctrl_rdata      (spi_axil_rdata),
        .m_axil_spi_ctrl_rresp      (spi_axil_rresp),
        .m_axil_spi_ctrl_rvalid     (spi_axil_rvalid),
        .m_axil_spi_ctrl_rready     (spi_axil_rready),

        // NPU register access (slot 8)
        .m_axil_npu_ctrl_awaddr     (npu_axil_awaddr),
        .m_axil_npu_ctrl_awvalid    (npu_axil_awvalid),
        .m_axil_npu_ctrl_awready    (npu_axil_awready),
        .m_axil_npu_ctrl_wdata      (npu_axil_wdata),
        .m_axil_npu_ctrl_wstrb      (npu_axil_wstrb),
        .m_axil_npu_ctrl_wvalid     (npu_axil_wvalid),
        .m_axil_npu_ctrl_wready     (npu_axil_wready),
        .m_axil_npu_ctrl_bresp      (npu_axil_bresp),
        .m_axil_npu_ctrl_bvalid     (npu_axil_bvalid),
        .m_axil_npu_ctrl_bready     (npu_axil_bready),
        .m_axil_npu_ctrl_araddr     (npu_axil_araddr),
        .m_axil_npu_ctrl_arvalid    (npu_axil_arvalid),
        .m_axil_npu_ctrl_arready    (npu_axil_arready),
        .m_axil_npu_ctrl_rdata      (npu_axil_rdata),
        .m_axil_npu_ctrl_rresp      (npu_axil_rresp),
        .m_axil_npu_ctrl_rvalid     (npu_axil_rvalid),
        .m_axil_npu_ctrl_rready     (npu_axil_rready),

        // UART / GPIO
        .uart_tx_o (uart_tx_o),
        .uart_rx_i (uart_rx_i),
        .gpio_i    (gpio_i),
        .gpio_o    (gpio_o),
        .gpio_oe   (gpio_oe),

        // IRQ sources
        .irq_npu_done_i      (irq_npu_done),
        .irq_dma_done_i      (1'b0),
        .irq_camera_ready_i  (irq_camera_ready),
        .irq_audio_ready_i   (irq_audio_ready),
        .irq_i2c_done_i      (irq_i2c_done)
    );

    // ================================================================
    // 4. NPU Subsystem
    // ================================================================
    npu_top u_npu (
        .clk   (sys_clk_i),
        .rst_n (periph_rst_n),

        // AXI-Lite slave (register access from CPU)
        .s_axi_lite_awaddr  (npu_axil_awaddr),
        .s_axi_lite_awvalid (npu_axil_awvalid),
        .s_axi_lite_awready (npu_axil_awready),
        .s_axi_lite_wdata   (npu_axil_wdata),
        .s_axi_lite_wstrb   (npu_axil_wstrb),
        .s_axi_lite_wvalid  (npu_axil_wvalid),
        .s_axi_lite_wready  (npu_axil_wready),
        .s_axi_lite_bresp   (npu_axil_bresp),
        .s_axi_lite_bvalid  (npu_axil_bvalid),
        .s_axi_lite_bready  (npu_axil_bready),
        .s_axi_lite_araddr  (npu_axil_araddr),
        .s_axi_lite_arvalid (npu_axil_arvalid),
        .s_axi_lite_arready (npu_axil_arready),
        .s_axi_lite_rdata   (npu_axil_rdata),
        .s_axi_lite_rresp   (npu_axil_rresp),
        .s_axi_lite_rvalid  (npu_axil_rvalid),
        .s_axi_lite_rready  (npu_axil_rready),

        // AXI4 DMA master (128-bit, to crossbar M2)
        .m_axi_dma_awid    (npu_dma_awid),
        .m_axi_dma_awaddr  (npu_dma_awaddr),
        .m_axi_dma_awlen   (npu_dma_awlen),
        .m_axi_dma_awsize  (npu_dma_awsize),
        .m_axi_dma_awburst (npu_dma_awburst),
        .m_axi_dma_awqos   (),
        .m_axi_dma_awvalid (npu_dma_awvalid),
        .m_axi_dma_awready (npu_dma_awready),
        .m_axi_dma_wdata   (npu_dma_wdata),
        .m_axi_dma_wstrb   (npu_dma_wstrb),
        .m_axi_dma_wlast   (npu_dma_wlast),
        .m_axi_dma_wvalid  (npu_dma_wvalid),
        .m_axi_dma_wready  (npu_dma_wready),
        .m_axi_dma_bid     (npu_dma_bid),
        .m_axi_dma_bresp   (npu_dma_bresp),
        .m_axi_dma_bvalid  (npu_dma_bvalid),
        .m_axi_dma_bready  (npu_dma_bready),
        .m_axi_dma_arid    (npu_dma_arid),
        .m_axi_dma_araddr  (npu_dma_araddr),
        .m_axi_dma_arlen   (npu_dma_arlen),
        .m_axi_dma_arsize  (npu_dma_arsize),
        .m_axi_dma_arburst (npu_dma_arburst),
        .m_axi_dma_arqos   (),
        .m_axi_dma_arvalid (npu_dma_arvalid),
        .m_axi_dma_arready (npu_dma_arready),
        .m_axi_dma_rid     (npu_dma_rid),
        .m_axi_dma_rdata   (npu_dma_rdata),
        .m_axi_dma_rresp   (npu_dma_rresp),
        .m_axi_dma_rlast   (npu_dma_rlast),
        .m_axi_dma_rvalid  (npu_dma_rvalid),
        .m_axi_dma_rready  (npu_dma_rready),

        .irq_npu_done (irq_npu_done)
    );

    // ================================================================
    // 5. Audio Subsystem
    // ================================================================
    audio_subsys_top u_audio (
        .clk_i  (sys_clk_i),
        .rst_ni (periph_rst_n),

        .i2s_sck_i (i2s_sck_i),
        .i2s_ws_i  (i2s_ws_i),
        .i2s_sd_i  (i2s_sd_i),

        // AXI-Lite (register access, zero-extend 8-bit addr to 32-bit)
        .s_axi_lite_awaddr  ({24'd0, aud_axil_awaddr}),
        .s_axi_lite_awvalid (aud_axil_awvalid),
        .s_axi_lite_awready (aud_axil_awready),
        .s_axi_lite_wdata   (aud_axil_wdata),
        .s_axi_lite_wstrb   (aud_axil_wstrb),
        .s_axi_lite_wvalid  (aud_axil_wvalid),
        .s_axi_lite_wready  (aud_axil_wready),
        .s_axi_lite_bresp   (aud_axil_bresp),
        .s_axi_lite_bvalid  (aud_axil_bvalid),
        .s_axi_lite_bready  (aud_axil_bready),
        .s_axi_lite_araddr  ({24'd0, aud_axil_araddr}),
        .s_axi_lite_arvalid (aud_axil_arvalid),
        .s_axi_lite_arready (aud_axil_arready),
        .s_axi_lite_rdata   (aud_axil_rdata),
        .s_axi_lite_rresp   (aud_axil_rresp),
        .s_axi_lite_rvalid  (aud_axil_rvalid),
        .s_axi_lite_rready  (aud_axil_rready),

        // AXI4 DMA master (write-only, 32-bit, to crossbar M4)
        .m_axi_dma_awid    (aud_dma_awid),
        .m_axi_dma_awaddr  (aud_dma_awaddr),
        .m_axi_dma_awlen   (aud_dma_awlen),
        .m_axi_dma_awsize  (aud_dma_awsize),
        .m_axi_dma_awburst (aud_dma_awburst),
        .m_axi_dma_awvalid (aud_dma_awvalid),
        .m_axi_dma_awready (aud_dma_awready),
        .m_axi_dma_wdata   (aud_dma_wdata),
        .m_axi_dma_wstrb   (aud_dma_wstrb),
        .m_axi_dma_wlast   (aud_dma_wlast),
        .m_axi_dma_wvalid  (aud_dma_wvalid),
        .m_axi_dma_wready  (aud_dma_wready),
        .m_axi_dma_bid     (aud_dma_bid),
        .m_axi_dma_bresp   (aud_dma_bresp),
        .m_axi_dma_bvalid  (aud_dma_bvalid),
        .m_axi_dma_bready  (aud_dma_bready),

        .irq_audio_ready_o (irq_audio_ready)
    );

    // ================================================================
    // 6. Camera Subsystem
    // ================================================================
    cam_subsys_top u_camera (
        .clk_i  (sys_clk_i),
        .rst_ni (periph_rst_n),

        .cam_pclk_i  (cam_pclk_i),
        .cam_vsync_i (cam_vsync_i),
        .cam_href_i  (cam_href_i),
        .cam_data_i  (cam_data_i),

        // AXI-Lite (register access, zero-extend 8-bit addr to 32-bit)
        .s_axi_lite_awaddr  ({24'd0, cam_axil_awaddr}),
        .s_axi_lite_awvalid (cam_axil_awvalid),
        .s_axi_lite_awready (cam_axil_awready),
        .s_axi_lite_wdata   (cam_axil_wdata),
        .s_axi_lite_wstrb   (cam_axil_wstrb),
        .s_axi_lite_wvalid  (cam_axil_wvalid),
        .s_axi_lite_wready  (cam_axil_wready),
        .s_axi_lite_bresp   (cam_axil_bresp),
        .s_axi_lite_bvalid  (cam_axil_bvalid),
        .s_axi_lite_bready  (cam_axil_bready),
        .s_axi_lite_araddr  ({24'd0, cam_axil_araddr}),
        .s_axi_lite_arvalid (cam_axil_arvalid),
        .s_axi_lite_arready (cam_axil_arready),
        .s_axi_lite_rdata   (cam_axil_rdata),
        .s_axi_lite_rresp   (cam_axil_rresp),
        .s_axi_lite_rvalid  (cam_axil_rvalid),
        .s_axi_lite_rready  (cam_axil_rready),

        // AXI4 DMA master (128-bit, to crossbar M3)
        .m_axi_vdma_awid    (cam_dma_awid),
        .m_axi_vdma_awaddr  (cam_dma_awaddr),
        .m_axi_vdma_awlen   (cam_dma_awlen),
        .m_axi_vdma_awsize  (cam_dma_awsize),
        .m_axi_vdma_awburst (cam_dma_awburst),
        .m_axi_vdma_awvalid (cam_dma_awvalid),
        .m_axi_vdma_awready (cam_dma_awready),
        .m_axi_vdma_wdata   (cam_dma_wdata),
        .m_axi_vdma_wstrb   (cam_dma_wstrb),
        .m_axi_vdma_wlast   (cam_dma_wlast),
        .m_axi_vdma_wvalid  (cam_dma_wvalid),
        .m_axi_vdma_wready  (cam_dma_wready),
        .m_axi_vdma_bid     (cam_dma_bid),
        .m_axi_vdma_bresp   (cam_dma_bresp),
        .m_axi_vdma_bvalid  (cam_dma_bvalid),
        .m_axi_vdma_bready  (cam_dma_bready),
        .m_axi_vdma_arid    (cam_dma_arid),
        .m_axi_vdma_araddr  (cam_dma_araddr),
        .m_axi_vdma_arlen   (cam_dma_arlen),
        .m_axi_vdma_arsize  (cam_dma_arsize),
        .m_axi_vdma_arburst (cam_dma_arburst),
        .m_axi_vdma_arvalid (cam_dma_arvalid),
        .m_axi_vdma_arready (cam_dma_arready),
        .m_axi_vdma_rid     (cam_dma_rid),
        .m_axi_vdma_rdata   (cam_dma_rdata),
        .m_axi_vdma_rresp   (cam_dma_rresp),
        .m_axi_vdma_rlast   (cam_dma_rlast),
        .m_axi_vdma_rvalid  (cam_dma_rvalid),
        .m_axi_vdma_rready  (cam_dma_rready),

        .irq_camera_ready_o (irq_camera_ready)
    );

    // ================================================================
    // 7. SPI Master (ESP32-C3)
    // ================================================================
    spi_master u_spi (
        .clk_i  (sys_clk_i),
        .rst_ni (periph_rst_n),

        .s_axi_lite_awaddr  (spi_axil_awaddr),
        .s_axi_lite_awvalid (spi_axil_awvalid),
        .s_axi_lite_awready (spi_axil_awready),
        .s_axi_lite_wdata   (spi_axil_wdata),
        .s_axi_lite_wstrb   (spi_axil_wstrb),
        .s_axi_lite_wvalid  (spi_axil_wvalid),
        .s_axi_lite_wready  (spi_axil_wready),
        .s_axi_lite_bresp   (spi_axil_bresp),
        .s_axi_lite_bvalid  (spi_axil_bvalid),
        .s_axi_lite_bready  (spi_axil_bready),
        .s_axi_lite_araddr  (spi_axil_araddr),
        .s_axi_lite_arvalid (spi_axil_arvalid),
        .s_axi_lite_arready (spi_axil_arready),
        .s_axi_lite_rdata   (spi_axil_rdata),
        .s_axi_lite_rresp   (spi_axil_rresp),
        .s_axi_lite_rvalid  (spi_axil_rvalid),
        .s_axi_lite_rready  (spi_axil_rready),

        .spi_sclk_o (spi_sclk_o),
        .spi_mosi_o (spi_mosi_o),
        .spi_miso_i (spi_miso_i),
        .spi_cs_n_o (spi_cs_n_o),

        .irq_spi_o  ()
    );

    // ================================================================
    // 8. I2C Master (IMU / Camera SCCB)
    // ================================================================
    i2c_master u_i2c (
        .clk_i  (sys_clk_i),
        .rst_ni (periph_rst_n),

        .s_axi_lite_awaddr  (i2c_axil_awaddr),
        .s_axi_lite_awvalid (i2c_axil_awvalid),
        .s_axi_lite_awready (i2c_axil_awready),
        .s_axi_lite_wdata   (i2c_axil_wdata),
        .s_axi_lite_wstrb   (i2c_axil_wstrb),
        .s_axi_lite_wvalid  (i2c_axil_wvalid),
        .s_axi_lite_wready  (i2c_axil_wready),
        .s_axi_lite_bresp   (i2c_axil_bresp),
        .s_axi_lite_bvalid  (i2c_axil_bvalid),
        .s_axi_lite_bready  (i2c_axil_bready),
        .s_axi_lite_araddr  (i2c_axil_araddr),
        .s_axi_lite_arvalid (i2c_axil_arvalid),
        .s_axi_lite_arready (i2c_axil_arready),
        .s_axi_lite_rdata   (i2c_axil_rdata),
        .s_axi_lite_rresp   (i2c_axil_rresp),
        .s_axi_lite_rvalid  (i2c_axil_rvalid),
        .s_axi_lite_rready  (i2c_axil_rready),

        .i2c_scl_o    (i2c_scl_o),
        .i2c_scl_oe_o (i2c_scl_oe_o),
        .i2c_scl_i    (i2c_scl_i),
        .i2c_sda_o    (i2c_sda_o),
        .i2c_sda_oe_o (i2c_sda_oe_o),
        .i2c_sda_i    (i2c_sda_i),

        .irq_i2c_done_o (irq_i2c_done)
    );

    // ================================================================
    // 9. AXI Crossbar (DDR arbitration: 5M × 5S)
    //    M0: riscv DDR (32-bit)   M1: unused
    //    M2: NPU DMA (128-bit)   M3: Camera DMA (128-bit)
    //    M4: Audio DMA (32-bit)
    //    S0-S2: tied off (never addressed)
    //    S3: DDR wrapper (128-bit)
    // ================================================================
    axi_crossbar u_xbar (
        .clk   (sys_clk_i),
        .rst_n (periph_rst_n),

        // --- M0: RISC-V DDR (32-bit, IDs truncated 4→3) ---
        .m0_awid    (rv_ddr_awid[2:0]),
        .m0_awaddr  (rv_ddr_awaddr),
        .m0_awlen   (rv_ddr_awlen),
        .m0_awsize  (rv_ddr_awsize),
        .m0_awburst (rv_ddr_awburst),
        .m0_awvalid (rv_ddr_awvalid),
        .m0_awready (rv_ddr_awready),
        .m0_wdata   (rv_ddr_wdata),
        .m0_wstrb   (rv_ddr_wstrb),
        .m0_wlast   (rv_ddr_wlast),
        .m0_wvalid  (rv_ddr_wvalid),
        .m0_wready  (rv_ddr_wready),
        .m0_bid     (rv_ddr_bid[2:0]),
        .m0_bresp   (rv_ddr_bresp),
        .m0_bvalid  (rv_ddr_bvalid),
        .m0_bready  (rv_ddr_bready),
        .m0_arid    (rv_ddr_arid[2:0]),
        .m0_araddr  (rv_ddr_araddr),
        .m0_arlen   (rv_ddr_arlen),
        .m0_arsize  (rv_ddr_arsize),
        .m0_arburst (rv_ddr_arburst),
        .m0_arvalid (rv_ddr_arvalid),
        .m0_arready (rv_ddr_arready),
        .m0_rid     (rv_ddr_rid[2:0]),
        .m0_rdata   (rv_ddr_rdata),
        .m0_rresp   (rv_ddr_rresp),
        .m0_rlast   (rv_ddr_rlast),
        .m0_rvalid  (rv_ddr_rvalid),
        .m0_rready  (rv_ddr_rready),

        // --- M1: Unused (tied off) ---
        .m1_awid    (3'd0),
        .m1_awaddr  (32'd0),
        .m1_awlen   (8'd0),
        .m1_awsize  (3'd0),
        .m1_awburst (2'd0),
        .m1_awvalid (1'b0),
        .m1_awready (),
        .m1_wdata   (32'd0),
        .m1_wstrb   (4'd0),
        .m1_wlast   (1'b0),
        .m1_wvalid  (1'b0),
        .m1_wready  (),
        .m1_bid     (),
        .m1_bresp   (),
        .m1_bvalid  (),
        .m1_bready  (1'b0),
        .m1_arid    (3'd0),
        .m1_araddr  (32'd0),
        .m1_arlen   (8'd0),
        .m1_arsize  (3'd0),
        .m1_arburst (2'd0),
        .m1_arvalid (1'b0),
        .m1_arready (),
        .m1_rid     (),
        .m1_rdata   (),
        .m1_rresp   (),
        .m1_rlast   (),
        .m1_rvalid  (),
        .m1_rready  (1'b0),

        // --- M2: NPU DMA (128-bit, IDs truncated 4→3) ---
        .m2_awid    (npu_dma_awid[2:0]),
        .m2_awaddr  (npu_dma_awaddr),
        .m2_awlen   (npu_dma_awlen),
        .m2_awsize  (npu_dma_awsize),
        .m2_awburst (npu_dma_awburst),
        .m2_awvalid (npu_dma_awvalid),
        .m2_awready (npu_dma_awready),
        .m2_wdata   (npu_dma_wdata),
        .m2_wstrb   (npu_dma_wstrb),
        .m2_wlast   (npu_dma_wlast),
        .m2_wvalid  (npu_dma_wvalid),
        .m2_wready  (npu_dma_wready),
        .m2_bid     (npu_dma_bid[2:0]),
        .m2_bresp   (npu_dma_bresp),
        .m2_bvalid  (npu_dma_bvalid),
        .m2_bready  (npu_dma_bready),
        .m2_arid    (npu_dma_arid[2:0]),
        .m2_araddr  (npu_dma_araddr),
        .m2_arlen   (npu_dma_arlen),
        .m2_arsize  (npu_dma_arsize),
        .m2_arburst (npu_dma_arburst),
        .m2_arvalid (npu_dma_arvalid),
        .m2_arready (npu_dma_arready),
        .m2_rid     (npu_dma_rid[2:0]),
        .m2_rdata   (npu_dma_rdata),
        .m2_rresp   (npu_dma_rresp),
        .m2_rlast   (npu_dma_rlast),
        .m2_rvalid  (npu_dma_rvalid),
        .m2_rready  (npu_dma_rready),

        // --- M3: Camera DMA (128-bit, IDs truncated 4→3) ---
        .m3_awid    (cam_dma_awid[2:0]),
        .m3_awaddr  (cam_dma_awaddr),
        .m3_awlen   (cam_dma_awlen),
        .m3_awsize  (cam_dma_awsize),
        .m3_awburst (cam_dma_awburst),
        .m3_awvalid (cam_dma_awvalid),
        .m3_awready (cam_dma_awready),
        .m3_wdata   (cam_dma_wdata),
        .m3_wstrb   (cam_dma_wstrb),
        .m3_wlast   (cam_dma_wlast),
        .m3_wvalid  (cam_dma_wvalid),
        .m3_wready  (cam_dma_wready),
        .m3_bid     (cam_dma_bid[2:0]),
        .m3_bresp   (cam_dma_bresp),
        .m3_bvalid  (cam_dma_bvalid),
        .m3_bready  (cam_dma_bready),
        .m3_arid    (cam_dma_arid[2:0]),
        .m3_araddr  (cam_dma_araddr),
        .m3_arlen   (cam_dma_arlen),
        .m3_arsize  (cam_dma_arsize),
        .m3_arburst (cam_dma_arburst),
        .m3_arvalid (cam_dma_arvalid),
        .m3_arready (cam_dma_arready),
        .m3_rid     (cam_dma_rid[2:0]),
        .m3_rdata   (cam_dma_rdata),
        .m3_rresp   (cam_dma_rresp),
        .m3_rlast   (cam_dma_rlast),
        .m3_rvalid  (cam_dma_rvalid),
        .m3_rready  (cam_dma_rready),

        // --- M4: Audio DMA (32-bit, write-only; read channel tied off) ---
        .m4_awid    (aud_dma_awid[2:0]),
        .m4_awaddr  (aud_dma_awaddr),
        .m4_awlen   (aud_dma_awlen),
        .m4_awsize  (aud_dma_awsize),
        .m4_awburst (aud_dma_awburst),
        .m4_awvalid (aud_dma_awvalid),
        .m4_awready (aud_dma_awready),
        .m4_wdata   (aud_dma_wdata),
        .m4_wstrb   (aud_dma_wstrb),
        .m4_wlast   (aud_dma_wlast),
        .m4_wvalid  (aud_dma_wvalid),
        .m4_wready  (aud_dma_wready),
        .m4_bid     (aud_dma_bid[2:0]),
        .m4_bresp   (aud_dma_bresp),
        .m4_bvalid  (aud_dma_bvalid),
        .m4_bready  (aud_dma_bready),
        .m4_arid    (3'd0),
        .m4_araddr  (32'd0),
        .m4_arlen   (8'd0),
        .m4_arsize  (3'd0),
        .m4_arburst (2'd0),
        .m4_arvalid (1'b0),
        .m4_arready (),
        .m4_rid     (),
        .m4_rdata   (),
        .m4_rresp   (),
        .m4_rlast   (),
        .m4_rvalid  (),
        .m4_rready  (1'b0),

        // --- S0: Boot ROM (tied off — handled inside riscv_subsys_top) ---
        .s0_awready (1'b0),
        .s0_wready  (1'b0),
        .s0_bid     (6'd0),
        .s0_bresp   (2'b10),
        .s0_bvalid  (1'b0),
        .s0_arready (1'b0),
        .s0_rid     (6'd0),
        .s0_rdata   (32'd0),
        .s0_rresp   (2'b10),
        .s0_rlast   (1'b0),
        .s0_rvalid  (1'b0),

        // --- S1: SRAM (tied off — handled inside riscv_subsys_top) ---
        .s1_awready (1'b0),
        .s1_wready  (1'b0),
        .s1_bid     (6'd0),
        .s1_bresp   (2'b10),
        .s1_bvalid  (1'b0),
        .s1_arready (1'b0),
        .s1_rid     (6'd0),
        .s1_rdata   (32'd0),
        .s1_rresp   (2'b10),
        .s1_rlast   (1'b0),
        .s1_rvalid  (1'b0),

        // --- S2: Peripheral bridge (tied off — handled inside riscv_subsys_top) ---
        .s2_awready (1'b0),
        .s2_wready  (1'b0),
        .s2_bid     (6'd0),
        .s2_bresp   (2'b10),
        .s2_bvalid  (1'b0),
        .s2_arready (1'b0),
        .s2_rid     (6'd0),
        .s2_rdata   (32'd0),
        .s2_rresp   (2'b10),
        .s2_rlast   (1'b0),
        .s2_rvalid  (1'b0),

        // --- S3: DDR (128-bit, to ddr_wrapper) ---
        .s3_awid    (xbar_ddr_awid),
        .s3_awaddr  (xbar_ddr_awaddr),
        .s3_awlen   (xbar_ddr_awlen),
        .s3_awsize  (xbar_ddr_awsize),
        .s3_awburst (xbar_ddr_awburst),
        .s3_awvalid (xbar_ddr_awvalid),
        .s3_awready (xbar_ddr_awready),
        .s3_wdata   (xbar_ddr_wdata),
        .s3_wstrb   (xbar_ddr_wstrb),
        .s3_wlast   (xbar_ddr_wlast),
        .s3_wvalid  (xbar_ddr_wvalid),
        .s3_wready  (xbar_ddr_wready),
        .s3_bid     (xbar_ddr_bid),
        .s3_bresp   (xbar_ddr_bresp),
        .s3_bvalid  (xbar_ddr_bvalid),
        .s3_bready  (xbar_ddr_bready),
        .s3_arid    (xbar_ddr_arid),
        .s3_araddr  (xbar_ddr_araddr),
        .s3_arlen   (xbar_ddr_arlen),
        .s3_arsize  (xbar_ddr_arsize),
        .s3_arburst (xbar_ddr_arburst),
        .s3_arvalid (xbar_ddr_arvalid),
        .s3_arready (xbar_ddr_arready),
        .s3_rid     (xbar_ddr_rid),
        .s3_rdata   (xbar_ddr_rdata),
        .s3_rresp   (xbar_ddr_rresp),
        .s3_rlast   (xbar_ddr_rlast),
        .s3_rvalid  (xbar_ddr_rvalid),
        .s3_rready  (xbar_ddr_rready),

        .timeout_events (),
        .timeout_sticky ()
    );

    // ================================================================
    // 10. DDR Wrapper (AXI4 128-bit → AXI3 64-bit → Zynq HP0)
    // ================================================================
    ddr_wrapper u_ddr (
        .clk   (sys_clk_i),
        .rst_n (periph_rst_n),

        // AXI4 slave (128-bit, from crossbar S3)
        .s_axi4_awid    (xbar_ddr_awid),
        .s_axi4_awaddr  (xbar_ddr_awaddr),
        .s_axi4_awlen   (xbar_ddr_awlen),
        .s_axi4_awsize  (xbar_ddr_awsize),
        .s_axi4_awburst (xbar_ddr_awburst),
        .s_axi4_awvalid (xbar_ddr_awvalid),
        .s_axi4_awready (xbar_ddr_awready),
        .s_axi4_wdata   (xbar_ddr_wdata),
        .s_axi4_wstrb   (xbar_ddr_wstrb),
        .s_axi4_wlast   (xbar_ddr_wlast),
        .s_axi4_wvalid  (xbar_ddr_wvalid),
        .s_axi4_wready  (xbar_ddr_wready),
        .s_axi4_bid     (xbar_ddr_bid),
        .s_axi4_bresp   (xbar_ddr_bresp),
        .s_axi4_bvalid  (xbar_ddr_bvalid),
        .s_axi4_bready  (xbar_ddr_bready),
        .s_axi4_arid    (xbar_ddr_arid),
        .s_axi4_araddr  (xbar_ddr_araddr),
        .s_axi4_arlen   (xbar_ddr_arlen),
        .s_axi4_arsize  (xbar_ddr_arsize),
        .s_axi4_arburst (xbar_ddr_arburst),
        .s_axi4_arvalid (xbar_ddr_arvalid),
        .s_axi4_arready (xbar_ddr_arready),
        .s_axi4_rid     (xbar_ddr_rid),
        .s_axi4_rdata   (xbar_ddr_rdata),
        .s_axi4_rresp   (xbar_ddr_rresp),
        .s_axi4_rlast   (xbar_ddr_rlast),
        .s_axi4_rvalid  (xbar_ddr_rvalid),
        .s_axi4_rready  (xbar_ddr_rready),

        // AXI3 master (64-bit, to Zynq HP0)
        .m_axi3_awid    (m_axi_hp0_awid),
        .m_axi3_awaddr  (m_axi_hp0_awaddr),
        .m_axi3_awlen   (m_axi_hp0_awlen),
        .m_axi3_awsize  (m_axi_hp0_awsize),
        .m_axi3_awburst (m_axi_hp0_awburst),
        .m_axi3_awqos   (m_axi_hp0_awqos),
        .m_axi3_awvalid (m_axi_hp0_awvalid),
        .m_axi3_awready (m_axi_hp0_awready),
        .m_axi3_wdata   (m_axi_hp0_wdata),
        .m_axi3_wstrb   (m_axi_hp0_wstrb),
        .m_axi3_wlast   (m_axi_hp0_wlast),
        .m_axi3_wvalid  (m_axi_hp0_wvalid),
        .m_axi3_wready  (m_axi_hp0_wready),
        .m_axi3_bid     (m_axi_hp0_bid),
        .m_axi3_bresp   (m_axi_hp0_bresp),
        .m_axi3_bvalid  (m_axi_hp0_bvalid),
        .m_axi3_bready  (m_axi_hp0_bready),
        .m_axi3_arid    (m_axi_hp0_arid),
        .m_axi3_araddr  (m_axi_hp0_araddr),
        .m_axi3_arlen   (m_axi_hp0_arlen),
        .m_axi3_arsize  (m_axi_hp0_arsize),
        .m_axi3_arburst (m_axi_hp0_arburst),
        .m_axi3_arqos   (m_axi_hp0_arqos),
        .m_axi3_arvalid (m_axi_hp0_arvalid),
        .m_axi3_arready (m_axi_hp0_arready),
        .m_axi3_rid     (m_axi_hp0_rid),
        .m_axi3_rdata   (m_axi_hp0_rdata),
        .m_axi3_rresp   (m_axi_hp0_rresp),
        .m_axi3_rlast   (m_axi_hp0_rlast),
        .m_axi3_rvalid  (m_axi_hp0_rvalid),
        .m_axi3_rready  (m_axi_hp0_rready)
    );

    // ================================================================
    // 11. ESP32 control wiring
    // ================================================================
    // ESP32 HANDSHAKE → GPIO input bit 0 (directly via gpio_i from board)
    // ESP32 RESET_N  → GPIO output bit 7
    assign esp32_reset_n_o = gpio_o[7];

endmodule
