`timescale 1ns/1ps
//============================================================================
// Module:      axi_to_axilite_bridge
// Project:     AI_GLASSES — AXI Interconnect
// Description: AXI4 to AXI-Lite protocol bridge. Single-beat pass-through.
//              Burst (arlen/awlen != 0) rejected with SLVERR. Strips AXI ID,
//              buffers internally, re-attaches on response.
//============================================================================

module axi_to_axilite_bridge #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32,
    parameter ID_WIDTH   = 6
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // AXI4 slave interface (from crossbar)
    input  wire [ID_WIDTH-1:0]     s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]   s_axi_awaddr,
    input  wire [7:0]              s_axi_awlen,
    input  wire [2:0]              s_axi_awsize,
    input  wire [1:0]              s_axi_awburst,
    input  wire                    s_axi_awvalid,
    output reg                     s_axi_awready,

    input  wire [DATA_WIDTH-1:0]   s_axi_wdata,
    input  wire [DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  wire                    s_axi_wlast,
    input  wire                    s_axi_wvalid,
    output reg                     s_axi_wready,

    output reg  [ID_WIDTH-1:0]     s_axi_bid,
    output reg  [1:0]              s_axi_bresp,
    output reg                     s_axi_bvalid,
    input  wire                    s_axi_bready,

    input  wire [ID_WIDTH-1:0]     s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]   s_axi_araddr,
    input  wire [7:0]              s_axi_arlen,
    input  wire [2:0]              s_axi_arsize,
    input  wire [1:0]              s_axi_arburst,
    input  wire                    s_axi_arvalid,
    output reg                     s_axi_arready,

    output reg  [ID_WIDTH-1:0]     s_axi_rid,
    output reg  [DATA_WIDTH-1:0]   s_axi_rdata,
    output reg  [1:0]              s_axi_rresp,
    output reg                     s_axi_rlast,
    output reg                     s_axi_rvalid,
    input  wire                    s_axi_rready,

    // AXI-Lite master interface (to peripheral fabric)
    output reg  [ADDR_WIDTH-1:0]   m_axil_awaddr,
    output reg  [2:0]              m_axil_awprot,
    output reg                     m_axil_awvalid,
    input  wire                    m_axil_awready,

    output reg  [DATA_WIDTH-1:0]   m_axil_wdata,
    output reg  [DATA_WIDTH/8-1:0] m_axil_wstrb,
    output reg                     m_axil_wvalid,
    input  wire                    m_axil_wready,

    input  wire [1:0]              m_axil_bresp,
    input  wire                    m_axil_bvalid,
    output reg                     m_axil_bready,

    output reg  [ADDR_WIDTH-1:0]   m_axil_araddr,
    output reg  [2:0]              m_axil_arprot,
    output reg                     m_axil_arvalid,
    input  wire                    m_axil_arready,

    input  wire [DATA_WIDTH-1:0]   m_axil_rdata,
    input  wire [1:0]              m_axil_rresp,
    input  wire                    m_axil_rvalid,
    output reg                     m_axil_rready
);

    localparam RESP_SLVERR = 2'b10;

    // Write FSM
    localparam WR_IDLE     = 3'd0;
    localparam WR_WDATA    = 3'd1;
    localparam WR_AXIL_AW  = 3'd2;
    localparam WR_AXIL_W   = 3'd3;
    localparam WR_AXIL_B   = 3'd4;
    localparam WR_RESP     = 3'd5;
    localparam WR_BURST_ERR = 3'd6;

    reg [2:0]           wr_state;
    reg [ID_WIDTH-1:0]  wr_saved_id;
    reg                 wr_burst_err;

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_state       <= WR_IDLE;
            s_axi_awready  <= 1'b0;
            s_axi_wready   <= 1'b0;
            s_axi_bvalid   <= 1'b0;
            s_axi_bid      <= {ID_WIDTH{1'b0}};
            s_axi_bresp    <= 2'b00;
            m_axil_awvalid <= 1'b0;
            m_axil_wvalid  <= 1'b0;
            m_axil_bready  <= 1'b0;
            m_axil_awaddr  <= {ADDR_WIDTH{1'b0}};
            m_axil_awprot  <= 3'b000;
            m_axil_wdata   <= {DATA_WIDTH{1'b0}};
            m_axil_wstrb   <= {(DATA_WIDTH/8){1'b0}};
            wr_saved_id    <= {ID_WIDTH{1'b0}};
            wr_burst_err   <= 1'b0;
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    s_axi_bvalid  <= 1'b0;
                    s_axi_awready <= 1'b1;
                    if (s_axi_awvalid && s_axi_awready) begin
                        wr_saved_id   <= s_axi_awid;
                        s_axi_awready <= 1'b0;

                        if (s_axi_awlen != 8'd0) begin
                            // Burst - reject with SLVERR after consuming W data
                            wr_burst_err <= 1'b1;
                            s_axi_wready <= 1'b1;
                            wr_state     <= WR_BURST_ERR;
                        end else begin
                            wr_burst_err <= 1'b0;
                            s_axi_wready <= 1'b1;
                            wr_state     <= WR_WDATA;
                        end
                    end
                end
                WR_BURST_ERR: begin
                    // Consume all W beats
                    if (s_axi_wvalid && s_axi_wready && s_axi_wlast) begin
                        s_axi_wready <= 1'b0;
                        s_axi_bid    <= wr_saved_id;
                        s_axi_bresp  <= RESP_SLVERR;
                        s_axi_bvalid <= 1'b1;
                        wr_state     <= WR_RESP;
                    end
                end
                WR_WDATA: begin
                    if (s_axi_wvalid && s_axi_wready) begin
                        s_axi_wready  <= 1'b0;
                        m_axil_awaddr <= m_axil_awaddr; // already set below
                        m_axil_wdata  <= s_axi_wdata;
                        m_axil_wstrb  <= s_axi_wstrb;
                        m_axil_awvalid <= 1'b1;
                        m_axil_wvalid  <= 1'b1;
                        wr_state      <= WR_AXIL_AW;
                    end
                end
                WR_AXIL_AW: begin
                    if (m_axil_awvalid && m_axil_awready)
                        m_axil_awvalid <= 1'b0;
                    if (m_axil_wvalid && m_axil_wready)
                        m_axil_wvalid <= 1'b0;

                    if (!m_axil_awvalid && !m_axil_wvalid) begin
                        m_axil_bready <= 1'b1;
                        wr_state      <= WR_AXIL_B;
                    end else if (m_axil_awready && m_axil_wready) begin
                        m_axil_awvalid <= 1'b0;
                        m_axil_wvalid  <= 1'b0;
                        m_axil_bready  <= 1'b1;
                        wr_state       <= WR_AXIL_B;
                    end
                end
                WR_AXIL_B: begin
                    if (m_axil_bvalid && m_axil_bready) begin
                        m_axil_bready <= 1'b0;
                        s_axi_bid     <= wr_saved_id;
                        s_axi_bresp   <= m_axil_bresp;
                        s_axi_bvalid  <= 1'b1;
                        wr_state      <= WR_RESP;
                    end
                end
                WR_RESP: begin
                    if (s_axi_bvalid && s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        wr_state     <= WR_IDLE;
                    end
                end
                default: wr_state <= WR_IDLE;
            endcase

            // Latch address on AW handshake
            if (s_axi_awvalid && s_axi_awready)
                m_axil_awaddr <= s_axi_awaddr;
        end
    end

    // Read FSM
    localparam RD_IDLE     = 3'd0;
    localparam RD_AXIL_AR  = 3'd1;
    localparam RD_AXIL_R   = 3'd2;
    localparam RD_RESP     = 3'd3;
    localparam RD_BURST_ERR = 3'd4;

    reg [2:0]           rd_state;
    reg [ID_WIDTH-1:0]  rd_saved_id;
    reg [7:0]           rd_burst_cnt;
    reg [7:0]           rd_burst_len;

    always @(posedge clk) begin
        if (!rst_n) begin
            rd_state       <= RD_IDLE;
            s_axi_arready  <= 1'b0;
            s_axi_rvalid   <= 1'b0;
            s_axi_rid      <= {ID_WIDTH{1'b0}};
            s_axi_rdata    <= {DATA_WIDTH{1'b0}};
            s_axi_rresp    <= 2'b00;
            s_axi_rlast    <= 1'b0;
            m_axil_arvalid <= 1'b0;
            m_axil_rready  <= 1'b0;
            m_axil_araddr  <= {ADDR_WIDTH{1'b0}};
            m_axil_arprot  <= 3'b000;
            rd_saved_id    <= {ID_WIDTH{1'b0}};
            rd_burst_cnt   <= 8'd0;
            rd_burst_len   <= 8'd0;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    s_axi_rvalid  <= 1'b0;
                    s_axi_rlast   <= 1'b0;
                    s_axi_arready <= 1'b1;
                    if (s_axi_arvalid && s_axi_arready) begin
                        rd_saved_id    <= s_axi_arid;
                        m_axil_araddr  <= s_axi_araddr;
                        s_axi_arready  <= 1'b0;

                        if (s_axi_arlen != 8'd0) begin
                            // Burst read - reject with SLVERR for all beats
                            rd_burst_len   <= s_axi_arlen;
                            rd_burst_cnt   <= 8'd0;
                            s_axi_rid      <= s_axi_arid;
                            s_axi_rdata    <= {DATA_WIDTH{1'b0}};
                            s_axi_rresp    <= RESP_SLVERR;
                            s_axi_rlast    <= (s_axi_arlen == 8'd0) ? 1'b1 : 1'b0;
                            s_axi_rvalid   <= 1'b1;
                            rd_state       <= RD_BURST_ERR;
                        end else begin
                            m_axil_arvalid <= 1'b1;
                            rd_state       <= RD_AXIL_AR;
                        end
                    end
                end
                RD_BURST_ERR: begin
                    if (s_axi_rvalid && s_axi_rready) begin
                        if (s_axi_rlast) begin
                            s_axi_rvalid <= 1'b0;
                            rd_state     <= RD_IDLE;
                        end else begin
                            rd_burst_cnt <= rd_burst_cnt + 8'd1;
                            if ((rd_burst_cnt + 8'd1) == rd_burst_len)
                                s_axi_rlast <= 1'b1;
                        end
                    end
                end
                RD_AXIL_AR: begin
                    if (m_axil_arvalid && m_axil_arready) begin
                        m_axil_arvalid <= 1'b0;
                        m_axil_rready  <= 1'b1;
                        rd_state       <= RD_AXIL_R;
                    end
                end
                RD_AXIL_R: begin
                    if (m_axil_rvalid && m_axil_rready) begin
                        m_axil_rready <= 1'b0;
                        s_axi_rid     <= rd_saved_id;
                        s_axi_rdata   <= m_axil_rdata;
                        s_axi_rresp   <= m_axil_rresp;
                        s_axi_rlast   <= 1'b1;
                        s_axi_rvalid  <= 1'b1;
                        rd_state      <= RD_RESP;
                    end
                end
                RD_RESP: begin
                    if (s_axi_rvalid && s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        s_axi_rlast  <= 1'b0;
                        rd_state     <= RD_IDLE;
                    end
                end
                default: rd_state <= RD_IDLE;
            endcase
        end
    end

endmodule
