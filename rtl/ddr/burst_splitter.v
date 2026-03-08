`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — DDR Subsystem
// Module: burst_splitter
// Description: Splits AXI4 bursts (up to 256 beats) into AXI3-compatible
//              sub-bursts (max 16 beats). Passthrough for bursts <= 16.
//////////////////////////////////////////////////////////////////////////////

module burst_splitter #(
    parameter MAX_AXI4_LEN   = 255,
    parameter MAX_AXI3_LEN   = 15,
    parameter ADDR_WIDTH      = 32,
    parameter DATA_WIDTH      = 128,
    parameter ID_WIDTH        = 6,
    parameter STRB_WIDTH      = DATA_WIDTH / 8
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // AXI4 Slave — Write Address
    input  wire [ID_WIDTH-1:0]     s_awid,
    input  wire [ADDR_WIDTH-1:0]   s_awaddr,
    input  wire [7:0]              s_awlen,
    input  wire [2:0]              s_awsize,
    input  wire [1:0]              s_awburst,
    input  wire                    s_awvalid,
    output reg                     s_awready,

    // AXI4 Slave — Write Data
    input  wire [DATA_WIDTH-1:0]   s_wdata,
    input  wire [STRB_WIDTH-1:0]   s_wstrb,
    input  wire                    s_wlast,
    input  wire                    s_wvalid,
    output reg                     s_wready,

    // AXI4 Slave — Write Response
    output reg  [ID_WIDTH-1:0]     s_bid,
    output reg  [1:0]              s_bresp,
    output reg                     s_bvalid,
    input  wire                    s_bready,

    // AXI4 Slave — Read Address
    input  wire [ID_WIDTH-1:0]     s_arid,
    input  wire [ADDR_WIDTH-1:0]   s_araddr,
    input  wire [7:0]              s_arlen,
    input  wire [2:0]              s_arsize,
    input  wire [1:0]              s_arburst,
    input  wire                    s_arvalid,
    output reg                     s_arready,

    // AXI4 Slave — Read Data
    output reg  [ID_WIDTH-1:0]     s_rid,
    output reg  [DATA_WIDTH-1:0]   s_rdata,
    output reg  [1:0]              s_rresp,
    output reg                     s_rlast,
    output reg                     s_rvalid,
    input  wire                    s_rready,

    // AXI3 Master — Write Address
    output reg  [ID_WIDTH-1:0]     m_awid,
    output reg  [ADDR_WIDTH-1:0]   m_awaddr,
    output reg  [3:0]              m_awlen,    // AXI3: 4-bit len
    output reg  [2:0]              m_awsize,
    output reg  [1:0]              m_awburst,
    output reg                     m_awvalid,
    input  wire                    m_awready,

    // AXI3 Master — Write Data
    output reg  [DATA_WIDTH-1:0]   m_wdata,
    output reg  [STRB_WIDTH-1:0]   m_wstrb,
    output reg                     m_wlast,
    output reg                     m_wvalid,
    input  wire                    m_wready,

    // AXI3 Master — Write Response
    input  wire [ID_WIDTH-1:0]     m_bid,
    input  wire [1:0]              m_bresp,
    input  wire                    m_bvalid,
    output reg                     m_bready,

    // AXI3 Master — Read Address
    output reg  [ID_WIDTH-1:0]     m_arid,
    output reg  [ADDR_WIDTH-1:0]   m_araddr,
    output reg  [3:0]              m_arlen,    // AXI3: 4-bit len
    output reg  [2:0]              m_arsize,
    output reg  [1:0]              m_arburst,
    output reg                     m_arvalid,
    input  wire                    m_arready,

    // AXI3 Master — Read Data
    input  wire [ID_WIDTH-1:0]     m_rid,
    input  wire [DATA_WIDTH-1:0]   m_rdata,
    input  wire [1:0]              m_rresp,
    input  wire                    m_rlast,
    input  wire                    m_rvalid,
    output reg                     m_rready
);

    // -----------------------------------------------------------------------
    // Write Channel — burst splitting FSM
    // -----------------------------------------------------------------------
    localparam WR_IDLE    = 2'd0;
    localparam WR_ISSUE   = 2'd1;
    localparam WR_DATA    = 2'd2;
    localparam WR_RESP    = 2'd3;

    reg [1:0]              wr_state;
    reg [ID_WIDTH-1:0]     wr_id;
    reg [ADDR_WIDTH-1:0]   wr_addr;
    reg [2:0]              wr_size;
    reg [1:0]              wr_burst;
    reg [8:0]              wr_beats_remaining; // total beats left (0-based count + 1)
    reg [3:0]              wr_sub_len;         // current sub-burst len (0-based)
    reg [3:0]              wr_sub_beat_cnt;    // beats sent in current sub-burst
    reg [8:0]              wr_sub_total;       // total sub-bursts expected
    reg [8:0]              wr_sub_resp_cnt;    // sub-burst responses received
    reg [1:0]              wr_worst_resp;

    // Compute beat size in bytes: 1 << awsize
    wire [15:0] wr_beat_bytes = (16'd1 << wr_size);

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_state          <= WR_IDLE;
            s_awready         <= 1'b0;
            s_wready          <= 1'b0;
            s_bvalid          <= 1'b0;
            s_bid             <= {ID_WIDTH{1'b0}};
            s_bresp           <= 2'b00;
            m_awvalid         <= 1'b0;
            m_awid            <= {ID_WIDTH{1'b0}};
            m_awaddr          <= {ADDR_WIDTH{1'b0}};
            m_awlen           <= 4'd0;
            m_awsize          <= 3'd0;
            m_awburst         <= 2'b01;
            m_wvalid          <= 1'b0;
            m_wdata           <= {DATA_WIDTH{1'b0}};
            m_wstrb           <= {STRB_WIDTH{1'b0}};
            m_wlast           <= 1'b0;
            m_bready          <= 1'b0;
            wr_beats_remaining <= 9'd0;
            wr_sub_len        <= 4'd0;
            wr_sub_beat_cnt   <= 4'd0;
            wr_sub_total      <= 9'd0;
            wr_sub_resp_cnt   <= 9'd0;
            wr_worst_resp     <= 2'b00;
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    // Do NOT unconditionally clear s_bvalid — let handshake logic handle it
                    s_awready <= 1'b1;
                    s_wready  <= 1'b0;
                    m_bready  <= 1'b0;
                    if (s_awvalid && s_awready) begin
                        s_awready          <= 1'b0;
                        wr_id              <= s_awid;
                        wr_addr            <= s_awaddr;
                        wr_size            <= s_awsize;
                        wr_burst           <= s_awburst;
                        wr_beats_remaining <= {1'b0, s_awlen} + 9'd1;
                        wr_sub_total       <= 9'd0;
                        wr_sub_resp_cnt    <= 9'd0;
                        wr_worst_resp      <= 2'b00;
                        wr_state           <= WR_ISSUE;
                    end
                end

                WR_ISSUE: begin
                    // Determine sub-burst length (parameterized for downstream width converter)
                    if (wr_beats_remaining > {5'd0, MAX_AXI3_LEN[3:0]} + 9'd1) begin
                        wr_sub_len <= MAX_AXI3_LEN[3:0];
                    end else begin
                        wr_sub_len <= wr_beats_remaining[3:0] - 4'd1;
                    end
                    // Issue AW
                    m_awvalid  <= 1'b1;
                    m_awid     <= wr_id;
                    m_awaddr   <= wr_addr;
                    m_awsize   <= wr_size;
                    m_awburst  <= wr_burst;
                    if (wr_beats_remaining > {5'd0, MAX_AXI3_LEN[3:0]} + 9'd1)
                        m_awlen <= MAX_AXI3_LEN[3:0];
                    else
                        m_awlen <= wr_beats_remaining[3:0] - 4'd1;

                    if (m_awvalid && m_awready) begin
                        m_awvalid       <= 1'b0;
                        wr_sub_beat_cnt <= 4'd0;
                        wr_sub_total    <= wr_sub_total + 9'd1;
                        wr_state        <= WR_DATA;
                    end
                end

                WR_DATA: begin
                    // Pipeline register W channel:
                    // After accepting a beat, deassert s_wready for 1 cycle
                    // to prevent double-counting when TB updates data
                    if (s_wvalid && s_wready) begin
                        // Accept upstream beat into pipeline register
                        m_wvalid <= 1'b1;
                        m_wdata  <= s_wdata;
                        m_wstrb  <= s_wstrb;
                        m_wlast  <= (wr_sub_beat_cnt == wr_sub_len);
                        s_wready <= 1'b0;  // Pause until downstream drains

                        wr_sub_beat_cnt    <= wr_sub_beat_cnt + 4'd1;
                        wr_beats_remaining <= wr_beats_remaining - 9'd1;

                        if (wr_sub_beat_cnt == wr_sub_len) begin
                            // Sub-burst complete
                            wr_addr  <= wr_addr + (({12'b0, wr_sub_len} + 16'd1) * wr_beat_bytes);
                            wr_state <= WR_RESP;
                            m_bready <= 1'b1;
                        end
                    end else if (m_wvalid && m_wready) begin
                        // Downstream consumed — clear register, re-enable upstream
                        m_wvalid <= 1'b0;
                        s_wready <= 1'b1;
                    end else if (!m_wvalid) begin
                        // Register empty, ensure ready is high
                        s_wready <= 1'b1;
                    end
                end

                WR_RESP: begin
                    // Drain any remaining m_wvalid (last beat still pending)
                    if (m_wvalid && m_wready)
                        m_wvalid <= 1'b0;

                    m_bready <= 1'b1;
                    if (m_bvalid && m_bready) begin
                        m_bready        <= 1'b0;
                        wr_sub_resp_cnt <= wr_sub_resp_cnt + 9'd1;
                        // Track worst-case response
                        if (m_bresp > wr_worst_resp)
                            wr_worst_resp <= m_bresp;

                        if (wr_beats_remaining == 9'd0) begin
                            // All sub-bursts done
                            s_bvalid <= 1'b1;
                            s_bid    <= wr_id;
                            s_bresp  <= (m_bresp > wr_worst_resp) ? m_bresp : wr_worst_resp;
                            wr_state <= WR_IDLE;
                        end else begin
                            wr_state <= WR_ISSUE;
                        end
                    end
                end
            endcase

            // Clear bvalid on handshake (works in all states)
            if (s_bvalid && s_bready)
                s_bvalid <= 1'b0;
        end
    end

    // -----------------------------------------------------------------------
    // Read Channel — burst splitting FSM
    // -----------------------------------------------------------------------
    localparam RD_IDLE    = 2'd0;
    localparam RD_ISSUE   = 2'd1;
    localparam RD_DATA    = 2'd2;

    reg [1:0]              rd_state;
    reg [ID_WIDTH-1:0]     rd_id;
    reg [ADDR_WIDTH-1:0]   rd_addr;
    reg [2:0]              rd_size;
    reg [1:0]              rd_burst;
    reg [8:0]              rd_beats_remaining;
    reg [3:0]              rd_sub_len;
    reg [1:0]              rd_worst_rresp;

    wire [15:0] rd_beat_bytes = (16'd1 << rd_size);

    always @(posedge clk) begin
        if (!rst_n) begin
            rd_state          <= RD_IDLE;
            s_arready         <= 1'b0;
            s_rvalid          <= 1'b0;
            s_rid             <= {ID_WIDTH{1'b0}};
            s_rdata           <= {DATA_WIDTH{1'b0}};
            s_rresp           <= 2'b00;
            s_rlast           <= 1'b0;
            m_arvalid         <= 1'b0;
            m_arid            <= {ID_WIDTH{1'b0}};
            m_araddr          <= {ADDR_WIDTH{1'b0}};
            m_arlen           <= 4'd0;
            m_arsize          <= 3'd0;
            m_arburst         <= 2'b01;
            m_rready          <= 1'b0;
            rd_beats_remaining <= 9'd0;
            rd_sub_len        <= 4'd0;
            rd_worst_rresp    <= 2'b00;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    // Do NOT unconditionally clear s_rvalid — let handshake logic handle it
                    s_arready <= 1'b1;
                    if (s_arvalid && s_arready) begin
                        s_arready          <= 1'b0;
                        rd_id              <= s_arid;
                        rd_addr            <= s_araddr;
                        rd_size            <= s_arsize;
                        rd_burst           <= s_arburst;
                        rd_beats_remaining <= {1'b0, s_arlen} + 9'd1;
                        rd_worst_rresp     <= 2'b00;
                        rd_state           <= RD_ISSUE;
                    end
                end

                RD_ISSUE: begin
                    if (rd_beats_remaining > {5'd0, MAX_AXI3_LEN[3:0]} + 9'd1) begin
                        rd_sub_len <= MAX_AXI3_LEN[3:0];
                    end else begin
                        rd_sub_len <= rd_beats_remaining[3:0] - 4'd1;
                    end

                    m_arvalid  <= 1'b1;
                    m_arid     <= rd_id;
                    m_araddr   <= rd_addr;
                    m_arsize   <= rd_size;
                    m_arburst  <= rd_burst;
                    if (rd_beats_remaining > {5'd0, MAX_AXI3_LEN[3:0]} + 9'd1)
                        m_arlen <= MAX_AXI3_LEN[3:0];
                    else
                        m_arlen <= rd_beats_remaining[3:0] - 4'd1;

                    if (m_arvalid && m_arready) begin
                        m_arvalid <= 1'b0;
                        m_rready  <= 1'b1;
                        rd_state  <= RD_DATA;
                    end
                end

                RD_DATA: begin
                    m_rready <= 1'b1;
                    if (m_rvalid && m_rready) begin
                        // Forward data
                        s_rvalid <= 1'b1;
                        s_rid    <= rd_id;
                        s_rdata  <= m_rdata;
                        // Track worst response
                        if (m_rresp > rd_worst_rresp)
                            rd_worst_rresp <= m_rresp;
                        s_rresp <= (m_rresp > rd_worst_rresp) ? m_rresp : rd_worst_rresp;

                        rd_beats_remaining <= rd_beats_remaining - 9'd1;

                        if (m_rlast) begin
                            m_rready <= 1'b0;
                            // Update address for next sub-burst
                            rd_addr <= rd_addr + (({12'b0, rd_sub_len} + 16'd1) * rd_beat_bytes);

                            if (rd_beats_remaining == 9'd1) begin
                                // Final beat of final sub-burst
                                s_rlast  <= 1'b1;
                                rd_state <= RD_IDLE;
                            end else begin
                                s_rlast  <= 1'b0;
                                rd_state <= RD_ISSUE;
                            end
                        end else begin
                            s_rlast <= 1'b0;
                        end
                    end
                end

                default: rd_state <= RD_IDLE;
            endcase

            // Clear rvalid on handshake (works in all states, except when new data arriving)
            if (s_rvalid && s_rready && !(m_rvalid && m_rready))
                s_rvalid <= 1'b0;
        end
    end

endmodule
