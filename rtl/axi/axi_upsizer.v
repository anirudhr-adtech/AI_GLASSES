`timescale 1ns/1ps
//============================================================================
// Module:      axi_upsizer
// Project:     AI_GLASSES — AXI Interconnect
// Description: Width converter 32->128 bit. Write: positions 32-bit data in
//              correct 128-bit lane based on addr[3:2], sets 4 of 16 wstrb.
//              Read: extracts 32-bit slice from 128-bit based on addr[3:2].
//============================================================================

module axi_upsizer #(
    parameter NARROW_WIDTH = 32,
    parameter WIDE_WIDTH   = 128,
    parameter ADDR_WIDTH   = 32,
    parameter ID_WIDTH     = 6
)(
    input  wire                        clk,
    input  wire                        rst_n,

    // Narrow slave interface (from master)
    input  wire [ID_WIDTH-1:0]         s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]       s_axi_awaddr,
    input  wire [7:0]                  s_axi_awlen,
    input  wire [2:0]                  s_axi_awsize,
    input  wire [1:0]                  s_axi_awburst,
    input  wire                        s_axi_awvalid,
    output reg                         s_axi_awready,

    input  wire [NARROW_WIDTH-1:0]     s_axi_wdata,
    input  wire [NARROW_WIDTH/8-1:0]   s_axi_wstrb,
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
    output reg  [NARROW_WIDTH-1:0]     s_axi_rdata,
    output reg  [1:0]                  s_axi_rresp,
    output reg                         s_axi_rlast,
    output reg                         s_axi_rvalid,
    input  wire                        s_axi_rready,

    // Wide master interface (to slave)
    output reg  [ID_WIDTH-1:0]         m_axi_awid,
    output reg  [ADDR_WIDTH-1:0]       m_axi_awaddr,
    output reg  [7:0]                  m_axi_awlen,
    output reg  [2:0]                  m_axi_awsize,
    output reg  [1:0]                  m_axi_awburst,
    output reg                         m_axi_awvalid,
    input  wire                        m_axi_awready,

    output reg  [WIDE_WIDTH-1:0]       m_axi_wdata,
    output reg  [WIDE_WIDTH/8-1:0]     m_axi_wstrb,
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
    input  wire [WIDE_WIDTH-1:0]       m_axi_rdata,
    input  wire [1:0]                  m_axi_rresp,
    input  wire                        m_axi_rlast,
    input  wire                        m_axi_rvalid,
    output reg                         m_axi_rready
);

    localparam NARROW_STRB = NARROW_WIDTH / 8;  // 4
    localparam WIDE_STRB   = WIDE_WIDTH / 8;    // 16
    localparam RATIO       = WIDE_WIDTH / NARROW_WIDTH; // 4

    // ---- Write Path ----
    // For single-beat: position narrow data in wide lane based on addr[3:2]
    localparam WR_IDLE = 2'd0;
    localparam WR_ADDR = 2'd1;
    localparam WR_DATA = 2'd2;
    localparam WR_RESP = 2'd3;

    reg [1:0]              wr_state;
    reg [ADDR_WIDTH-1:0]   wr_addr;
    reg [ID_WIDTH-1:0]     wr_id;
    reg [7:0]              wr_len;
    reg [2:0]              wr_size;
    reg [1:0]              wr_burst;

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
            m_axi_wdata    <= {WIDE_WIDTH{1'b0}};
            m_axi_wstrb    <= {WIDE_STRB{1'b0}};
            m_axi_wlast    <= 1'b0;
            wr_addr        <= {ADDR_WIDTH{1'b0}};
            wr_id          <= {ID_WIDTH{1'b0}};
            wr_len         <= 8'd0;
            wr_size        <= 3'd0;
            wr_burst       <= 2'd0;
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    s_axi_bvalid  <= 1'b0;
                    s_axi_awready <= 1'b1;
                    s_axi_wready  <= 1'b0;
                    m_axi_awvalid <= 1'b0;
                    m_axi_wvalid  <= 1'b0;
                    m_axi_bready  <= 1'b0;
                    if (s_axi_awvalid && s_axi_awready) begin
                        wr_addr        <= s_axi_awaddr;
                        wr_id          <= s_axi_awid;
                        wr_len         <= s_axi_awlen;
                        wr_size        <= s_axi_awsize;
                        wr_burst       <= s_axi_awburst;
                        s_axi_awready  <= 1'b0;
                        // Forward AW to wide side (aligned address)
                        m_axi_awid     <= s_axi_awid;
                        m_axi_awaddr   <= {s_axi_awaddr[ADDR_WIDTH-1:4], 4'b0000};
                        m_axi_awlen    <= s_axi_awlen;
                        m_axi_awsize   <= 3'd4; // 16 bytes = 128 bits
                        m_axi_awburst  <= s_axi_awburst;
                        m_axi_awvalid  <= 1'b1;
                        wr_state       <= WR_ADDR;
                    end
                end
                WR_ADDR: begin
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        s_axi_wready  <= 1'b1;
                        wr_state      <= WR_DATA;
                    end
                end
                WR_DATA: begin
                    if (s_axi_wvalid && s_axi_wready) begin
                        // Position narrow data in correct lane
                        m_axi_wdata <= {WIDE_WIDTH{1'b0}};
                        m_axi_wstrb <= {WIDE_STRB{1'b0}};
                        m_axi_wdata[wr_addr[3:2]*NARROW_WIDTH +: NARROW_WIDTH] <= s_axi_wdata;
                        m_axi_wstrb[wr_addr[3:2]*NARROW_STRB +: NARROW_STRB]  <= s_axi_wstrb;
                        m_axi_wlast  <= s_axi_wlast;
                        m_axi_wvalid <= 1'b1;
                        s_axi_wready <= 1'b0;

                        // Increment address for burst
                        if (wr_burst == 2'b01) // INCR
                            wr_addr <= wr_addr + (1 << wr_size);

                        if (s_axi_wlast) begin
                            wr_state <= WR_RESP;
                        end
                    end
                    // Wait for wide side to accept W
                    if (m_axi_wvalid && m_axi_wready) begin
                        m_axi_wvalid <= 1'b0;
                        if (wr_state != WR_RESP) begin
                            s_axi_wready <= 1'b1;
                        end else begin
                            m_axi_bready <= 1'b1;
                        end
                    end
                end
                WR_RESP: begin
                    m_axi_bready <= 1'b1;
                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bready <= 1'b0;
                        s_axi_bid    <= m_axi_bid;
                        s_axi_bresp  <= m_axi_bresp;
                        s_axi_bvalid <= 1'b1;
                        wr_state     <= WR_IDLE;
                    end
                end
            endcase
        end
    end

    // ---- Read Path ----
    localparam RD_IDLE = 2'd0;
    localparam RD_ADDR = 2'd1;
    localparam RD_DATA = 2'd2;

    reg [1:0]              rd_state;
    reg [ADDR_WIDTH-1:0]   rd_addr;
    reg [ID_WIDTH-1:0]     rd_id;
    reg [7:0]              rd_len;
    reg [2:0]              rd_size;
    reg [1:0]              rd_burst;

    always @(posedge clk) begin
        if (!rst_n) begin
            rd_state       <= RD_IDLE;
            s_axi_arready  <= 1'b0;
            s_axi_rvalid   <= 1'b0;
            s_axi_rid      <= {ID_WIDTH{1'b0}};
            s_axi_rdata    <= {NARROW_WIDTH{1'b0}};
            s_axi_rresp    <= 2'b00;
            s_axi_rlast    <= 1'b0;
            m_axi_arvalid  <= 1'b0;
            m_axi_rready   <= 1'b0;
            m_axi_arid     <= {ID_WIDTH{1'b0}};
            m_axi_araddr   <= {ADDR_WIDTH{1'b0}};
            m_axi_arlen    <= 8'd0;
            m_axi_arsize   <= 3'd0;
            m_axi_arburst  <= 2'd0;
            rd_addr        <= {ADDR_WIDTH{1'b0}};
            rd_id          <= {ID_WIDTH{1'b0}};
            rd_len         <= 8'd0;
            rd_size        <= 3'd0;
            rd_burst       <= 2'd0;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    s_axi_rvalid  <= 1'b0;
                    s_axi_rlast   <= 1'b0;
                    s_axi_arready <= 1'b1;
                    m_axi_arvalid <= 1'b0;
                    m_axi_rready  <= 1'b0;
                    if (s_axi_arvalid && s_axi_arready) begin
                        rd_addr        <= s_axi_araddr;
                        rd_id          <= s_axi_arid;
                        rd_len         <= s_axi_arlen;
                        rd_size        <= s_axi_arsize;
                        rd_burst       <= s_axi_arburst;
                        s_axi_arready  <= 1'b0;
                        // Forward AR to wide side
                        m_axi_arid     <= s_axi_arid;
                        m_axi_araddr   <= {s_axi_araddr[ADDR_WIDTH-1:4], 4'b0000};
                        m_axi_arlen    <= s_axi_arlen;
                        m_axi_arsize   <= 3'd4; // 16 bytes
                        m_axi_arburst  <= s_axi_arburst;
                        m_axi_arvalid  <= 1'b1;
                        rd_state       <= RD_ADDR;
                    end
                end
                RD_ADDR: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        m_axi_rready  <= 1'b1;
                        rd_state      <= RD_DATA;
                    end
                end
                RD_DATA: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        // Extract correct 32-bit slice from 128-bit data
                        s_axi_rid   <= m_axi_rid;
                        s_axi_rdata <= m_axi_rdata[rd_addr[3:2]*NARROW_WIDTH +: NARROW_WIDTH];
                        s_axi_rresp <= m_axi_rresp;
                        s_axi_rlast <= m_axi_rlast;
                        s_axi_rvalid <= 1'b1;
                        m_axi_rready <= 1'b0;

                        // Increment address for burst
                        if (rd_burst == 2'b01) // INCR
                            rd_addr <= rd_addr + (1 << rd_size);

                        if (m_axi_rlast) begin
                            rd_state <= RD_IDLE;
                        end
                    end
                    // Wait for narrow side to accept R
                    if (s_axi_rvalid && s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        if (rd_state == RD_DATA)
                            m_axi_rready <= 1'b1;
                    end
                end
            endcase
        end
    end

endmodule
