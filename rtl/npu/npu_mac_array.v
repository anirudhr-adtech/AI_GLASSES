`timescale 1ns/1ps
//============================================================================
// Module : npu_mac_array
// Project : AI_GLASSES — NPU Subsystem
// Description : 8x8 systolic-style MAC array (64 parallel MACs).
//               Supports Conv2D, depthwise Conv2D, and fully-connected
//               modes via weight-stationary dataflow.
//============================================================================

module npu_mac_array #(
    parameter MAC_ROWS   = 8,
    parameter MAC_COLS   = 8,
    parameter DATA_WIDTH = 8,
    parameter ACC_WIDTH  = 32
)(
    input  wire                                  clk,
    input  wire                                  rst_n,
    input  wire                                  en,          // array enable
    input  wire                                  clear_acc,   // clear all accumulators
    input  wire [1:0]                            mode,        // 0=Conv2D, 1=DW-Conv2D, 2=FC
    input  wire [MAC_COLS*DATA_WIDTH-1:0]        weight_data, // 8 weights x 8 bits (one column)
    input  wire [MAC_ROWS*DATA_WIDTH-1:0]        act_data,    // 8 activations x 8 bits (one row)
    output wire [MAC_COLS*ACC_WIDTH-1:0]         acc_out,     // 8 accumulators x 32 bits (one row)
    output wire                                  acc_valid    // accumulator output valid
);

    // Mode encoding
    localparam MODE_CONV2D    = 2'd0;
    localparam MODE_DW_CONV2D = 2'd1;
    localparam MODE_FC        = 2'd2;

    //------------------------------------------------------------------------
    // Per-MAC enable gating
    //   Conv2D / FC : all 64 MACs active
    //   DW-Conv2D   : only row 0 active (8 MACs), rows 1-7 disabled
    //------------------------------------------------------------------------
    wire [MAC_ROWS-1:0] row_en;

    genvar ri;
    generate
        for (ri = 0; ri < MAC_ROWS; ri = ri + 1) begin : gen_row_en
            if (ri == 0) begin : row0
                assign row_en[ri] = en;
            end else begin : row_n
                assign row_en[ri] = en & (mode != MODE_DW_CONV2D);
            end
        end
    endgenerate

    //------------------------------------------------------------------------
    // Weight and activation extraction wires
    //------------------------------------------------------------------------
    wire [DATA_WIDTH-1:0] weight_w [0:MAC_COLS-1];
    wire [DATA_WIDTH-1:0] act_w    [0:MAC_ROWS-1];

    genvar wi, ai;
    generate
        for (wi = 0; wi < MAC_COLS; wi = wi + 1) begin : gen_weight_unpack
            assign weight_w[wi] = weight_data[wi*DATA_WIDTH +: DATA_WIDTH];
        end
        for (ai = 0; ai < MAC_ROWS; ai = ai + 1) begin : gen_act_unpack
            assign act_w[ai] = act_data[ai*DATA_WIDTH +: DATA_WIDTH];
        end
    endgenerate

    //------------------------------------------------------------------------
    // 8x8 MAC grid — generate instantiation
    //------------------------------------------------------------------------
    wire [ACC_WIDTH-1:0] mac_acc [0:MAC_ROWS-1][0:MAC_COLS-1];

    genvar r, c;
    generate
        for (r = 0; r < MAC_ROWS; r = r + 1) begin : gen_mac_row
            for (c = 0; c < MAC_COLS; c = c + 1) begin : gen_mac_col
                mac_unit #(
                    .DATA_WIDTH (DATA_WIDTH),
                    .ACC_WIDTH  (ACC_WIDTH)
                ) u_mac (
                    .clk       (clk),
                    .rst_n     (rst_n),
                    .en        (row_en[r]),
                    .clear_acc (clear_acc),
                    .weight_i  (weight_w[c]),
                    .act_i     (act_w[r]),
                    .acc_o     (mac_acc[r][c])
                );
            end
        end
    endgenerate

    //------------------------------------------------------------------------
    // Accumulator bank — collect row-0 results (one per output channel col)
    // In Conv2D/FC modes all rows contribute; the external controller
    // iterates over rows. The array exposes the row-0 accumulator bank
    // as the primary output vector (8 x 32-bit).
    //------------------------------------------------------------------------
    reg [ACC_WIDTH-1:0] acc_bank [0:MAC_COLS-1];

    genvar bc;
    generate
        for (bc = 0; bc < MAC_COLS; bc = bc + 1) begin : gen_acc_bank
            always @(posedge clk) begin
                if (!rst_n)
                    acc_bank[bc] <= {ACC_WIDTH{1'b0}};
                else
                    acc_bank[bc] <= mac_acc[0][bc];
            end
        end
    endgenerate

    // Pack accumulator bank into flat output bus
    genvar oi;
    generate
        for (oi = 0; oi < MAC_COLS; oi = oi + 1) begin : gen_acc_out
            assign acc_out[oi*ACC_WIDTH +: ACC_WIDTH] = acc_bank[oi];
        end
    endgenerate

    //------------------------------------------------------------------------
    // acc_valid generation — cycle counter after en asserts
    // mac_unit has 2-cycle latency (multiply + accumulate) plus one
    // register stage in the accumulator bank = 3 cycles total.
    //------------------------------------------------------------------------
    localparam LATENCY = 3;

    reg [3:0] valid_cnt;

    always @(posedge clk) begin
        if (!rst_n) begin
            valid_cnt <= 4'd0;
        end else if (clear_acc) begin
            valid_cnt <= 4'd0;
        end else if (en && valid_cnt < LATENCY) begin
            valid_cnt <= valid_cnt + 4'd1;
        end
    end

    reg acc_valid_r;

    always @(posedge clk) begin
        if (!rst_n)
            acc_valid_r <= 1'b0;
        else if (clear_acc)
            acc_valid_r <= 1'b0;
        else if (valid_cnt == LATENCY)
            acc_valid_r <= 1'b1;
        else
            acc_valid_r <= 1'b0;
    end

    assign acc_valid = acc_valid_r;

endmodule
