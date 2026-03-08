`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem
// Module: mel_filterbank
// Description: Applies 40 triangular mel filters to power spectrum.
//              Sequential accumulator iterates over each filter's bin range.
//              Instantiates mel_coeff_rom for filter parameters.
//////////////////////////////////////////////////////////////////////////////

module mel_filterbank (
    input  wire        clk,
    input  wire        rst_n,
    // Control
    input  wire        start_i,
    // Power spectrum memory interface (external BRAM)
    input  wire [31:0] pwr_data_i,
    output reg  [9:0]  pwr_addr_o,
    output reg         pwr_rd_en_o,
    // Status
    output reg         done_o,
    // Mel energy output
    output reg  [31:0] mel_data_o,
    output reg  [5:0]  mel_idx_o,
    output reg         mel_valid_o
);

    // FSM states
    localparam S_IDLE        = 3'd0;
    localparam S_LOAD_FILTER = 3'd1;
    localparam S_WAIT_META   = 3'd2;
    localparam S_BIN_REQ     = 3'd3;
    localparam S_BIN_WAIT    = 3'd4;
    localparam S_BIN_ACC     = 3'd5;
    localparam S_STORE       = 3'd6;
    localparam S_DONE        = 3'd7;

    reg [2:0]  state;
    reg [5:0]  filter_cnt;
    reg [5:0]  bin_cnt;
    reg [8:0]  cur_start_bin;
    reg [5:0]  cur_num_bins;
    reg [47:0] accumulator;   // 48-bit to hold sum of 32*16 products

    // ROM interface
    wire [8:0]  rom_start_bin;
    wire [5:0]  rom_num_bins;
    wire [15:0] rom_weight;

    reg [5:0] rom_filter_id;
    reg [5:0] rom_coeff_idx;

    mel_coeff_rom u_mel_rom (
        .clk          (clk),
        .filter_id_i  (rom_filter_id),
        .coeff_idx_i  (rom_coeff_idx),
        .start_bin_o  (rom_start_bin),
        .num_bins_o   (rom_num_bins),
        .weight_o     (rom_weight)
    );

    // Pipeline: power data arrives 1 cycle after address, weight arrives 1 cycle after idx
    reg [15:0] weight_r;
    reg [31:0] pwr_data_r;
    reg        acc_valid;

    always @(posedge clk) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            filter_cnt   <= 6'd0;
            bin_cnt      <= 6'd0;
            accumulator  <= 48'd0;
            cur_start_bin <= 9'd0;
            cur_num_bins <= 6'd0;
            done_o       <= 1'b0;
            mel_data_o   <= 32'd0;
            mel_idx_o    <= 6'd0;
            mel_valid_o  <= 1'b0;
            pwr_addr_o   <= 10'd0;
            pwr_rd_en_o  <= 1'b0;
            rom_filter_id <= 6'd0;
            rom_coeff_idx <= 6'd0;
            weight_r     <= 16'd0;
            pwr_data_r   <= 32'd0;
            acc_valid    <= 1'b0;
        end else begin
            done_o      <= 1'b0;
            mel_valid_o <= 1'b0;
            acc_valid   <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start_i) begin
                        filter_cnt    <= 6'd0;
                        state         <= S_LOAD_FILTER;
                        rom_filter_id <= 6'd0;
                        rom_coeff_idx <= 6'd0;
                    end
                end

                S_LOAD_FILTER: begin
                    // Request filter metadata from ROM
                    rom_filter_id <= filter_cnt;
                    rom_coeff_idx <= 6'd0;
                    state         <= S_WAIT_META;
                end

                S_WAIT_META: begin
                    // ROM output valid this cycle (1-cycle latency)
                    cur_start_bin <= rom_start_bin;
                    cur_num_bins  <= rom_num_bins;
                    accumulator   <= 48'd0;
                    bin_cnt       <= 6'd0;
                    state         <= S_BIN_REQ;
                end

                S_BIN_REQ: begin
                    if (bin_cnt < cur_num_bins) begin
                        // Request power spectrum value and weight
                        pwr_addr_o    <= cur_start_bin + {4'd0, bin_cnt};
                        pwr_rd_en_o   <= 1'b1;
                        rom_filter_id <= filter_cnt;
                        rom_coeff_idx <= bin_cnt;
                        state         <= S_BIN_WAIT;
                    end else begin
                        state <= S_STORE;
                    end
                end

                S_BIN_WAIT: begin
                    // Wait for ROM and memory read latency (1 cycle)
                    pwr_rd_en_o <= 1'b0;
                    state       <= S_BIN_ACC;
                end

                S_BIN_ACC: begin
                    // Accumulate: power * weight (32-bit * 16-bit = 48-bit)
                    accumulator <= accumulator + (pwr_data_i * rom_weight);
                    bin_cnt     <= bin_cnt + 6'd1;
                    state       <= S_BIN_REQ;
                end

                S_STORE: begin
                    // Output mel energy (take upper 32 bits: >>16 for Q0.16 weight)
                    mel_data_o  <= accumulator[47:16];
                    mel_idx_o   <= filter_cnt;
                    mel_valid_o <= 1'b1;
                    pwr_rd_en_o <= 1'b0;

                    if (filter_cnt == 6'd39) begin
                        state <= S_DONE;
                    end else begin
                        filter_cnt <= filter_cnt + 6'd1;
                        state      <= S_LOAD_FILTER;
                    end
                end

                S_DONE: begin
                    done_o <= 1'b1;
                    state  <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
