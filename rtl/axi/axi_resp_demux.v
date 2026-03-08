`timescale 1ns/1ps
//============================================================================
// Module:      axi_resp_demux
// Project:     AI_GLASSES — AXI Interconnect
// Description: Response demultiplexer (B + R). Routes write responses and
//              read data back to the correct master using AXI ID prefix.
//              Top 3 bits of ID: 000->M0, 001->M1, 010->M2, 011->M3, 100->M4
//============================================================================

module axi_resp_demux #(
    parameter NUM_MASTERS = 5,
    parameter DATA_WIDTH  = 32,
    parameter ID_WIDTH    = 6
)(
    input  wire                                clk,
    input  wire                                rst_n,

    // Slave-side B channel (from slave)
    input  wire [ID_WIDTH-1:0]                 s_bid_i,
    input  wire [1:0]                          s_bresp_i,
    input  wire                                s_bvalid_i,
    output reg                                 s_bready_o,

    // Slave-side R channel (from slave)
    input  wire [ID_WIDTH-1:0]                 s_rid_i,
    input  wire [DATA_WIDTH-1:0]               s_rdata_i,
    input  wire [1:0]                          s_rresp_i,
    input  wire                                s_rlast_i,
    input  wire                                s_rvalid_i,
    output reg                                 s_rready_o,

    // Master-side B channels (packed, to masters)
    output reg  [NUM_MASTERS*ID_WIDTH-1:0]     m_bid_o,
    output reg  [NUM_MASTERS*2-1:0]            m_bresp_o,
    output reg  [NUM_MASTERS-1:0]              m_bvalid_o,
    input  wire [NUM_MASTERS-1:0]              m_bready_i,

    // Master-side R channels (packed, to masters)
    output reg  [NUM_MASTERS*ID_WIDTH-1:0]     m_rid_o,
    output reg  [NUM_MASTERS*DATA_WIDTH-1:0]   m_rdata_o,
    output reg  [NUM_MASTERS*2-1:0]            m_rresp_o,
    output reg  [NUM_MASTERS-1:0]              m_rlast_o,
    output reg  [NUM_MASTERS-1:0]              m_rvalid_o,
    input  wire [NUM_MASTERS-1:0]              m_rready_i
);

    // Decode master index from top 3 bits of AXI ID
    wire [2:0] b_master_idx = s_bid_i[ID_WIDTH-1 -: 3];
    wire [2:0] r_master_idx = s_rid_i[ID_WIDTH-1 -: 3];

    integer i;

    // B channel demux - registered
    always @(posedge clk) begin
        if (!rst_n) begin
            m_bvalid_o <= {NUM_MASTERS{1'b0}};
            m_bid_o    <= {(NUM_MASTERS*ID_WIDTH){1'b0}};
            m_bresp_o  <= {(NUM_MASTERS*2){1'b0}};
            s_bready_o <= 1'b0;
        end else begin
            // Default: deassert all
            m_bvalid_o <= {NUM_MASTERS{1'b0}};
            s_bready_o <= 1'b0;

            if (s_bvalid_i && (b_master_idx < NUM_MASTERS)) begin
                m_bid_o[b_master_idx*ID_WIDTH +: ID_WIDTH] <= s_bid_i;
                m_bresp_o[b_master_idx*2 +: 2]             <= s_bresp_i;
                m_bvalid_o[b_master_idx]                   <= 1'b1;
                s_bready_o                                 <= m_bready_i[b_master_idx];
            end
        end
    end

    // R channel demux - registered
    always @(posedge clk) begin
        if (!rst_n) begin
            m_rvalid_o <= {NUM_MASTERS{1'b0}};
            m_rid_o    <= {(NUM_MASTERS*ID_WIDTH){1'b0}};
            m_rdata_o  <= {(NUM_MASTERS*DATA_WIDTH){1'b0}};
            m_rresp_o  <= {(NUM_MASTERS*2){1'b0}};
            m_rlast_o  <= {NUM_MASTERS{1'b0}};
            s_rready_o <= 1'b0;
        end else begin
            // Default: deassert all
            m_rvalid_o <= {NUM_MASTERS{1'b0}};
            s_rready_o <= 1'b0;

            if (s_rvalid_i && (r_master_idx < NUM_MASTERS)) begin
                m_rid_o[r_master_idx*ID_WIDTH +: ID_WIDTH]         <= s_rid_i;
                m_rdata_o[r_master_idx*DATA_WIDTH +: DATA_WIDTH]   <= s_rdata_i;
                m_rresp_o[r_master_idx*2 +: 2]                    <= s_rresp_i;
                m_rlast_o[r_master_idx]                            <= s_rlast_i;
                m_rvalid_o[r_master_idx]                           <= 1'b1;
                s_rready_o                                         <= m_rready_i[r_master_idx];
            end
        end
    end

endmodule
