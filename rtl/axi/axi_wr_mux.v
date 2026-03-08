`timescale 1ns/1ps
//============================================================================
// Module:      axi_wr_mux
// Project:     AI_GLASSES — AXI Interconnect
// Description: Write channel multiplexer (AW + W). Selects granted master's
//              write address and write data signals to forward to slave.
//============================================================================

module axi_wr_mux #(
    parameter NUM_MASTERS = 5,
    parameter DATA_WIDTH  = 32,
    parameter ADDR_WIDTH  = 32,
    parameter ID_WIDTH    = 6
)(
    input  wire                                clk,
    input  wire                                rst_n,

    // Grant from arbiter (one-hot)
    input  wire [NUM_MASTERS-1:0]              grant_i,

    // Master-side AW channels (packed arrays)
    input  wire [NUM_MASTERS*ID_WIDTH-1:0]     m_awid_i,
    input  wire [NUM_MASTERS*ADDR_WIDTH-1:0]   m_awaddr_i,
    input  wire [NUM_MASTERS*8-1:0]            m_awlen_i,
    input  wire [NUM_MASTERS*3-1:0]            m_awsize_i,
    input  wire [NUM_MASTERS*2-1:0]            m_awburst_i,
    input  wire [NUM_MASTERS-1:0]              m_awvalid_i,
    output reg  [NUM_MASTERS-1:0]              m_awready_o,

    // Master-side W channels (packed arrays)
    input  wire [NUM_MASTERS*DATA_WIDTH-1:0]   m_wdata_i,
    input  wire [NUM_MASTERS*(DATA_WIDTH/8)-1:0] m_wstrb_i,
    input  wire [NUM_MASTERS-1:0]              m_wlast_i,
    input  wire [NUM_MASTERS-1:0]              m_wvalid_i,
    output reg  [NUM_MASTERS-1:0]              m_wready_o,

    // Slave-side AW channel (single)
    output reg  [ID_WIDTH-1:0]                 s_awid_o,
    output reg  [ADDR_WIDTH-1:0]               s_awaddr_o,
    output reg  [7:0]                          s_awlen_o,
    output reg  [2:0]                          s_awsize_o,
    output reg  [1:0]                          s_awburst_o,
    output reg                                 s_awvalid_o,
    input  wire                                s_awready_i,

    // Slave-side W channel (single)
    output reg  [DATA_WIDTH-1:0]               s_wdata_o,
    output reg  [(DATA_WIDTH/8)-1:0]           s_wstrb_o,
    output reg                                 s_wlast_o,
    output reg                                 s_wvalid_o,
    input  wire                                s_wready_i
);

    localparam STRB_WIDTH = DATA_WIDTH / 8;

    // Find granted master index
    reg [2:0] sel;
    reg       sel_valid;
    integer i;

    always @(*) begin
        sel       = 3'd0;
        sel_valid = 1'b0;
        for (i = 0; i < NUM_MASTERS; i = i + 1) begin
            if (grant_i[i]) begin
                sel       = i[2:0];
                sel_valid = 1'b1;
            end
        end
    end

    // AW channel mux - registered
    always @(posedge clk) begin
        if (!rst_n) begin
            s_awid_o    <= {ID_WIDTH{1'b0}};
            s_awaddr_o  <= {ADDR_WIDTH{1'b0}};
            s_awlen_o   <= 8'd0;
            s_awsize_o  <= 3'd0;
            s_awburst_o <= 2'd0;
            s_awvalid_o <= 1'b0;
            m_awready_o <= {NUM_MASTERS{1'b0}};
        end else begin
            if (sel_valid) begin
                s_awid_o    <= m_awid_i[sel*ID_WIDTH +: ID_WIDTH];
                s_awaddr_o  <= m_awaddr_i[sel*ADDR_WIDTH +: ADDR_WIDTH];
                s_awlen_o   <= m_awlen_i[sel*8 +: 8];
                s_awsize_o  <= m_awsize_i[sel*3 +: 3];
                s_awburst_o <= m_awburst_i[sel*2 +: 2];
                s_awvalid_o <= m_awvalid_i[sel];

                m_awready_o <= {NUM_MASTERS{1'b0}};
                m_awready_o[sel] <= s_awready_i;
            end else begin
                s_awvalid_o <= 1'b0;
                m_awready_o <= {NUM_MASTERS{1'b0}};
            end
        end
    end

    // W channel mux - registered
    always @(posedge clk) begin
        if (!rst_n) begin
            s_wdata_o   <= {DATA_WIDTH{1'b0}};
            s_wstrb_o   <= {STRB_WIDTH{1'b0}};
            s_wlast_o   <= 1'b0;
            s_wvalid_o  <= 1'b0;
            m_wready_o  <= {NUM_MASTERS{1'b0}};
        end else begin
            if (sel_valid) begin
                s_wdata_o  <= m_wdata_i[sel*DATA_WIDTH +: DATA_WIDTH];
                s_wstrb_o  <= m_wstrb_i[sel*STRB_WIDTH +: STRB_WIDTH];
                s_wlast_o  <= m_wlast_i[sel];
                s_wvalid_o <= m_wvalid_i[sel];

                m_wready_o <= {NUM_MASTERS{1'b0}};
                m_wready_o[sel] <= s_wready_i;
            end else begin
                s_wvalid_o <= 1'b0;
                m_wready_o <= {NUM_MASTERS{1'b0}};
            end
        end
    end

endmodule
