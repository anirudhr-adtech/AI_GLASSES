`timescale 1ns/1ps
//============================================================================
// Module:      axi_downsizer
// Project:     AI_GLASSES — AXI Interconnect
// Description: Width converter 128->32 bit. Write: splits 128-bit beat into
//              4x 32-bit writes, wstrb groups of 4 bits, skips zero-strobe.
//              Read: 4 sequential 32-bit reads assembled into 128-bit.
//              Suppress RLAST until final sub-beat.
//============================================================================

module axi_downsizer #(
    parameter NARROW_WIDTH = 32,
    parameter WIDE_WIDTH   = 128,
    parameter ADDR_WIDTH   = 32,
    parameter ID_WIDTH     = 6
)(
    input  wire                        clk,
    input  wire                        rst_n,

    // Wide slave interface (from master)
    input  wire [ID_WIDTH-1:0]         s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]       s_axi_awaddr,
    input  wire [7:0]                  s_axi_awlen,
    input  wire [2:0]                  s_axi_awsize,
    input  wire [1:0]                  s_axi_awburst,
    input  wire                        s_axi_awvalid,
    output reg                         s_axi_awready,

    input  wire [WIDE_WIDTH-1:0]       s_axi_wdata,
    input  wire [WIDE_WIDTH/8-1:0]     s_axi_wstrb,
    input  wire                        s_axi_wlast,
    input  wire                        s_axi_wvalid,
    output reg                         s_axi_wready,

    output reg  [ID_WIDTH-1:0]         s_axi_bid,
    output reg  [1:0]                  s_axi_bresp,
    output reg                         s_axi_bvalid,
    input  wire                        s_axi_bready,

    input  wire [ID_WIDTH-1:0]         s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]       s_axi_araddr,
    input  wire [7:0]                  s_axi_arlen,
    input  wire [2:0]                  s_axi_arsize,
    input  wire [1:0]                  s_axi_arburst,
    input  wire                        s_axi_arvalid,
    output reg                         s_axi_arready,

    output reg  [ID_WIDTH-1:0]         s_axi_rid,
    output reg  [WIDE_WIDTH-1:0]       s_axi_rdata,
    output reg  [1:0]                  s_axi_rresp,
    output reg                         s_axi_rlast,
    output reg                         s_axi_rvalid,
    input  wire                        s_axi_rready,

    // Narrow master interface (to slave)
    output reg  [ID_WIDTH-1:0]         m_axi_awid,
    output reg  [ADDR_WIDTH-1:0]       m_axi_awaddr,
    output reg  [7:0]                  m_axi_awlen,
    output reg  [2:0]                  m_axi_awsize,
    output reg  [1:0]                  m_axi_awburst,
    output reg                         m_axi_awvalid,
    input  wire                        m_axi_awready,

    output reg  [NARROW_WIDTH-1:0]     m_axi_wdata,
    output reg  [NARROW_WIDTH/8-1:0]   m_axi_wstrb,
    output reg                         m_axi_wlast,
    output reg                         m_axi_wvalid,
    input  wire                        m_axi_wready,

    input  wire [ID_WIDTH-1:0]         m_axi_bid,
    input  wire [1:0]                  m_axi_bresp,
    input  wire                        m_axi_bvalid,
    output reg                         m_axi_bready,

    output reg  [ID_WIDTH-1:0]         m_axi_arid,
    output reg  [ADDR_WIDTH-1:0]       m_axi_araddr,
    output reg  [7:0]                  m_axi_arlen,
    output reg  [2:0]                  m_axi_arsize,
    output reg  [1:0]                  m_axi_arburst,
    output reg                         m_axi_arvalid,
    input  wire                        m_axi_arready,

    input  wire [ID_WIDTH-1:0]         m_axi_rid,
    input  wire [NARROW_WIDTH-1:0]     m_axi_rdata,
    input  wire [1:0]                  m_axi_rresp,
    input  wire                        m_axi_rlast,
    input  wire                        m_axi_rvalid,
    output reg                         m_axi_rready
);

    localparam NARROW_STRB = NARROW_WIDTH / 8;  // 4
    localparam WIDE_STRB   = WIDE_WIDTH / 8;    // 16
    localparam RATIO       = WIDE_WIDTH / NARROW_WIDTH; // 4

    // ---- Write Path ----
    localparam WR_IDLE     = 3'd0;
    localparam WR_SPLIT    = 3'd1;
    localparam WR_NARROW   = 3'd2;
    localparam WR_RESP     = 3'd3;

    reg [2:0]              wr_state;
    reg [ID_WIDTH-1:0]     wr_id;
    reg [ADDR_WIDTH-1:0]   wr_base_addr;
    reg [7:0]              wr_beat_cnt;
    reg [7:0]              wr_len;
    reg [1:0]              wr_sub_idx;       // 0-3 sub-beat within wide beat
    reg [WIDE_WIDTH-1:0]   wr_data_buf;
    reg [WIDE_STRB-1:0]    wr_strb_buf;
    reg                    wr_is_last_beat;
    reg [1:0]              wr_bresp_acc;     // Accumulated worst response

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_state       <= WR_IDLE;
            s_axi_awready  <= 1'b0;
            s_axi_wready   <= 1'b0;
            s_axi_bvalid   <= 1'b0;
            s_axi_bid      <= {ID_WIDTH{1'b0}};
            s_axi_bresp    <= 2'b00;
            m_axi_awvalid  <= 1'b0;
            m_axi_wvalid   <= 1'b0;
            m_axi_bready   <= 1'b0;
            m_axi_awid     <= {ID_WIDTH{1'b0}};
            m_axi_awaddr   <= {ADDR_WIDTH{1'b0}};
            m_axi_awlen    <= 8'd0;
            m_axi_awsize   <= 3'd0;
            m_axi_awburst  <= 2'd0;
            m_axi_wdata    <= {NARROW_WIDTH{1'b0}};
            m_axi_wstrb    <= {NARROW_STRB{1'b0}};
            m_axi_wlast    <= 1'b0;
            wr_id          <= {ID_WIDTH{1'b0}};
            wr_base_addr   <= {ADDR_WIDTH{1'b0}};
            wr_beat_cnt    <= 8'd0;
            wr_len         <= 8'd0;
            wr_sub_idx     <= 2'd0;
            wr_data_buf    <= {WIDE_WIDTH{1'b0}};
            wr_strb_buf    <= {WIDE_STRB{1'b0}};
            wr_is_last_beat <= 1'b0;
            wr_bresp_acc   <= 2'b00;
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    s_axi_bvalid   <= 1'b0;
                    s_axi_awready  <= 1'b1;
                    s_axi_wready   <= 1'b0;
                    m_axi_awvalid  <= 1'b0;
                    m_axi_wvalid   <= 1'b0;
                    wr_bresp_acc   <= 2'b00;
                    if (s_axi_awvalid && s_axi_awready) begin
                        wr_id          <= s_axi_awid;
                        wr_base_addr   <= s_axi_awaddr;
                        wr_len         <= s_axi_awlen;
                        wr_beat_cnt    <= 8'd0;
                        s_axi_awready  <= 1'b0;
                        s_axi_wready   <= 1'b1;
                        wr_state       <= WR_SPLIT;
                    end
                end
                WR_SPLIT: begin
                    if (s_axi_wvalid && s_axi_wready) begin
                        wr_data_buf     <= s_axi_wdata;
                        wr_strb_buf     <= s_axi_wstrb;
                        wr_is_last_beat <= s_axi_wlast;
                        wr_sub_idx      <= 2'd0;
                        s_axi_wready    <= 1'b0;

                        // Issue narrow AW for first sub-beat
                        m_axi_awid     <= wr_id;
                        m_axi_awaddr   <= wr_base_addr + (wr_beat_cnt << 4); // 16 bytes per wide beat
                        m_axi_awlen    <= 8'd3;  // 4 sub-beats
                        m_axi_awsize   <= 3'd2;  // 4 bytes
                        m_axi_awburst  <= 2'b01; // INCR
                        m_axi_awvalid  <= 1'b1;
                        wr_state       <= WR_NARROW;
                    end
                end
                WR_NARROW: begin
                    // Wait for AW acceptance
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                    end

                    // Send sub-beats
                    if (!m_axi_awvalid) begin
                        // Skip zero-strobe sub-beats
                        if (wr_strb_buf[wr_sub_idx*NARROW_STRB +: NARROW_STRB] == {NARROW_STRB{1'b0}}) begin
                            if (wr_sub_idx == 2'd3) begin
                                // Last sub-beat, send with wlast
                                m_axi_wdata  <= {NARROW_WIDTH{1'b0}};
                                m_axi_wstrb  <= {NARROW_STRB{1'b0}};
                                m_axi_wlast  <= 1'b1;
                                m_axi_wvalid <= 1'b1;
                            end else begin
                                wr_sub_idx <= wr_sub_idx + 2'd1;
                            end
                        end else begin
                            m_axi_wdata  <= wr_data_buf[wr_sub_idx*NARROW_WIDTH +: NARROW_WIDTH];
                            m_axi_wstrb  <= wr_strb_buf[wr_sub_idx*NARROW_STRB +: NARROW_STRB];
                            m_axi_wlast  <= (wr_sub_idx == 2'd3) ? 1'b1 : 1'b0;
                            m_axi_wvalid <= 1'b1;
                        end
                    end

                    if (m_axi_wvalid && m_axi_wready) begin
                        m_axi_wvalid <= 1'b0;
                        if (m_axi_wlast) begin
                            // Wait for B response
                            m_axi_bready <= 1'b1;
                        end else begin
                            wr_sub_idx <= wr_sub_idx + 2'd1;
                        end
                    end

                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bready <= 1'b0;
                        // Accumulate worst response
                        if (m_axi_bresp > wr_bresp_acc)
                            wr_bresp_acc <= m_axi_bresp;

                        wr_beat_cnt <= wr_beat_cnt + 8'd1;
                        if (wr_is_last_beat) begin
                            s_axi_bid    <= wr_id;
                            s_axi_bresp  <= (m_axi_bresp > wr_bresp_acc) ? m_axi_bresp : wr_bresp_acc;
                            s_axi_bvalid <= 1'b1;
                            wr_state     <= WR_RESP;
                        end else begin
                            s_axi_wready <= 1'b1;
                            wr_state     <= WR_SPLIT;
                        end
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
        end
    end

    // ---- Read Path ----
    localparam RD_IDLE     = 3'd0;
    localparam RD_NARROW   = 3'd1;
    localparam RD_ASSEMBLE = 3'd2;
    localparam RD_WIDE     = 3'd3;

    reg [2:0]              rd_state;
    reg [ID_WIDTH-1:0]     rd_id;
    reg [ADDR_WIDTH-1:0]   rd_base_addr;
    reg [7:0]              rd_beat_cnt;
    reg [7:0]              rd_len;
    reg [1:0]              rd_sub_idx;
    reg [WIDE_WIDTH-1:0]   rd_data_buf;
    reg [1:0]              rd_rresp_acc;

    always @(posedge clk) begin
        if (!rst_n) begin
            rd_state       <= RD_IDLE;
            s_axi_arready  <= 1'b0;
            s_axi_rvalid   <= 1'b0;
            s_axi_rid      <= {ID_WIDTH{1'b0}};
            s_axi_rdata    <= {WIDE_WIDTH{1'b0}};
            s_axi_rresp    <= 2'b00;
            s_axi_rlast    <= 1'b0;
            m_axi_arvalid  <= 1'b0;
            m_axi_rready   <= 1'b0;
            m_axi_arid     <= {ID_WIDTH{1'b0}};
            m_axi_araddr   <= {ADDR_WIDTH{1'b0}};
            m_axi_arlen    <= 8'd0;
            m_axi_arsize   <= 3'd0;
            m_axi_arburst  <= 2'd0;
            rd_id          <= {ID_WIDTH{1'b0}};
            rd_base_addr   <= {ADDR_WIDTH{1'b0}};
            rd_beat_cnt    <= 8'd0;
            rd_len         <= 8'd0;
            rd_sub_idx     <= 2'd0;
            rd_data_buf    <= {WIDE_WIDTH{1'b0}};
            rd_rresp_acc   <= 2'b00;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    s_axi_rvalid   <= 1'b0;
                    s_axi_arready  <= 1'b1;
                    m_axi_arvalid  <= 1'b0;
                    m_axi_rready   <= 1'b0;
                    rd_rresp_acc   <= 2'b00;
                    if (s_axi_arvalid && s_axi_arready) begin
                        rd_id          <= s_axi_arid;
                        rd_base_addr   <= s_axi_araddr;
                        rd_len         <= s_axi_arlen;
                        rd_beat_cnt    <= 8'd0;
                        s_axi_arready  <= 1'b0;
                        // Issue narrow AR
                        m_axi_arid     <= s_axi_arid;
                        m_axi_araddr   <= s_axi_araddr;
                        m_axi_arlen    <= 8'd3;  // 4 sub-beats
                        m_axi_arsize   <= 3'd2;  // 4 bytes
                        m_axi_arburst  <= 2'b01; // INCR
                        m_axi_arvalid  <= 1'b1;
                        rd_sub_idx     <= 2'd0;
                        rd_data_buf    <= {WIDE_WIDTH{1'b0}};
                        rd_state       <= RD_NARROW;
                    end
                end
                RD_NARROW: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                    end

                    if (m_axi_rvalid && m_axi_rready) begin
                        rd_data_buf[rd_sub_idx*NARROW_WIDTH +: NARROW_WIDTH] <= m_axi_rdata;
                        if (m_axi_rresp > rd_rresp_acc)
                            rd_rresp_acc <= m_axi_rresp;

                        if (m_axi_rlast) begin
                            // All 4 sub-beats received, present wide data
                            m_axi_rready <= 1'b0;
                            rd_state     <= RD_WIDE;
                        end else begin
                            rd_sub_idx <= rd_sub_idx + 2'd1;
                        end
                    end
                end
                RD_WIDE: begin
                    s_axi_rid   <= rd_id;
                    s_axi_rdata <= rd_data_buf;
                    s_axi_rdata[3*NARROW_WIDTH +: NARROW_WIDTH] <= m_axi_rdata; // last sub-beat
                    s_axi_rresp <= rd_rresp_acc;
                    s_axi_rlast <= (rd_beat_cnt == rd_len) ? 1'b1 : 1'b0;
                    s_axi_rvalid <= 1'b1;
                    rd_state     <= RD_ASSEMBLE;
                end
                RD_ASSEMBLE: begin
                    if (s_axi_rvalid && s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        rd_beat_cnt  <= rd_beat_cnt + 8'd1;
                        if (s_axi_rlast) begin
                            rd_state <= RD_IDLE;
                        end else begin
                            // Issue next narrow AR burst
                            rd_rresp_acc   <= 2'b00;
                            m_axi_arid     <= rd_id;
                            m_axi_araddr   <= rd_base_addr + ((rd_beat_cnt + 8'd1) << 4);
                            m_axi_arlen    <= 8'd3;
                            m_axi_arsize   <= 3'd2;
                            m_axi_arburst  <= 2'b01;
                            m_axi_arvalid  <= 1'b1;
                            rd_sub_idx     <= 2'd0;
                            rd_data_buf    <= {WIDE_WIDTH{1'b0}};
                            rd_state       <= RD_NARROW;
                        end
                    end
                end
                default: rd_state <= RD_IDLE;
            endcase
        end
    end

endmodule
