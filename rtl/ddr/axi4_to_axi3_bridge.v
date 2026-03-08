`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — DDR Subsystem
// Module: axi4_to_axi3_bridge
// Description: Full AXI4-to-AXI3 protocol bridge. Instantiates burst_splitter
//              and qos_mapper. Adds QoS to AW/AR channels.
//////////////////////////////////////////////////////////////////////////////

module axi4_to_axi3_bridge #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 128,
    parameter ID_WIDTH   = 6,
    parameter STRB_WIDTH = DATA_WIDTH / 8
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // AXI4 Slave interface (from crossbar S3)
    input  wire [ID_WIDTH-1:0]     s_awid,
    input  wire [ADDR_WIDTH-1:0]   s_awaddr,
    input  wire [7:0]              s_awlen,
    input  wire [2:0]              s_awsize,
    input  wire [1:0]              s_awburst,
    input  wire                    s_awvalid,
    output wire                    s_awready,

    input  wire [DATA_WIDTH-1:0]   s_wdata,
    input  wire [STRB_WIDTH-1:0]   s_wstrb,
    input  wire                    s_wlast,
    input  wire                    s_wvalid,
    output wire                    s_wready,

    output wire [ID_WIDTH-1:0]     s_bid,
    output wire [1:0]              s_bresp,
    output wire                    s_bvalid,
    input  wire                    s_bready,

    input  wire [ID_WIDTH-1:0]     s_arid,
    input  wire [ADDR_WIDTH-1:0]   s_araddr,
    input  wire [7:0]              s_arlen,
    input  wire [2:0]              s_arsize,
    input  wire [1:0]              s_arburst,
    input  wire                    s_arvalid,
    output wire                    s_arready,

    output wire [ID_WIDTH-1:0]     s_rid,
    output wire [DATA_WIDTH-1:0]   s_rdata,
    output wire [1:0]              s_rresp,
    output wire                    s_rlast,
    output wire                    s_rvalid,
    input  wire                    s_rready,

    // AXI3 Master interface (128-bit, burst limited to 16)
    output wire [ID_WIDTH-1:0]     m_awid,
    output wire [ADDR_WIDTH-1:0]   m_awaddr,
    output wire [3:0]              m_awlen,
    output wire [2:0]              m_awsize,
    output wire [1:0]              m_awburst,
    output wire [3:0]              m_awqos,
    output wire                    m_awvalid,
    input  wire                    m_awready,

    output wire [DATA_WIDTH-1:0]   m_wdata,
    output wire [STRB_WIDTH-1:0]   m_wstrb,
    output wire                    m_wlast,
    output wire                    m_wvalid,
    input  wire                    m_wready,

    input  wire [ID_WIDTH-1:0]     m_bid,
    input  wire [1:0]              m_bresp,
    input  wire                    m_bvalid,
    output wire                    m_bready,

    output wire [ID_WIDTH-1:0]     m_arid,
    output wire [ADDR_WIDTH-1:0]   m_araddr,
    output wire [3:0]              m_arlen,
    output wire [2:0]              m_arsize,
    output wire [1:0]              m_arburst,
    output wire [3:0]              m_arqos,
    output wire                    m_arvalid,
    input  wire                    m_arready,

    input  wire [ID_WIDTH-1:0]     m_rid,
    input  wire [DATA_WIDTH-1:0]   m_rdata,
    input  wire [1:0]              m_rresp,
    input  wire                    m_rlast,
    input  wire                    m_rvalid,
    output wire                    m_rready
);

    // -----------------------------------------------------------------------
    // QoS mappers for AW and AR channels
    // -----------------------------------------------------------------------
    qos_mapper #(
        .ID_WIDTH(ID_WIDTH)
    ) u_qos_aw (
        .clk      (clk),
        .rst_n    (rst_n),
        .axi_id_i (s_awid),
        .qos_o    (m_awqos)
    );

    qos_mapper #(
        .ID_WIDTH(ID_WIDTH)
    ) u_qos_ar (
        .clk      (clk),
        .rst_n    (rst_n),
        .axi_id_i (s_arid),
        .qos_o    (m_arqos)
    );

    // -----------------------------------------------------------------------
    // Burst splitter: AXI4 -> AXI3 burst conversion
    // -----------------------------------------------------------------------
    burst_splitter #(
        .ADDR_WIDTH  (ADDR_WIDTH),
        .DATA_WIDTH  (DATA_WIDTH),
        .ID_WIDTH    (ID_WIDTH),
        .MAX_AXI3_LEN(7)       // 8-beat max: width converter doubles to 16 (AXI3 max)
    ) u_burst_splitter (
        .clk        (clk),
        .rst_n      (rst_n),

        // AXI4 slave side
        .s_awid     (s_awid),
        .s_awaddr   (s_awaddr),
        .s_awlen    (s_awlen),
        .s_awsize   (s_awsize),
        .s_awburst  (s_awburst),
        .s_awvalid  (s_awvalid),
        .s_awready  (s_awready),

        .s_wdata    (s_wdata),
        .s_wstrb    (s_wstrb),
        .s_wlast    (s_wlast),
        .s_wvalid   (s_wvalid),
        .s_wready   (s_wready),

        .s_bid      (s_bid),
        .s_bresp    (s_bresp),
        .s_bvalid   (s_bvalid),
        .s_bready   (s_bready),

        .s_arid     (s_arid),
        .s_araddr   (s_araddr),
        .s_arlen    (s_arlen),
        .s_arsize   (s_arsize),
        .s_arburst  (s_arburst),
        .s_arvalid  (s_arvalid),
        .s_arready  (s_arready),

        .s_rid      (s_rid),
        .s_rdata    (s_rdata),
        .s_rresp    (s_rresp),
        .s_rlast    (s_rlast),
        .s_rvalid   (s_rvalid),
        .s_rready   (s_rready),

        // AXI3 master side
        .m_awid     (m_awid),
        .m_awaddr   (m_awaddr),
        .m_awlen    (m_awlen),
        .m_awsize   (m_awsize),
        .m_awburst  (m_awburst),
        .m_awvalid  (m_awvalid),
        .m_awready  (m_awready),

        .m_wdata    (m_wdata),
        .m_wstrb    (m_wstrb),
        .m_wlast    (m_wlast),
        .m_wvalid   (m_wvalid),
        .m_wready   (m_wready),

        .m_bid      (m_bid),
        .m_bresp    (m_bresp),
        .m_bvalid   (m_bvalid),
        .m_bready   (m_bready),

        .m_arid     (m_arid),
        .m_araddr   (m_araddr),
        .m_arlen    (m_arlen),
        .m_arsize   (m_arsize),
        .m_arburst  (m_arburst),
        .m_arvalid  (m_arvalid),
        .m_arready  (m_arready),

        .m_rid      (m_rid),
        .m_rdata    (m_rdata),
        .m_rresp    (m_rresp),
        .m_rlast    (m_rlast),
        .m_rvalid   (m_rvalid),
        .m_rready   (m_rready)
    );

endmodule
