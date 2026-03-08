`timescale 1ns/1ps
//============================================================================
// Module : riscv_subsys_top
// Project : AI_GLASSES — RISC-V Subsystem
// Description : Top-level integration of entire RISC-V subsystem.
//               Instantiates CPU, bus adapters, interconnect, memories,
//               bridge, peripheral fabric, and all peripherals.
//============================================================================

module riscv_subsys_top (
    input  wire        clk_i,
    input  wire        rst_ni,

    // AXI4 Master to DDR controller (from interconnect S3)
    output wire [31:0] m_axi_ddr_awaddr,
    output wire        m_axi_ddr_awvalid,
    input  wire        m_axi_ddr_awready,
    output wire [3:0]  m_axi_ddr_awid,
    output wire [7:0]  m_axi_ddr_awlen,
    output wire [2:0]  m_axi_ddr_awsize,
    output wire [1:0]  m_axi_ddr_awburst,
    output wire [31:0] m_axi_ddr_wdata,
    output wire [3:0]  m_axi_ddr_wstrb,
    output wire        m_axi_ddr_wvalid,
    output wire        m_axi_ddr_wlast,
    input  wire        m_axi_ddr_wready,
    input  wire [3:0]  m_axi_ddr_bid,
    input  wire [1:0]  m_axi_ddr_bresp,
    input  wire        m_axi_ddr_bvalid,
    output wire        m_axi_ddr_bready,
    output wire [31:0] m_axi_ddr_araddr,
    output wire        m_axi_ddr_arvalid,
    input  wire        m_axi_ddr_arready,
    output wire [3:0]  m_axi_ddr_arid,
    output wire [7:0]  m_axi_ddr_arlen,
    output wire [2:0]  m_axi_ddr_arsize,
    output wire [1:0]  m_axi_ddr_arburst,
    input  wire [31:0] m_axi_ddr_rdata,
    input  wire        m_axi_ddr_rvalid,
    output wire        m_axi_ddr_rready,
    input  wire [1:0]  m_axi_ddr_rresp,
    input  wire [3:0]  m_axi_ddr_rid,
    input  wire        m_axi_ddr_rlast,

    // AXI4 Slave from NPU DMA (connected as M2 on interconnect)
    input  wire [31:0] s_axi_npu_data_awaddr,
    input  wire        s_axi_npu_data_awvalid,
    output wire        s_axi_npu_data_awready,
    input  wire [3:0]  s_axi_npu_data_awid,
    input  wire [7:0]  s_axi_npu_data_awlen,
    input  wire [2:0]  s_axi_npu_data_awsize,
    input  wire [1:0]  s_axi_npu_data_awburst,
    input  wire [31:0] s_axi_npu_data_wdata,
    input  wire [3:0]  s_axi_npu_data_wstrb,
    input  wire        s_axi_npu_data_wvalid,
    input  wire        s_axi_npu_data_wlast,
    output wire        s_axi_npu_data_wready,
    output wire [3:0]  s_axi_npu_data_bid,
    output wire [1:0]  s_axi_npu_data_bresp,
    output wire        s_axi_npu_data_bvalid,
    input  wire        s_axi_npu_data_bready,
    input  wire [31:0] s_axi_npu_data_araddr,
    input  wire        s_axi_npu_data_arvalid,
    output wire        s_axi_npu_data_arready,
    input  wire [3:0]  s_axi_npu_data_arid,
    input  wire [7:0]  s_axi_npu_data_arlen,
    input  wire [2:0]  s_axi_npu_data_arsize,
    input  wire [1:0]  s_axi_npu_data_arburst,
    output wire [31:0] s_axi_npu_data_rdata,
    output wire        s_axi_npu_data_rvalid,
    input  wire        s_axi_npu_data_rready,
    output wire [1:0]  s_axi_npu_data_rresp,
    output wire [3:0]  s_axi_npu_data_rid,
    output wire        s_axi_npu_data_rlast,

    // AXI-Lite masters to external peripherals (slots 4-7)
    output wire [7:0]  m_axil_camera_ctrl_awaddr,
    output wire        m_axil_camera_ctrl_awvalid,
    input  wire        m_axil_camera_ctrl_awready,
    output wire [31:0] m_axil_camera_ctrl_wdata,
    output wire [3:0]  m_axil_camera_ctrl_wstrb,
    output wire        m_axil_camera_ctrl_wvalid,
    input  wire        m_axil_camera_ctrl_wready,
    input  wire [1:0]  m_axil_camera_ctrl_bresp,
    input  wire        m_axil_camera_ctrl_bvalid,
    output wire        m_axil_camera_ctrl_bready,
    output wire [7:0]  m_axil_camera_ctrl_araddr,
    output wire        m_axil_camera_ctrl_arvalid,
    input  wire        m_axil_camera_ctrl_arready,
    input  wire [31:0] m_axil_camera_ctrl_rdata,
    input  wire [1:0]  m_axil_camera_ctrl_rresp,
    input  wire        m_axil_camera_ctrl_rvalid,
    output wire        m_axil_camera_ctrl_rready,

    output wire [7:0]  m_axil_audio_ctrl_awaddr,
    output wire        m_axil_audio_ctrl_awvalid,
    input  wire        m_axil_audio_ctrl_awready,
    output wire [31:0] m_axil_audio_ctrl_wdata,
    output wire [3:0]  m_axil_audio_ctrl_wstrb,
    output wire        m_axil_audio_ctrl_wvalid,
    input  wire        m_axil_audio_ctrl_wready,
    input  wire [1:0]  m_axil_audio_ctrl_bresp,
    input  wire        m_axil_audio_ctrl_bvalid,
    output wire        m_axil_audio_ctrl_bready,
    output wire [7:0]  m_axil_audio_ctrl_araddr,
    output wire        m_axil_audio_ctrl_arvalid,
    input  wire        m_axil_audio_ctrl_arready,
    input  wire [31:0] m_axil_audio_ctrl_rdata,
    input  wire [1:0]  m_axil_audio_ctrl_rresp,
    input  wire        m_axil_audio_ctrl_rvalid,
    output wire        m_axil_audio_ctrl_rready,

    output wire [7:0]  m_axil_i2c_ctrl_awaddr,
    output wire        m_axil_i2c_ctrl_awvalid,
    input  wire        m_axil_i2c_ctrl_awready,
    output wire [31:0] m_axil_i2c_ctrl_wdata,
    output wire [3:0]  m_axil_i2c_ctrl_wstrb,
    output wire        m_axil_i2c_ctrl_wvalid,
    input  wire        m_axil_i2c_ctrl_wready,
    input  wire [1:0]  m_axil_i2c_ctrl_bresp,
    input  wire        m_axil_i2c_ctrl_bvalid,
    output wire        m_axil_i2c_ctrl_bready,
    output wire [7:0]  m_axil_i2c_ctrl_araddr,
    output wire        m_axil_i2c_ctrl_arvalid,
    input  wire        m_axil_i2c_ctrl_arready,
    input  wire [31:0] m_axil_i2c_ctrl_rdata,
    input  wire [1:0]  m_axil_i2c_ctrl_rresp,
    input  wire        m_axil_i2c_ctrl_rvalid,
    output wire        m_axil_i2c_ctrl_rready,

    output wire [7:0]  m_axil_spi_ctrl_awaddr,
    output wire        m_axil_spi_ctrl_awvalid,
    input  wire        m_axil_spi_ctrl_awready,
    output wire [31:0] m_axil_spi_ctrl_wdata,
    output wire [3:0]  m_axil_spi_ctrl_wstrb,
    output wire        m_axil_spi_ctrl_wvalid,
    input  wire        m_axil_spi_ctrl_wready,
    input  wire [1:0]  m_axil_spi_ctrl_bresp,
    input  wire        m_axil_spi_ctrl_bvalid,
    output wire        m_axil_spi_ctrl_bready,
    output wire [7:0]  m_axil_spi_ctrl_araddr,
    output wire        m_axil_spi_ctrl_arvalid,
    input  wire        m_axil_spi_ctrl_arready,
    input  wire [31:0] m_axil_spi_ctrl_rdata,
    input  wire [1:0]  m_axil_spi_ctrl_rresp,
    input  wire        m_axil_spi_ctrl_rvalid,
    output wire        m_axil_spi_ctrl_rready,

    // AXI-Lite master to NPU regfile (slot 8, 0x2000_0800)
    output wire [7:0]  m_axil_npu_ctrl_awaddr,
    output wire        m_axil_npu_ctrl_awvalid,
    input  wire        m_axil_npu_ctrl_awready,
    output wire [31:0] m_axil_npu_ctrl_wdata,
    output wire [3:0]  m_axil_npu_ctrl_wstrb,
    output wire        m_axil_npu_ctrl_wvalid,
    input  wire        m_axil_npu_ctrl_wready,
    input  wire [1:0]  m_axil_npu_ctrl_bresp,
    input  wire        m_axil_npu_ctrl_bvalid,
    output wire        m_axil_npu_ctrl_bready,
    output wire [7:0]  m_axil_npu_ctrl_araddr,
    output wire        m_axil_npu_ctrl_arvalid,
    input  wire        m_axil_npu_ctrl_arready,
    input  wire [31:0] m_axil_npu_ctrl_rdata,
    input  wire [1:0]  m_axil_npu_ctrl_rresp,
    input  wire        m_axil_npu_ctrl_rvalid,
    output wire        m_axil_npu_ctrl_rready,

    // UART
    output wire        uart_tx_o,
    input  wire        uart_rx_i,

    // GPIO
    input  wire [7:0]  gpio_i,
    output wire [7:0]  gpio_o,
    output wire [7:0]  gpio_oe,

    // External interrupt sources
    input  wire        irq_npu_done_i,
    input  wire        irq_dma_done_i,
    input  wire        irq_camera_ready_i,
    input  wire        irq_audio_ready_i,
    input  wire        irq_i2c_done_i
);

    // ================================================================
    // 1. Reset synchronizer
    // ================================================================
    wire rst_n;

    rst_sync u_rst_sync (
        .clk          (clk_i),
        .rst_n_async  (rst_ni),
        .rst_n_sync   (rst_n)
    );

    // ================================================================
    // 2. Reset sequencing: peripherals first, CPU 8 cycles later
    // ================================================================
    reg [3:0] rst_seq_cnt;
    reg       periph_rst_n;
    reg       cpu_rst_n;

    always @(posedge clk_i) begin
        if (!rst_n) begin
            rst_seq_cnt <= 4'd0;
            periph_rst_n <= 1'b0;
            cpu_rst_n    <= 1'b0;
        end else begin
            if (rst_seq_cnt < 4'd10) begin
                rst_seq_cnt <= rst_seq_cnt + 4'd1;
            end
            // Release peripheral reset after 2 cycles
            if (rst_seq_cnt >= 4'd2)
                periph_rst_n <= 1'b1;
            // Release CPU reset after 10 cycles (8 after peripherals)
            if (rst_seq_cnt >= 4'd10)
                cpu_rst_n <= 1'b1;
        end
    end

    // ================================================================
    // 3. Ibex core wrapper
    // ================================================================
    wire        instr_req;
    wire        instr_gnt;
    wire        instr_rvalid;
    wire [31:0] instr_addr;
    wire [31:0] instr_rdata;
    wire        instr_err;

    wire        data_req;
    wire        data_gnt;
    wire        data_rvalid;
    wire        data_we;
    wire [3:0]  data_be;
    wire [31:0] data_addr;
    wire [31:0] data_wdata;
    wire [31:0] data_rdata;
    wire        data_err;

    wire        irq_timer;
    wire        irq_external;

    ibex_core_wrapper u_ibex (
        .clk            (clk_i),
        .rst_n          (cpu_rst_n),
        .instr_req_o    (instr_req),
        .instr_gnt_i    (instr_gnt),
        .instr_rvalid_i (instr_rvalid),
        .instr_addr_o   (instr_addr),
        .instr_rdata_i  (instr_rdata),
        .instr_err_i    (instr_err),
        .data_req_o     (data_req),
        .data_gnt_i     (data_gnt),
        .data_rvalid_i  (data_rvalid),
        .data_we_o      (data_we),
        .data_be_o      (data_be),
        .data_addr_o    (data_addr),
        .data_wdata_o   (data_wdata),
        .data_rdata_i   (data_rdata),
        .data_err_i     (data_err),
        .irq_timer_i    (irq_timer),
        .irq_external_i (irq_external),
        .irq_software_i (1'b0),
        .boot_addr_i    (32'h0000_0000)
    );

    // ================================================================
    // 4. iBus AXI adapter (M0 — read-only)
    // ================================================================
    wire        m0_arvalid, m0_arready;
    wire [31:0] m0_araddr;
    wire [7:0]  m0_arlen;
    wire [2:0]  m0_arsize;
    wire [1:0]  m0_arburst;
    wire [3:0]  m0_arid;
    wire        m0_rvalid, m0_rready;
    wire [31:0] m0_rdata;
    wire [1:0]  m0_rresp;
    wire [3:0]  m0_rid;
    wire        m0_rlast;

    ibus_axi_adapter u_ibus_adapter (
        .clk             (clk_i),
        .rst_n           (cpu_rst_n),
        .instr_req_i     (instr_req),
        .instr_gnt_o     (instr_gnt),
        .instr_rvalid_o  (instr_rvalid),
        .instr_addr_i    (instr_addr),
        .instr_rdata_o   (instr_rdata),
        .instr_err_o     (instr_err),
        .m_axi_arvalid   (m0_arvalid),
        .m_axi_arready   (m0_arready),
        .m_axi_araddr    (m0_araddr),
        .m_axi_arlen     (m0_arlen),
        .m_axi_arsize    (m0_arsize),
        .m_axi_arburst   (m0_arburst),
        .m_axi_arid      (m0_arid),
        .m_axi_rvalid    (m0_rvalid),
        .m_axi_rready    (m0_rready),
        .m_axi_rdata     (m0_rdata),
        .m_axi_rresp     (m0_rresp),
        .m_axi_rid       (m0_rid),
        .m_axi_rlast     (m0_rlast)
    );

    // ================================================================
    // 5. dBus AXI adapter (M1 — R/W)
    // ================================================================
    wire        m1_awvalid, m1_awready;
    wire [31:0] m1_awaddr;
    wire [7:0]  m1_awlen;
    wire [2:0]  m1_awsize;
    wire [1:0]  m1_awburst;
    wire [3:0]  m1_awid;
    wire        m1_wvalid, m1_wready;
    wire [31:0] m1_wdata;
    wire [3:0]  m1_wstrb;
    wire        m1_wlast;
    wire        m1_bvalid, m1_bready;
    wire [1:0]  m1_bresp;
    wire [3:0]  m1_bid;
    wire        m1_arvalid, m1_arready;
    wire [31:0] m1_araddr;
    wire [7:0]  m1_arlen;
    wire [2:0]  m1_arsize;
    wire [1:0]  m1_arburst;
    wire [3:0]  m1_arid;
    wire        m1_rvalid, m1_rready;
    wire [31:0] m1_rdata_w;
    wire [1:0]  m1_rresp;
    wire [3:0]  m1_rid;
    wire        m1_rlast;

    dbus_axi_adapter u_dbus_adapter (
        .clk             (clk_i),
        .rst_n           (cpu_rst_n),
        .data_req_i      (data_req),
        .data_gnt_o      (data_gnt),
        .data_rvalid_o   (data_rvalid),
        .data_we_i       (data_we),
        .data_be_i       (data_be),
        .data_addr_i     (data_addr),
        .data_wdata_i    (data_wdata),
        .data_rdata_o    (data_rdata),
        .data_err_o      (data_err),
        .m_axi_awvalid   (m1_awvalid),
        .m_axi_awready   (m1_awready),
        .m_axi_awaddr    (m1_awaddr),
        .m_axi_awlen     (m1_awlen),
        .m_axi_awsize    (m1_awsize),
        .m_axi_awburst   (m1_awburst),
        .m_axi_awid      (m1_awid),
        .m_axi_wvalid    (m1_wvalid),
        .m_axi_wready    (m1_wready),
        .m_axi_wdata     (m1_wdata),
        .m_axi_wstrb     (m1_wstrb),
        .m_axi_wlast     (m1_wlast),
        .m_axi_bvalid    (m1_bvalid),
        .m_axi_bready    (m1_bready),
        .m_axi_bresp     (m1_bresp),
        .m_axi_bid       (m1_bid),
        .m_axi_arvalid   (m1_arvalid),
        .m_axi_arready   (m1_arready),
        .m_axi_araddr    (m1_araddr),
        .m_axi_arlen     (m1_arlen),
        .m_axi_arsize    (m1_arsize),
        .m_axi_arburst   (m1_arburst),
        .m_axi_arid      (m1_arid),
        .m_axi_rvalid    (m1_rvalid),
        .m_axi_rready    (m1_rready),
        .m_axi_rdata     (m1_rdata_w),
        .m_axi_rresp     (m1_rresp),
        .m_axi_rid       (m1_rid),
        .m_axi_rlast     (m1_rlast)
    );

    // ================================================================
    // 6. AXI Interconnect: 3M x 4S
    // ================================================================
    // Internal wires: S0 (Boot ROM), S1 (SRAM), S2 (Bridge), S3 (DDR)
    // S0 wires
    wire [31:0] s0_awaddr;  wire        s0_awvalid, s0_awready;
    wire [3:0]  s0_awid;    wire [7:0]  s0_awlen;
    wire [2:0]  s0_awsize;  wire [1:0]  s0_awburst;
    wire [31:0] s0_wdata;   wire [3:0]  s0_wstrb;
    wire        s0_wvalid, s0_wready, s0_wlast;
    wire [3:0]  s0_bid;     wire [1:0]  s0_bresp;
    wire        s0_bvalid, s0_bready;
    wire [31:0] s0_araddr;  wire        s0_arvalid, s0_arready;
    wire [3:0]  s0_arid;    wire [7:0]  s0_arlen;
    wire [2:0]  s0_arsize;  wire [1:0]  s0_arburst;
    wire [31:0] s0_rdata;   wire [1:0]  s0_rresp;
    wire        s0_rvalid, s0_rready;
    wire [3:0]  s0_rid;     wire        s0_rlast;

    // S1 wires
    wire [31:0] s1_awaddr;  wire        s1_awvalid, s1_awready;
    wire [3:0]  s1_awid;    wire [7:0]  s1_awlen;
    wire [2:0]  s1_awsize;  wire [1:0]  s1_awburst;
    wire [31:0] s1_wdata;   wire [3:0]  s1_wstrb;
    wire        s1_wvalid, s1_wready, s1_wlast;
    wire [3:0]  s1_bid;     wire [1:0]  s1_bresp;
    wire        s1_bvalid, s1_bready;
    wire [31:0] s1_araddr;  wire        s1_arvalid, s1_arready;
    wire [3:0]  s1_arid;    wire [7:0]  s1_arlen;
    wire [2:0]  s1_arsize;  wire [1:0]  s1_arburst;
    wire [31:0] s1_rdata;   wire [1:0]  s1_rresp;
    wire        s1_rvalid, s1_rready;
    wire [3:0]  s1_rid;     wire        s1_rlast;

    // S2 wires (to bridge)
    wire [31:0] s2_awaddr;  wire        s2_awvalid, s2_awready;
    wire [3:0]  s2_awid;    wire [7:0]  s2_awlen;
    wire [2:0]  s2_awsize;  wire [1:0]  s2_awburst;
    wire [31:0] s2_wdata;   wire [3:0]  s2_wstrb;
    wire        s2_wvalid, s2_wready, s2_wlast;
    wire [3:0]  s2_bid;     wire [1:0]  s2_bresp;
    wire        s2_bvalid, s2_bready;
    wire [31:0] s2_araddr;  wire        s2_arvalid, s2_arready;
    wire [3:0]  s2_arid;    wire [7:0]  s2_arlen;
    wire [2:0]  s2_arsize;  wire [1:0]  s2_arburst;
    wire [31:0] s2_rdata;   wire [1:0]  s2_rresp;
    wire        s2_rvalid, s2_rready;
    wire [3:0]  s2_rid;     wire        s2_rlast;

    axi_interconnect #(
        .DATA_WIDTH  (32),
        .ADDR_WIDTH  (32),
        .ID_WIDTH    (4),
        .NUM_MASTERS (3),
        .NUM_SLAVES  (4)
    ) u_axi_xbar (
        .clk   (clk_i),
        .rst_n (periph_rst_n),

        // M0 — iBus (read-only, tie off write channels)
        .s_axi_0_araddr   (m0_araddr),
        .s_axi_0_arvalid  (m0_arvalid),
        .s_axi_0_arready  (m0_arready),
        .s_axi_0_arid     (m0_arid),
        .s_axi_0_arlen    (m0_arlen),
        .s_axi_0_arsize   (m0_arsize),
        .s_axi_0_arburst  (m0_arburst),
        .s_axi_0_rdata    (m0_rdata),
        .s_axi_0_rvalid   (m0_rvalid),
        .s_axi_0_rready   (m0_rready),
        .s_axi_0_rresp    (m0_rresp),
        .s_axi_0_rid      (m0_rid),
        .s_axi_0_rlast    (m0_rlast),

        // M1 — dBus
        .s_axi_1_awaddr   (m1_awaddr),
        .s_axi_1_awvalid  (m1_awvalid),
        .s_axi_1_awready  (m1_awready),
        .s_axi_1_awid     (m1_awid),
        .s_axi_1_awlen    (m1_awlen),
        .s_axi_1_awsize   (m1_awsize),
        .s_axi_1_awburst  (m1_awburst),
        .s_axi_1_wdata    (m1_wdata),
        .s_axi_1_wstrb    (m1_wstrb),
        .s_axi_1_wvalid   (m1_wvalid),
        .s_axi_1_wlast    (m1_wlast),
        .s_axi_1_wready   (m1_wready),
        .s_axi_1_bid      (m1_bid),
        .s_axi_1_bresp    (m1_bresp),
        .s_axi_1_bvalid   (m1_bvalid),
        .s_axi_1_bready   (m1_bready),
        .s_axi_1_araddr   (m1_araddr),
        .s_axi_1_arvalid  (m1_arvalid),
        .s_axi_1_arready  (m1_arready),
        .s_axi_1_arid     (m1_arid),
        .s_axi_1_arlen    (m1_arlen),
        .s_axi_1_arsize   (m1_arsize),
        .s_axi_1_arburst  (m1_arburst),
        .s_axi_1_rdata    (m1_rdata_w),
        .s_axi_1_rvalid   (m1_rvalid),
        .s_axi_1_rready   (m1_rready),
        .s_axi_1_rresp    (m1_rresp),
        .s_axi_1_rid      (m1_rid),
        .s_axi_1_rlast    (m1_rlast),

        // M2 — NPU DMA (from external port)
        .s_axi_2_awaddr   (s_axi_npu_data_awaddr),
        .s_axi_2_awvalid  (s_axi_npu_data_awvalid),
        .s_axi_2_awready  (s_axi_npu_data_awready),
        .s_axi_2_awid     (s_axi_npu_data_awid),
        .s_axi_2_awlen    (s_axi_npu_data_awlen),
        .s_axi_2_awsize   (s_axi_npu_data_awsize),
        .s_axi_2_awburst  (s_axi_npu_data_awburst),
        .s_axi_2_wdata    (s_axi_npu_data_wdata),
        .s_axi_2_wstrb    (s_axi_npu_data_wstrb),
        .s_axi_2_wvalid   (s_axi_npu_data_wvalid),
        .s_axi_2_wlast    (s_axi_npu_data_wlast),
        .s_axi_2_wready   (s_axi_npu_data_wready),
        .s_axi_2_bid      (s_axi_npu_data_bid),
        .s_axi_2_bresp    (s_axi_npu_data_bresp),
        .s_axi_2_bvalid   (s_axi_npu_data_bvalid),
        .s_axi_2_bready   (s_axi_npu_data_bready),
        .s_axi_2_araddr   (s_axi_npu_data_araddr),
        .s_axi_2_arvalid  (s_axi_npu_data_arvalid),
        .s_axi_2_arready  (s_axi_npu_data_arready),
        .s_axi_2_arid     (s_axi_npu_data_arid),
        .s_axi_2_arlen    (s_axi_npu_data_arlen),
        .s_axi_2_arsize   (s_axi_npu_data_arsize),
        .s_axi_2_arburst  (s_axi_npu_data_arburst),
        .s_axi_2_rdata    (s_axi_npu_data_rdata),
        .s_axi_2_rvalid   (s_axi_npu_data_rvalid),
        .s_axi_2_rready   (s_axi_npu_data_rready),
        .s_axi_2_rresp    (s_axi_npu_data_rresp),
        .s_axi_2_rid      (s_axi_npu_data_rid),
        .s_axi_2_rlast    (s_axi_npu_data_rlast),

        // S0 — Boot ROM
        .m_axi_0_awaddr   (s0_awaddr),  .m_axi_0_awvalid  (s0_awvalid),
        .m_axi_0_awready  (s0_awready), .m_axi_0_awid     (s0_awid),
        .m_axi_0_awlen    (s0_awlen),   .m_axi_0_awsize   (s0_awsize),
        .m_axi_0_awburst  (s0_awburst),
        .m_axi_0_wdata    (s0_wdata),   .m_axi_0_wstrb    (s0_wstrb),
        .m_axi_0_wvalid   (s0_wvalid),  .m_axi_0_wlast    (s0_wlast),
        .m_axi_0_wready   (s0_wready),
        .m_axi_0_bid      (s0_bid),     .m_axi_0_bresp    (s0_bresp),
        .m_axi_0_bvalid   (s0_bvalid),  .m_axi_0_bready   (s0_bready),
        .m_axi_0_araddr   (s0_araddr),  .m_axi_0_arvalid  (s0_arvalid),
        .m_axi_0_arready  (s0_arready), .m_axi_0_arid     (s0_arid),
        .m_axi_0_arlen    (s0_arlen),   .m_axi_0_arsize   (s0_arsize),
        .m_axi_0_arburst  (s0_arburst),
        .m_axi_0_rdata    (s0_rdata),   .m_axi_0_rvalid   (s0_rvalid),
        .m_axi_0_rready   (s0_rready),  .m_axi_0_rresp    (s0_rresp),
        .m_axi_0_rid      (s0_rid),     .m_axi_0_rlast    (s0_rlast),

        // S1 — SRAM
        .m_axi_1_awaddr   (s1_awaddr),  .m_axi_1_awvalid  (s1_awvalid),
        .m_axi_1_awready  (s1_awready), .m_axi_1_awid     (s1_awid),
        .m_axi_1_awlen    (s1_awlen),   .m_axi_1_awsize   (s1_awsize),
        .m_axi_1_awburst  (s1_awburst),
        .m_axi_1_wdata    (s1_wdata),   .m_axi_1_wstrb    (s1_wstrb),
        .m_axi_1_wvalid   (s1_wvalid),  .m_axi_1_wlast    (s1_wlast),
        .m_axi_1_wready   (s1_wready),
        .m_axi_1_bid      (s1_bid),     .m_axi_1_bresp    (s1_bresp),
        .m_axi_1_bvalid   (s1_bvalid),  .m_axi_1_bready   (s1_bready),
        .m_axi_1_araddr   (s1_araddr),  .m_axi_1_arvalid  (s1_arvalid),
        .m_axi_1_arready  (s1_arready), .m_axi_1_arid     (s1_arid),
        .m_axi_1_arlen    (s1_arlen),   .m_axi_1_arsize   (s1_arsize),
        .m_axi_1_arburst  (s1_arburst),
        .m_axi_1_rdata    (s1_rdata),   .m_axi_1_rvalid   (s1_rvalid),
        .m_axi_1_rready   (s1_rready),  .m_axi_1_rresp    (s1_rresp),
        .m_axi_1_rid      (s1_rid),     .m_axi_1_rlast    (s1_rlast),

        // S2 — Peripheral bridge
        .m_axi_2_awaddr   (s2_awaddr),  .m_axi_2_awvalid  (s2_awvalid),
        .m_axi_2_awready  (s2_awready), .m_axi_2_awid     (s2_awid),
        .m_axi_2_awlen    (s2_awlen),   .m_axi_2_awsize   (s2_awsize),
        .m_axi_2_awburst  (s2_awburst),
        .m_axi_2_wdata    (s2_wdata),   .m_axi_2_wstrb    (s2_wstrb),
        .m_axi_2_wvalid   (s2_wvalid),  .m_axi_2_wlast    (s2_wlast),
        .m_axi_2_wready   (s2_wready),
        .m_axi_2_bid      (s2_bid),     .m_axi_2_bresp    (s2_bresp),
        .m_axi_2_bvalid   (s2_bvalid),  .m_axi_2_bready   (s2_bready),
        .m_axi_2_araddr   (s2_araddr),  .m_axi_2_arvalid  (s2_arvalid),
        .m_axi_2_arready  (s2_arready), .m_axi_2_arid     (s2_arid),
        .m_axi_2_arlen    (s2_arlen),   .m_axi_2_arsize   (s2_arsize),
        .m_axi_2_arburst  (s2_arburst),
        .m_axi_2_rdata    (s2_rdata),   .m_axi_2_rvalid   (s2_rvalid),
        .m_axi_2_rready   (s2_rready),  .m_axi_2_rresp    (s2_rresp),
        .m_axi_2_rid      (s2_rid),     .m_axi_2_rlast    (s2_rlast),

        // S3 — DDR (routed to top-level)
        .m_axi_3_awaddr   (m_axi_ddr_awaddr),  .m_axi_3_awvalid  (m_axi_ddr_awvalid),
        .m_axi_3_awready  (m_axi_ddr_awready),  .m_axi_3_awid     (m_axi_ddr_awid),
        .m_axi_3_awlen    (m_axi_ddr_awlen),    .m_axi_3_awsize   (m_axi_ddr_awsize),
        .m_axi_3_awburst  (m_axi_ddr_awburst),
        .m_axi_3_wdata    (m_axi_ddr_wdata),    .m_axi_3_wstrb    (m_axi_ddr_wstrb),
        .m_axi_3_wvalid   (m_axi_ddr_wvalid),   .m_axi_3_wlast    (m_axi_ddr_wlast),
        .m_axi_3_wready   (m_axi_ddr_wready),
        .m_axi_3_bid      (m_axi_ddr_bid),      .m_axi_3_bresp    (m_axi_ddr_bresp),
        .m_axi_3_bvalid   (m_axi_ddr_bvalid),   .m_axi_3_bready   (m_axi_ddr_bready),
        .m_axi_3_araddr   (m_axi_ddr_araddr),   .m_axi_3_arvalid  (m_axi_ddr_arvalid),
        .m_axi_3_arready  (m_axi_ddr_arready),  .m_axi_3_arid     (m_axi_ddr_arid),
        .m_axi_3_arlen    (m_axi_ddr_arlen),    .m_axi_3_arsize   (m_axi_ddr_arsize),
        .m_axi_3_arburst  (m_axi_ddr_arburst),
        .m_axi_3_rdata    (m_axi_ddr_rdata),    .m_axi_3_rvalid   (m_axi_ddr_rvalid),
        .m_axi_3_rready   (m_axi_ddr_rready),   .m_axi_3_rresp    (m_axi_ddr_rresp),
        .m_axi_3_rid      (m_axi_ddr_rid),      .m_axi_3_rlast    (m_axi_ddr_rlast)
    );

    // ================================================================
    // 7. Boot ROM (S0)
    // ================================================================
    boot_rom #(
        .ADDR_WIDTH (12),
        .DATA_WIDTH (32),
        .DEPTH      (1024),
        .INIT_FILE  ("boot_rom.hex")
    ) u_boot_rom (
        .clk            (clk_i),
        .rst_n          (periph_rst_n),
        .s_axi_araddr   (s0_araddr),
        .s_axi_arvalid  (s0_arvalid),
        .s_axi_arready  (s0_arready),
        .s_axi_arid     (s0_arid),
        .s_axi_arlen    (s0_arlen),
        .s_axi_arsize   (s0_arsize),
        .s_axi_arburst  (s0_arburst),
        .s_axi_rdata    (s0_rdata),
        .s_axi_rvalid   (s0_rvalid),
        .s_axi_rready   (s0_rready),
        .s_axi_rresp    (s0_rresp),
        .s_axi_rid      (s0_rid),
        .s_axi_rlast    (s0_rlast),
        .s_axi_awaddr   (s0_awaddr),
        .s_axi_awvalid  (s0_awvalid),
        .s_axi_awready  (s0_awready),
        .s_axi_awid     (s0_awid),
        .s_axi_awlen    (s0_awlen),
        .s_axi_awsize   (s0_awsize),
        .s_axi_awburst  (s0_awburst),
        .s_axi_wdata    (s0_wdata),
        .s_axi_wstrb    (s0_wstrb),
        .s_axi_wvalid   (s0_wvalid),
        .s_axi_wlast    (s0_wlast),
        .s_axi_wready   (s0_wready),
        .s_axi_bid      (s0_bid),
        .s_axi_bresp    (s0_bresp),
        .s_axi_bvalid   (s0_bvalid),
        .s_axi_bready   (s0_bready)
    );

    // ================================================================
    // 8. On-chip SRAM (S1) — Port A from iBus, Port B from dBus
    // ================================================================
    onchip_sram #(
        .NUM_BANKS       (4),
        .BANK_ADDR_WIDTH (15),
        .DATA_WIDTH      (32)
    ) u_sram (
        .clk   (clk_i),
        .rst_n (periph_rst_n),
        // Port A — iBus read-only
        .s_axi_a_araddr   (s1_araddr),
        .s_axi_a_arvalid  (s1_arvalid),
        .s_axi_a_arready  (s1_arready),
        .s_axi_a_arid     (s1_arid),
        .s_axi_a_arlen    (s1_arlen),
        .s_axi_a_arsize   (s1_arsize),
        .s_axi_a_arburst  (s1_arburst),
        .s_axi_a_rdata    (s1_rdata),
        .s_axi_a_rvalid   (s1_rvalid),
        .s_axi_a_rready   (s1_rready),
        .s_axi_a_rresp    (s1_rresp),
        .s_axi_a_rid      (s1_rid),
        .s_axi_a_rlast    (s1_rlast),
        // Port B — dBus read/write
        .s_axi_b_awaddr   (s1_awaddr),
        .s_axi_b_awvalid  (s1_awvalid),
        .s_axi_b_awready  (s1_awready),
        .s_axi_b_awid     (s1_awid),
        .s_axi_b_awlen    (s1_awlen),
        .s_axi_b_awsize   (s1_awsize),
        .s_axi_b_awburst  (s1_awburst),
        .s_axi_b_wdata    (s1_wdata),
        .s_axi_b_wstrb    (s1_wstrb),
        .s_axi_b_wvalid   (s1_wvalid),
        .s_axi_b_wlast    (s1_wlast),
        .s_axi_b_wready   (s1_wready),
        .s_axi_b_bid      (s1_bid),
        .s_axi_b_bresp    (s1_bresp),
        .s_axi_b_bvalid   (s1_bvalid),
        .s_axi_b_bready   (s1_bready),
        .s_axi_b_araddr   (s1_araddr),
        .s_axi_b_arvalid  (1'b0),
        .s_axi_b_arready  (),
        .s_axi_b_arid     (4'd0),
        .s_axi_b_arlen    (8'd0),
        .s_axi_b_arsize   (3'd0),
        .s_axi_b_arburst  (2'd0),
        .s_axi_b_rdata    (),
        .s_axi_b_rvalid   (),
        .s_axi_b_rready   (1'b0),
        .s_axi_b_rresp    (),
        .s_axi_b_rid      (),
        .s_axi_b_rlast    ()
    );

    // ================================================================
    // 9. AXI-to-AXI-Lite Bridge (S2)
    // ================================================================
    wire [31:0] bridge_axil_awaddr, bridge_axil_araddr;
    wire        bridge_axil_awvalid, bridge_axil_awready;
    wire [31:0] bridge_axil_wdata;
    wire [3:0]  bridge_axil_wstrb;
    wire        bridge_axil_wvalid, bridge_axil_wready;
    wire [1:0]  bridge_axil_bresp;
    wire        bridge_axil_bvalid, bridge_axil_bready;
    wire        bridge_axil_arvalid, bridge_axil_arready;
    wire [31:0] bridge_axil_rdata;
    wire [1:0]  bridge_axil_rresp;
    wire        bridge_axil_rvalid, bridge_axil_rready;

    riscv_axi_to_axilite_bridge #(
        .ADDR_WIDTH (32),
        .DATA_WIDTH (32),
        .ID_WIDTH   (4)
    ) u_bridge (
        .clk              (clk_i),
        .rst_n            (periph_rst_n),
        // AXI4 slave (from interconnect S2)
        .s_axi_awaddr     (s2_awaddr),
        .s_axi_awvalid    (s2_awvalid),
        .s_axi_awready    (s2_awready),
        .s_axi_awid       (s2_awid),
        .s_axi_awlen      (s2_awlen),
        .s_axi_awsize     (s2_awsize),
        .s_axi_awburst    (s2_awburst),
        .s_axi_wdata      (s2_wdata),
        .s_axi_wstrb      (s2_wstrb),
        .s_axi_wvalid     (s2_wvalid),
        .s_axi_wlast      (s2_wlast),
        .s_axi_wready     (s2_wready),
        .s_axi_bid        (s2_bid),
        .s_axi_bresp      (s2_bresp),
        .s_axi_bvalid     (s2_bvalid),
        .s_axi_bready     (s2_bready),
        .s_axi_araddr     (s2_araddr),
        .s_axi_arvalid    (s2_arvalid),
        .s_axi_arready    (s2_arready),
        .s_axi_arid       (s2_arid),
        .s_axi_arlen      (s2_arlen),
        .s_axi_arsize     (s2_arsize),
        .s_axi_arburst    (s2_arburst),
        .s_axi_rdata      (s2_rdata),
        .s_axi_rresp      (s2_rresp),
        .s_axi_rvalid     (s2_rvalid),
        .s_axi_rid        (s2_rid),
        .s_axi_rlast      (s2_rlast),
        .s_axi_rready     (s2_rready),
        // AXI-Lite master
        .m_axil_awaddr    (bridge_axil_awaddr),
        .m_axil_awvalid   (bridge_axil_awvalid),
        .m_axil_awready   (bridge_axil_awready),
        .m_axil_wdata     (bridge_axil_wdata),
        .m_axil_wstrb     (bridge_axil_wstrb),
        .m_axil_wvalid    (bridge_axil_wvalid),
        .m_axil_wready    (bridge_axil_wready),
        .m_axil_bresp     (bridge_axil_bresp),
        .m_axil_bvalid    (bridge_axil_bvalid),
        .m_axil_bready    (bridge_axil_bready),
        .m_axil_araddr    (bridge_axil_araddr),
        .m_axil_arvalid   (bridge_axil_arvalid),
        .m_axil_arready   (bridge_axil_arready),
        .m_axil_rdata     (bridge_axil_rdata),
        .m_axil_rresp     (bridge_axil_rresp),
        .m_axil_rvalid    (bridge_axil_rvalid),
        .m_axil_rready    (bridge_axil_rready)
    );

    // ================================================================
    // 10. AXI-Lite Interconnect: 1M x 8S
    // ================================================================
    // Internal peripheral AXI-Lite wires for slots 0-3
    wire [7:0]  p0_awaddr, p0_araddr, p1_awaddr, p1_araddr;
    wire [7:0]  p2_awaddr, p2_araddr, p3_awaddr, p3_araddr;
    wire        p0_awvalid, p0_awready, p0_wvalid, p0_wready;
    wire [31:0] p0_wdata; wire [3:0] p0_wstrb;
    wire [1:0]  p0_bresp; wire p0_bvalid, p0_bready;
    wire        p0_arvalid, p0_arready;
    wire [31:0] p0_rdata; wire [1:0] p0_rresp; wire p0_rvalid, p0_rready;

    wire        p1_awvalid, p1_awready, p1_wvalid, p1_wready;
    wire [31:0] p1_wdata; wire [3:0] p1_wstrb;
    wire [1:0]  p1_bresp; wire p1_bvalid, p1_bready;
    wire        p1_arvalid, p1_arready;
    wire [31:0] p1_rdata; wire [1:0] p1_rresp; wire p1_rvalid, p1_rready;

    wire        p2_awvalid, p2_awready, p2_wvalid, p2_wready;
    wire [31:0] p2_wdata; wire [3:0] p2_wstrb;
    wire [1:0]  p2_bresp; wire p2_bvalid, p2_bready;
    wire        p2_arvalid, p2_arready;
    wire [31:0] p2_rdata; wire [1:0] p2_rresp; wire p2_rvalid, p2_rready;

    wire        p3_awvalid, p3_awready, p3_wvalid, p3_wready;
    wire [31:0] p3_wdata; wire [3:0] p3_wstrb;
    wire [1:0]  p3_bresp; wire p3_bvalid, p3_bready;
    wire        p3_arvalid, p3_arready;
    wire [31:0] p3_rdata; wire [1:0] p3_rresp; wire p3_rvalid, p3_rready;

    axilite_interconnect #(
        .ADDR_WIDTH (32),
        .DATA_WIDTH (32),
        .NUM_SLAVES (9)
    ) u_axil_xbar (
        .clk   (clk_i),
        .rst_n (periph_rst_n),

        // Slave port (from bridge)
        .s_axil_awaddr  (bridge_axil_awaddr),
        .s_axil_awvalid (bridge_axil_awvalid),
        .s_axil_awready (bridge_axil_awready),
        .s_axil_wdata   (bridge_axil_wdata),
        .s_axil_wstrb   (bridge_axil_wstrb),
        .s_axil_wvalid  (bridge_axil_wvalid),
        .s_axil_wready  (bridge_axil_wready),
        .s_axil_bresp   (bridge_axil_bresp),
        .s_axil_bvalid  (bridge_axil_bvalid),
        .s_axil_bready  (bridge_axil_bready),
        .s_axil_araddr  (bridge_axil_araddr),
        .s_axil_arvalid (bridge_axil_arvalid),
        .s_axil_arready (bridge_axil_arready),
        .s_axil_rdata   (bridge_axil_rdata),
        .s_axil_rresp   (bridge_axil_rresp),
        .s_axil_rvalid  (bridge_axil_rvalid),
        .s_axil_rready  (bridge_axil_rready),

        // Slot 0: UART
        .m_axil_0_awaddr  (p0_awaddr),  .m_axil_0_awvalid (p0_awvalid),
        .m_axil_0_awready (p0_awready),
        .m_axil_0_wdata   (p0_wdata),   .m_axil_0_wstrb   (p0_wstrb),
        .m_axil_0_wvalid  (p0_wvalid),  .m_axil_0_wready  (p0_wready),
        .m_axil_0_bresp   (p0_bresp),   .m_axil_0_bvalid  (p0_bvalid),
        .m_axil_0_bready  (p0_bready),
        .m_axil_0_araddr  (p0_araddr),  .m_axil_0_arvalid (p0_arvalid),
        .m_axil_0_arready (p0_arready),
        .m_axil_0_rdata   (p0_rdata),   .m_axil_0_rresp   (p0_rresp),
        .m_axil_0_rvalid  (p0_rvalid),  .m_axil_0_rready  (p0_rready),

        // Slot 1: Timer
        .m_axil_1_awaddr  (p1_awaddr),  .m_axil_1_awvalid (p1_awvalid),
        .m_axil_1_awready (p1_awready),
        .m_axil_1_wdata   (p1_wdata),   .m_axil_1_wstrb   (p1_wstrb),
        .m_axil_1_wvalid  (p1_wvalid),  .m_axil_1_wready  (p1_wready),
        .m_axil_1_bresp   (p1_bresp),   .m_axil_1_bvalid  (p1_bvalid),
        .m_axil_1_bready  (p1_bready),
        .m_axil_1_araddr  (p1_araddr),  .m_axil_1_arvalid (p1_arvalid),
        .m_axil_1_arready (p1_arready),
        .m_axil_1_rdata   (p1_rdata),   .m_axil_1_rresp   (p1_rresp),
        .m_axil_1_rvalid  (p1_rvalid),  .m_axil_1_rready  (p1_rready),

        // Slot 2: IRQ Controller
        .m_axil_2_awaddr  (p2_awaddr),  .m_axil_2_awvalid (p2_awvalid),
        .m_axil_2_awready (p2_awready),
        .m_axil_2_wdata   (p2_wdata),   .m_axil_2_wstrb   (p2_wstrb),
        .m_axil_2_wvalid  (p2_wvalid),  .m_axil_2_wready  (p2_wready),
        .m_axil_2_bresp   (p2_bresp),   .m_axil_2_bvalid  (p2_bvalid),
        .m_axil_2_bready  (p2_bready),
        .m_axil_2_araddr  (p2_araddr),  .m_axil_2_arvalid (p2_arvalid),
        .m_axil_2_arready (p2_arready),
        .m_axil_2_rdata   (p2_rdata),   .m_axil_2_rresp   (p2_rresp),
        .m_axil_2_rvalid  (p2_rvalid),  .m_axil_2_rready  (p2_rready),

        // Slot 3: GPIO
        .m_axil_3_awaddr  (p3_awaddr),  .m_axil_3_awvalid (p3_awvalid),
        .m_axil_3_awready (p3_awready),
        .m_axil_3_wdata   (p3_wdata),   .m_axil_3_wstrb   (p3_wstrb),
        .m_axil_3_wvalid  (p3_wvalid),  .m_axil_3_wready  (p3_wready),
        .m_axil_3_bresp   (p3_bresp),   .m_axil_3_bvalid  (p3_bvalid),
        .m_axil_3_bready  (p3_bready),
        .m_axil_3_araddr  (p3_araddr),  .m_axil_3_arvalid (p3_arvalid),
        .m_axil_3_arready (p3_arready),
        .m_axil_3_rdata   (p3_rdata),   .m_axil_3_rresp   (p3_rresp),
        .m_axil_3_rvalid  (p3_rvalid),  .m_axil_3_rready  (p3_rready),

        // Slots 4-7: routed to top-level
        .m_axil_4_awaddr  (m_axil_camera_ctrl_awaddr),
        .m_axil_4_awvalid (m_axil_camera_ctrl_awvalid),
        .m_axil_4_awready (m_axil_camera_ctrl_awready),
        .m_axil_4_wdata   (m_axil_camera_ctrl_wdata),
        .m_axil_4_wstrb   (m_axil_camera_ctrl_wstrb),
        .m_axil_4_wvalid  (m_axil_camera_ctrl_wvalid),
        .m_axil_4_wready  (m_axil_camera_ctrl_wready),
        .m_axil_4_bresp   (m_axil_camera_ctrl_bresp),
        .m_axil_4_bvalid  (m_axil_camera_ctrl_bvalid),
        .m_axil_4_bready  (m_axil_camera_ctrl_bready),
        .m_axil_4_araddr  (m_axil_camera_ctrl_araddr),
        .m_axil_4_arvalid (m_axil_camera_ctrl_arvalid),
        .m_axil_4_arready (m_axil_camera_ctrl_arready),
        .m_axil_4_rdata   (m_axil_camera_ctrl_rdata),
        .m_axil_4_rresp   (m_axil_camera_ctrl_rresp),
        .m_axil_4_rvalid  (m_axil_camera_ctrl_rvalid),
        .m_axil_4_rready  (m_axil_camera_ctrl_rready),

        .m_axil_5_awaddr  (m_axil_audio_ctrl_awaddr),
        .m_axil_5_awvalid (m_axil_audio_ctrl_awvalid),
        .m_axil_5_awready (m_axil_audio_ctrl_awready),
        .m_axil_5_wdata   (m_axil_audio_ctrl_wdata),
        .m_axil_5_wstrb   (m_axil_audio_ctrl_wstrb),
        .m_axil_5_wvalid  (m_axil_audio_ctrl_wvalid),
        .m_axil_5_wready  (m_axil_audio_ctrl_wready),
        .m_axil_5_bresp   (m_axil_audio_ctrl_bresp),
        .m_axil_5_bvalid  (m_axil_audio_ctrl_bvalid),
        .m_axil_5_bready  (m_axil_audio_ctrl_bready),
        .m_axil_5_araddr  (m_axil_audio_ctrl_araddr),
        .m_axil_5_arvalid (m_axil_audio_ctrl_arvalid),
        .m_axil_5_arready (m_axil_audio_ctrl_arready),
        .m_axil_5_rdata   (m_axil_audio_ctrl_rdata),
        .m_axil_5_rresp   (m_axil_audio_ctrl_rresp),
        .m_axil_5_rvalid  (m_axil_audio_ctrl_rvalid),
        .m_axil_5_rready  (m_axil_audio_ctrl_rready),

        .m_axil_6_awaddr  (m_axil_i2c_ctrl_awaddr),
        .m_axil_6_awvalid (m_axil_i2c_ctrl_awvalid),
        .m_axil_6_awready (m_axil_i2c_ctrl_awready),
        .m_axil_6_wdata   (m_axil_i2c_ctrl_wdata),
        .m_axil_6_wstrb   (m_axil_i2c_ctrl_wstrb),
        .m_axil_6_wvalid  (m_axil_i2c_ctrl_wvalid),
        .m_axil_6_wready  (m_axil_i2c_ctrl_wready),
        .m_axil_6_bresp   (m_axil_i2c_ctrl_bresp),
        .m_axil_6_bvalid  (m_axil_i2c_ctrl_bvalid),
        .m_axil_6_bready  (m_axil_i2c_ctrl_bready),
        .m_axil_6_araddr  (m_axil_i2c_ctrl_araddr),
        .m_axil_6_arvalid (m_axil_i2c_ctrl_arvalid),
        .m_axil_6_arready (m_axil_i2c_ctrl_arready),
        .m_axil_6_rdata   (m_axil_i2c_ctrl_rdata),
        .m_axil_6_rresp   (m_axil_i2c_ctrl_rresp),
        .m_axil_6_rvalid  (m_axil_i2c_ctrl_rvalid),
        .m_axil_6_rready  (m_axil_i2c_ctrl_rready),

        .m_axil_7_awaddr  (m_axil_spi_ctrl_awaddr),
        .m_axil_7_awvalid (m_axil_spi_ctrl_awvalid),
        .m_axil_7_awready (m_axil_spi_ctrl_awready),
        .m_axil_7_wdata   (m_axil_spi_ctrl_wdata),
        .m_axil_7_wstrb   (m_axil_spi_ctrl_wstrb),
        .m_axil_7_wvalid  (m_axil_spi_ctrl_wvalid),
        .m_axil_7_wready  (m_axil_spi_ctrl_wready),
        .m_axil_7_bresp   (m_axil_spi_ctrl_bresp),
        .m_axil_7_bvalid  (m_axil_spi_ctrl_bvalid),
        .m_axil_7_bready  (m_axil_spi_ctrl_bready),
        .m_axil_7_araddr  (m_axil_spi_ctrl_araddr),
        .m_axil_7_arvalid (m_axil_spi_ctrl_arvalid),
        .m_axil_7_arready (m_axil_spi_ctrl_arready),
        .m_axil_7_rdata   (m_axil_spi_ctrl_rdata),
        .m_axil_7_rresp   (m_axil_spi_ctrl_rresp),
        .m_axil_7_rvalid  (m_axil_spi_ctrl_rvalid),
        .m_axil_7_rready  (m_axil_spi_ctrl_rready),

        // Slot 8: NPU Regfile (0x2000_0800)
        .m_axil_8_awaddr  (m_axil_npu_ctrl_awaddr),
        .m_axil_8_awvalid (m_axil_npu_ctrl_awvalid),
        .m_axil_8_awready (m_axil_npu_ctrl_awready),
        .m_axil_8_wdata   (m_axil_npu_ctrl_wdata),
        .m_axil_8_wstrb   (m_axil_npu_ctrl_wstrb),
        .m_axil_8_wvalid  (m_axil_npu_ctrl_wvalid),
        .m_axil_8_wready  (m_axil_npu_ctrl_wready),
        .m_axil_8_bresp   (m_axil_npu_ctrl_bresp),
        .m_axil_8_bvalid  (m_axil_npu_ctrl_bvalid),
        .m_axil_8_bready  (m_axil_npu_ctrl_bready),
        .m_axil_8_araddr  (m_axil_npu_ctrl_araddr),
        .m_axil_8_arvalid (m_axil_npu_ctrl_arvalid),
        .m_axil_8_arready (m_axil_npu_ctrl_arready),
        .m_axil_8_rdata   (m_axil_npu_ctrl_rdata),
        .m_axil_8_rresp   (m_axil_npu_ctrl_rresp),
        .m_axil_8_rvalid  (m_axil_npu_ctrl_rvalid),
        .m_axil_8_rready  (m_axil_npu_ctrl_rready)
    );

    // ================================================================
    // 11. UART Peripheral (Slot 0)
    // ================================================================
    wire irq_uart_tx, irq_uart_rx;

    uart_peripheral #(
        .FIFO_DEPTH (16)
    ) u_uart (
        .clk            (clk_i),
        .rst_n          (periph_rst_n),
        .s_axil_awaddr  (p0_awaddr),
        .s_axil_awvalid (p0_awvalid),
        .s_axil_awready (p0_awready),
        .s_axil_wdata   (p0_wdata),
        .s_axil_wstrb   (p0_wstrb),
        .s_axil_wvalid  (p0_wvalid),
        .s_axil_wready  (p0_wready),
        .s_axil_bresp   (p0_bresp),
        .s_axil_bvalid  (p0_bvalid),
        .s_axil_bready  (p0_bready),
        .s_axil_araddr  (p0_araddr),
        .s_axil_arvalid (p0_arvalid),
        .s_axil_arready (p0_arready),
        .s_axil_rdata   (p0_rdata),
        .s_axil_rresp   (p0_rresp),
        .s_axil_rvalid  (p0_rvalid),
        .s_axil_rready  (p0_rready),
        .uart_tx_o      (uart_tx_o),
        .uart_rx_i      (uart_rx_i),
        .irq_tx_empty   (irq_uart_tx),
        .irq_rx_ready   (irq_uart_rx)
    );

    // ================================================================
    // 12. Timer CLINT (Slot 1)
    // ================================================================
    timer_clint u_timer (
        .clk            (clk_i),
        .rst_n          (periph_rst_n),
        .s_axil_awaddr  (p1_awaddr),
        .s_axil_awvalid (p1_awvalid),
        .s_axil_awready (p1_awready),
        .s_axil_wdata   (p1_wdata),
        .s_axil_wstrb   (p1_wstrb),
        .s_axil_wvalid  (p1_wvalid),
        .s_axil_wready  (p1_wready),
        .s_axil_bresp   (p1_bresp),
        .s_axil_bvalid  (p1_bvalid),
        .s_axil_bready  (p1_bready),
        .s_axil_araddr  (p1_araddr),
        .s_axil_arvalid (p1_arvalid),
        .s_axil_arready (p1_arready),
        .s_axil_rdata   (p1_rdata),
        .s_axil_rresp   (p1_rresp),
        .s_axil_rvalid  (p1_rvalid),
        .s_axil_rready  (p1_rready),
        .irq_timer_o    (irq_timer)
    );

    // ================================================================
    // 13. IRQ Controller (Slot 2)
    // ================================================================
    wire irq_gpio;
    wire [7:0] irq_sources;
    assign irq_sources = {
        irq_i2c_done_i,       // [7]
        irq_audio_ready_i,    // [6]
        irq_camera_ready_i,   // [5]
        irq_dma_done_i,       // [4]
        irq_npu_done_i,       // [3]
        irq_gpio,             // [2]
        irq_uart_rx,          // [1]
        irq_uart_tx           // [0]
    };

    irq_controller u_irq_ctrl (
        .clk            (clk_i),
        .rst_n          (periph_rst_n),
        .s_axil_awaddr  (p2_awaddr),
        .s_axil_awvalid (p2_awvalid),
        .s_axil_awready (p2_awready),
        .s_axil_wdata   (p2_wdata),
        .s_axil_wstrb   (p2_wstrb),
        .s_axil_wvalid  (p2_wvalid),
        .s_axil_wready  (p2_wready),
        .s_axil_bresp   (p2_bresp),
        .s_axil_bvalid  (p2_bvalid),
        .s_axil_bready  (p2_bready),
        .s_axil_araddr  (p2_araddr),
        .s_axil_arvalid (p2_arvalid),
        .s_axil_arready (p2_arready),
        .s_axil_rdata   (p2_rdata),
        .s_axil_rresp   (p2_rresp),
        .s_axil_rvalid  (p2_rvalid),
        .s_axil_rready  (p2_rready),
        .irq_sources_i  (irq_sources),
        .irq_external_o (irq_external)
    );

    // ================================================================
    // 14. GPIO Peripheral (Slot 3)
    // ================================================================
    gpio_peripheral #(
        .GPIO_WIDTH (8)
    ) u_gpio (
        .clk            (clk_i),
        .rst_n          (periph_rst_n),
        .s_axil_awaddr  (p3_awaddr),
        .s_axil_awvalid (p3_awvalid),
        .s_axil_awready (p3_awready),
        .s_axil_wdata   (p3_wdata),
        .s_axil_wstrb   (p3_wstrb),
        .s_axil_wvalid  (p3_wvalid),
        .s_axil_wready  (p3_wready),
        .s_axil_bresp   (p3_bresp),
        .s_axil_bvalid  (p3_bvalid),
        .s_axil_bready  (p3_bready),
        .s_axil_araddr  (p3_araddr),
        .s_axil_arvalid (p3_arvalid),
        .s_axil_arready (p3_arready),
        .s_axil_rdata   (p3_rdata),
        .s_axil_rresp   (p3_rresp),
        .s_axil_rvalid  (p3_rvalid),
        .s_axil_rready  (p3_rready),
        .gpio_i         (gpio_i),
        .gpio_o         (gpio_o),
        .gpio_oe        (gpio_oe),
        .irq_gpio       (irq_gpio)
    );

endmodule
