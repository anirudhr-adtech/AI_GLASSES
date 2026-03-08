`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — DDR Subsystem
// Module: axi_width_128to64
// Description: Data width converter 128-bit -> 64-bit for Zynq HP0.
//   Write: 1x128-bit -> 2x64-bit beats (AWLEN doubled, AWSIZE 4->3)
//   Read:  2x64-bit -> 1x128-bit beats (suppress odd-beat RLAST)
//////////////////////////////////////////////////////////////////////////////

module axi_width_128to64 #(
    parameter ADDR_WIDTH   = 32,
    parameter ID_WIDTH     = 6,
    parameter WIDE_DATA    = 128,
    parameter NARROW_DATA  = 64,
    parameter WIDE_STRB    = WIDE_DATA / 8,
    parameter NARROW_STRB  = NARROW_DATA / 8
)(
    input  wire                      clk,
    input  wire                      rst_n,

    // Wide slave interface (128-bit, AXI3)
    input  wire [ID_WIDTH-1:0]       s_awid,
    input  wire [ADDR_WIDTH-1:0]     s_awaddr,
    input  wire [3:0]                s_awlen,
    input  wire [2:0]                s_awsize,
    input  wire [1:0]                s_awburst,
    input  wire [3:0]                s_awqos,
    input  wire                      s_awvalid,
    output reg                       s_awready,

    input  wire [WIDE_DATA-1:0]      s_wdata,
    input  wire [WIDE_STRB-1:0]      s_wstrb,
    input  wire                      s_wlast,
    input  wire                      s_wvalid,
    output reg                       s_wready,

    output reg  [ID_WIDTH-1:0]       s_bid,
    output reg  [1:0]                s_bresp,
    output reg                       s_bvalid,
    input  wire                      s_bready,

    input  wire [ID_WIDTH-1:0]       s_arid,
    input  wire [ADDR_WIDTH-1:0]     s_araddr,
    input  wire [3:0]                s_arlen,
    input  wire [2:0]                s_arsize,
    input  wire [1:0]                s_arburst,
    input  wire [3:0]                s_arqos,
    input  wire                      s_arvalid,
    output reg                       s_arready,

    output reg  [ID_WIDTH-1:0]       s_rid,
    output reg  [WIDE_DATA-1:0]      s_rdata,
    output reg  [1:0]                s_rresp,
    output reg                       s_rlast,
    output reg                       s_rvalid,
    input  wire                      s_rready,

    // Narrow master interface (64-bit, AXI3)
    output reg  [ID_WIDTH-1:0]       m_awid,
    output reg  [ADDR_WIDTH-1:0]     m_awaddr,
    output reg  [3:0]                m_awlen,
    output reg  [2:0]                m_awsize,
    output reg  [1:0]                m_awburst,
    output reg  [3:0]                m_awqos,
    output reg                       m_awvalid,
    input  wire                      m_awready,

    output reg  [NARROW_DATA-1:0]    m_wdata,
    output reg  [NARROW_STRB-1:0]    m_wstrb,
    output reg                       m_wlast,
    output reg                       m_wvalid,
    input  wire                      m_wready,

    input  wire [ID_WIDTH-1:0]       m_bid,
    input  wire [1:0]                m_bresp,
    input  wire                      m_bvalid,
    output reg                       m_bready,

    output reg  [ID_WIDTH-1:0]       m_arid,
    output reg  [ADDR_WIDTH-1:0]     m_araddr,
    output reg  [3:0]                m_arlen,
    output reg  [2:0]                m_arsize,
    output reg  [1:0]                m_arburst,
    output reg  [3:0]                m_arqos,
    output reg                       m_arvalid,
    input  wire                      m_arready,

    input  wire [ID_WIDTH-1:0]       m_rid,
    input  wire [NARROW_DATA-1:0]    m_rdata,
    input  wire [1:0]                m_rresp,
    input  wire                      m_rlast,
    input  wire                      m_rvalid,
    output reg                       m_rready
);

    // -----------------------------------------------------------------------
    // Write Address Channel: double len, reduce size
    // -----------------------------------------------------------------------
    localparam WAW_IDLE = 1'b0;
    localparam WAW_PASS = 1'b1;

    reg        waw_state;

    always @(posedge clk) begin
        if (!rst_n) begin
            waw_state  <= WAW_IDLE;
            s_awready  <= 1'b0;
            m_awvalid  <= 1'b0;
            m_awid     <= {ID_WIDTH{1'b0}};
            m_awaddr   <= {ADDR_WIDTH{1'b0}};
            m_awlen    <= 4'd0;
            m_awsize   <= 3'd0;
            m_awburst  <= 2'b01;
            m_awqos    <= 4'd0;
        end else begin
            case (waw_state)
                WAW_IDLE: begin
                    s_awready <= 1'b1;
                    if (s_awvalid && s_awready) begin
                        s_awready <= 1'b0;
                        m_awvalid <= 1'b1;
                        m_awid    <= s_awid;
                        m_awaddr  <= s_awaddr;
                        // Double the beat count: new_len = (old_len+1)*2 - 1
                        m_awlen   <= {s_awlen[2:0], 1'b1};
                        // Clamp size: 4 (16B) -> 3 (8B)
                        m_awsize  <= (s_awsize > 3'd3) ? 3'd3 : s_awsize;
                        m_awburst <= s_awburst;
                        m_awqos   <= s_awqos;
                        waw_state <= WAW_PASS;
                    end
                end
                WAW_PASS: begin
                    if (m_awvalid && m_awready) begin
                        m_awvalid <= 1'b0;
                        waw_state <= WAW_IDLE;
                    end
                end
            endcase
        end
    end

    // -----------------------------------------------------------------------
    // Write Data Channel: split 128-bit into 2x 64-bit
    // -----------------------------------------------------------------------
    localparam WD_LOW  = 1'b0;
    localparam WD_HIGH = 1'b1;

    reg        wd_phase;
    reg [WIDE_DATA-1:0]  wd_data_hold;
    reg [WIDE_STRB-1:0]  wd_strb_hold;
    reg                   wd_last_hold;

    always @(posedge clk) begin
        if (!rst_n) begin
            wd_phase    <= WD_LOW;
            s_wready    <= 1'b0;
            m_wvalid    <= 1'b0;
            m_wdata     <= {NARROW_DATA{1'b0}};
            m_wstrb     <= {NARROW_STRB{1'b0}};
            m_wlast     <= 1'b0;
            wd_data_hold <= {WIDE_DATA{1'b0}};
            wd_strb_hold <= {WIDE_STRB{1'b0}};
            wd_last_hold <= 1'b0;
        end else begin
            case (wd_phase)
                WD_LOW: begin
                    s_wready <= 1'b1;
                    if (s_wvalid && s_wready) begin
                        s_wready     <= 1'b0;
                        // Send low half
                        m_wvalid     <= 1'b1;
                        m_wdata      <= s_wdata[NARROW_DATA-1:0];
                        m_wstrb      <= s_wstrb[NARROW_STRB-1:0];
                        m_wlast      <= 1'b0; // never last on low half
                        // Save high half
                        wd_data_hold <= s_wdata;
                        wd_strb_hold <= s_wstrb;
                        wd_last_hold <= s_wlast;
                        wd_phase     <= WD_HIGH;
                    end
                end
                WD_HIGH: begin
                    if (m_wvalid && m_wready) begin
                        // Send high half
                        m_wdata  <= wd_data_hold[WIDE_DATA-1:NARROW_DATA];
                        m_wstrb  <= wd_strb_hold[WIDE_STRB-1:NARROW_STRB];
                        m_wlast  <= wd_last_hold; // wlast on high half only
                        m_wvalid <= 1'b1;
                        wd_phase <= WD_LOW;
                    end
                end
            endcase

            // Deassert wvalid after high-half accepted
            if (wd_phase == WD_LOW && m_wvalid && m_wready) begin
                m_wvalid <= 1'b0;
            end
        end
    end

    // -----------------------------------------------------------------------
    // Write Response Channel: pass through
    // -----------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            s_bvalid <= 1'b0;
            s_bid    <= {ID_WIDTH{1'b0}};
            s_bresp  <= 2'b00;
            m_bready <= 1'b0;
        end else begin
            m_bready <= !s_bvalid || s_bready;
            if (m_bvalid && m_bready) begin
                s_bvalid <= 1'b1;
                s_bid    <= m_bid;
                s_bresp  <= m_bresp;
            end else if (s_bvalid && s_bready) begin
                s_bvalid <= 1'b0;
            end
        end
    end

    // -----------------------------------------------------------------------
    // Read Address Channel: double len, reduce size
    // -----------------------------------------------------------------------
    localparam RAR_IDLE = 1'b0;
    localparam RAR_PASS = 1'b1;

    reg        rar_state;

    always @(posedge clk) begin
        if (!rst_n) begin
            rar_state  <= RAR_IDLE;
            s_arready  <= 1'b0;
            m_arvalid  <= 1'b0;
            m_arid     <= {ID_WIDTH{1'b0}};
            m_araddr   <= {ADDR_WIDTH{1'b0}};
            m_arlen    <= 4'd0;
            m_arsize   <= 3'd0;
            m_arburst  <= 2'b01;
            m_arqos    <= 4'd0;
        end else begin
            case (rar_state)
                RAR_IDLE: begin
                    s_arready <= 1'b1;
                    if (s_arvalid && s_arready) begin
                        s_arready <= 1'b0;
                        m_arvalid <= 1'b1;
                        m_arid    <= s_arid;
                        m_araddr  <= s_araddr;
                        m_arlen   <= {s_arlen[2:0], 1'b1};
                        m_arsize  <= (s_arsize > 3'd3) ? 3'd3 : s_arsize;
                        m_arburst <= s_arburst;
                        m_arqos   <= s_arqos;
                        rar_state <= RAR_PASS;
                    end
                end
                RAR_PASS: begin
                    if (m_arvalid && m_arready) begin
                        m_arvalid <= 1'b0;
                        rar_state <= RAR_IDLE;
                    end
                end
            endcase
        end
    end

    // -----------------------------------------------------------------------
    // Read Data Channel: merge 2x 64-bit into 128-bit
    // -----------------------------------------------------------------------
    localparam RD_LOW  = 1'b0;
    localparam RD_HIGH = 1'b1;

    reg                    rd_phase;
    reg [NARROW_DATA-1:0]  rd_low_data;
    reg [1:0]              rd_low_rresp;

    always @(posedge clk) begin
        if (!rst_n) begin
            rd_phase     <= RD_LOW;
            s_rvalid     <= 1'b0;
            s_rid        <= {ID_WIDTH{1'b0}};
            s_rdata      <= {WIDE_DATA{1'b0}};
            s_rresp      <= 2'b00;
            s_rlast      <= 1'b0;
            m_rready     <= 1'b0;
            rd_low_data  <= {NARROW_DATA{1'b0}};
            rd_low_rresp <= 2'b00;
        end else begin
            // Default: accept read data when slave side is free
            m_rready <= (rd_phase == RD_LOW) ? 1'b1 :
                        (rd_phase == RD_HIGH) ? (!s_rvalid || s_rready) : 1'b0;

            case (rd_phase)
                RD_LOW: begin
                    if (m_rvalid && m_rready) begin
                        rd_low_data  <= m_rdata;
                        rd_low_rresp <= m_rresp;
                        rd_phase     <= RD_HIGH;
                    end
                    // Clear previous rvalid
                    if (s_rvalid && s_rready)
                        s_rvalid <= 1'b0;
                end
                RD_HIGH: begin
                    if (m_rvalid && m_rready) begin
                        s_rvalid <= 1'b1;
                        s_rid    <= m_rid;
                        s_rdata  <= {m_rdata, rd_low_data};
                        // Worst-case response
                        s_rresp  <= (m_rresp > rd_low_rresp) ? m_rresp : rd_low_rresp;
                        // Only pass rlast on high beat (which is the "real" last)
                        s_rlast  <= m_rlast;
                        rd_phase <= RD_LOW;
                    end
                end
            endcase
        end
    end

endmodule
