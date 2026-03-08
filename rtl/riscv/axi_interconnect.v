`timescale 1ns/1ps
//============================================================================
// Module : axi_interconnect
// Project : AI_GLASSES — RISC-V Subsystem
// Description : AXI4 crossbar: 3 masters x 4 slaves. Shared bus with
//               round-robin arbiter. Single transaction at a time.
//               M0=iBus(RO), M1=dBus(R/W), M2=NPU DMA(R/W burst).
//============================================================================

module axi_interconnect #(
    parameter DATA_WIDTH  = 32,
    parameter ADDR_WIDTH  = 32,
    parameter ID_WIDTH    = 4,
    parameter NUM_MASTERS = 3,
    parameter NUM_SLAVES  = 4
)(
    input  wire        clk,
    input  wire        rst_n,

    // ================================================================
    // Slave port 0 (from master M0 — CPU iBus, read-only)
    // ================================================================
    // AR
    input  wire [ADDR_WIDTH-1:0]   s_axi_0_araddr,
    input  wire                    s_axi_0_arvalid,
    output wire                    s_axi_0_arready,
    input  wire [ID_WIDTH-1:0]     s_axi_0_arid,
    input  wire [7:0]              s_axi_0_arlen,
    input  wire [2:0]              s_axi_0_arsize,
    input  wire [1:0]              s_axi_0_arburst,
    // R
    output wire [DATA_WIDTH-1:0]   s_axi_0_rdata,
    output wire                    s_axi_0_rvalid,
    input  wire                    s_axi_0_rready,
    output wire [1:0]              s_axi_0_rresp,
    output wire [ID_WIDTH-1:0]     s_axi_0_rid,
    output wire                    s_axi_0_rlast,

    // ================================================================
    // Slave port 1 (from master M1 — CPU dBus, R/W)
    // ================================================================
    // AW
    input  wire [ADDR_WIDTH-1:0]   s_axi_1_awaddr,
    input  wire                    s_axi_1_awvalid,
    output wire                    s_axi_1_awready,
    input  wire [ID_WIDTH-1:0]     s_axi_1_awid,
    input  wire [7:0]              s_axi_1_awlen,
    input  wire [2:0]              s_axi_1_awsize,
    input  wire [1:0]              s_axi_1_awburst,
    // W
    input  wire [DATA_WIDTH-1:0]   s_axi_1_wdata,
    input  wire [DATA_WIDTH/8-1:0] s_axi_1_wstrb,
    input  wire                    s_axi_1_wvalid,
    input  wire                    s_axi_1_wlast,
    output wire                    s_axi_1_wready,
    // B
    output wire [ID_WIDTH-1:0]     s_axi_1_bid,
    output wire [1:0]              s_axi_1_bresp,
    output wire                    s_axi_1_bvalid,
    input  wire                    s_axi_1_bready,
    // AR
    input  wire [ADDR_WIDTH-1:0]   s_axi_1_araddr,
    input  wire                    s_axi_1_arvalid,
    output wire                    s_axi_1_arready,
    input  wire [ID_WIDTH-1:0]     s_axi_1_arid,
    input  wire [7:0]              s_axi_1_arlen,
    input  wire [2:0]              s_axi_1_arsize,
    input  wire [1:0]              s_axi_1_arburst,
    // R
    output wire [DATA_WIDTH-1:0]   s_axi_1_rdata,
    output wire                    s_axi_1_rvalid,
    input  wire                    s_axi_1_rready,
    output wire [1:0]              s_axi_1_rresp,
    output wire [ID_WIDTH-1:0]     s_axi_1_rid,
    output wire                    s_axi_1_rlast,

    // ================================================================
    // Slave port 2 (from master M2 — NPU DMA, R/W burst)
    // ================================================================
    // AW
    input  wire [ADDR_WIDTH-1:0]   s_axi_2_awaddr,
    input  wire                    s_axi_2_awvalid,
    output wire                    s_axi_2_awready,
    input  wire [ID_WIDTH-1:0]     s_axi_2_awid,
    input  wire [7:0]              s_axi_2_awlen,
    input  wire [2:0]              s_axi_2_awsize,
    input  wire [1:0]              s_axi_2_awburst,
    // W
    input  wire [DATA_WIDTH-1:0]   s_axi_2_wdata,
    input  wire [DATA_WIDTH/8-1:0] s_axi_2_wstrb,
    input  wire                    s_axi_2_wvalid,
    input  wire                    s_axi_2_wlast,
    output wire                    s_axi_2_wready,
    // B
    output wire [ID_WIDTH-1:0]     s_axi_2_bid,
    output wire [1:0]              s_axi_2_bresp,
    output wire                    s_axi_2_bvalid,
    input  wire                    s_axi_2_bready,
    // AR
    input  wire [ADDR_WIDTH-1:0]   s_axi_2_araddr,
    input  wire                    s_axi_2_arvalid,
    output wire                    s_axi_2_arready,
    input  wire [ID_WIDTH-1:0]     s_axi_2_arid,
    input  wire [7:0]              s_axi_2_arlen,
    input  wire [2:0]              s_axi_2_arsize,
    input  wire [1:0]              s_axi_2_arburst,
    // R
    output wire [DATA_WIDTH-1:0]   s_axi_2_rdata,
    output wire                    s_axi_2_rvalid,
    input  wire                    s_axi_2_rready,
    output wire [1:0]              s_axi_2_rresp,
    output wire [ID_WIDTH-1:0]     s_axi_2_rid,
    output wire                    s_axi_2_rlast,

    // ================================================================
    // Master port 0 (to slave S0 — Boot ROM)
    // ================================================================
    output wire [ADDR_WIDTH-1:0]   m_axi_0_awaddr,
    output wire                    m_axi_0_awvalid,
    input  wire                    m_axi_0_awready,
    output wire [ID_WIDTH-1:0]     m_axi_0_awid,
    output wire [7:0]              m_axi_0_awlen,
    output wire [2:0]              m_axi_0_awsize,
    output wire [1:0]              m_axi_0_awburst,
    output wire [DATA_WIDTH-1:0]   m_axi_0_wdata,
    output wire [DATA_WIDTH/8-1:0] m_axi_0_wstrb,
    output wire                    m_axi_0_wvalid,
    output wire                    m_axi_0_wlast,
    input  wire                    m_axi_0_wready,
    input  wire [ID_WIDTH-1:0]     m_axi_0_bid,
    input  wire [1:0]              m_axi_0_bresp,
    input  wire                    m_axi_0_bvalid,
    output wire                    m_axi_0_bready,
    output wire [ADDR_WIDTH-1:0]   m_axi_0_araddr,
    output wire                    m_axi_0_arvalid,
    input  wire                    m_axi_0_arready,
    output wire [ID_WIDTH-1:0]     m_axi_0_arid,
    output wire [7:0]              m_axi_0_arlen,
    output wire [2:0]              m_axi_0_arsize,
    output wire [1:0]              m_axi_0_arburst,
    input  wire [DATA_WIDTH-1:0]   m_axi_0_rdata,
    input  wire                    m_axi_0_rvalid,
    output wire                    m_axi_0_rready,
    input  wire [1:0]              m_axi_0_rresp,
    input  wire [ID_WIDTH-1:0]     m_axi_0_rid,
    input  wire                    m_axi_0_rlast,

    // ================================================================
    // Master port 1 (to slave S1 — SRAM)
    // ================================================================
    output wire [ADDR_WIDTH-1:0]   m_axi_1_awaddr,
    output wire                    m_axi_1_awvalid,
    input  wire                    m_axi_1_awready,
    output wire [ID_WIDTH-1:0]     m_axi_1_awid,
    output wire [7:0]              m_axi_1_awlen,
    output wire [2:0]              m_axi_1_awsize,
    output wire [1:0]              m_axi_1_awburst,
    output wire [DATA_WIDTH-1:0]   m_axi_1_wdata,
    output wire [DATA_WIDTH/8-1:0] m_axi_1_wstrb,
    output wire                    m_axi_1_wvalid,
    output wire                    m_axi_1_wlast,
    input  wire                    m_axi_1_wready,
    input  wire [ID_WIDTH-1:0]     m_axi_1_bid,
    input  wire [1:0]              m_axi_1_bresp,
    input  wire                    m_axi_1_bvalid,
    output wire                    m_axi_1_bready,
    output wire [ADDR_WIDTH-1:0]   m_axi_1_araddr,
    output wire                    m_axi_1_arvalid,
    input  wire                    m_axi_1_arready,
    output wire [ID_WIDTH-1:0]     m_axi_1_arid,
    output wire [7:0]              m_axi_1_arlen,
    output wire [2:0]              m_axi_1_arsize,
    output wire [1:0]              m_axi_1_arburst,
    input  wire [DATA_WIDTH-1:0]   m_axi_1_rdata,
    input  wire                    m_axi_1_rvalid,
    output wire                    m_axi_1_rready,
    input  wire [1:0]              m_axi_1_rresp,
    input  wire [ID_WIDTH-1:0]     m_axi_1_rid,
    input  wire                    m_axi_1_rlast,

    // ================================================================
    // Master port 2 (to slave S2 — Peripheral bridge)
    // ================================================================
    output wire [ADDR_WIDTH-1:0]   m_axi_2_awaddr,
    output wire                    m_axi_2_awvalid,
    input  wire                    m_axi_2_awready,
    output wire [ID_WIDTH-1:0]     m_axi_2_awid,
    output wire [7:0]              m_axi_2_awlen,
    output wire [2:0]              m_axi_2_awsize,
    output wire [1:0]              m_axi_2_awburst,
    output wire [DATA_WIDTH-1:0]   m_axi_2_wdata,
    output wire [DATA_WIDTH/8-1:0] m_axi_2_wstrb,
    output wire                    m_axi_2_wvalid,
    output wire                    m_axi_2_wlast,
    input  wire                    m_axi_2_wready,
    input  wire [ID_WIDTH-1:0]     m_axi_2_bid,
    input  wire [1:0]              m_axi_2_bresp,
    input  wire                    m_axi_2_bvalid,
    output wire                    m_axi_2_bready,
    output wire [ADDR_WIDTH-1:0]   m_axi_2_araddr,
    output wire                    m_axi_2_arvalid,
    input  wire                    m_axi_2_arready,
    output wire [ID_WIDTH-1:0]     m_axi_2_arid,
    output wire [7:0]              m_axi_2_arlen,
    output wire [2:0]              m_axi_2_arsize,
    output wire [1:0]              m_axi_2_arburst,
    input  wire [DATA_WIDTH-1:0]   m_axi_2_rdata,
    input  wire                    m_axi_2_rvalid,
    output wire                    m_axi_2_rready,
    input  wire [1:0]              m_axi_2_rresp,
    input  wire [ID_WIDTH-1:0]     m_axi_2_rid,
    input  wire                    m_axi_2_rlast,

    // ================================================================
    // Master port 3 (to slave S3 — DDR)
    // ================================================================
    output wire [ADDR_WIDTH-1:0]   m_axi_3_awaddr,
    output wire                    m_axi_3_awvalid,
    input  wire                    m_axi_3_awready,
    output wire [ID_WIDTH-1:0]     m_axi_3_awid,
    output wire [7:0]              m_axi_3_awlen,
    output wire [2:0]              m_axi_3_awsize,
    output wire [1:0]              m_axi_3_awburst,
    output wire [DATA_WIDTH-1:0]   m_axi_3_wdata,
    output wire [DATA_WIDTH/8-1:0] m_axi_3_wstrb,
    output wire                    m_axi_3_wvalid,
    output wire                    m_axi_3_wlast,
    input  wire                    m_axi_3_wready,
    input  wire [ID_WIDTH-1:0]     m_axi_3_bid,
    input  wire [1:0]              m_axi_3_bresp,
    input  wire                    m_axi_3_bvalid,
    output wire                    m_axi_3_bready,
    output wire [ADDR_WIDTH-1:0]   m_axi_3_araddr,
    output wire                    m_axi_3_arvalid,
    input  wire                    m_axi_3_arready,
    output wire [ID_WIDTH-1:0]     m_axi_3_arid,
    output wire [7:0]              m_axi_3_arlen,
    output wire [2:0]              m_axi_3_arsize,
    output wire [1:0]              m_axi_3_arburst,
    input  wire [DATA_WIDTH-1:0]   m_axi_3_rdata,
    input  wire                    m_axi_3_rvalid,
    output wire                    m_axi_3_rready,
    input  wire [1:0]              m_axi_3_rresp,
    input  wire [ID_WIDTH-1:0]     m_axi_3_rid,
    input  wire                    m_axi_3_rlast
);

    // ================================================================
    // FSM: Single transaction at a time shared bus
    // ================================================================
    localparam [2:0] ST_IDLE     = 3'd0,
                     ST_DECODE   = 3'd1,
                     ST_AR_FWD   = 3'd2,
                     ST_R_FWD    = 3'd3,
                     ST_AW_FWD   = 3'd4,
                     ST_W_FWD    = 3'd5,
                     ST_B_FWD    = 3'd6;

    reg [2:0]  state_r;
    reg [1:0]  cur_master_r;   // Which master won arbitration
    reg [1:0]  cur_slave_r;    // Which slave is target
    reg        cur_is_write_r; // Write transaction flag

    // Latched signals from winning master
    reg [ADDR_WIDTH-1:0]   lat_addr_r;
    reg [ID_WIDTH-1:0]     lat_id_r;
    reg [7:0]              lat_len_r;
    reg [2:0]              lat_size_r;
    reg [1:0]              lat_burst_r;

    // Arbiter signals
    wire [NUM_MASTERS-1:0] arb_req;
    wire [NUM_MASTERS-1:0] arb_grant;
    wire [1:0]             arb_last;
    reg                    arb_done;

    // Request: any master has a pending AR or AW
    assign arb_req[0] = s_axi_0_arvalid;
    assign arb_req[1] = s_axi_1_arvalid | s_axi_1_awvalid;
    assign arb_req[2] = s_axi_2_arvalid | s_axi_2_awvalid;

    riscv_axi_arbiter #(
        .NUM_MASTERS  (NUM_MASTERS),
        .STARVE_LIMIT (16)
    ) u_arbiter (
        .clk     (clk),
        .rst_n   (rst_n),
        .req_i   (arb_req),
        .done_i  (arb_done),
        .grant_o (arb_grant),
        .last_o  (arb_last)
    );

    // Address decoder (combinational use — we decode from latched addr)
    reg [1:0] decoded_slave;
    always @(*) begin
        case (lat_addr_r[31:28])
            4'h0:           decoded_slave = 2'd0;
            4'h1:           decoded_slave = 2'd1;
            4'h2, 4'h3, 4'h4:
                            decoded_slave = 2'd2;
            default:        decoded_slave = 2'd3;
        endcase
    end

    // ================================================================
    // Registered outputs to slave ports (master→slave direction)
    // ================================================================
    // Forward AR channel regs
    reg [ADDR_WIDTH-1:0]   fwd_araddr_r;
    reg                    fwd_arvalid_r  [0:NUM_SLAVES-1];
    reg [ID_WIDTH-1:0]     fwd_arid_r;
    reg [7:0]              fwd_arlen_r;
    reg [2:0]              fwd_arsize_r;
    reg [1:0]              fwd_arburst_r;

    // Forward AW channel regs
    reg [ADDR_WIDTH-1:0]   fwd_awaddr_r;
    reg                    fwd_awvalid_r  [0:NUM_SLAVES-1];
    reg [ID_WIDTH-1:0]     fwd_awid_r;
    reg [7:0]              fwd_awlen_r;
    reg [2:0]              fwd_awsize_r;
    reg [1:0]              fwd_awburst_r;

    // Forward W channel regs
    reg [DATA_WIDTH-1:0]   fwd_wdata_r;
    reg [DATA_WIDTH/8-1:0] fwd_wstrb_r;
    reg                    fwd_wvalid_r   [0:NUM_SLAVES-1];
    reg                    fwd_wlast_r;

    // Forward B ready
    reg                    fwd_bready_r   [0:NUM_SLAVES-1];

    // Forward R ready
    reg                    fwd_rready_r   [0:NUM_SLAVES-1];

    // ================================================================
    // Registered outputs to master ports (slave→master direction)
    // ================================================================
    // Response to M0
    reg [DATA_WIDTH-1:0]   m0_rdata_r;
    reg                    m0_rvalid_r;
    reg [1:0]              m0_rresp_r;
    reg [ID_WIDTH-1:0]     m0_rid_r;
    reg                    m0_rlast_r;
    reg                    m0_arready_r;

    // Response to M1
    reg [DATA_WIDTH-1:0]   m1_rdata_r;
    reg                    m1_rvalid_r;
    reg [1:0]              m1_rresp_r;
    reg [ID_WIDTH-1:0]     m1_rid_r;
    reg                    m1_rlast_r;
    reg                    m1_arready_r;
    reg                    m1_awready_r;
    reg                    m1_wready_r;
    reg [ID_WIDTH-1:0]     m1_bid_r;
    reg [1:0]              m1_bresp_r;
    reg                    m1_bvalid_r;

    // Response to M2
    reg [DATA_WIDTH-1:0]   m2_rdata_r;
    reg                    m2_rvalid_r;
    reg [1:0]              m2_rresp_r;
    reg [ID_WIDTH-1:0]     m2_rid_r;
    reg                    m2_rlast_r;
    reg                    m2_arready_r;
    reg                    m2_awready_r;
    reg                    m2_wready_r;
    reg [ID_WIDTH-1:0]     m2_bid_r;
    reg [1:0]              m2_bresp_r;
    reg                    m2_bvalid_r;

    // Slave-side ready mux wires
    wire [NUM_SLAVES-1:0] slv_arready;
    wire [NUM_SLAVES-1:0] slv_awready;
    wire [NUM_SLAVES-1:0] slv_wready;

    assign slv_arready = {m_axi_3_arready, m_axi_2_arready, m_axi_1_arready, m_axi_0_arready};
    assign slv_awready = {m_axi_3_awready, m_axi_2_awready, m_axi_1_awready, m_axi_0_awready};
    assign slv_wready  = {m_axi_3_wready,  m_axi_2_wready,  m_axi_1_wready,  m_axi_0_wready};

    // Slave-side response mux
    wire [DATA_WIDTH-1:0] slv_rdata  [0:NUM_SLAVES-1];
    wire                  slv_rvalid [0:NUM_SLAVES-1];
    wire [1:0]            slv_rresp  [0:NUM_SLAVES-1];
    wire [ID_WIDTH-1:0]   slv_rid    [0:NUM_SLAVES-1];
    wire                  slv_rlast  [0:NUM_SLAVES-1];
    wire [ID_WIDTH-1:0]   slv_bid    [0:NUM_SLAVES-1];
    wire [1:0]            slv_bresp  [0:NUM_SLAVES-1];
    wire                  slv_bvalid [0:NUM_SLAVES-1];

    assign slv_rdata[0]  = m_axi_0_rdata;   assign slv_rvalid[0] = m_axi_0_rvalid;
    assign slv_rresp[0]  = m_axi_0_rresp;   assign slv_rid[0]    = m_axi_0_rid;
    assign slv_rlast[0]  = m_axi_0_rlast;   assign slv_bid[0]    = m_axi_0_bid;
    assign slv_bresp[0]  = m_axi_0_bresp;   assign slv_bvalid[0] = m_axi_0_bvalid;

    assign slv_rdata[1]  = m_axi_1_rdata;   assign slv_rvalid[1] = m_axi_1_rvalid;
    assign slv_rresp[1]  = m_axi_1_rresp;   assign slv_rid[1]    = m_axi_1_rid;
    assign slv_rlast[1]  = m_axi_1_rlast;   assign slv_bid[1]    = m_axi_1_bid;
    assign slv_bresp[1]  = m_axi_1_bresp;   assign slv_bvalid[1] = m_axi_1_bvalid;

    assign slv_rdata[2]  = m_axi_2_rdata;   assign slv_rvalid[2] = m_axi_2_rvalid;
    assign slv_rresp[2]  = m_axi_2_rresp;   assign slv_rid[2]    = m_axi_2_rid;
    assign slv_rlast[2]  = m_axi_2_rlast;   assign slv_bid[2]    = m_axi_2_bid;
    assign slv_bresp[2]  = m_axi_2_bresp;   assign slv_bvalid[2] = m_axi_2_bvalid;

    assign slv_rdata[3]  = m_axi_3_rdata;   assign slv_rvalid[3] = m_axi_3_rvalid;
    assign slv_rresp[3]  = m_axi_3_rresp;   assign slv_rid[3]    = m_axi_3_rid;
    assign slv_rlast[3]  = m_axi_3_rlast;   assign slv_bid[3]    = m_axi_3_bid;
    assign slv_bresp[3]  = m_axi_3_bresp;   assign slv_bvalid[3] = m_axi_3_bvalid;

    // ================================================================
    // Main FSM
    // ================================================================
    integer fi;
    always @(posedge clk) begin
        if (!rst_n) begin
            state_r        <= ST_IDLE;
            cur_master_r   <= 2'd0;
            cur_slave_r    <= 2'd0;
            cur_is_write_r <= 1'b0;
            arb_done       <= 1'b0;
            lat_addr_r     <= {ADDR_WIDTH{1'b0}};
            lat_id_r       <= {ID_WIDTH{1'b0}};
            lat_len_r      <= 8'd0;
            lat_size_r     <= 3'd0;
            lat_burst_r    <= 2'd0;
            fwd_araddr_r   <= {ADDR_WIDTH{1'b0}};
            fwd_arid_r     <= {ID_WIDTH{1'b0}};
            fwd_arlen_r    <= 8'd0;
            fwd_arsize_r   <= 3'd0;
            fwd_arburst_r  <= 2'd0;
            fwd_awaddr_r   <= {ADDR_WIDTH{1'b0}};
            fwd_awid_r     <= {ID_WIDTH{1'b0}};
            fwd_awlen_r    <= 8'd0;
            fwd_awsize_r   <= 3'd0;
            fwd_awburst_r  <= 2'd0;
            fwd_wdata_r    <= {DATA_WIDTH{1'b0}};
            fwd_wstrb_r    <= {(DATA_WIDTH/8){1'b0}};
            fwd_wlast_r    <= 1'b0;
            m0_rdata_r     <= {DATA_WIDTH{1'b0}};
            m0_rvalid_r    <= 1'b0;
            m0_rresp_r     <= 2'b00;
            m0_rid_r       <= {ID_WIDTH{1'b0}};
            m0_rlast_r     <= 1'b0;
            m0_arready_r   <= 1'b0;
            m1_rdata_r     <= {DATA_WIDTH{1'b0}};
            m1_rvalid_r    <= 1'b0;
            m1_rresp_r     <= 2'b00;
            m1_rid_r       <= {ID_WIDTH{1'b0}};
            m1_rlast_r     <= 1'b0;
            m1_arready_r   <= 1'b0;
            m1_awready_r   <= 1'b0;
            m1_wready_r    <= 1'b0;
            m1_bid_r       <= {ID_WIDTH{1'b0}};
            m1_bresp_r     <= 2'b00;
            m1_bvalid_r    <= 1'b0;
            m2_rdata_r     <= {DATA_WIDTH{1'b0}};
            m2_rvalid_r    <= 1'b0;
            m2_rresp_r     <= 2'b00;
            m2_rid_r       <= {ID_WIDTH{1'b0}};
            m2_rlast_r     <= 1'b0;
            m2_arready_r   <= 1'b0;
            m2_awready_r   <= 1'b0;
            m2_wready_r    <= 1'b0;
            m2_bid_r       <= {ID_WIDTH{1'b0}};
            m2_bresp_r     <= 2'b00;
            m2_bvalid_r    <= 1'b0;
            for (fi = 0; fi < NUM_SLAVES; fi = fi + 1) begin
                fwd_arvalid_r[fi] <= 1'b0;
                fwd_awvalid_r[fi] <= 1'b0;
                fwd_wvalid_r[fi]  <= 1'b0;
                fwd_bready_r[fi]  <= 1'b0;
                fwd_rready_r[fi]  <= 1'b0;
            end
        end else begin
            // Default pulse deasserts
            arb_done     <= 1'b0;
            m0_arready_r <= 1'b0;
            m1_arready_r <= 1'b0;
            m1_awready_r <= 1'b0;
            m1_wready_r  <= 1'b0;
            m2_arready_r <= 1'b0;
            m2_awready_r <= 1'b0;
            m2_wready_r  <= 1'b0;

            // Clear response valids on handshake
            if (m0_rvalid_r && s_axi_0_rready) begin
                m0_rvalid_r <= 1'b0;
                m0_rlast_r  <= 1'b0;
            end
            if (m1_rvalid_r && s_axi_1_rready) begin
                m1_rvalid_r <= 1'b0;
                m1_rlast_r  <= 1'b0;
            end
            if (m1_bvalid_r && s_axi_1_bready) begin
                m1_bvalid_r <= 1'b0;
            end
            if (m2_rvalid_r && s_axi_2_rready) begin
                m2_rvalid_r <= 1'b0;
                m2_rlast_r  <= 1'b0;
            end
            if (m2_bvalid_r && s_axi_2_bready) begin
                m2_bvalid_r <= 1'b0;
            end

            case (state_r)
                ST_IDLE: begin
                    if (|arb_grant) begin
                        cur_master_r <= arb_last;
                        // Latch address/control from winning master
                        case (arb_last)
                            2'd0: begin
                                // M0: read-only
                                lat_addr_r     <= s_axi_0_araddr;
                                lat_id_r       <= s_axi_0_arid;
                                lat_len_r      <= s_axi_0_arlen;
                                lat_size_r     <= s_axi_0_arsize;
                                lat_burst_r    <= s_axi_0_arburst;
                                cur_is_write_r <= 1'b0;
                                m0_arready_r   <= 1'b1;
                            end
                            2'd1: begin
                                // M1: check if write first
                                if (s_axi_1_awvalid) begin
                                    lat_addr_r     <= s_axi_1_awaddr;
                                    lat_id_r       <= s_axi_1_awid;
                                    lat_len_r      <= s_axi_1_awlen;
                                    lat_size_r     <= s_axi_1_awsize;
                                    lat_burst_r    <= s_axi_1_awburst;
                                    cur_is_write_r <= 1'b1;
                                    m1_awready_r   <= 1'b1;
                                end else begin
                                    lat_addr_r     <= s_axi_1_araddr;
                                    lat_id_r       <= s_axi_1_arid;
                                    lat_len_r      <= s_axi_1_arlen;
                                    lat_size_r     <= s_axi_1_arsize;
                                    lat_burst_r    <= s_axi_1_arburst;
                                    cur_is_write_r <= 1'b0;
                                    m1_arready_r   <= 1'b1;
                                end
                            end
                            2'd2: begin
                                if (s_axi_2_awvalid) begin
                                    lat_addr_r     <= s_axi_2_awaddr;
                                    lat_id_r       <= s_axi_2_awid;
                                    lat_len_r      <= s_axi_2_awlen;
                                    lat_size_r     <= s_axi_2_awsize;
                                    lat_burst_r    <= s_axi_2_awburst;
                                    cur_is_write_r <= 1'b1;
                                    m2_awready_r   <= 1'b1;
                                end else begin
                                    lat_addr_r     <= s_axi_2_araddr;
                                    lat_id_r       <= s_axi_2_arid;
                                    lat_len_r      <= s_axi_2_arlen;
                                    lat_size_r     <= s_axi_2_arsize;
                                    lat_burst_r    <= s_axi_2_arburst;
                                    cur_is_write_r <= 1'b0;
                                    m2_arready_r   <= 1'b1;
                                end
                            end
                            default: ;
                        endcase
                        state_r <= ST_DECODE;
                    end
                end

                ST_DECODE: begin
                    cur_slave_r <= decoded_slave;
                    if (cur_is_write_r) begin
                        // Forward AW to target slave
                        fwd_awaddr_r                  <= lat_addr_r;
                        fwd_awid_r                    <= lat_id_r;
                        fwd_awlen_r                   <= lat_len_r;
                        fwd_awsize_r                  <= lat_size_r;
                        fwd_awburst_r                 <= lat_burst_r;
                        fwd_awvalid_r[decoded_slave]  <= 1'b1;
                        state_r <= ST_AW_FWD;
                    end else begin
                        fwd_araddr_r                  <= lat_addr_r;
                        fwd_arid_r                    <= lat_id_r;
                        fwd_arlen_r                   <= lat_len_r;
                        fwd_arsize_r                  <= lat_size_r;
                        fwd_arburst_r                 <= lat_burst_r;
                        fwd_arvalid_r[decoded_slave]  <= 1'b1;
                        state_r <= ST_AR_FWD;
                    end
                end

                ST_AR_FWD: begin
                    if (slv_arready[cur_slave_r] && fwd_arvalid_r[cur_slave_r]) begin
                        fwd_arvalid_r[cur_slave_r] <= 1'b0;
                        fwd_rready_r[cur_slave_r]  <= 1'b1;
                        state_r <= ST_R_FWD;
                    end
                end

                ST_R_FWD: begin
                    if (slv_rvalid[cur_slave_r]) begin
                        fwd_rready_r[cur_slave_r] <= 1'b0;
                        // Route response to correct master
                        case (cur_master_r)
                            2'd0: begin
                                m0_rdata_r  <= slv_rdata[cur_slave_r];
                                m0_rresp_r  <= slv_rresp[cur_slave_r];
                                m0_rid_r    <= slv_rid[cur_slave_r];
                                m0_rlast_r  <= slv_rlast[cur_slave_r];
                                m0_rvalid_r <= 1'b1;
                            end
                            2'd1: begin
                                m1_rdata_r  <= slv_rdata[cur_slave_r];
                                m1_rresp_r  <= slv_rresp[cur_slave_r];
                                m1_rid_r    <= slv_rid[cur_slave_r];
                                m1_rlast_r  <= slv_rlast[cur_slave_r];
                                m1_rvalid_r <= 1'b1;
                            end
                            2'd2: begin
                                m2_rdata_r  <= slv_rdata[cur_slave_r];
                                m2_rresp_r  <= slv_rresp[cur_slave_r];
                                m2_rid_r    <= slv_rid[cur_slave_r];
                                m2_rlast_r  <= slv_rlast[cur_slave_r];
                                m2_rvalid_r <= 1'b1;
                            end
                            default: ;
                        endcase
                        arb_done <= 1'b1;
                        state_r  <= ST_IDLE;
                    end
                end

                ST_AW_FWD: begin
                    if (slv_awready[cur_slave_r] && fwd_awvalid_r[cur_slave_r]) begin
                        fwd_awvalid_r[cur_slave_r] <= 1'b0;
                        state_r <= ST_W_FWD;
                    end
                end

                ST_W_FWD: begin
                    // Forward W data from master to slave
                    case (cur_master_r)
                        2'd1: begin
                            if (s_axi_1_wvalid) begin
                                fwd_wdata_r                 <= s_axi_1_wdata;
                                fwd_wstrb_r                 <= s_axi_1_wstrb;
                                fwd_wlast_r                 <= s_axi_1_wlast;
                                fwd_wvalid_r[cur_slave_r]   <= 1'b1;
                                m1_wready_r                 <= 1'b1;
                            end
                        end
                        2'd2: begin
                            if (s_axi_2_wvalid) begin
                                fwd_wdata_r                 <= s_axi_2_wdata;
                                fwd_wstrb_r                 <= s_axi_2_wstrb;
                                fwd_wlast_r                 <= s_axi_2_wlast;
                                fwd_wvalid_r[cur_slave_r]   <= 1'b1;
                                m2_wready_r                 <= 1'b1;
                            end
                        end
                        default: ;
                    endcase
                    if (fwd_wvalid_r[cur_slave_r] && slv_wready[cur_slave_r]) begin
                        fwd_wvalid_r[cur_slave_r] <= 1'b0;
                        fwd_bready_r[cur_slave_r] <= 1'b1;
                        state_r <= ST_B_FWD;
                    end
                end

                ST_B_FWD: begin
                    if (slv_bvalid[cur_slave_r]) begin
                        fwd_bready_r[cur_slave_r] <= 1'b0;
                        case (cur_master_r)
                            2'd1: begin
                                m1_bid_r    <= slv_bid[cur_slave_r];
                                m1_bresp_r  <= slv_bresp[cur_slave_r];
                                m1_bvalid_r <= 1'b1;
                            end
                            2'd2: begin
                                m2_bid_r    <= slv_bid[cur_slave_r];
                                m2_bresp_r  <= slv_bresp[cur_slave_r];
                                m2_bvalid_r <= 1'b1;
                            end
                            default: ;
                        endcase
                        arb_done <= 1'b1;
                        state_r  <= ST_IDLE;
                    end
                end

                default: state_r <= ST_IDLE;
            endcase
        end
    end

    // ================================================================
    // Output assignments — Slave port 0 (M0, read-only)
    // ================================================================
    assign s_axi_0_arready = m0_arready_r;
    assign s_axi_0_rdata   = m0_rdata_r;
    assign s_axi_0_rvalid  = m0_rvalid_r;
    assign s_axi_0_rresp   = m0_rresp_r;
    assign s_axi_0_rid     = m0_rid_r;
    assign s_axi_0_rlast   = m0_rlast_r;

    // ================================================================
    // Output assignments — Slave port 1 (M1, R/W)
    // ================================================================
    assign s_axi_1_awready = m1_awready_r;
    assign s_axi_1_wready  = m1_wready_r;
    assign s_axi_1_bid     = m1_bid_r;
    assign s_axi_1_bresp   = m1_bresp_r;
    assign s_axi_1_bvalid  = m1_bvalid_r;
    assign s_axi_1_arready = m1_arready_r;
    assign s_axi_1_rdata   = m1_rdata_r;
    assign s_axi_1_rvalid  = m1_rvalid_r;
    assign s_axi_1_rresp   = m1_rresp_r;
    assign s_axi_1_rid     = m1_rid_r;
    assign s_axi_1_rlast   = m1_rlast_r;

    // ================================================================
    // Output assignments — Slave port 2 (M2, R/W)
    // ================================================================
    assign s_axi_2_awready = m2_awready_r;
    assign s_axi_2_wready  = m2_wready_r;
    assign s_axi_2_bid     = m2_bid_r;
    assign s_axi_2_bresp   = m2_bresp_r;
    assign s_axi_2_bvalid  = m2_bvalid_r;
    assign s_axi_2_arready = m2_arready_r;
    assign s_axi_2_rdata   = m2_rdata_r;
    assign s_axi_2_rvalid  = m2_rvalid_r;
    assign s_axi_2_rresp   = m2_rresp_r;
    assign s_axi_2_rid     = m2_rid_r;
    assign s_axi_2_rlast   = m2_rlast_r;

    // ================================================================
    // Output assignments — Master port 0 (S0, Boot ROM)
    // ================================================================
    assign m_axi_0_araddr  = fwd_araddr_r;
    assign m_axi_0_arvalid = fwd_arvalid_r[0];
    assign m_axi_0_arid    = fwd_arid_r;
    assign m_axi_0_arlen   = fwd_arlen_r;
    assign m_axi_0_arsize  = fwd_arsize_r;
    assign m_axi_0_arburst = fwd_arburst_r;
    assign m_axi_0_rready  = fwd_rready_r[0];
    assign m_axi_0_awaddr  = fwd_awaddr_r;
    assign m_axi_0_awvalid = fwd_awvalid_r[0];
    assign m_axi_0_awid    = fwd_awid_r;
    assign m_axi_0_awlen   = fwd_awlen_r;
    assign m_axi_0_awsize  = fwd_awsize_r;
    assign m_axi_0_awburst = fwd_awburst_r;
    assign m_axi_0_wdata   = fwd_wdata_r;
    assign m_axi_0_wstrb   = fwd_wstrb_r;
    assign m_axi_0_wvalid  = fwd_wvalid_r[0];
    assign m_axi_0_wlast   = fwd_wlast_r;
    assign m_axi_0_bready  = fwd_bready_r[0];

    // ================================================================
    // Output assignments — Master port 1 (S1, SRAM)
    // ================================================================
    assign m_axi_1_araddr  = fwd_araddr_r;
    assign m_axi_1_arvalid = fwd_arvalid_r[1];
    assign m_axi_1_arid    = fwd_arid_r;
    assign m_axi_1_arlen   = fwd_arlen_r;
    assign m_axi_1_arsize  = fwd_arsize_r;
    assign m_axi_1_arburst = fwd_arburst_r;
    assign m_axi_1_rready  = fwd_rready_r[1];
    assign m_axi_1_awaddr  = fwd_awaddr_r;
    assign m_axi_1_awvalid = fwd_awvalid_r[1];
    assign m_axi_1_awid    = fwd_awid_r;
    assign m_axi_1_awlen   = fwd_awlen_r;
    assign m_axi_1_awsize  = fwd_awsize_r;
    assign m_axi_1_awburst = fwd_awburst_r;
    assign m_axi_1_wdata   = fwd_wdata_r;
    assign m_axi_1_wstrb   = fwd_wstrb_r;
    assign m_axi_1_wvalid  = fwd_wvalid_r[1];
    assign m_axi_1_wlast   = fwd_wlast_r;
    assign m_axi_1_bready  = fwd_bready_r[1];

    // ================================================================
    // Output assignments — Master port 2 (S2, Periph bridge)
    // ================================================================
    assign m_axi_2_araddr  = fwd_araddr_r;
    assign m_axi_2_arvalid = fwd_arvalid_r[2];
    assign m_axi_2_arid    = fwd_arid_r;
    assign m_axi_2_arlen   = fwd_arlen_r;
    assign m_axi_2_arsize  = fwd_arsize_r;
    assign m_axi_2_arburst = fwd_arburst_r;
    assign m_axi_2_rready  = fwd_rready_r[2];
    assign m_axi_2_awaddr  = fwd_awaddr_r;
    assign m_axi_2_awvalid = fwd_awvalid_r[2];
    assign m_axi_2_awid    = fwd_awid_r;
    assign m_axi_2_awlen   = fwd_awlen_r;
    assign m_axi_2_awsize  = fwd_awsize_r;
    assign m_axi_2_awburst = fwd_awburst_r;
    assign m_axi_2_wdata   = fwd_wdata_r;
    assign m_axi_2_wstrb   = fwd_wstrb_r;
    assign m_axi_2_wvalid  = fwd_wvalid_r[2];
    assign m_axi_2_wlast   = fwd_wlast_r;
    assign m_axi_2_bready  = fwd_bready_r[2];

    // ================================================================
    // Output assignments — Master port 3 (S3, DDR)
    // ================================================================
    assign m_axi_3_araddr  = fwd_araddr_r;
    assign m_axi_3_arvalid = fwd_arvalid_r[3];
    assign m_axi_3_arid    = fwd_arid_r;
    assign m_axi_3_arlen   = fwd_arlen_r;
    assign m_axi_3_arsize  = fwd_arsize_r;
    assign m_axi_3_arburst = fwd_arburst_r;
    assign m_axi_3_rready  = fwd_rready_r[3];
    assign m_axi_3_awaddr  = fwd_awaddr_r;
    assign m_axi_3_awvalid = fwd_awvalid_r[3];
    assign m_axi_3_awid    = fwd_awid_r;
    assign m_axi_3_awlen   = fwd_awlen_r;
    assign m_axi_3_awsize  = fwd_awsize_r;
    assign m_axi_3_awburst = fwd_awburst_r;
    assign m_axi_3_wdata   = fwd_wdata_r;
    assign m_axi_3_wstrb   = fwd_wstrb_r;
    assign m_axi_3_wvalid  = fwd_wvalid_r[3];
    assign m_axi_3_wlast   = fwd_wlast_r;
    assign m_axi_3_bready  = fwd_bready_r[3];

endmodule
