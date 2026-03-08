`timescale 1ns/1ps
//============================================================================
// AI_GLASSES — DDR Subsystem (Simulation Model)
// Module: axi_mem_aw_channel
// Description: AW channel handler. Accepts AW handshake, captures burst
//              parameters, and tracks outstanding writes.
//============================================================================

module axi_mem_aw_channel #(
    parameter ADDR_WIDTH = 32,
    parameter ID_WIDTH   = 6
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // AXI AW channel
    input  wire [ID_WIDTH-1:0]    s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire [7:0]             s_axi_awlen,
    input  wire [2:0]             s_axi_awsize,
    input  wire [1:0]             s_axi_awburst,
    input  wire                   s_axi_awvalid,
    output reg                    s_axi_awready,

    // Captured burst info to downstream
    output reg                    aw_valid_o,
    output reg  [ADDR_WIDTH-1:0]  aw_addr_o,
    output reg  [7:0]             aw_len_o,
    output reg  [2:0]             aw_size_o,
    output reg  [ID_WIDTH-1:0]    aw_id_o,

    // Backpressure from downstream
    input  wire                   aw_ready_i
);

    initial begin
        s_axi_awready = 1'b0;
        aw_valid_o    = 1'b0;
        aw_addr_o     = {ADDR_WIDTH{1'b0}};
        aw_len_o      = 8'd0;
        aw_size_o     = 3'd0;
        aw_id_o       = {ID_WIDTH{1'b0}};
    end

    // Simple handshake: accept AW when downstream is ready
    always @(posedge clk) begin
        if (!rst_n) begin
            s_axi_awready <= 1'b0;
            aw_valid_o    <= 1'b0;
            aw_addr_o     <= {ADDR_WIDTH{1'b0}};
            aw_len_o      <= 8'd0;
            aw_size_o     <= 3'd0;
            aw_id_o       <= {ID_WIDTH{1'b0}};
        end else begin
            // Default: ready to accept if no outstanding or downstream consumed
            if (aw_valid_o && aw_ready_i)
                aw_valid_o <= 1'b0;

            if (!aw_valid_o || aw_ready_i)
                s_axi_awready <= 1'b1;
            else
                s_axi_awready <= 1'b0;

            // Capture on handshake
            if (s_axi_awvalid && s_axi_awready) begin
                aw_valid_o <= 1'b1;
                aw_addr_o  <= s_axi_awaddr;
                aw_len_o   <= s_axi_awlen;
                aw_size_o  <= s_axi_awsize;
                aw_id_o    <= s_axi_awid;
            end
        end
    end

endmodule
