`timescale 1ns/1ps
//============================================================================
// Module:      axilite_addr_decoder
// Project:     AI_GLASSES — AXI Interconnect
// Description: Peripheral address decoder with 11 slots.
//              P0-P7: 0x2000_0x00, P8: 0x3000_0000 (NPU), P9: 0x4000_0000 (DMA).
//              Unmapped -> decode error (SLVERR).
//============================================================================

module axilite_addr_decoder #(
    parameter ADDR_WIDTH  = 32,
    parameter NUM_PERIPHS = 11
)(
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire [ADDR_WIDTH-1:0]     addr_i,
    output reg  [3:0]                periph_sel_o,
    output reg                       decode_error_o
);

    // Peripheral indices
    localparam P_UART    = 4'd0;
    localparam P_TIMER   = 4'd1;
    localparam P_IRQ     = 4'd2;
    localparam P_GPIO    = 4'd3;
    localparam P_CAMERA  = 4'd4;
    localparam P_AUDIO   = 4'd5;
    localparam P_I2C     = 4'd6;
    localparam P_SPI     = 4'd7;
    localparam P_NPU     = 4'd8;
    localparam P_DMA     = 4'd9;
    localparam P_ERROR   = 4'd10;

    reg [3:0] periph_sel_comb;
    reg       decode_error_comb;

    always @(*) begin
        periph_sel_comb   = P_ERROR;
        decode_error_comb = 1'b0;

        case (addr_i[31:28])
            4'h2: begin
                // 0x2000_xxxx region
                if (addr_i[27:12] == 16'h0000) begin
                    case (addr_i[11:8])
                        4'h0: periph_sel_comb = P_UART;
                        4'h1: periph_sel_comb = P_TIMER;
                        4'h2: periph_sel_comb = P_IRQ;
                        4'h3: periph_sel_comb = P_GPIO;
                        4'h4: periph_sel_comb = P_CAMERA;
                        4'h5: periph_sel_comb = P_AUDIO;
                        4'h6: periph_sel_comb = P_I2C;
                        4'h7: periph_sel_comb = P_SPI;
                        default: begin
                            periph_sel_comb   = P_ERROR;
                            decode_error_comb = 1'b1;
                        end
                    endcase
                end else begin
                    periph_sel_comb   = P_ERROR;
                    decode_error_comb = 1'b1;
                end
            end
            4'h3: begin
                // 0x3000_0000 - NPU registers
                if (addr_i[27:8] == 20'h00000) begin
                    periph_sel_comb = P_NPU;
                end else begin
                    periph_sel_comb   = P_ERROR;
                    decode_error_comb = 1'b1;
                end
            end
            4'h4: begin
                // 0x4000_0000 - DMA registers
                if (addr_i[27:8] == 20'h00000) begin
                    periph_sel_comb = P_DMA;
                end else begin
                    periph_sel_comb   = P_ERROR;
                    decode_error_comb = 1'b1;
                end
            end
            default: begin
                periph_sel_comb   = P_ERROR;
                decode_error_comb = 1'b1;
            end
        endcase
    end

    // Registered output
    always @(posedge clk) begin
        if (!rst_n) begin
            periph_sel_o   <= P_ERROR;
            decode_error_o <= 1'b0;
        end else begin
            periph_sel_o   <= periph_sel_comb;
            decode_error_o <= decode_error_comb;
        end
    end

endmodule
