`timescale 1ns/1ps
//============================================================================
// npu_activation.v
// Activation function unit (ReLU, ReLU6, bypass)
//
// act_type encoding:
//   2'b00 - Bypass (pass through)
//   2'b01 - ReLU  (clamp negative to 0)
//   2'b10 - ReLU6 (clamp to [0, 6])
//
// Latency: 1 clock cycle
//============================================================================

module npu_activation (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       en,
    input  wire [1:0] act_type,
    input  wire [7:0] data_i,
    input  wire       valid_i,
    output reg  [7:0] data_o,
    output reg        valid_o
);

    // -----------------------------------------------------------------------
    // Combinational activation select
    // -----------------------------------------------------------------------
    reg [7:0] act_result;

    always @(*) begin
        case (act_type)
            2'b01: begin
                // ReLU: negative -> 0
                act_result = (data_i[7]) ? 8'd0 : data_i;
            end
            2'b10: begin
                // ReLU6: clamp to [0, 6]
                if (data_i[7])
                    act_result = 8'd0;
                else if ($signed(data_i) > $signed(8'sd6))
                    act_result = 8'sd6;
                else
                    act_result = data_i;
            end
            default: begin
                // Bypass: pass through unchanged
                act_result = data_i;
            end
        endcase
    end

    // -----------------------------------------------------------------------
    // Registered output (1-cycle latency)
    // -----------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            data_o  <= 8'd0;
            valid_o <= 1'b0;
        end else if (en) begin
            data_o  <= act_result;
            valid_o <= valid_i;
        end
    end

endmodule
