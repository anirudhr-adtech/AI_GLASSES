`timescale 1ns/1ps
//============================================================================
// Module:      axi_slave_port
// Project:     AI_GLASSES — AXI Interconnect
// Description: Per-slave port: arbiter + wr_mux + rd_mux + resp_demux.
//              One instance per slave in the crossbar.
//============================================================================

module axi_slave_port #(
    parameter NUM_MASTERS  = 5,
    parameter DATA_WIDTH   = 32,
    parameter ADDR_WIDTH   = 32,
    parameter ID_WIDTH     = 6,
    parameter STALL_LIMIT  = 32
)(
    input  wire                                clk,
    input  wire                                rst_n,

    // Per-master tier assignments (2 bits each, packed)
    input  wire [2*NUM_MASTERS-1:0]            tier_i,

    // Master-side AW (packed)
    input  wire [NUM_MASTERS*ID_WIDTH-1:0]     m_awid_i,
    input  wire [NUM_MASTERS*ADDR_WIDTH-1:0]   m_awaddr_i,
    input  wire [NUM_MASTERS*8-1:0]            m_awlen_i,
    input  wire [NUM_MASTERS*3-1:0]            m_awsize_i,
    input  wire [NUM_MASTERS*2-1:0]            m_awburst_i,
    input  wire [NUM_MASTERS-1:0]              m_awvalid_i,
    output wire [NUM_MASTERS-1:0]              m_awready_o,

    // Master-side W (packed)
    input  wire [NUM_MASTERS*DATA_WIDTH-1:0]   m_wdata_i,
    input  wire [NUM_MASTERS*(DATA_WIDTH/8)-1:0] m_wstrb_i,
    input  wire [NUM_MASTERS-1:0]              m_wlast_i,
    input  wire [NUM_MASTERS-1:0]              m_wvalid_i,
    output wire [NUM_MASTERS-1:0]              m_wready_o,

    // Master-side B (packed, back to masters)
    output wire [NUM_MASTERS*ID_WIDTH-1:0]     m_bid_o,
    output wire [NUM_MASTERS*2-1:0]            m_bresp_o,
    output wire [NUM_MASTERS-1:0]              m_bvalid_o,
    input  wire [NUM_MASTERS-1:0]              m_bready_i,

    // Master-side AR (packed)
    input  wire [NUM_MASTERS*ID_WIDTH-1:0]     m_arid_i,
    input  wire [NUM_MASTERS*ADDR_WIDTH-1:0]   m_araddr_i,
    input  wire [NUM_MASTERS*8-1:0]            m_arlen_i,
    input  wire [NUM_MASTERS*3-1:0]            m_arsize_i,
    input  wire [NUM_MASTERS*2-1:0]            m_arburst_i,
    input  wire [NUM_MASTERS-1:0]              m_arvalid_i,
    output wire [NUM_MASTERS-1:0]              m_arready_o,

    // Master-side R (packed, back to masters)
    output wire [NUM_MASTERS*ID_WIDTH-1:0]     m_rid_o,
    output wire [NUM_MASTERS*DATA_WIDTH-1:0]   m_rdata_o,
    output wire [NUM_MASTERS*2-1:0]            m_rresp_o,
    output wire [NUM_MASTERS-1:0]              m_rlast_o,
    output wire [NUM_MASTERS-1:0]              m_rvalid_o,
    input  wire [NUM_MASTERS-1:0]              m_rready_i,

    // Slave-side AXI (single, to actual slave)
    output wire [ID_WIDTH-1:0]                 s_awid_o,
    output wire [ADDR_WIDTH-1:0]               s_awaddr_o,
    output wire [7:0]                          s_awlen_o,
    output wire [2:0]                          s_awsize_o,
    output wire [1:0]                          s_awburst_o,
    output wire                                s_awvalid_o,
    input  wire                                s_awready_i,

    output wire [DATA_WIDTH-1:0]               s_wdata_o,
    output wire [(DATA_WIDTH/8)-1:0]           s_wstrb_o,
    output wire                                s_wlast_o,
    output wire                                s_wvalid_o,
    input  wire                                s_wready_i,

    input  wire [ID_WIDTH-1:0]                 s_bid_i,
    input  wire [1:0]                          s_bresp_i,
    input  wire                                s_bvalid_i,
    output wire                                s_bready_o,

    output wire [ID_WIDTH-1:0]                 s_arid_o,
    output wire [ADDR_WIDTH-1:0]               s_araddr_o,
    output wire [7:0]                          s_arlen_o,
    output wire [2:0]                          s_arsize_o,
    output wire [1:0]                          s_arburst_o,
    output wire                                s_arvalid_o,
    input  wire                                s_arready_i,

    input  wire [ID_WIDTH-1:0]                 s_rid_i,
    input  wire [DATA_WIDTH-1:0]               s_rdata_i,
    input  wire [1:0]                          s_rresp_i,
    input  wire                                s_rlast_i,
    input  wire                                s_rvalid_i,
    output wire                                s_rready_o
);

    // Arbiter request: master has valid AW or AR targeting this slave
    wire [NUM_MASTERS-1:0] arb_req;
    wire [NUM_MASTERS-1:0] arb_grant;
    wire [16*NUM_MASTERS-1:0] arb_stall;

    // Request = master has a pending AW or AR
    genvar g;
    generate
        for (g = 0; g < NUM_MASTERS; g = g + 1) begin : gen_req
            assign arb_req[g] = m_awvalid_i[g] | m_arvalid_i[g];
        end
    endgenerate

    // Lock: burst in progress (W data flowing without WLAST yet, or R data without RLAST)
    // Done: WLAST+B handshake or RLAST handshake
    reg lock_r;
    reg done_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            lock_r <= 1'b0;
            done_r <= 1'b0;
        end else begin
            done_r <= 1'b0;

            // Lock on AW handshake (burst started)
            if (s_awvalid_o && s_awready_i)
                lock_r <= 1'b1;
            if (s_arvalid_o && s_arready_i)
                lock_r <= 1'b1;

            // Unlock on B handshake (write complete)
            if (s_bvalid_i && s_bready_o) begin
                lock_r <= 1'b0;
                done_r <= 1'b1;
            end
            // Unlock on RLAST (read complete)
            if (s_rvalid_i && s_rready_o && s_rlast_i) begin
                lock_r <= 1'b0;
                done_r <= 1'b1;
            end
        end
    end

    axi_arbiter #(
        .NUM_MASTERS (NUM_MASTERS),
        .STALL_LIMIT (STALL_LIMIT)
    ) u_arbiter (
        .clk            (clk),
        .rst_n          (rst_n),
        .req_i          (arb_req),
        .tier_i         (tier_i),
        .lock_i         (lock_r),
        .done_i         (done_r),
        .grant_o        (arb_grant),
        .stall_count_o  (arb_stall)
    );

    axi_wr_mux #(
        .NUM_MASTERS (NUM_MASTERS),
        .DATA_WIDTH  (DATA_WIDTH),
        .ADDR_WIDTH  (ADDR_WIDTH),
        .ID_WIDTH    (ID_WIDTH)
    ) u_wr_mux (
        .clk          (clk),
        .rst_n        (rst_n),
        .grant_i      (arb_grant),
        .m_awid_i     (m_awid_i),
        .m_awaddr_i   (m_awaddr_i),
        .m_awlen_i    (m_awlen_i),
        .m_awsize_i   (m_awsize_i),
        .m_awburst_i  (m_awburst_i),
        .m_awvalid_i  (m_awvalid_i),
        .m_awready_o  (m_awready_o),
        .m_wdata_i    (m_wdata_i),
        .m_wstrb_i    (m_wstrb_i),
        .m_wlast_i    (m_wlast_i),
        .m_wvalid_i   (m_wvalid_i),
        .m_wready_o   (m_wready_o),
        .s_awid_o     (s_awid_o),
        .s_awaddr_o   (s_awaddr_o),
        .s_awlen_o    (s_awlen_o),
        .s_awsize_o   (s_awsize_o),
        .s_awburst_o  (s_awburst_o),
        .s_awvalid_o  (s_awvalid_o),
        .s_awready_i  (s_awready_i),
        .s_wdata_o    (s_wdata_o),
        .s_wstrb_o    (s_wstrb_o),
        .s_wlast_o    (s_wlast_o),
        .s_wvalid_o   (s_wvalid_o),
        .s_wready_i   (s_wready_i)
    );

    axi_rd_mux #(
        .NUM_MASTERS (NUM_MASTERS),
        .DATA_WIDTH  (DATA_WIDTH),
        .ADDR_WIDTH  (ADDR_WIDTH),
        .ID_WIDTH    (ID_WIDTH)
    ) u_rd_mux (
        .clk          (clk),
        .rst_n        (rst_n),
        .grant_i      (arb_grant),
        .m_arid_i     (m_arid_i),
        .m_araddr_i   (m_araddr_i),
        .m_arlen_i    (m_arlen_i),
        .m_arsize_i   (m_arsize_i),
        .m_arburst_i  (m_arburst_i),
        .m_arvalid_i  (m_arvalid_i),
        .m_arready_o  (m_arready_o),
        .s_arid_o     (s_arid_o),
        .s_araddr_o   (s_araddr_o),
        .s_arlen_o    (s_arlen_o),
        .s_arsize_o   (s_arsize_o),
        .s_arburst_o  (s_arburst_o),
        .s_arvalid_o  (s_arvalid_o),
        .s_arready_i  (s_arready_i)
    );

    // Response demux: route B and R responses back to correct master
    wire                                 demux_bready;
    wire                                 demux_rready;

    axi_resp_demux #(
        .NUM_MASTERS (NUM_MASTERS),
        .DATA_WIDTH  (DATA_WIDTH),
        .ID_WIDTH    (ID_WIDTH)
    ) u_resp_demux (
        .clk          (clk),
        .rst_n        (rst_n),
        .s_bid_i      (s_bid_i),
        .s_bresp_i    (s_bresp_i),
        .s_bvalid_i   (s_bvalid_i),
        .s_bready_o   (s_bready_o),
        .s_rid_i      (s_rid_i),
        .s_rdata_i    (s_rdata_i),
        .s_rresp_i    (s_rresp_i),
        .s_rlast_i    (s_rlast_i),
        .s_rvalid_i   (s_rvalid_i),
        .s_rready_o   (s_rready_o),
        .m_bid_o      (m_bid_o),
        .m_bresp_o    (m_bresp_o),
        .m_bvalid_o   (m_bvalid_o),
        .m_bready_i   (m_bready_i),
        .m_rid_o      (m_rid_o),
        .m_rdata_o    (m_rdata_o),
        .m_rresp_o    (m_rresp_o),
        .m_rlast_o    (m_rlast_o),
        .m_rvalid_o   (m_rvalid_o),
        .m_rready_i   (m_rready_i)
    );

endmodule
