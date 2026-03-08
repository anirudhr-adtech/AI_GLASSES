`timescale 1ns/1ps
//============================================================================
// Module:      axilite_mux
// Project:     AI_GLASSES — AXI Interconnect
// Description: AXI-Lite response multiplexer. Routes read/write responses
//              from selected peripheral back to bridge. 11 slave ports.
//============================================================================

module axilite_mux #(
    parameter NUM_SLAVES = 11,
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // Peripheral select from decoder
    input  wire [3:0]              periph_sel_i,

    // AXI-Lite master (from bridge, single)
    input  wire [ADDR_WIDTH-1:0]   s_axil_awaddr,
    input  wire [2:0]              s_axil_awprot,
    input  wire                    s_axil_awvalid,
    output reg                     s_axil_awready,

    input  wire [DATA_WIDTH-1:0]   s_axil_wdata,
    input  wire [DATA_WIDTH/8-1:0] s_axil_wstrb,
    input  wire                    s_axil_wvalid,
    output reg                     s_axil_wready,

    output reg  [1:0]              s_axil_bresp,
    output reg                     s_axil_bvalid,
    input  wire                    s_axil_bready,

    input  wire [ADDR_WIDTH-1:0]   s_axil_araddr,
    input  wire [2:0]              s_axil_arprot,
    input  wire                    s_axil_arvalid,
    output reg                     s_axil_arready,

    output reg  [DATA_WIDTH-1:0]   s_axil_rdata,
    output reg  [1:0]              s_axil_rresp,
    output reg                     s_axil_rvalid,
    input  wire                    s_axil_rready,

    // Peripheral AXI-Lite ports (packed arrays, NUM_SLAVES ports)
    output reg  [NUM_SLAVES*ADDR_WIDTH-1:0]    m_axil_awaddr,
    output reg  [NUM_SLAVES*3-1:0]             m_axil_awprot,
    output reg  [NUM_SLAVES-1:0]               m_axil_awvalid,
    input  wire [NUM_SLAVES-1:0]               m_axil_awready,

    output reg  [NUM_SLAVES*DATA_WIDTH-1:0]    m_axil_wdata,
    output reg  [NUM_SLAVES*(DATA_WIDTH/8)-1:0] m_axil_wstrb,
    output reg  [NUM_SLAVES-1:0]               m_axil_wvalid,
    input  wire [NUM_SLAVES-1:0]               m_axil_wready,

    input  wire [NUM_SLAVES*2-1:0]             m_axil_bresp,
    input  wire [NUM_SLAVES-1:0]               m_axil_bvalid,
    output reg  [NUM_SLAVES-1:0]               m_axil_bready,

    output reg  [NUM_SLAVES*ADDR_WIDTH-1:0]    m_axil_araddr,
    output reg  [NUM_SLAVES*3-1:0]             m_axil_arprot,
    output reg  [NUM_SLAVES-1:0]               m_axil_arvalid,
    input  wire [NUM_SLAVES-1:0]               m_axil_arready,

    input  wire [NUM_SLAVES*DATA_WIDTH-1:0]    m_axil_rdata,
    input  wire [NUM_SLAVES*2-1:0]             m_axil_rresp,
    input  wire [NUM_SLAVES-1:0]               m_axil_rvalid,
    output reg  [NUM_SLAVES-1:0]               m_axil_rready
);

    localparam RESP_SLVERR = 2'b10;

    // Write path state
    localparam WR_IDLE = 2'd0;
    localparam WR_WAIT = 2'd1;
    localparam WR_RESP = 2'd2;
    localparam WR_ERR  = 2'd3;

    reg [1:0] wr_state;
    reg [3:0] wr_sel;

    // Read path state
    localparam RD_IDLE = 2'd0;
    localparam RD_WAIT = 2'd1;
    localparam RD_RESP = 2'd2;
    localparam RD_ERR  = 2'd3;

    reg [1:0] rd_state;
    reg [3:0] rd_sel;

    integer i;

    // Write path
    always @(posedge clk) begin
        if (!rst_n) begin
            wr_state       <= WR_IDLE;
            s_axil_awready <= 1'b0;
            s_axil_wready  <= 1'b0;
            s_axil_bvalid  <= 1'b0;
            s_axil_bresp   <= 2'b00;
            m_axil_awvalid <= {NUM_SLAVES{1'b0}};
            m_axil_wvalid  <= {NUM_SLAVES{1'b0}};
            m_axil_bready  <= {NUM_SLAVES{1'b0}};
            wr_sel         <= 4'd0;
            for (i = 0; i < NUM_SLAVES; i = i + 1) begin
                m_axil_awaddr[i*ADDR_WIDTH +: ADDR_WIDTH] <= {ADDR_WIDTH{1'b0}};
                m_axil_awprot[i*3 +: 3] <= 3'b000;
                m_axil_wdata[i*DATA_WIDTH +: DATA_WIDTH] <= {DATA_WIDTH{1'b0}};
                m_axil_wstrb[i*(DATA_WIDTH/8) +: (DATA_WIDTH/8)] <= {(DATA_WIDTH/8){1'b0}};
            end
        end else begin
            case (wr_state)
                WR_IDLE: begin
                    s_axil_bvalid  <= 1'b0;
                    s_axil_awready <= 1'b1;
                    s_axil_wready  <= 1'b1;

                    if (s_axil_awvalid && s_axil_awready && s_axil_wvalid && s_axil_wready) begin
                        s_axil_awready <= 1'b0;
                        s_axil_wready  <= 1'b0;
                        wr_sel <= periph_sel_i;

                        if (periph_sel_i >= NUM_SLAVES) begin
                            // Error - unmapped
                            s_axil_bresp  <= RESP_SLVERR;
                            s_axil_bvalid <= 1'b1;
                            wr_state      <= WR_ERR;
                        end else begin
                            // Forward to selected peripheral
                            m_axil_awaddr[periph_sel_i*ADDR_WIDTH +: ADDR_WIDTH] <= s_axil_awaddr;
                            m_axil_awprot[periph_sel_i*3 +: 3] <= s_axil_awprot;
                            m_axil_awvalid[periph_sel_i] <= 1'b1;
                            m_axil_wdata[periph_sel_i*DATA_WIDTH +: DATA_WIDTH] <= s_axil_wdata;
                            m_axil_wstrb[periph_sel_i*(DATA_WIDTH/8) +: (DATA_WIDTH/8)] <= s_axil_wstrb;
                            m_axil_wvalid[periph_sel_i] <= 1'b1;
                            wr_state <= WR_WAIT;
                        end
                    end
                end
                WR_WAIT: begin
                    if (m_axil_awvalid[wr_sel] && m_axil_awready[wr_sel])
                        m_axil_awvalid[wr_sel] <= 1'b0;
                    if (m_axil_wvalid[wr_sel] && m_axil_wready[wr_sel])
                        m_axil_wvalid[wr_sel] <= 1'b0;

                    if (!m_axil_awvalid[wr_sel] && !m_axil_wvalid[wr_sel]) begin
                        m_axil_bready[wr_sel] <= 1'b1;
                    end

                    if (m_axil_bvalid[wr_sel] && m_axil_bready[wr_sel]) begin
                        m_axil_bready[wr_sel] <= 1'b0;
                        s_axil_bresp  <= m_axil_bresp[wr_sel*2 +: 2];
                        s_axil_bvalid <= 1'b1;
                        wr_state      <= WR_RESP;
                    end
                end
                WR_RESP: begin
                    if (s_axil_bvalid && s_axil_bready) begin
                        s_axil_bvalid <= 1'b0;
                        wr_state      <= WR_IDLE;
                    end
                end
                WR_ERR: begin
                    if (s_axil_bvalid && s_axil_bready) begin
                        s_axil_bvalid <= 1'b0;
                        wr_state      <= WR_IDLE;
                    end
                end
            endcase
        end
    end

    // Read path
    always @(posedge clk) begin
        if (!rst_n) begin
            rd_state       <= RD_IDLE;
            s_axil_arready <= 1'b0;
            s_axil_rvalid  <= 1'b0;
            s_axil_rdata   <= {DATA_WIDTH{1'b0}};
            s_axil_rresp   <= 2'b00;
            m_axil_arvalid <= {NUM_SLAVES{1'b0}};
            m_axil_rready  <= {NUM_SLAVES{1'b0}};
            rd_sel         <= 4'd0;
            for (i = 0; i < NUM_SLAVES; i = i + 1) begin
                m_axil_araddr[i*ADDR_WIDTH +: ADDR_WIDTH] <= {ADDR_WIDTH{1'b0}};
                m_axil_arprot[i*3 +: 3] <= 3'b000;
            end
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    s_axil_rvalid  <= 1'b0;
                    s_axil_arready <= 1'b1;

                    if (s_axil_arvalid && s_axil_arready) begin
                        s_axil_arready <= 1'b0;
                        rd_sel <= periph_sel_i;

                        if (periph_sel_i >= NUM_SLAVES) begin
                            s_axil_rdata  <= {DATA_WIDTH{1'b0}};
                            s_axil_rresp  <= RESP_SLVERR;
                            s_axil_rvalid <= 1'b1;
                            rd_state      <= RD_ERR;
                        end else begin
                            m_axil_araddr[periph_sel_i*ADDR_WIDTH +: ADDR_WIDTH] <= s_axil_araddr;
                            m_axil_arprot[periph_sel_i*3 +: 3] <= s_axil_arprot;
                            m_axil_arvalid[periph_sel_i] <= 1'b1;
                            rd_state <= RD_WAIT;
                        end
                    end
                end
                RD_WAIT: begin
                    if (m_axil_arvalid[rd_sel] && m_axil_arready[rd_sel]) begin
                        m_axil_arvalid[rd_sel] <= 1'b0;
                        m_axil_rready[rd_sel]  <= 1'b1;
                    end

                    if (m_axil_rvalid[rd_sel] && m_axil_rready[rd_sel]) begin
                        m_axil_rready[rd_sel] <= 1'b0;
                        s_axil_rdata  <= m_axil_rdata[rd_sel*DATA_WIDTH +: DATA_WIDTH];
                        s_axil_rresp  <= m_axil_rresp[rd_sel*2 +: 2];
                        s_axil_rvalid <= 1'b1;
                        rd_state      <= RD_RESP;
                    end
                end
                RD_RESP: begin
                    if (s_axil_rvalid && s_axil_rready) begin
                        s_axil_rvalid <= 1'b0;
                        rd_state      <= RD_IDLE;
                    end
                end
                RD_ERR: begin
                    if (s_axil_rvalid && s_axil_rready) begin
                        s_axil_rvalid <= 1'b0;
                        rd_state      <= RD_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
