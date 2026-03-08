`timescale 1ns/1ps
//============================================================================
// Module : axi_to_axilite_bridge
// Project : AI_GLASSES — RISC-V Subsystem
// Description : Protocol bridge converting AXI4 slave to AXI4-Lite master.
//               Single-beat pass-through only; rejects bursts with SLVERR.
//               Strips AXI IDs and returns them on responses.
//============================================================================

module riscv_axi_to_axilite_bridge #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    parameter ID_WIDTH   = 4
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // AXI4 Slave interface (from interconnect)
    // Write Address
    input  wire [ADDR_WIDTH-1:0]   s_axi_awaddr,
    input  wire                    s_axi_awvalid,
    output wire                    s_axi_awready,
    input  wire [ID_WIDTH-1:0]     s_axi_awid,
    input  wire [7:0]              s_axi_awlen,
    input  wire [2:0]              s_axi_awsize,
    input  wire [1:0]              s_axi_awburst,
    // Write Data
    input  wire [DATA_WIDTH-1:0]   s_axi_wdata,
    input  wire [DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  wire                    s_axi_wvalid,
    input  wire                    s_axi_wlast,
    output wire                    s_axi_wready,
    // Write Response
    output wire [ID_WIDTH-1:0]     s_axi_bid,
    output wire [1:0]              s_axi_bresp,
    output wire                    s_axi_bvalid,
    input  wire                    s_axi_bready,
    // Read Address
    input  wire [ADDR_WIDTH-1:0]   s_axi_araddr,
    input  wire                    s_axi_arvalid,
    output wire                    s_axi_arready,
    input  wire [ID_WIDTH-1:0]     s_axi_arid,
    input  wire [7:0]              s_axi_arlen,
    input  wire [2:0]              s_axi_arsize,
    input  wire [1:0]              s_axi_arburst,
    // Read Data
    output wire [DATA_WIDTH-1:0]   s_axi_rdata,
    output wire [1:0]              s_axi_rresp,
    output wire                    s_axi_rvalid,
    output wire [ID_WIDTH-1:0]     s_axi_rid,
    output wire                    s_axi_rlast,
    input  wire                    s_axi_rready,

    // AXI4-Lite Master interface (to peripheral fabric)
    // Write Address
    output wire [ADDR_WIDTH-1:0]   m_axil_awaddr,
    output wire                    m_axil_awvalid,
    input  wire                    m_axil_awready,
    // Write Data
    output wire [DATA_WIDTH-1:0]   m_axil_wdata,
    output wire [DATA_WIDTH/8-1:0] m_axil_wstrb,
    output wire                    m_axil_wvalid,
    input  wire                    m_axil_wready,
    // Write Response
    input  wire [1:0]              m_axil_bresp,
    input  wire                    m_axil_bvalid,
    output wire                    m_axil_bready,
    // Read Address
    output wire [ADDR_WIDTH-1:0]   m_axil_araddr,
    output wire                    m_axil_arvalid,
    input  wire                    m_axil_arready,
    // Read Data
    input  wire [DATA_WIDTH-1:0]   m_axil_rdata,
    input  wire [1:0]              m_axil_rresp,
    input  wire                    m_axil_rvalid,
    output wire                    m_axil_rready
);

    // FSM states
    localparam [2:0] IDLE    = 3'd0,
                     WR_ADDR = 3'd1,
                     WR_DATA = 3'd2,
                     WR_RESP = 3'd3,
                     RD_ADDR = 3'd4,
                     RD_RESP = 3'd5,
                     BURST_REJECT_W = 3'd6,
                     BURST_REJECT_R = 3'd7;

    reg [2:0]              state_r;
    reg [ADDR_WIDTH-1:0]   addr_r;
    reg [ID_WIDTH-1:0]     id_r;
    reg [DATA_WIDTH-1:0]   wdata_r;
    reg [DATA_WIDTH/8-1:0] wstrb_r;
    reg                    is_burst_r;

    // AXI4 slave output regs
    reg                    s_awready_r;
    reg                    s_wready_r;
    reg [ID_WIDTH-1:0]     s_bid_r;
    reg [1:0]              s_bresp_r;
    reg                    s_bvalid_r;
    reg                    s_arready_r;
    reg [DATA_WIDTH-1:0]   s_rdata_r;
    reg [1:0]              s_rresp_r;
    reg                    s_rvalid_r;
    reg [ID_WIDTH-1:0]     s_rid_r;
    reg                    s_rlast_r;

    // AXI-Lite master output regs
    reg [ADDR_WIDTH-1:0]   m_awaddr_r;
    reg                    m_awvalid_r;
    reg [DATA_WIDTH-1:0]   m_wdata_r;
    reg [DATA_WIDTH/8-1:0] m_wstrb_r;
    reg                    m_wvalid_r;
    reg                    m_bready_r;
    reg [ADDR_WIDTH-1:0]   m_araddr_r;
    reg                    m_arvalid_r;
    reg                    m_rready_r;

    // Outputs
    assign s_axi_awready  = s_awready_r;
    assign s_axi_wready   = s_wready_r;
    assign s_axi_bid      = s_bid_r;
    assign s_axi_bresp    = s_bresp_r;
    assign s_axi_bvalid   = s_bvalid_r;
    assign s_axi_arready  = s_arready_r;
    assign s_axi_rdata    = s_rdata_r;
    assign s_axi_rresp    = s_rresp_r;
    assign s_axi_rvalid   = s_rvalid_r;
    assign s_axi_rid      = s_rid_r;
    assign s_axi_rlast    = s_rlast_r;

    assign m_axil_awaddr  = m_awaddr_r;
    assign m_axil_awvalid = m_awvalid_r;
    assign m_axil_wdata   = m_wdata_r;
    assign m_axil_wstrb   = m_wstrb_r;
    assign m_axil_wvalid  = m_wvalid_r;
    assign m_axil_bready  = m_bready_r;
    assign m_axil_araddr  = m_araddr_r;
    assign m_axil_arvalid = m_arvalid_r;
    assign m_axil_rready  = m_rready_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            state_r     <= IDLE;
            addr_r      <= {ADDR_WIDTH{1'b0}};
            id_r        <= {ID_WIDTH{1'b0}};
            wdata_r     <= {DATA_WIDTH{1'b0}};
            wstrb_r     <= {(DATA_WIDTH/8){1'b0}};
            is_burst_r  <= 1'b0;
            s_awready_r <= 1'b0;
            s_wready_r  <= 1'b0;
            s_bid_r     <= {ID_WIDTH{1'b0}};
            s_bresp_r   <= 2'b00;
            s_bvalid_r  <= 1'b0;
            s_arready_r <= 1'b0;
            s_rdata_r   <= {DATA_WIDTH{1'b0}};
            s_rresp_r   <= 2'b00;
            s_rvalid_r  <= 1'b0;
            s_rid_r     <= {ID_WIDTH{1'b0}};
            s_rlast_r   <= 1'b0;
            m_awaddr_r  <= {ADDR_WIDTH{1'b0}};
            m_awvalid_r <= 1'b0;
            m_wdata_r   <= {DATA_WIDTH{1'b0}};
            m_wstrb_r   <= {(DATA_WIDTH/8){1'b0}};
            m_wvalid_r  <= 1'b0;
            m_bready_r  <= 1'b0;
            m_araddr_r  <= {ADDR_WIDTH{1'b0}};
            m_arvalid_r <= 1'b0;
            m_rready_r  <= 1'b0;
        end else begin
            // Default deassert handshake signals
            s_awready_r <= 1'b0;
            s_wready_r  <= 1'b0;
            s_arready_r <= 1'b0;

            case (state_r)
                IDLE: begin
                    s_bvalid_r  <= 1'b0;
                    s_rvalid_r  <= 1'b0;
                    s_rlast_r   <= 1'b0;
                    m_awvalid_r <= 1'b0;
                    m_wvalid_r  <= 1'b0;
                    m_arvalid_r <= 1'b0;
                    m_bready_r  <= 1'b0;
                    m_rready_r  <= 1'b0;

                    // Write request takes priority
                    if (s_axi_awvalid) begin
                        s_awready_r <= 1'b1;
                        addr_r      <= s_axi_awaddr;
                        id_r        <= s_axi_awid;
                        is_burst_r  <= (s_axi_awlen != 8'd0);
                        if (s_axi_awlen != 8'd0) begin
                            // Burst: accept AW, then consume W beats and reject
                            state_r <= BURST_REJECT_W;
                        end else begin
                            state_r <= WR_ADDR;
                        end
                    end else if (s_axi_arvalid) begin
                        s_arready_r <= 1'b1;
                        addr_r      <= s_axi_araddr;
                        id_r        <= s_axi_arid;
                        is_burst_r  <= (s_axi_arlen != 8'd0);
                        if (s_axi_arlen != 8'd0) begin
                            // Burst read: reject immediately
                            state_r <= BURST_REJECT_R;
                        end else begin
                            state_r <= RD_ADDR;
                        end
                    end
                end

                // --- Write path ---
                WR_ADDR: begin
                    // Wait for W data from AXI slave side
                    if (s_axi_wvalid) begin
                        s_wready_r  <= 1'b1;
                        wdata_r     <= s_axi_wdata;
                        wstrb_r     <= s_axi_wstrb;
                        // Forward to AXI-Lite master
                        m_awaddr_r  <= addr_r;
                        m_awvalid_r <= 1'b1;
                        m_wdata_r   <= s_axi_wdata;
                        m_wstrb_r   <= s_axi_wstrb;
                        m_wvalid_r  <= 1'b1;
                        state_r     <= WR_DATA;
                    end
                end

                WR_DATA: begin
                    // Wait for AXI-Lite AW and W handshakes
                    if (m_axil_awready && m_awvalid_r)
                        m_awvalid_r <= 1'b0;
                    if (m_axil_wready && m_wvalid_r)
                        m_wvalid_r <= 1'b0;

                    if ((!m_awvalid_r || m_axil_awready) && (!m_wvalid_r || m_axil_wready)) begin
                        m_awvalid_r <= 1'b0;
                        m_wvalid_r  <= 1'b0;
                        m_bready_r  <= 1'b1;
                        state_r     <= WR_RESP;
                    end
                end

                WR_RESP: begin
                    if (m_axil_bvalid && m_bready_r) begin
                        m_bready_r <= 1'b0;
                        s_bid_r    <= id_r;
                        s_bresp_r  <= m_axil_bresp;
                        s_bvalid_r <= 1'b1;
                        state_r    <= IDLE;
                    end
                end

                // --- Read path ---
                RD_ADDR: begin
                    m_araddr_r  <= addr_r;
                    m_arvalid_r <= 1'b1;
                    state_r     <= RD_RESP;
                end

                RD_RESP: begin
                    if (m_axil_arready && m_arvalid_r)
                        m_arvalid_r <= 1'b0;

                    if (!m_arvalid_r || m_axil_arready) begin
                        m_arvalid_r <= 1'b0;
                        m_rready_r  <= 1'b1;
                    end

                    if (m_axil_rvalid && m_rready_r) begin
                        m_rready_r <= 1'b0;
                        s_rdata_r  <= m_axil_rdata;
                        s_rresp_r  <= m_axil_rresp;
                        s_rid_r    <= id_r;
                        s_rlast_r  <= 1'b1;
                        s_rvalid_r <= 1'b1;
                        state_r    <= IDLE;
                    end
                end

                // --- Burst rejection ---
                BURST_REJECT_W: begin
                    // Consume the W beat (there should be wlast eventually)
                    if (s_axi_wvalid) begin
                        s_wready_r <= 1'b1;
                        if (s_axi_wlast) begin
                            s_bid_r    <= id_r;
                            s_bresp_r  <= 2'b10;  // SLVERR
                            s_bvalid_r <= 1'b1;
                            state_r    <= IDLE;
                        end
                    end
                end

                BURST_REJECT_R: begin
                    s_rdata_r  <= {DATA_WIDTH{1'b0}};
                    s_rresp_r  <= 2'b10;  // SLVERR
                    s_rid_r    <= id_r;
                    s_rlast_r  <= 1'b1;
                    s_rvalid_r <= 1'b1;
                    state_r    <= IDLE;
                end

                default: state_r <= IDLE;
            endcase

            // Clear response valids on handshake
            if (s_bvalid_r && s_axi_bready)
                s_bvalid_r <= 1'b0;
            if (s_rvalid_r && s_axi_rready) begin
                s_rvalid_r <= 1'b0;
                s_rlast_r  <= 1'b0;
            end
        end
    end

endmodule
