`timescale 1ns/1ps
//============================================================================
// npu_dma.v
// DMA top — instantiates weight and activation DMA channels,
// arbitrates the AXI4 master port (priority to weight channel on AR).
// Verilog-2005, active-low synchronous reset.
//============================================================================

module npu_dma (
    // Clock / reset
    input  wire         clk,
    input  wire         rst_n,

    // ---------------------------------------------------------------
    // Control interface (from NPU controller)
    // ---------------------------------------------------------------
    // Weight channel control
    input  wire         weight_start,
    input  wire [31:0]  weight_src_addr,
    input  wire [31:0]  weight_xfer_len,
    output wire         weight_done,

    // Activation channel control
    input  wire         act_start,
    input  wire [31:0]  act_src_addr,
    input  wire [31:0]  act_dst_addr,
    input  wire [31:0]  act_xfer_len,
    input  wire         act_direction,
    output wire         act_done,

    // ---------------------------------------------------------------
    // Buffer interfaces
    // ---------------------------------------------------------------
    // Weight buffer write
    output wire         wbuf_we,
    output wire [14:0]  wbuf_addr,
    output wire [31:0]  wbuf_wdata,

    // Activation buffer write (DMA -> buffer)
    output wire         abuf_we,
    output wire [14:0]  abuf_waddr,
    output wire [31:0]  abuf_wdata,

    // Activation buffer read (buffer -> DMA)
    output wire         abuf_re,
    output wire [14:0]  abuf_raddr,
    input  wire [31:0]  abuf_rdata,

    // ---------------------------------------------------------------
    // AXI4 master interface (128-bit, external)
    // ---------------------------------------------------------------
    // Write address channel
    output reg  [ 3:0]  m_axi_awid,
    output reg  [31:0]  m_axi_awaddr,
    output reg  [ 7:0]  m_axi_awlen,
    output reg  [ 2:0]  m_axi_awsize,
    output reg  [ 1:0]  m_axi_awburst,
    output reg  [ 3:0]  m_axi_awqos,
    output reg          m_axi_awvalid,
    input  wire         m_axi_awready,

    // Write data channel
    output reg  [127:0] m_axi_wdata,
    output reg  [ 15:0] m_axi_wstrb,
    output reg          m_axi_wlast,
    output reg          m_axi_wvalid,
    input  wire         m_axi_wready,

    // Write response channel
    input  wire [ 3:0]  m_axi_bid,
    input  wire [ 1:0]  m_axi_bresp,
    input  wire         m_axi_bvalid,
    output reg          m_axi_bready,

    // Read address channel
    output reg  [ 3:0]  m_axi_arid,
    output reg  [31:0]  m_axi_araddr,
    output reg  [ 7:0]  m_axi_arlen,
    output reg  [ 2:0]  m_axi_arsize,
    output reg  [ 1:0]  m_axi_arburst,
    output reg  [ 3:0]  m_axi_arqos,
    output reg          m_axi_arvalid,
    input  wire         m_axi_arready,

    // Read data channel
    input  wire [ 3:0]  m_axi_rid,
    input  wire [127:0] m_axi_rdata,
    input  wire [ 1:0]  m_axi_rresp,
    input  wire         m_axi_rlast,
    input  wire         m_axi_rvalid,
    output reg          m_axi_rready
);

    // ---------------------------------------------------------------
    // Internal wires — weight channel AXI
    // ---------------------------------------------------------------
    wire [31:0]  wch_araddr;
    wire [ 7:0]  wch_arlen;
    wire [ 2:0]  wch_arsize;
    wire [ 1:0]  wch_arburst;
    wire         wch_arvalid;
    reg          wch_arready;

    wire [127:0] wch_rdata;
    wire [ 1:0]  wch_rresp;
    wire         wch_rlast;
    wire         wch_rvalid;
    wire         wch_rready;

    // ---------------------------------------------------------------
    // Internal wires — activation channel AXI
    // ---------------------------------------------------------------
    // AR
    wire [31:0]  ach_araddr;
    wire [ 7:0]  ach_arlen;
    wire [ 2:0]  ach_arsize;
    wire [ 1:0]  ach_arburst;
    wire         ach_arvalid;
    reg          ach_arready;

    // R
    wire [127:0] ach_rdata;
    wire [ 1:0]  ach_rresp;
    wire         ach_rlast;
    wire         ach_rvalid;
    wire         ach_rready;

    // AW
    wire [31:0]  ach_awaddr;
    wire [ 7:0]  ach_awlen;
    wire [ 2:0]  ach_awsize;
    wire [ 1:0]  ach_awburst;
    wire         ach_awvalid;
    wire         ach_awready;

    // W
    wire [127:0] ach_wdata;
    wire [ 15:0] ach_wstrb;
    wire         ach_wlast;
    wire         ach_wvalid;
    wire         ach_wready;

    // B
    wire [ 1:0]  ach_bresp;
    wire         ach_bvalid;
    wire         ach_bready;

    // ---------------------------------------------------------------
    // Weight DMA channel instance
    // ---------------------------------------------------------------
    dma_weight_ch u_weight_ch (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (weight_start),
        .src_addr       (weight_src_addr),
        .xfer_len       (weight_xfer_len),
        .done           (weight_done),
        .buf_we         (wbuf_we),
        .buf_addr       (wbuf_addr),
        .buf_wdata      (wbuf_wdata),
        .m_axi_araddr   (wch_araddr),
        .m_axi_arlen    (wch_arlen),
        .m_axi_arsize   (wch_arsize),
        .m_axi_arburst  (wch_arburst),
        .m_axi_arvalid  (wch_arvalid),
        .m_axi_arready  (wch_arready),
        .m_axi_rdata    (wch_rdata),
        .m_axi_rresp    (wch_rresp),
        .m_axi_rlast    (wch_rlast),
        .m_axi_rvalid   (wch_rvalid),
        .m_axi_rready   (wch_rready)
    );

    // ---------------------------------------------------------------
    // Activation DMA channel instance
    // ---------------------------------------------------------------
    dma_act_ch u_act_ch (
        .clk            (clk),
        .rst_n          (rst_n),
        .start          (act_start),
        .direction      (act_direction),
        .src_addr       (act_src_addr),
        .dst_addr       (act_dst_addr),
        .xfer_len       (act_xfer_len),
        .done           (act_done),
        .buf_we         (abuf_we),
        .buf_addr       (abuf_waddr),
        .buf_wdata      (abuf_wdata),
        .buf_re         (abuf_re),
        .buf_raddr      (abuf_raddr),
        .buf_rdata      (abuf_rdata),
        .m_axi_araddr   (ach_araddr),
        .m_axi_arlen    (ach_arlen),
        .m_axi_arsize   (ach_arsize),
        .m_axi_arburst  (ach_arburst),
        .m_axi_arvalid  (ach_arvalid),
        .m_axi_arready  (ach_arready),
        .m_axi_rdata    (ach_rdata),
        .m_axi_rresp    (ach_rresp),
        .m_axi_rlast    (ach_rlast),
        .m_axi_rvalid   (ach_rvalid),
        .m_axi_rready   (ach_rready),
        .m_axi_awaddr   (ach_awaddr),
        .m_axi_awlen    (ach_awlen),
        .m_axi_awsize   (ach_awsize),
        .m_axi_awburst  (ach_awburst),
        .m_axi_awvalid  (ach_awvalid),
        .m_axi_awready  (ach_awready),
        .m_axi_wdata    (ach_wdata),
        .m_axi_wstrb    (ach_wstrb),
        .m_axi_wlast    (ach_wlast),
        .m_axi_wvalid   (ach_wvalid),
        .m_axi_wready   (ach_wready),
        .m_axi_bresp    (ach_bresp),
        .m_axi_bvalid   (ach_bvalid),
        .m_axi_bready   (ach_bready)
    );

    // ---------------------------------------------------------------
    // AXI read arbitration — weight channel has priority
    // ---------------------------------------------------------------
    // Track which channel is currently granted the read bus.
    // ar_grant_weight_r is latched when the arbiter FORWARDS a request
    // (not when the external handshake completes, since the sub-channel
    // deasserts its arvalid before the registered external handshake fires).
    reg ar_grant_weight_r;  // 1 = weight channel owns read bus

    // Latch the grant when we register a new AR transaction.
    // Hold the grant until the read burst completes (rlast accepted).
    reg ar_burst_active;  // 1 = a read burst is in progress

    always @(posedge clk) begin
        if (!rst_n) begin
            ar_grant_weight_r <= 1'b0;
            ar_burst_active   <= 1'b0;
        end else begin
            // When rlast is accepted, burst is complete
            if (m_axi_rvalid && m_axi_rready && m_axi_rlast) begin
                ar_burst_active <= 1'b0;
            end

            // Only update grant when no burst is active
            if (!ar_burst_active) begin
                if (wch_arvalid) begin
                    ar_grant_weight_r <= 1'b1;
                    ar_burst_active   <= 1'b1;
                end else if (ach_arvalid) begin
                    ar_grant_weight_r <= 1'b0;
                    ar_burst_active   <= 1'b1;
                end
            end
        end
    end

    // AR mux: weight has priority
    always @(posedge clk) begin
        if (!rst_n) begin
            m_axi_arid    <= 4'b0100;
            m_axi_araddr  <= 32'd0;
            m_axi_arlen   <= 8'd0;
            m_axi_arsize  <= 3'd0;
            m_axi_arburst <= 2'd0;
            m_axi_arqos   <= 4'hF;
            m_axi_arvalid <= 1'b0;
        end else begin
            if (m_axi_arvalid && m_axi_arready) begin
                // Handshake complete — check for new request
                if (wch_arvalid) begin
                    m_axi_araddr  <= wch_araddr;
                    m_axi_arlen   <= wch_arlen;
                    m_axi_arsize  <= wch_arsize;
                    m_axi_arburst <= wch_arburst;
                    m_axi_arvalid <= 1'b1;
                end else if (ach_arvalid) begin
                    m_axi_araddr  <= ach_araddr;
                    m_axi_arlen   <= ach_arlen;
                    m_axi_arsize  <= ach_arsize;
                    m_axi_arburst <= ach_arburst;
                    m_axi_arvalid <= 1'b1;
                end else begin
                    m_axi_arvalid <= 1'b0;
                end
            end else if (!m_axi_arvalid) begin
                // Not currently driving — check for new request
                if (wch_arvalid) begin
                    m_axi_araddr  <= wch_araddr;
                    m_axi_arlen   <= wch_arlen;
                    m_axi_arsize  <= wch_arsize;
                    m_axi_arburst <= wch_arburst;
                    m_axi_arvalid <= 1'b1;
                end else if (ach_arvalid) begin
                    m_axi_araddr  <= ach_araddr;
                    m_axi_arlen   <= ach_arlen;
                    m_axi_arsize  <= ach_arsize;
                    m_axi_arburst <= ach_arburst;
                    m_axi_arvalid <= 1'b1;
                end
            end
            // Hold arvalid high until external handshake completes
            m_axi_arid  <= 4'b0100;
            m_axi_arqos <= 4'hF;
        end
    end

    // AR ready back to channels — only assert when external handshake completes
    always @(*) begin
        wch_arready = 1'b0;
        ach_arready = 1'b0;
        if (m_axi_arvalid && m_axi_arready) begin
            if (ar_grant_weight_r)
                wch_arready = 1'b1;
            else
                ach_arready = 1'b1;
        end
    end

    // R channel — route responses back based on grant
    assign wch_rdata  = m_axi_rdata;
    assign wch_rresp  = m_axi_rresp;
    assign wch_rlast  = m_axi_rlast;
    assign wch_rvalid = ar_grant_weight_r ? m_axi_rvalid : 1'b0;

    assign ach_rdata  = m_axi_rdata;
    assign ach_rresp  = m_axi_rresp;
    assign ach_rlast  = m_axi_rlast;
    assign ach_rvalid = ar_grant_weight_r ? 1'b0 : m_axi_rvalid;

    // R ready — combinational OR of both channels (only one will be active)
    always @(*) begin
        m_axi_rready = wch_rready | ach_rready;
    end

    // ---------------------------------------------------------------
    // AXI write path — only act channel writes, no arbitration needed
    // ---------------------------------------------------------------
    assign ach_awready = m_axi_awready;
    assign ach_wready  = m_axi_wready;
    assign ach_bresp   = m_axi_bresp;
    assign ach_bvalid  = m_axi_bvalid;

    always @(posedge clk) begin
        if (!rst_n) begin
            m_axi_awid    <= 4'b0100;
            m_axi_awaddr  <= 32'd0;
            m_axi_awlen   <= 8'd0;
            m_axi_awsize  <= 3'd0;
            m_axi_awburst <= 2'd0;
            m_axi_awqos   <= 4'hF;
            m_axi_awvalid <= 1'b0;
            m_axi_wdata   <= 128'd0;
            m_axi_wstrb   <= 16'd0;
            m_axi_wlast   <= 1'b0;
            m_axi_wvalid  <= 1'b0;
            m_axi_bready  <= 1'b0;
        end else begin
            m_axi_awid    <= 4'b0100;
            m_axi_awqos   <= 4'hF;
            m_axi_awaddr  <= ach_awaddr;
            m_axi_awlen   <= ach_awlen;
            m_axi_awsize  <= ach_awsize;
            m_axi_awburst <= ach_awburst;
            m_axi_awvalid <= ach_awvalid;
            m_axi_wdata   <= ach_wdata;
            m_axi_wstrb   <= ach_wstrb;
            m_axi_wlast   <= ach_wlast;
            m_axi_wvalid  <= ach_wvalid;
            m_axi_bready  <= ach_bready;
        end
    end

endmodule
