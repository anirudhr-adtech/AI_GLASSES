`timescale 1ns/1ps
//============================================================================
// AI_GLASSES — DDR Subsystem (Simulation Model)
// Module: axi_mem_ar_channel
// Description: AR channel handler. Accepts AR handshake, captures burst
//              parameters, and feeds to read pipeline.
//============================================================================

module axi_mem_ar_channel #(
    parameter ADDR_WIDTH = 32,
    parameter ID_WIDTH   = 6
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // AXI AR channel
    input  wire [ID_WIDTH-1:0]    s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_araddr,
    input  wire [7:0]             s_axi_arlen,
    input  wire [2:0]             s_axi_arsize,
    input  wire [1:0]             s_axi_arburst,
    input  wire                   s_axi_arvalid,
    output reg                    s_axi_arready,

    // Captured burst info to downstream
    output reg                    ar_valid_o,
    output reg  [ADDR_WIDTH-1:0]  ar_addr_o,
    output reg  [7:0]             ar_len_o,
    output reg  [2:0]             ar_size_o,
    output reg  [ID_WIDTH-1:0]    ar_id_o,

    // Backpressure from downstream
    input  wire                   ar_ready_i
);

    initial begin
        s_axi_arready = 1'b0;
        ar_valid_o    = 1'b0;
        ar_addr_o     = {ADDR_WIDTH{1'b0}};
        ar_len_o      = 8'd0;
        ar_size_o     = 3'd0;
        ar_id_o       = {ID_WIDTH{1'b0}};
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            s_axi_arready <= 1'b0;
            ar_valid_o    <= 1'b0;
            ar_addr_o     <= {ADDR_WIDTH{1'b0}};
            ar_len_o      <= 8'd0;
            ar_size_o     <= 3'd0;
            ar_id_o       <= {ID_WIDTH{1'b0}};
        end else begin
            // Consume downstream
            if (ar_valid_o && ar_ready_i)
                ar_valid_o <= 1'b0;

            // Ready when no outstanding or downstream consumed
            if (!ar_valid_o || ar_ready_i)
                s_axi_arready <= 1'b1;
            else
                s_axi_arready <= 1'b0;

            // Capture on handshake
            if (s_axi_arvalid && s_axi_arready) begin
                ar_valid_o <= 1'b1;
                ar_addr_o  <= s_axi_araddr;
                ar_len_o   <= s_axi_arlen;
                ar_size_o  <= s_axi_arsize;
                ar_id_o    <= s_axi_arid;
            end
        end
    end

endmodule
