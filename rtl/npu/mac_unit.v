`timescale 1ns/1ps
//============================================================================
// Module : mac_unit
// Project : AI_GLASSES — NPU Subsystem
// Description : Single INT8 x INT8 -> INT32 multiply-accumulate cell.
//               Weight-stationary dataflow. 2-cycle latency
//               (registered multiply followed by registered accumulate).
//============================================================================

module mac_unit #(
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 32
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    en,
    input  wire                    clear_acc,
    input  wire [DATA_WIDTH-1:0]  weight_i,   // signed INT8 weight
    input  wire [DATA_WIDTH-1:0]  act_i,      // signed INT8 activation
    output wire [ACC_WIDTH-1:0]   acc_o       // signed INT32 accumulated result
);

    //------------------------------------------------------------------------
    // Stage 1 — Registered multiply (targets DSP48 inference)
    //------------------------------------------------------------------------
    reg signed [2*DATA_WIDTH-1:0] product;

    always @(posedge clk) begin
        if (!rst_n) begin
            product <= {(2*DATA_WIDTH){1'b0}};
        end else if (en) begin
            product <= $signed(weight_i) * $signed(act_i);
        end
    end

    //------------------------------------------------------------------------
    // Stage 2 — Registered accumulate
    //------------------------------------------------------------------------
    reg signed [ACC_WIDTH-1:0] acc;

    always @(posedge clk) begin
        if (!rst_n) begin
            acc <= {ACC_WIDTH{1'b0}};
        end else if (en) begin
            if (clear_acc)
                acc <= {ACC_WIDTH{1'b0}};
            else
                acc <= acc + {{(ACC_WIDTH-2*DATA_WIDTH){product[2*DATA_WIDTH-1]}}, product};
        end
    end

    //------------------------------------------------------------------------
    // Registered output
    //------------------------------------------------------------------------
    reg [ACC_WIDTH-1:0] acc_out_r;

    always @(posedge clk) begin
        if (!rst_n)
            acc_out_r <= {ACC_WIDTH{1'b0}};
        else
            acc_out_r <= acc;
    end

    assign acc_o = acc_out_r;

endmodule
