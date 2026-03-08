`timescale 1ns/1ps
//============================================================================
// Module:      axi_rd_mux
// Project:     AI_GLASSES — AXI Interconnect
// Description: Read address channel multiplexer (AR). Selects granted
//              master's read address signals to forward to slave.
//============================================================================

module axi_rd_mux #(
    parameter NUM_MASTERS = 5,
    parameter DATA_WIDTH  = 32,
    parameter ADDR_WIDTH  = 32,
    parameter ID_WIDTH    = 6
)(
    input  wire                                clk,
    input  wire                                rst_n,

    // Grant from arbiter (one-hot)
    input  wire [NUM_MASTERS-1:0]              grant_i,

    // Master-side AR channels (packed arrays)
    input  wire [NUM_MASTERS*ID_WIDTH-1:0]     m_arid_i,
    input  wire [NUM_MASTERS*ADDR_WIDTH-1:0]   m_araddr_i,
    input  wire [NUM_MASTERS*8-1:0]            m_arlen_i,
    input  wire [NUM_MASTERS*3-1:0]            m_arsize_i,
    input  wire [NUM_MASTERS*2-1:0]            m_arburst_i,
    input  wire [NUM_MASTERS-1:0]              m_arvalid_i,
    output reg  [NUM_MASTERS-1:0]              m_arready_o,

    // Slave-side AR channel (single)
    output reg  [ID_WIDTH-1:0]                 s_arid_o,
    output reg  [ADDR_WIDTH-1:0]               s_araddr_o,
    output reg  [7:0]                          s_arlen_o,
    output reg  [2:0]                          s_arsize_o,
    output reg  [1:0]                          s_arburst_o,
    output reg                                 s_arvalid_o,
    input  wire                                s_arready_i
);

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

    // AR channel mux - registered
    always @(posedge clk) begin
        if (!rst_n) begin
            s_arid_o    <= {ID_WIDTH{1'b0}};
            s_araddr_o  <= {ADDR_WIDTH{1'b0}};
            s_arlen_o   <= 8'd0;
            s_arsize_o  <= 3'd0;
            s_arburst_o <= 2'd0;
            s_arvalid_o <= 1'b0;
            m_arready_o <= {NUM_MASTERS{1'b0}};
        end else begin
            if (sel_valid) begin
                s_arid_o    <= m_arid_i[sel*ID_WIDTH +: ID_WIDTH];
                s_araddr_o  <= m_araddr_i[sel*ADDR_WIDTH +: ADDR_WIDTH];
                s_arlen_o   <= m_arlen_i[sel*8 +: 8];
                s_arsize_o  <= m_arsize_i[sel*3 +: 3];
                s_arburst_o <= m_arburst_i[sel*2 +: 2];
                s_arvalid_o <= m_arvalid_i[sel];

                m_arready_o <= {NUM_MASTERS{1'b0}};
                m_arready_o[sel] <= s_arready_i;
            end else begin
                s_arvalid_o <= 1'b0;
                m_arready_o <= {NUM_MASTERS{1'b0}};
            end
        end
    end

endmodule
