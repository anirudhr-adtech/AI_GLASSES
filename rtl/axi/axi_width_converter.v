`timescale 1ns/1ps
//============================================================================
// Module:      axi_width_converter
// Project:     AI_GLASSES — AXI Interconnect
// Description: Wraps upsizer + downsizer. Selects based on src/dst width.
//              If src==dst: pass-through. If src<dst: upsizer. If src>dst: downsizer.
//============================================================================

module axi_width_converter #(
    parameter NARROW_WIDTH = 32,
    parameter WIDE_WIDTH   = 128,
    parameter ADDR_WIDTH   = 32,
    parameter ID_WIDTH     = 6
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // Width configuration
    input  wire [1:0]              src_width_i,  // 00=32, 01=64, 10=128
    input  wire [1:0]              dst_width_i,  // 00=32, 01=64, 10=128

    // Slave AXI interface (from source/master side)
    input  wire [ID_WIDTH-1:0]     s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]   s_axi_awaddr,
    input  wire [7:0]              s_axi_awlen,
    input  wire [2:0]              s_axi_awsize,
    input  wire [1:0]              s_axi_awburst,
    input  wire                    s_axi_awvalid,
    output wire                    s_axi_awready,

    input  wire [WIDE_WIDTH-1:0]   s_axi_wdata,
    input  wire [WIDE_WIDTH/8-1:0] s_axi_wstrb,
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
    output wire [WIDE_WIDTH-1:0]   s_axi_rdata,
    output wire [1:0]              s_axi_rresp,
    output wire                    s_axi_rlast,
    output wire                    s_axi_rvalid,
    input  wire                    s_axi_rready,

    // Master AXI interface (to destination/slave side)
    output wire [ID_WIDTH-1:0]     m_axi_awid,
    output wire [ADDR_WIDTH-1:0]   m_axi_awaddr,
    output wire [7:0]              m_axi_awlen,
    output wire [2:0]              m_axi_awsize,
    output wire [1:0]              m_axi_awburst,
    output wire                    m_axi_awvalid,
    input  wire                    m_axi_awready,

    output wire [WIDE_WIDTH-1:0]   m_axi_wdata,
    output wire [WIDE_WIDTH/8-1:0] m_axi_wstrb,
    output wire                    m_axi_wlast,
    output wire                    m_axi_wvalid,
    input  wire                    m_axi_wready,

    input  wire [ID_WIDTH-1:0]     m_axi_bid,
    input  wire [1:0]              m_axi_bresp,
    input  wire                    m_axi_bvalid,
    output wire                    m_axi_bready,

    output wire [ID_WIDTH-1:0]     m_axi_arid,
    output wire [ADDR_WIDTH-1:0]   m_axi_araddr,
    output wire [7:0]              m_axi_arlen,
    output wire [2:0]              m_axi_arsize,
    output wire [1:0]              m_axi_arburst,
    output wire                    m_axi_arvalid,
    input  wire                    m_axi_arready,

    input  wire [ID_WIDTH-1:0]     m_axi_rid,
    input  wire [WIDE_WIDTH-1:0]   m_axi_rdata,
    input  wire [1:0]              m_axi_rresp,
    input  wire                    m_axi_rlast,
    input  wire                    m_axi_rvalid,
    output wire                    m_axi_rready
);

    // Mode: 0=pass-through, 1=upsize, 2=downsize
    wire passthrough = (src_width_i == dst_width_i);
    wire upsize      = (src_width_i < dst_width_i);
    wire downsize    = (src_width_i > dst_width_i);

    // Upsizer wires
    wire                    up_s_awready, up_s_wready, up_s_arready;
    wire [ID_WIDTH-1:0]     up_s_bid, up_s_rid;
    wire [1:0]              up_s_bresp, up_s_rresp;
    wire                    up_s_bvalid, up_s_rvalid, up_s_rlast;
    wire [NARROW_WIDTH-1:0] up_s_rdata;

    wire [ID_WIDTH-1:0]     up_m_awid, up_m_arid;
    wire [ADDR_WIDTH-1:0]   up_m_awaddr, up_m_araddr;
    wire [7:0]              up_m_awlen, up_m_arlen;
    wire [2:0]              up_m_awsize, up_m_arsize;
    wire [1:0]              up_m_awburst, up_m_arburst;
    wire                    up_m_awvalid, up_m_arvalid;
    wire [WIDE_WIDTH-1:0]   up_m_wdata;
    wire [WIDE_WIDTH/8-1:0] up_m_wstrb;
    wire                    up_m_wlast, up_m_wvalid;
    wire                    up_m_bready, up_m_rready;

    axi_upsizer #(
        .NARROW_WIDTH (NARROW_WIDTH),
        .WIDE_WIDTH   (WIDE_WIDTH),
        .ADDR_WIDTH   (ADDR_WIDTH),
        .ID_WIDTH     (ID_WIDTH)
    ) u_upsizer (
        .clk             (clk),
        .rst_n           (rst_n),
        .s_axi_awid      (s_axi_awid),
        .s_axi_awaddr    (s_axi_awaddr),
        .s_axi_awlen     (s_axi_awlen),
        .s_axi_awsize    (s_axi_awsize),
        .s_axi_awburst   (s_axi_awburst),
        .s_axi_awvalid   (upsize ? s_axi_awvalid : 1'b0),
        .s_axi_awready   (up_s_awready),
        .s_axi_wdata     (s_axi_wdata[NARROW_WIDTH-1:0]),
        .s_axi_wstrb     (s_axi_wstrb[NARROW_WIDTH/8-1:0]),
        .s_axi_wlast     (s_axi_wlast),
        .s_axi_wvalid    (upsize ? s_axi_wvalid : 1'b0),
        .s_axi_wready    (up_s_wready),
        .s_axi_bid       (up_s_bid),
        .s_axi_bresp     (up_s_bresp),
        .s_axi_bvalid    (up_s_bvalid),
        .s_axi_bready    (s_axi_bready),
        .s_axi_arid      (s_axi_arid),
        .s_axi_araddr    (s_axi_araddr),
        .s_axi_arlen     (s_axi_arlen),
        .s_axi_arsize    (s_axi_arsize),
        .s_axi_arburst   (s_axi_arburst),
        .s_axi_arvalid   (upsize ? s_axi_arvalid : 1'b0),
        .s_axi_arready   (up_s_arready),
        .s_axi_rid       (up_s_rid),
        .s_axi_rdata     (up_s_rdata),
        .s_axi_rresp     (up_s_rresp),
        .s_axi_rlast     (up_s_rlast),
        .s_axi_rvalid    (up_s_rvalid),
        .s_axi_rready    (s_axi_rready),
        .m_axi_awid      (up_m_awid),
        .m_axi_awaddr    (up_m_awaddr),
        .m_axi_awlen     (up_m_awlen),
        .m_axi_awsize    (up_m_awsize),
        .m_axi_awburst   (up_m_awburst),
        .m_axi_awvalid   (up_m_awvalid),
        .m_axi_awready   (m_axi_awready),
        .m_axi_wdata     (up_m_wdata),
        .m_axi_wstrb     (up_m_wstrb),
        .m_axi_wlast     (up_m_wlast),
        .m_axi_wvalid    (up_m_wvalid),
        .m_axi_wready    (m_axi_wready),
        .m_axi_bid       (m_axi_bid),
        .m_axi_bresp     (m_axi_bresp),
        .m_axi_bvalid    (m_axi_bvalid),
        .m_axi_bready    (up_m_bready),
        .m_axi_arid      (up_m_arid),
        .m_axi_araddr    (up_m_araddr),
        .m_axi_arlen     (up_m_arlen),
        .m_axi_arsize    (up_m_arsize),
        .m_axi_arburst   (up_m_arburst),
        .m_axi_arvalid   (up_m_arvalid),
        .m_axi_arready   (m_axi_arready),
        .m_axi_rid       (m_axi_rid),
        .m_axi_rdata     (m_axi_rdata),
        .m_axi_rresp     (m_axi_rresp),
        .m_axi_rlast     (m_axi_rlast),
        .m_axi_rvalid    (m_axi_rvalid),
        .m_axi_rready    (up_m_rready)
    );

    // Downsizer wires
    wire                    dn_s_awready, dn_s_wready, dn_s_arready;
    wire [ID_WIDTH-1:0]     dn_s_bid, dn_s_rid;
    wire [1:0]              dn_s_bresp, dn_s_rresp;
    wire                    dn_s_bvalid, dn_s_rvalid, dn_s_rlast;
    wire [WIDE_WIDTH-1:0]   dn_s_rdata;

    wire [ID_WIDTH-1:0]     dn_m_awid, dn_m_arid;
    wire [ADDR_WIDTH-1:0]   dn_m_awaddr, dn_m_araddr;
    wire [7:0]              dn_m_awlen, dn_m_arlen;
    wire [2:0]              dn_m_awsize, dn_m_arsize;
    wire [1:0]              dn_m_awburst, dn_m_arburst;
    wire                    dn_m_awvalid, dn_m_arvalid;
    wire [NARROW_WIDTH-1:0] dn_m_wdata;
    wire [NARROW_WIDTH/8-1:0] dn_m_wstrb;
    wire                    dn_m_wlast, dn_m_wvalid;
    wire                    dn_m_bready, dn_m_rready;

    axi_downsizer #(
        .NARROW_WIDTH (NARROW_WIDTH),
        .WIDE_WIDTH   (WIDE_WIDTH),
        .ADDR_WIDTH   (ADDR_WIDTH),
        .ID_WIDTH     (ID_WIDTH)
    ) u_downsizer (
        .clk             (clk),
        .rst_n           (rst_n),
        .s_axi_awid      (s_axi_awid),
        .s_axi_awaddr    (s_axi_awaddr),
        .s_axi_awlen     (s_axi_awlen),
        .s_axi_awsize    (s_axi_awsize),
        .s_axi_awburst   (s_axi_awburst),
        .s_axi_awvalid   (downsize ? s_axi_awvalid : 1'b0),
        .s_axi_awready   (dn_s_awready),
        .s_axi_wdata     (s_axi_wdata),
        .s_axi_wstrb     (s_axi_wstrb),
        .s_axi_wlast     (s_axi_wlast),
        .s_axi_wvalid    (downsize ? s_axi_wvalid : 1'b0),
        .s_axi_wready    (dn_s_wready),
        .s_axi_bid       (dn_s_bid),
        .s_axi_bresp     (dn_s_bresp),
        .s_axi_bvalid    (dn_s_bvalid),
        .s_axi_bready    (s_axi_bready),
        .s_axi_arid      (s_axi_arid),
        .s_axi_araddr    (s_axi_araddr),
        .s_axi_arlen     (s_axi_arlen),
        .s_axi_arsize    (s_axi_arsize),
        .s_axi_arburst   (s_axi_arburst),
        .s_axi_arvalid   (downsize ? s_axi_arvalid : 1'b0),
        .s_axi_arready   (dn_s_arready),
        .s_axi_rid       (dn_s_rid),
        .s_axi_rdata     (dn_s_rdata),
        .s_axi_rresp     (dn_s_rresp),
        .s_axi_rlast     (dn_s_rlast),
        .s_axi_rvalid    (dn_s_rvalid),
        .s_axi_rready    (s_axi_rready),
        .m_axi_awid      (dn_m_awid),
        .m_axi_awaddr    (dn_m_awaddr),
        .m_axi_awlen     (dn_m_awlen),
        .m_axi_awsize    (dn_m_awsize),
        .m_axi_awburst   (dn_m_awburst),
        .m_axi_awvalid   (dn_m_awvalid),
        .m_axi_awready   (m_axi_awready),
        .m_axi_wdata     (dn_m_wdata),
        .m_axi_wstrb     (dn_m_wstrb),
        .m_axi_wlast     (dn_m_wlast),
        .m_axi_wvalid    (dn_m_wvalid),
        .m_axi_wready    (m_axi_wready),
        .m_axi_bid       (m_axi_bid),
        .m_axi_bresp     (m_axi_bresp),
        .m_axi_bvalid    (m_axi_bvalid),
        .m_axi_bready    (dn_m_bready),
        .m_axi_arid      (dn_m_arid),
        .m_axi_araddr    (dn_m_araddr),
        .m_axi_arlen     (dn_m_arlen),
        .m_axi_arsize    (dn_m_arsize),
        .m_axi_arburst   (dn_m_arburst),
        .m_axi_arvalid   (dn_m_arvalid),
        .m_axi_arready   (m_axi_arready),
        .m_axi_rid       (m_axi_rid),
        .m_axi_rdata     (m_axi_rdata[NARROW_WIDTH-1:0]),
        .m_axi_rresp     (m_axi_rresp),
        .m_axi_rlast     (m_axi_rlast),
        .m_axi_rvalid    (m_axi_rvalid),
        .m_axi_rready    (dn_m_rready)
    );

    // Output muxing
    // AW
    assign m_axi_awid    = passthrough ? s_axi_awid    : (upsize ? up_m_awid    : dn_m_awid);
    assign m_axi_awaddr  = passthrough ? s_axi_awaddr  : (upsize ? up_m_awaddr  : dn_m_awaddr);
    assign m_axi_awlen   = passthrough ? s_axi_awlen   : (upsize ? up_m_awlen   : dn_m_awlen);
    assign m_axi_awsize  = passthrough ? s_axi_awsize  : (upsize ? up_m_awsize  : dn_m_awsize);
    assign m_axi_awburst = passthrough ? s_axi_awburst : (upsize ? up_m_awburst : dn_m_awburst);
    assign m_axi_awvalid = passthrough ? s_axi_awvalid : (upsize ? up_m_awvalid : dn_m_awvalid);
    assign s_axi_awready = passthrough ? m_axi_awready : (upsize ? up_s_awready : dn_s_awready);

    // W
    assign m_axi_wdata   = passthrough ? s_axi_wdata   : (upsize ? up_m_wdata   : {{(WIDE_WIDTH-NARROW_WIDTH){1'b0}}, dn_m_wdata});
    assign m_axi_wstrb   = passthrough ? s_axi_wstrb   : (upsize ? up_m_wstrb   : {{(WIDE_WIDTH/8-NARROW_WIDTH/8){1'b0}}, dn_m_wstrb});
    assign m_axi_wlast   = passthrough ? s_axi_wlast   : (upsize ? up_m_wlast   : dn_m_wlast);
    assign m_axi_wvalid  = passthrough ? s_axi_wvalid  : (upsize ? up_m_wvalid  : dn_m_wvalid);
    assign s_axi_wready  = passthrough ? m_axi_wready  : (upsize ? up_s_wready  : dn_s_wready);

    // B
    assign s_axi_bid     = passthrough ? m_axi_bid     : (upsize ? up_s_bid     : dn_s_bid);
    assign s_axi_bresp   = passthrough ? m_axi_bresp   : (upsize ? up_s_bresp   : dn_s_bresp);
    assign s_axi_bvalid  = passthrough ? m_axi_bvalid  : (upsize ? up_s_bvalid  : dn_s_bvalid);
    assign m_axi_bready  = passthrough ? s_axi_bready  : (upsize ? up_m_bready  : dn_m_bready);

    // AR
    assign m_axi_arid    = passthrough ? s_axi_arid    : (upsize ? up_m_arid    : dn_m_arid);
    assign m_axi_araddr  = passthrough ? s_axi_araddr  : (upsize ? up_m_araddr  : dn_m_araddr);
    assign m_axi_arlen   = passthrough ? s_axi_arlen   : (upsize ? up_m_arlen   : dn_m_arlen);
    assign m_axi_arsize  = passthrough ? s_axi_arsize  : (upsize ? up_m_arsize  : dn_m_arsize);
    assign m_axi_arburst = passthrough ? s_axi_arburst : (upsize ? up_m_arburst : dn_m_arburst);
    assign m_axi_arvalid = passthrough ? s_axi_arvalid : (upsize ? up_m_arvalid : dn_m_arvalid);
    assign s_axi_arready = passthrough ? m_axi_arready : (upsize ? up_s_arready : dn_s_arready);

    // R
    assign s_axi_rid     = passthrough ? m_axi_rid     : (upsize ? up_s_rid     : dn_s_rid);
    assign s_axi_rdata   = passthrough ? m_axi_rdata   : (upsize ? {{(WIDE_WIDTH-NARROW_WIDTH){1'b0}}, up_s_rdata} : dn_s_rdata);
    assign s_axi_rresp   = passthrough ? m_axi_rresp   : (upsize ? up_s_rresp   : dn_s_rresp);
    assign s_axi_rlast   = passthrough ? m_axi_rlast   : (upsize ? up_s_rlast   : dn_s_rlast);
    assign s_axi_rvalid  = passthrough ? m_axi_rvalid  : (upsize ? up_s_rvalid  : dn_s_rvalid);
    assign m_axi_rready  = passthrough ? s_axi_rready  : (upsize ? up_m_rready  : dn_m_rready);

endmodule
