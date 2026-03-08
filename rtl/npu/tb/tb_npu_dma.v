`timescale 1ns/1ps
//============================================================================
// Testbench: tb_npu_dma
// Basic integration test for DMA top module
//============================================================================

module tb_npu_dma;

    reg         clk;
    reg         rst_n;

    // Weight control
    reg         weight_start;
    reg  [31:0] weight_src_addr;
    reg  [31:0] weight_xfer_len;
    wire        weight_done;

    // Act control
    reg         act_start;
    reg  [31:0] act_src_addr;
    reg  [31:0] act_dst_addr;
    reg  [31:0] act_xfer_len;
    reg         act_direction;
    wire        act_done;

    // Buffer interfaces
    wire        wbuf_we;
    wire [14:0] wbuf_addr;
    wire [31:0] wbuf_wdata;
    wire        abuf_we;
    wire [14:0] abuf_waddr;
    wire [31:0] abuf_wdata;
    wire        abuf_re;
    wire [14:0] abuf_raddr;
    reg  [31:0] abuf_rdata;

    // AXI4 master
    wire [3:0]   m_axi_awid;
    wire [31:0]  m_axi_awaddr;
    wire [7:0]   m_axi_awlen;
    wire [2:0]   m_axi_awsize;
    wire [1:0]   m_axi_awburst;
    wire [3:0]   m_axi_awqos;
    wire         m_axi_awvalid;
    reg          m_axi_awready;
    wire [127:0] m_axi_wdata;
    wire [15:0]  m_axi_wstrb;
    wire         m_axi_wlast;
    wire         m_axi_wvalid;
    reg          m_axi_wready;
    reg  [3:0]   m_axi_bid;
    reg  [1:0]   m_axi_bresp;
    reg          m_axi_bvalid;
    wire         m_axi_bready;
    wire [3:0]   m_axi_arid;
    wire [31:0]  m_axi_araddr;
    wire [7:0]   m_axi_arlen;
    wire [2:0]   m_axi_arsize;
    wire [1:0]   m_axi_arburst;
    wire [3:0]   m_axi_arqos;
    wire         m_axi_arvalid;
    reg          m_axi_arready;
    reg  [3:0]   m_axi_rid;
    reg  [127:0] m_axi_rdata;
    reg  [1:0]   m_axi_rresp;
    reg          m_axi_rlast;
    reg          m_axi_rvalid;
    wire         m_axi_rready;

    initial clk = 0;
    always #5 clk = ~clk;

    npu_dma dut (
        .clk(clk), .rst_n(rst_n),
        .weight_start(weight_start), .weight_src_addr(weight_src_addr),
        .weight_xfer_len(weight_xfer_len), .weight_done(weight_done),
        .act_start(act_start), .act_src_addr(act_src_addr),
        .act_dst_addr(act_dst_addr), .act_xfer_len(act_xfer_len),
        .act_direction(act_direction), .act_done(act_done),
        .wbuf_we(wbuf_we), .wbuf_addr(wbuf_addr), .wbuf_wdata(wbuf_wdata),
        .abuf_we(abuf_we), .abuf_waddr(abuf_waddr), .abuf_wdata(abuf_wdata),
        .abuf_re(abuf_re), .abuf_raddr(abuf_raddr), .abuf_rdata(abuf_rdata),
        .m_axi_awid(m_axi_awid), .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen), .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst), .m_axi_awqos(m_axi_awqos),
        .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bid(m_axi_bid), .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready),
        .m_axi_arid(m_axi_arid), .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen), .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst), .m_axi_arqos(m_axi_arqos),
        .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rid(m_axi_rid), .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp), .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid), .m_axi_rready(m_axi_rready)
    );

    initial begin
        rst_n = 0;
        weight_start = 0; weight_src_addr = 0; weight_xfer_len = 0;
        act_start = 0; act_src_addr = 0; act_dst_addr = 0;
        act_xfer_len = 0; act_direction = 0; abuf_rdata = 0;
        m_axi_awready = 0; m_axi_wready = 0;
        m_axi_bid = 0; m_axi_bresp = 0; m_axi_bvalid = 0;
        m_axi_arready = 0; m_axi_rid = 0; m_axi_rdata = 0;
        m_axi_rresp = 0; m_axi_rlast = 0; m_axi_rvalid = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Verify AXI ID and QoS
        $display("AXI ID prefix check (expect 4'b0100): awid=%b, arid=%b", m_axi_awid, m_axi_arid);
        $display("AXI QoS check (expect 4'hF): awqos=%h, arqos=%h", m_axi_awqos, m_axi_arqos);

        repeat (10) @(posedge clk);
        $display("========================================");
        $display("tb_npu_dma: stub test complete");
        $display("========================================");
        $finish;
    end

endmodule
