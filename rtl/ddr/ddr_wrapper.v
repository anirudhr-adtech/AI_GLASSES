`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — DDR Subsystem
// Module: ddr_wrapper
// Description: Top-level DDR wrapper. Pipeline:
//   SoC AXI4 128-bit -> burst split -> QoS map -> width convert -> Zynq HP AXI3 64-bit
//////////////////////////////////////////////////////////////////////////////

module ddr_wrapper #(
    parameter ADDR_WIDTH   = 32,
    parameter WIDE_DATA    = 128,
    parameter NARROW_DATA  = 64,
    parameter ID_WIDTH     = 6,
    parameter WIDE_STRB    = WIDE_DATA / 8,
    parameter NARROW_STRB  = NARROW_DATA / 8
)(
    input  wire                      clk,
    input  wire                      rst_n,

    // AXI4 Slave interface (128-bit, from SoC crossbar)
    input  wire [ID_WIDTH-1:0]       s_axi4_awid,
    input  wire [ADDR_WIDTH-1:0]     s_axi4_awaddr,
    input  wire [7:0]                s_axi4_awlen,
    input  wire [2:0]                s_axi4_awsize,
    input  wire [1:0]                s_axi4_awburst,
    input  wire                      s_axi4_awvalid,
    output wire                      s_axi4_awready,

    input  wire [WIDE_DATA-1:0]      s_axi4_wdata,
    input  wire [WIDE_STRB-1:0]      s_axi4_wstrb,
    input  wire                      s_axi4_wlast,
    input  wire                      s_axi4_wvalid,
    output wire                      s_axi4_wready,

    output wire [ID_WIDTH-1:0]       s_axi4_bid,
    output wire [1:0]                s_axi4_bresp,
    output wire                      s_axi4_bvalid,
    input  wire                      s_axi4_bready,

    input  wire [ID_WIDTH-1:0]       s_axi4_arid,
    input  wire [ADDR_WIDTH-1:0]     s_axi4_araddr,
    input  wire [7:0]                s_axi4_arlen,
    input  wire [2:0]                s_axi4_arsize,
    input  wire [1:0]                s_axi4_arburst,
    input  wire                      s_axi4_arvalid,
    output wire                      s_axi4_arready,

    output wire [ID_WIDTH-1:0]       s_axi4_rid,
    output wire [WIDE_DATA-1:0]      s_axi4_rdata,
    output wire [1:0]                s_axi4_rresp,
    output wire                      s_axi4_rlast,
    output wire                      s_axi4_rvalid,
    input  wire                      s_axi4_rready,

    // AXI3 Master interface (64-bit, to Zynq HP0)
    output wire [ID_WIDTH-1:0]       m_axi3_awid,
    output wire [ADDR_WIDTH-1:0]     m_axi3_awaddr,
    output wire [3:0]                m_axi3_awlen,
    output wire [2:0]                m_axi3_awsize,
    output wire [1:0]                m_axi3_awburst,
    output wire [3:0]                m_axi3_awqos,
    output wire                      m_axi3_awvalid,
    input  wire                      m_axi3_awready,

    output wire [NARROW_DATA-1:0]    m_axi3_wdata,
    output wire [NARROW_STRB-1:0]    m_axi3_wstrb,
    output wire                      m_axi3_wlast,
    output wire                      m_axi3_wvalid,
    input  wire                      m_axi3_wready,

    input  wire [ID_WIDTH-1:0]       m_axi3_bid,
    input  wire [1:0]                m_axi3_bresp,
    input  wire                      m_axi3_bvalid,
    output wire                      m_axi3_bready,

    output wire [ID_WIDTH-1:0]       m_axi3_arid,
    output wire [ADDR_WIDTH-1:0]     m_axi3_araddr,
    output wire [3:0]                m_axi3_arlen,
    output wire [2:0]                m_axi3_arsize,
    output wire [1:0]                m_axi3_arburst,
    output wire [3:0]                m_axi3_arqos,
    output wire                      m_axi3_arvalid,
    input  wire                      m_axi3_arready,

    input  wire [ID_WIDTH-1:0]       m_axi3_rid,
    input  wire [NARROW_DATA-1:0]    m_axi3_rdata,
    input  wire [1:0]                m_axi3_rresp,
    input  wire                      m_axi3_rlast,
    input  wire                      m_axi3_rvalid,
    output wire                      m_axi3_rready
);

    // -----------------------------------------------------------------------
    // Internal wires: bridge (128-bit AXI3) to width converter
    // -----------------------------------------------------------------------
    wire [ID_WIDTH-1:0]     int_awid;
    wire [ADDR_WIDTH-1:0]   int_awaddr;
    wire [3:0]              int_awlen;
    wire [2:0]              int_awsize;
    wire [1:0]              int_awburst;
    wire [3:0]              int_awqos;
    wire                    int_awvalid;
    wire                    int_awready;

    wire [WIDE_DATA-1:0]    int_wdata;
    wire [WIDE_STRB-1:0]    int_wstrb;
    wire                    int_wlast;
    wire                    int_wvalid;
    wire                    int_wready;

    wire [ID_WIDTH-1:0]     int_bid;
    wire [1:0]              int_bresp;
    wire                    int_bvalid;
    wire                    int_bready;

    wire [ID_WIDTH-1:0]     int_arid;
    wire [ADDR_WIDTH-1:0]   int_araddr;
    wire [3:0]              int_arlen;
    wire [2:0]              int_arsize;
    wire [1:0]              int_arburst;
    wire [3:0]              int_arqos;
    wire                    int_arvalid;
    wire                    int_arready;

    wire [ID_WIDTH-1:0]     int_rid;
    wire [WIDE_DATA-1:0]    int_rdata;
    wire [1:0]              int_rresp;
    wire                    int_rlast;
    wire                    int_rvalid;
    wire                    int_rready;

    // -----------------------------------------------------------------------
    // Stage 1: AXI4-to-AXI3 bridge (burst split + QoS)
    // -----------------------------------------------------------------------
    axi4_to_axi3_bridge #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (WIDE_DATA),
        .ID_WIDTH   (ID_WIDTH)
    ) u_bridge (
        .clk        (clk),
        .rst_n      (rst_n),

        // AXI4 slave
        .s_awid     (s_axi4_awid),
        .s_awaddr   (s_axi4_awaddr),
        .s_awlen    (s_axi4_awlen),
        .s_awsize   (s_axi4_awsize),
        .s_awburst  (s_axi4_awburst),
        .s_awvalid  (s_axi4_awvalid),
        .s_awready  (s_axi4_awready),

        .s_wdata    (s_axi4_wdata),
        .s_wstrb    (s_axi4_wstrb),
        .s_wlast    (s_axi4_wlast),
        .s_wvalid   (s_axi4_wvalid),
        .s_wready   (s_axi4_wready),

        .s_bid      (s_axi4_bid),
        .s_bresp    (s_axi4_bresp),
        .s_bvalid   (s_axi4_bvalid),
        .s_bready   (s_axi4_bready),

        .s_arid     (s_axi4_arid),
        .s_araddr   (s_axi4_araddr),
        .s_arlen    (s_axi4_arlen),
        .s_arsize   (s_axi4_arsize),
        .s_arburst  (s_axi4_arburst),
        .s_arvalid  (s_axi4_arvalid),
        .s_arready  (s_axi4_arready),

        .s_rid      (s_axi4_rid),
        .s_rdata    (s_axi4_rdata),
        .s_rresp    (s_axi4_rresp),
        .s_rlast    (s_axi4_rlast),
        .s_rvalid   (s_axi4_rvalid),
        .s_rready   (s_axi4_rready),

        // AXI3 master (128-bit internal)
        .m_awid     (int_awid),
        .m_awaddr   (int_awaddr),
        .m_awlen    (int_awlen),
        .m_awsize   (int_awsize),
        .m_awburst  (int_awburst),
        .m_awqos    (int_awqos),
        .m_awvalid  (int_awvalid),
        .m_awready  (int_awready),

        .m_wdata    (int_wdata),
        .m_wstrb    (int_wstrb),
        .m_wlast    (int_wlast),
        .m_wvalid   (int_wvalid),
        .m_wready   (int_wready),

        .m_bid      (int_bid),
        .m_bresp    (int_bresp),
        .m_bvalid   (int_bvalid),
        .m_bready   (int_bready),

        .m_arid     (int_arid),
        .m_araddr   (int_araddr),
        .m_arlen    (int_arlen),
        .m_arsize   (int_arsize),
        .m_arburst  (int_arburst),
        .m_arqos    (int_arqos),
        .m_arvalid  (int_arvalid),
        .m_arready  (int_arready),

        .m_rid      (int_rid),
        .m_rdata    (int_rdata),
        .m_rresp    (int_rresp),
        .m_rlast    (int_rlast),
        .m_rvalid   (int_rvalid),
        .m_rready   (int_rready)
    );

    // -----------------------------------------------------------------------
    // Stage 2: Width converter 128-bit -> 64-bit
    // -----------------------------------------------------------------------
    axi_width_128to64 #(
        .ADDR_WIDTH  (ADDR_WIDTH),
        .ID_WIDTH    (ID_WIDTH),
        .WIDE_DATA   (WIDE_DATA),
        .NARROW_DATA (NARROW_DATA)
    ) u_width_conv (
        .clk        (clk),
        .rst_n      (rst_n),

        // Wide slave (128-bit AXI3 from bridge)
        .s_awid     (int_awid),
        .s_awaddr   (int_awaddr),
        .s_awlen    (int_awlen),
        .s_awsize   (int_awsize),
        .s_awburst  (int_awburst),
        .s_awqos    (int_awqos),
        .s_awvalid  (int_awvalid),
        .s_awready  (int_awready),

        .s_wdata    (int_wdata),
        .s_wstrb    (int_wstrb),
        .s_wlast    (int_wlast),
        .s_wvalid   (int_wvalid),
        .s_wready   (int_wready),

        .s_bid      (int_bid),
        .s_bresp    (int_bresp),
        .s_bvalid   (int_bvalid),
        .s_bready   (int_bready),

        .s_arid     (int_arid),
        .s_araddr   (int_araddr),
        .s_arlen    (int_arlen),
        .s_arsize   (int_arsize),
        .s_arburst  (int_arburst),
        .s_arqos    (int_arqos),
        .s_arvalid  (int_arvalid),
        .s_arready  (int_arready),

        .s_rid      (int_rid),
        .s_rdata    (int_rdata),
        .s_rresp    (int_rresp),
        .s_rlast    (int_rlast),
        .s_rvalid   (int_rvalid),
        .s_rready   (int_rready),

        // Narrow master (64-bit AXI3 to Zynq HP0)
        .m_awid     (m_axi3_awid),
        .m_awaddr   (m_axi3_awaddr),
        .m_awlen    (m_axi3_awlen),
        .m_awsize   (m_axi3_awsize),
        .m_awburst  (m_axi3_awburst),
        .m_awqos    (m_axi3_awqos),
        .m_awvalid  (m_axi3_awvalid),
        .m_awready  (m_axi3_awready),

        .m_wdata    (m_axi3_wdata),
        .m_wstrb    (m_axi3_wstrb),
        .m_wlast    (m_axi3_wlast),
        .m_wvalid   (m_axi3_wvalid),
        .m_wready   (m_axi3_wready),

        .m_bid      (m_axi3_bid),
        .m_bresp    (m_axi3_bresp),
        .m_bvalid   (m_axi3_bvalid),
        .m_bready   (m_axi3_bready),

        .m_arid     (m_axi3_arid),
        .m_araddr   (m_axi3_araddr),
        .m_arlen    (m_axi3_arlen),
        .m_arsize   (m_axi3_arsize),
        .m_arburst  (m_axi3_arburst),
        .m_arqos    (m_axi3_arqos),
        .m_arvalid  (m_axi3_arvalid),
        .m_arready  (m_axi3_arready),

        .m_rid      (m_axi3_rid),
        .m_rdata    (m_axi3_rdata),
        .m_rresp    (m_axi3_rresp),
        .m_rlast    (m_axi3_rlast),
        .m_rvalid   (m_axi3_rvalid),
        .m_rready   (m_axi3_rready)
    );

endmodule
