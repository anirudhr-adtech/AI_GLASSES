`timescale 1ns/1ps
//============================================================================
// Module:      axilite_fabric
// Project:     AI_GLASSES — AXI Interconnect
// Description: Top-level 1M x 11S AXI-Lite fabric. Instantiates
//              axi_to_axilite_bridge, axilite_addr_decoder, axilite_mux.
//              One AXI4 slave port (from crossbar S2), 11 AXI-Lite master ports.
//============================================================================

module axilite_fabric #(
    parameter DATA_WIDTH  = 32,
    parameter ADDR_WIDTH  = 32,
    parameter ID_WIDTH    = 6,
    parameter NUM_PERIPHS = 11
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // AXI4 slave interface (from crossbar S2)
    input  wire [ID_WIDTH-1:0]     s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]   s_axi_awaddr,
    input  wire [7:0]              s_axi_awlen,
    input  wire [2:0]              s_axi_awsize,
    input  wire [1:0]              s_axi_awburst,
    input  wire                    s_axi_awvalid,
    output wire                    s_axi_awready,

    input  wire [DATA_WIDTH-1:0]   s_axi_wdata,
    input  wire [DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  wire                    s_axi_wlast,
    input  wire                    s_axi_wvalid,
    output wire                    s_axi_wready,

    output wire [ID_WIDTH-1:0]     s_axi_bid,
    output wire [1:0]              s_axi_bresp,
    output wire                    s_axi_bvalid,
    input  wire                    s_axi_bready,

    input  wire [ID_WIDTH-1:0]     s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]   s_axi_araddr,
    input  wire [7:0]              s_axi_arlen,
    input  wire [2:0]              s_axi_arsize,
    input  wire [1:0]              s_axi_arburst,
    input  wire                    s_axi_arvalid,
    output wire                    s_axi_arready,

    output wire [ID_WIDTH-1:0]     s_axi_rid,
    output wire [DATA_WIDTH-1:0]   s_axi_rdata,
    output wire [1:0]              s_axi_rresp,
    output wire                    s_axi_rlast,
    output wire                    s_axi_rvalid,
    input  wire                    s_axi_rready,

    // 11 AXI-Lite master ports (packed arrays)
    output wire [NUM_PERIPHS*ADDR_WIDTH-1:0]    m_axil_awaddr,
    output wire [NUM_PERIPHS*3-1:0]             m_axil_awprot,
    output wire [NUM_PERIPHS-1:0]               m_axil_awvalid,
    input  wire [NUM_PERIPHS-1:0]               m_axil_awready,

    output wire [NUM_PERIPHS*DATA_WIDTH-1:0]    m_axil_wdata,
    output wire [NUM_PERIPHS*(DATA_WIDTH/8)-1:0] m_axil_wstrb,
    output wire [NUM_PERIPHS-1:0]               m_axil_wvalid,
    input  wire [NUM_PERIPHS-1:0]               m_axil_wready,

    input  wire [NUM_PERIPHS*2-1:0]             m_axil_bresp,
    input  wire [NUM_PERIPHS-1:0]               m_axil_bvalid,
    output wire [NUM_PERIPHS-1:0]               m_axil_bready,

    output wire [NUM_PERIPHS*ADDR_WIDTH-1:0]    m_axil_araddr,
    output wire [NUM_PERIPHS*3-1:0]             m_axil_arprot,
    output wire [NUM_PERIPHS-1:0]               m_axil_arvalid,
    input  wire [NUM_PERIPHS-1:0]               m_axil_arready,

    input  wire [NUM_PERIPHS*DATA_WIDTH-1:0]    m_axil_rdata,
    input  wire [NUM_PERIPHS*2-1:0]             m_axil_rresp,
    input  wire [NUM_PERIPHS-1:0]               m_axil_rvalid,
    output wire [NUM_PERIPHS-1:0]               m_axil_rready
);

    // Internal wires: bridge to mux
    wire [ADDR_WIDTH-1:0]   bridge_awaddr;
    wire [2:0]              bridge_awprot;
    wire                    bridge_awvalid;
    wire                    bridge_awready;
    wire [DATA_WIDTH-1:0]   bridge_wdata;
    wire [DATA_WIDTH/8-1:0] bridge_wstrb;
    wire                    bridge_wvalid;
    wire                    bridge_wready;
    wire [1:0]              bridge_bresp;
    wire                    bridge_bvalid;
    wire                    bridge_bready;
    wire [ADDR_WIDTH-1:0]   bridge_araddr;
    wire [2:0]              bridge_arprot;
    wire                    bridge_arvalid;
    wire                    bridge_arready;
    wire [DATA_WIDTH-1:0]   bridge_rdata;
    wire [1:0]              bridge_rresp;
    wire                    bridge_rvalid;
    wire                    bridge_rready;

    // Decoder output
    wire [3:0] periph_sel;
    wire       decode_error;

    // AXI4 to AXI-Lite bridge
    axi_to_axilite_bridge #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) u_bridge (
        .clk              (clk),
        .rst_n            (rst_n),
        .s_axi_awid       (s_axi_awid),
        .s_axi_awaddr     (s_axi_awaddr),
        .s_axi_awlen      (s_axi_awlen),
        .s_axi_awsize     (s_axi_awsize),
        .s_axi_awburst    (s_axi_awburst),
        .s_axi_awvalid    (s_axi_awvalid),
        .s_axi_awready    (s_axi_awready),
        .s_axi_wdata      (s_axi_wdata),
        .s_axi_wstrb      (s_axi_wstrb),
        .s_axi_wlast      (s_axi_wlast),
        .s_axi_wvalid     (s_axi_wvalid),
        .s_axi_wready     (s_axi_wready),
        .s_axi_bid        (s_axi_bid),
        .s_axi_bresp      (s_axi_bresp),
        .s_axi_bvalid     (s_axi_bvalid),
        .s_axi_bready     (s_axi_bready),
        .s_axi_arid       (s_axi_arid),
        .s_axi_araddr     (s_axi_araddr),
        .s_axi_arlen      (s_axi_arlen),
        .s_axi_arsize     (s_axi_arsize),
        .s_axi_arburst    (s_axi_arburst),
        .s_axi_arvalid    (s_axi_arvalid),
        .s_axi_arready    (s_axi_arready),
        .s_axi_rid        (s_axi_rid),
        .s_axi_rdata      (s_axi_rdata),
        .s_axi_rresp      (s_axi_rresp),
        .s_axi_rlast      (s_axi_rlast),
        .s_axi_rvalid     (s_axi_rvalid),
        .s_axi_rready     (s_axi_rready),
        .m_axil_awaddr    (bridge_awaddr),
        .m_axil_awprot    (bridge_awprot),
        .m_axil_awvalid   (bridge_awvalid),
        .m_axil_awready   (bridge_awready),
        .m_axil_wdata     (bridge_wdata),
        .m_axil_wstrb     (bridge_wstrb),
        .m_axil_wvalid    (bridge_wvalid),
        .m_axil_wready    (bridge_wready),
        .m_axil_bresp     (bridge_bresp),
        .m_axil_bvalid    (bridge_bvalid),
        .m_axil_bready    (bridge_bready),
        .m_axil_araddr    (bridge_araddr),
        .m_axil_arprot    (bridge_arprot),
        .m_axil_arvalid   (bridge_arvalid),
        .m_axil_arready   (bridge_arready),
        .m_axil_rdata     (bridge_rdata),
        .m_axil_rresp     (bridge_rresp),
        .m_axil_rvalid    (bridge_rvalid),
        .m_axil_rready    (bridge_rready)
    );

    // Address decoder - decode bridge output address
    // Use the AW or AR address depending on which is valid
    wire [ADDR_WIDTH-1:0] decode_addr = bridge_awvalid ? bridge_awaddr : bridge_araddr;

    axilite_addr_decoder #(
        .ADDR_WIDTH  (ADDR_WIDTH),
        .NUM_PERIPHS (NUM_PERIPHS)
    ) u_decoder (
        .clk            (clk),
        .rst_n          (rst_n),
        .addr_i         (decode_addr),
        .periph_sel_o   (periph_sel),
        .decode_error_o (decode_error)
    );

    // AXI-Lite mux
    axilite_mux #(
        .NUM_SLAVES (NUM_PERIPHS),
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_mux (
        .clk              (clk),
        .rst_n            (rst_n),
        .periph_sel_i     (periph_sel),
        .s_axil_awaddr    (bridge_awaddr),
        .s_axil_awprot    (bridge_awprot),
        .s_axil_awvalid   (bridge_awvalid),
        .s_axil_awready   (bridge_awready),
        .s_axil_wdata     (bridge_wdata),
        .s_axil_wstrb     (bridge_wstrb),
        .s_axil_wvalid    (bridge_wvalid),
        .s_axil_wready    (bridge_wready),
        .s_axil_bresp     (bridge_bresp),
        .s_axil_bvalid    (bridge_bvalid),
        .s_axil_bready    (bridge_bready),
        .s_axil_araddr    (bridge_araddr),
        .s_axil_arprot    (bridge_arprot),
        .s_axil_arvalid   (bridge_arvalid),
        .s_axil_arready   (bridge_arready),
        .s_axil_rdata     (bridge_rdata),
        .s_axil_rresp     (bridge_rresp),
        .s_axil_rvalid    (bridge_rvalid),
        .s_axil_rready    (bridge_rready),
        .m_axil_awaddr    (m_axil_awaddr),
        .m_axil_awprot    (m_axil_awprot),
        .m_axil_awvalid   (m_axil_awvalid),
        .m_axil_awready   (m_axil_awready),
        .m_axil_wdata     (m_axil_wdata),
        .m_axil_wstrb     (m_axil_wstrb),
        .m_axil_wvalid    (m_axil_wvalid),
        .m_axil_wready    (m_axil_wready),
        .m_axil_bresp     (m_axil_bresp),
        .m_axil_bvalid    (m_axil_bvalid),
        .m_axil_bready    (m_axil_bready),
        .m_axil_araddr    (m_axil_araddr),
        .m_axil_arprot    (m_axil_arprot),
        .m_axil_arvalid   (m_axil_arvalid),
        .m_axil_arready   (m_axil_arready),
        .m_axil_rdata     (m_axil_rdata),
        .m_axil_rresp     (m_axil_rresp),
        .m_axil_rvalid    (m_axil_rvalid),
        .m_axil_rready    (m_axil_rready)
    );

endmodule
