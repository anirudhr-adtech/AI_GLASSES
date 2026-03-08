`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — DDR Subsystem
// Module: qos_mapper
// Description: Maps AXI ID prefix (top 3 bits of 6-bit ID) to 4-bit QoS
//              value for Zynq HP port priority scheduling.
//////////////////////////////////////////////////////////////////////////////

module qos_mapper #(
    parameter ID_WIDTH = 6
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire [ID_WIDTH-1:0]   axi_id_i,
    output reg  [3:0]            qos_o
);

    // Combinational lookup
    reg [3:0] qos_comb;

    always @(*) begin
        case (axi_id_i[ID_WIDTH-1 -: 3])
            3'b010:  qos_comb = 4'hF;  // NPU M2 — highest
            3'b011:  qos_comb = 4'hC;  // Camera M3
            3'b001:  qos_comb = 4'h8;  // CPU dBus M1
            3'b000:  qos_comb = 4'h4;  // CPU iBus M0
            3'b100:  qos_comb = 4'h2;  // Audio M4 — lowest
            default: qos_comb = 4'h0;
        endcase
    end

    // Registered output
    always @(posedge clk) begin
        if (!rst_n)
            qos_o <= 4'h0;
        else
            qos_o <= qos_comb;
    end

endmodule
