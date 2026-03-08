`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem
// Module: mel_coeff_rom
// Description: Mel filterbank coefficient ROM. 40 triangular filters spanning
//              0-8 kHz at 1024-pt FFT, 16 kHz sample rate. Stores per-filter
//              start_bin, num_bins, and per-bin weight (Q0.16).
//////////////////////////////////////////////////////////////////////////////

module mel_coeff_rom #(
    parameter NUM_FILTERS = 40
)(
    input  wire        clk,
    input  wire [5:0]  filter_id_i,
    input  wire [5:0]  coeff_idx_i,
    output reg  [8:0]  start_bin_o,
    output reg  [5:0]  num_bins_o,
    output reg  [15:0] weight_o
);

    // ---------------------------------------------------------------
    // Filter metadata: start_bin and num_bins for each of 40 filters
    // Mel-spaced filters: 0-8 kHz on 1024-pt FFT (bin spacing = 15.625 Hz)
    // ---------------------------------------------------------------
    reg [8:0] start_bin_lut [0:39];
    reg [5:0] num_bins_lut  [0:39];

    initial begin
        // Filter 0-9: low frequency, narrow filters
        start_bin_lut[ 0] = 9'd1;   num_bins_lut[ 0] = 6'd4;
        start_bin_lut[ 1] = 9'd3;   num_bins_lut[ 1] = 6'd4;
        start_bin_lut[ 2] = 9'd5;   num_bins_lut[ 2] = 6'd5;
        start_bin_lut[ 3] = 9'd7;   num_bins_lut[ 3] = 6'd5;
        start_bin_lut[ 4] = 9'd10;  num_bins_lut[ 4] = 6'd5;
        start_bin_lut[ 5] = 9'd13;  num_bins_lut[ 5] = 6'd6;
        start_bin_lut[ 6] = 9'd16;  num_bins_lut[ 6] = 6'd6;
        start_bin_lut[ 7] = 9'd19;  num_bins_lut[ 7] = 6'd7;
        start_bin_lut[ 8] = 9'd23;  num_bins_lut[ 8] = 6'd7;
        start_bin_lut[ 9] = 9'd27;  num_bins_lut[ 9] = 6'd8;
        // Filter 10-19: mid-low frequency
        start_bin_lut[10] = 9'd31;  num_bins_lut[10] = 6'd9;
        start_bin_lut[11] = 9'd36;  num_bins_lut[11] = 6'd9;
        start_bin_lut[12] = 9'd41;  num_bins_lut[12] = 6'd10;
        start_bin_lut[13] = 9'd47;  num_bins_lut[13] = 6'd11;
        start_bin_lut[14] = 9'd53;  num_bins_lut[14] = 6'd12;
        start_bin_lut[15] = 9'd60;  num_bins_lut[15] = 6'd13;
        start_bin_lut[16] = 9'd68;  num_bins_lut[16] = 6'd14;
        start_bin_lut[17] = 9'd77;  num_bins_lut[17] = 6'd15;
        start_bin_lut[18] = 9'd87;  num_bins_lut[18] = 6'd16;
        start_bin_lut[19] = 9'd98;  num_bins_lut[19] = 6'd18;
        // Filter 20-29: mid-high frequency
        start_bin_lut[20] = 9'd110; num_bins_lut[20] = 6'd19;
        start_bin_lut[21] = 9'd124; num_bins_lut[21] = 6'd21;
        start_bin_lut[22] = 9'd139; num_bins_lut[22] = 6'd23;
        start_bin_lut[23] = 9'd156; num_bins_lut[23] = 6'd25;
        start_bin_lut[24] = 9'd175; num_bins_lut[24] = 6'd27;
        start_bin_lut[25] = 9'd196; num_bins_lut[25] = 6'd29;
        start_bin_lut[26] = 9'd219; num_bins_lut[26] = 6'd32;
        start_bin_lut[27] = 9'd245; num_bins_lut[27] = 6'd35;
        start_bin_lut[28] = 9'd274; num_bins_lut[28] = 6'd38;
        start_bin_lut[29] = 9'd306; num_bins_lut[29] = 6'd41;
        // Filter 30-39: high frequency, wide filters
        start_bin_lut[30] = 9'd341; num_bins_lut[30] = 6'd44;
        start_bin_lut[31] = 9'd350; num_bins_lut[31] = 6'd48;
        start_bin_lut[32] = 9'd360; num_bins_lut[32] = 6'd52;
        start_bin_lut[33] = 9'd370; num_bins_lut[33] = 6'd56;
        start_bin_lut[34] = 9'd382; num_bins_lut[34] = 6'd60;
        start_bin_lut[35] = 9'd395; num_bins_lut[35] = 6'd63;
        start_bin_lut[36] = 9'd410; num_bins_lut[36] = 6'd63;
        start_bin_lut[37] = 9'd430; num_bins_lut[37] = 6'd63;
        start_bin_lut[38] = 9'd455; num_bins_lut[38] = 6'd63;
        start_bin_lut[39] = 9'd480; num_bins_lut[39] = 6'd33;
    end

    // ---------------------------------------------------------------
    // Weight ROM: triangular weights for each (filter, bin_offset)
    // Addressed as flat array: addr = filter_id * 64 + coeff_idx
    // Weight is Q0.16: 0x0000 = 0.0, 0xFFFF ~ 1.0
    // Triangular: rises linearly to peak, then falls linearly
    // ---------------------------------------------------------------
    reg [15:0] weight_rom [0:2559]; // 40 * 64 = 2560 entries

    // Generate triangular weights for each filter
    integer f, b, half;
    initial begin
        for (f = 0; f < 2560; f = f + 1)
            weight_rom[f] = 16'd0;

        for (f = 0; f < 40; f = f + 1) begin
            half = (num_bins_lut[f] + 1) / 2;
            for (b = 0; b < num_bins_lut[f]; b = b + 1) begin
                if (b < half)
                    weight_rom[f * 64 + b] = (b + 1) * (16'd65535 / half);
                else
                    weight_rom[f * 64 + b] = (num_bins_lut[f] - b) * (16'd65535 / (num_bins_lut[f] - half + 1));
            end
        end
    end

    // Registered output (1-cycle read latency)
    always @(posedge clk) begin
        start_bin_o <= start_bin_lut[filter_id_i];
        num_bins_o  <= num_bins_lut[filter_id_i];
        weight_o    <= weight_rom[{filter_id_i, coeff_idx_i}];
    end

endmodule
