`timescale 1ns/1ps
//============================================================================
// Module:      axi_timeout
// Project:     AI_GLASSES — AXI Interconnect
// Description: Per-slave timeout monitor. If no response within
//              TIMEOUT_CYCLES, forces SLVERR and releases bus.
//              Counter resets on any handshake. Sticky timeout debug bit.
//============================================================================

module axi_timeout #(
    parameter TIMEOUT_CYCLES = 4096,
    parameter DATA_WIDTH     = 32,
    parameter ID_WIDTH       = 6,
    parameter ADDR_WIDTH     = 32
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // From master side (crossbar to slave)
    input  wire [ID_WIDTH-1:0]    s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire [7:0]             s_axi_awlen,
    input  wire [2:0]             s_axi_awsize,
    input  wire [1:0]             s_axi_awburst,
    input  wire                   s_axi_awvalid,
    output wire                   s_axi_awready,

    input  wire [DATA_WIDTH-1:0]  s_axi_wdata,
    input  wire [DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  wire                   s_axi_wlast,
    input  wire                   s_axi_wvalid,
    output wire                   s_axi_wready,

    output wire [ID_WIDTH-1:0]    s_axi_bid,
    output wire [1:0]             s_axi_bresp,
    output wire                   s_axi_bvalid,
    input  wire                   s_axi_bready,

    input  wire [ID_WIDTH-1:0]    s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_araddr,
    input  wire [7:0]             s_axi_arlen,
    input  wire [2:0]             s_axi_arsize,
    input  wire [1:0]             s_axi_arburst,
    input  wire                   s_axi_arvalid,
    output wire                   s_axi_arready,

    output wire [ID_WIDTH-1:0]    s_axi_rid,
    output wire [DATA_WIDTH-1:0]  s_axi_rdata,
    output wire [1:0]             s_axi_rresp,
    output wire                   s_axi_rlast,
    output wire                   s_axi_rvalid,
    input  wire                   s_axi_rready,

    // To slave
    output wire [ID_WIDTH-1:0]    m_axi_awid,
    output wire [ADDR_WIDTH-1:0]  m_axi_awaddr,
    output wire [7:0]             m_axi_awlen,
    output wire [2:0]             m_axi_awsize,
    output wire [1:0]             m_axi_awburst,
    output wire                   m_axi_awvalid,
    input  wire                   m_axi_awready,

    output wire [DATA_WIDTH-1:0]  m_axi_wdata,
    output wire [DATA_WIDTH/8-1:0] m_axi_wstrb,
    output wire                   m_axi_wlast,
    output wire                   m_axi_wvalid,
    input  wire                   m_axi_wready,

    input  wire [ID_WIDTH-1:0]    m_axi_bid,
    input  wire [1:0]             m_axi_bresp,
    input  wire                   m_axi_bvalid,
    output wire                   m_axi_bready,

    output wire [ID_WIDTH-1:0]    m_axi_arid,
    output wire [ADDR_WIDTH-1:0]  m_axi_araddr,
    output wire [7:0]             m_axi_arlen,
    output wire [2:0]             m_axi_arsize,
    output wire [1:0]             m_axi_arburst,
    output wire                   m_axi_arvalid,
    input  wire                   m_axi_arready,

    input  wire [ID_WIDTH-1:0]    m_axi_rid,
    input  wire [DATA_WIDTH-1:0]  m_axi_rdata,
    input  wire [1:0]             m_axi_rresp,
    input  wire                   m_axi_rlast,
    input  wire                   m_axi_rvalid,
    output wire                   m_axi_rready,

    // Debug
    output reg                    timeout_event_o,
    output reg                    timeout_sticky_o
);

    localparam RESP_SLVERR = 2'b10;

    // Timeout counter
    reg [15:0] timeout_cnt;
    reg        timeout_active;   // A transaction is outstanding
    reg        timed_out;

    // Saved transaction info for timeout response
    reg [ID_WIDTH-1:0] saved_awid;
    reg [ID_WIDTH-1:0] saved_arid;
    reg [7:0]          saved_arlen;
    reg [7:0]          rd_beat_cnt;
    reg                wr_pending;
    reg                rd_pending;

    // Timeout FSM
    localparam NORMAL   = 2'd0;
    localparam TO_BRESP = 2'd1;
    localparam TO_RRESP = 2'd2;

    reg [1:0] to_state;

    // Pass-through in normal mode, intercept in timeout mode
    wire normal_mode = (to_state == NORMAL) && !timed_out;

    // AW pass-through
    assign m_axi_awid    = s_axi_awid;
    assign m_axi_awaddr  = s_axi_awaddr;
    assign m_axi_awlen   = s_axi_awlen;
    assign m_axi_awsize  = s_axi_awsize;
    assign m_axi_awburst = s_axi_awburst;
    assign m_axi_awvalid = normal_mode ? s_axi_awvalid : 1'b0;
    assign s_axi_awready = normal_mode ? m_axi_awready : 1'b0;

    // W pass-through
    assign m_axi_wdata   = s_axi_wdata;
    assign m_axi_wstrb   = s_axi_wstrb;
    assign m_axi_wlast   = s_axi_wlast;
    assign m_axi_wvalid  = normal_mode ? s_axi_wvalid : 1'b0;
    assign s_axi_wready  = normal_mode ? m_axi_wready : 1'b0;

    // AR pass-through
    assign m_axi_arid    = s_axi_arid;
    assign m_axi_araddr  = s_axi_araddr;
    assign m_axi_arlen   = s_axi_arlen;
    assign m_axi_arsize  = s_axi_arsize;
    assign m_axi_arburst = s_axi_arburst;
    assign m_axi_arvalid = normal_mode ? s_axi_arvalid : 1'b0;
    assign s_axi_arready = normal_mode ? m_axi_arready : 1'b0;

    // B channel: mux between slave response and timeout response
    reg  [ID_WIDTH-1:0] to_bid;
    reg  [1:0]          to_bresp;
    reg                 to_bvalid;

    assign s_axi_bid    = (to_state == TO_BRESP) ? to_bid    : m_axi_bid;
    assign s_axi_bresp  = (to_state == TO_BRESP) ? to_bresp  : m_axi_bresp;
    assign s_axi_bvalid = (to_state == TO_BRESP) ? to_bvalid : m_axi_bvalid;
    assign m_axi_bready = (to_state == TO_BRESP) ? 1'b0      : s_axi_bready;

    // R channel: mux between slave response and timeout response
    reg  [ID_WIDTH-1:0]   to_rid;
    reg  [DATA_WIDTH-1:0] to_rdata;
    reg  [1:0]            to_rresp;
    reg                   to_rlast;
    reg                   to_rvalid;

    assign s_axi_rid    = (to_state == TO_RRESP) ? to_rid    : m_axi_rid;
    assign s_axi_rdata  = (to_state == TO_RRESP) ? to_rdata  : m_axi_rdata;
    assign s_axi_rresp  = (to_state == TO_RRESP) ? to_rresp  : m_axi_rresp;
    assign s_axi_rlast  = (to_state == TO_RRESP) ? to_rlast  : m_axi_rlast;
    assign s_axi_rvalid = (to_state == TO_RRESP) ? to_rvalid : m_axi_rvalid;
    assign m_axi_rready = (to_state == TO_RRESP) ? 1'b0      : s_axi_rready;

    // Detect any handshake for counter reset
    wire any_handshake = (s_axi_awvalid && s_axi_awready) ||
                         (s_axi_wvalid  && s_axi_wready)  ||
                         (s_axi_bvalid  && s_axi_bready)  ||
                         (s_axi_arvalid && s_axi_arready) ||
                         (s_axi_rvalid  && s_axi_rready);

    // Track outstanding transactions
    always @(posedge clk) begin
        if (!rst_n) begin
            wr_pending  <= 1'b0;
            rd_pending  <= 1'b0;
            saved_awid  <= {ID_WIDTH{1'b0}};
            saved_arid  <= {ID_WIDTH{1'b0}};
            saved_arlen <= 8'd0;
        end else if (to_state == NORMAL) begin
            if (s_axi_awvalid && s_axi_awready) begin
                wr_pending <= 1'b1;
                saved_awid <= s_axi_awid;
            end
            if (s_axi_bvalid && s_axi_bready)
                wr_pending <= 1'b0;

            if (s_axi_arvalid && s_axi_arready) begin
                rd_pending  <= 1'b1;
                saved_arid  <= s_axi_arid;
                saved_arlen <= s_axi_arlen;
            end
            if (s_axi_rvalid && s_axi_rready && s_axi_rlast)
                rd_pending <= 1'b0;
        end
    end

    // Timeout counter and FSM
    always @(posedge clk) begin
        if (!rst_n) begin
            timeout_cnt    <= 16'd0;
            timeout_active <= 1'b0;
            timed_out      <= 1'b0;
            timeout_event_o  <= 1'b0;
            timeout_sticky_o <= 1'b0;
            to_state       <= NORMAL;
            to_bid         <= {ID_WIDTH{1'b0}};
            to_bresp       <= 2'b00;
            to_bvalid      <= 1'b0;
            to_rid         <= {ID_WIDTH{1'b0}};
            to_rdata       <= {DATA_WIDTH{1'b0}};
            to_rresp       <= 2'b00;
            to_rlast       <= 1'b0;
            to_rvalid      <= 1'b0;
            rd_beat_cnt    <= 8'd0;
        end else begin
            timeout_event_o <= 1'b0;

            case (to_state)
                NORMAL: begin
                    timeout_active <= wr_pending || rd_pending;

                    if (any_handshake) begin
                        timeout_cnt <= 16'd0;
                    end else if (timeout_active) begin
                        timeout_cnt <= timeout_cnt + 16'd1;
                    end

                    if (timeout_cnt >= TIMEOUT_CYCLES) begin
                        timed_out        <= 1'b1;
                        timeout_event_o  <= 1'b1;
                        timeout_sticky_o <= 1'b1;
                        timeout_cnt      <= 16'd0;

                        // Generate timeout response
                        if (wr_pending) begin
                            to_bid    <= saved_awid;
                            to_bresp  <= RESP_SLVERR;
                            to_bvalid <= 1'b1;
                            to_state  <= TO_BRESP;
                        end else if (rd_pending) begin
                            to_rid      <= saved_arid;
                            to_rdata    <= {DATA_WIDTH{1'b0}};
                            to_rresp    <= RESP_SLVERR;
                            to_rlast    <= (saved_arlen == 8'd0) ? 1'b1 : 1'b0;
                            to_rvalid   <= 1'b1;
                            rd_beat_cnt <= 8'd0;
                            to_state    <= TO_RRESP;
                        end
                    end
                end

                TO_BRESP: begin
                    if (to_bvalid && s_axi_bready) begin
                        to_bvalid <= 1'b0;
                        timed_out <= 1'b0;
                        to_state  <= NORMAL;
                    end
                end

                TO_RRESP: begin
                    if (to_rvalid && s_axi_rready) begin
                        if (to_rlast) begin
                            to_rvalid <= 1'b0;
                            timed_out <= 1'b0;
                            to_state  <= NORMAL;
                        end else begin
                            rd_beat_cnt <= rd_beat_cnt + 8'd1;
                            if ((rd_beat_cnt + 8'd1) == saved_arlen) begin
                                to_rlast <= 1'b1;
                            end
                        end
                    end
                end

                default: to_state <= NORMAL;
            endcase
        end
    end

endmodule
