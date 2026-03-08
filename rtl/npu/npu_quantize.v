`timescale 1ns/1ps
//============================================================================
// npu_quantize.v
// INT32 -> INT8 quantization unit (TFLite-compatible)
//
// Formula: INT8_out = clamp((INT32_in >>> SHIFT) * SCALE, -128, +127)
//
// Pipeline:
//   Stage 1 - Arithmetic right shift
//   Stage 2 - Multiply by scale
//   Stage 3 - Clamp to [-128, +127]
//
// Latency: 3 clock cycles
//============================================================================

module npu_quantize (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        en,
    input  wire [31:0] data_i,
    input  wire        valid_i,
    input  wire [7:0]  shift_i,
    input  wire [15:0] scale_i,
    output reg  [7:0]  data_o,
    output reg         valid_o
);

    // -----------------------------------------------------------------------
    // Pipeline stage 1: arithmetic right shift
    // -----------------------------------------------------------------------
    reg signed [31:0] s1_shifted;
    reg               s1_valid;

    always @(posedge clk) begin
        if (!rst_n) begin
            s1_shifted <= 32'd0;
            s1_valid   <= 1'b0;
        end else if (en) begin
            s1_shifted <= $signed(data_i) >>> shift_i;
            s1_valid   <= valid_i;
        end
    end

    // -----------------------------------------------------------------------
    // Pipeline stage 2: multiply by scale (16-bit x 32-bit -> 48-bit, take
    // lower 32 bits)
    // -----------------------------------------------------------------------
    reg signed [31:0] s2_product;
    reg               s2_valid;

    wire signed [47:0] mul_result;
    assign mul_result = $signed(s1_shifted) * $signed({1'b0, scale_i});

    always @(posedge clk) begin
        if (!rst_n) begin
            s2_product <= 32'd0;
            s2_valid   <= 1'b0;
        end else if (en) begin
            s2_product <= mul_result[31:0];
            s2_valid   <= s1_valid;
        end
    end

    // -----------------------------------------------------------------------
    // Pipeline stage 3: clamp to [-128, +127]
    // -----------------------------------------------------------------------
    reg signed [7:0] clamped;

    always @(*) begin
        if ($signed(s2_product) > $signed(32'd127))
            clamped = 8'sd127;
        else if ($signed(s2_product) < $signed(-32'd128))
            clamped = -8'sd128;
        else
            clamped = s2_product[7:0];
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            data_o  <= 8'd0;
            valid_o <= 1'b0;
        end else if (en) begin
            data_o  <= clamped;
            valid_o <= s2_valid;
        end
    end

endmodule
