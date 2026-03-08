`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem
// Module: dct_unit
// Description: Type-II DCT: 40 log-mel energies -> 10 MFCC coefficients.
//              MAC-based sequential: for each output c (0-9), sums
//              log_mel[m] * cos_coeff[c][m] for m=0..39.
//////////////////////////////////////////////////////////////////////////////

module dct_unit (
    input  wire        clk,
    input  wire        rst_n,
    // Control
    input  wire        start_i,
    // Log-mel input (streaming from log_compress)
    input  wire [15:0] log_data_i,
    input  wire [5:0]  log_idx_i,
    input  wire        log_valid_i,
    // Status
    output reg         done_o,
    // MFCC output
    output reg  [15:0] mfcc_data_o,
    output reg  [3:0]  mfcc_idx_o,
    output reg         mfcc_valid_o
);

    // FSM states
    localparam S_IDLE    = 3'd0;
    localparam S_COLLECT = 3'd1;
    localparam S_COMPUTE = 3'd2;
    localparam S_MAC     = 3'd3;
    localparam S_OUTPUT  = 3'd4;
    localparam S_DONE    = 3'd5;

    reg [2:0]  state;
    reg [3:0]  c_cnt;     // DCT output coefficient index (0-9)
    reg [5:0]  m_cnt;     // Mel input index (0-39)
    reg [5:0]  collect_cnt;

    // Local storage for 40 log-mel values
    reg [15:0] log_mel_buf [0:39];

    // MAC accumulator (signed: Q8.8 * Q1.15 = Q9.23, sum of 40 -> ~Q15.23)
    reg signed [31:0] accumulator;

    // DCT coefficient ROM
    reg  [3:0]  rom_c_idx;
    reg  [5:0]  rom_m_idx;
    wire [15:0] rom_coeff;

    dct_coeff_rom u_dct_rom (
        .clk     (clk),
        .c_idx_i (rom_c_idx),
        .m_idx_i (rom_m_idx),
        .coeff_o (rom_coeff)
    );

    // Pipeline registers for MAC
    reg signed [15:0] log_val_r;
    reg signed [15:0] coeff_r;
    reg               mac_valid;

    integer i;

    always @(posedge clk) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            c_cnt       <= 4'd0;
            m_cnt       <= 6'd0;
            collect_cnt <= 6'd0;
            accumulator <= 32'd0;
            done_o      <= 1'b0;
            mfcc_data_o <= 16'd0;
            mfcc_idx_o  <= 4'd0;
            mfcc_valid_o <= 1'b0;
            rom_c_idx   <= 4'd0;
            rom_m_idx   <= 6'd0;
            log_val_r   <= 16'd0;
            coeff_r     <= 16'd0;
            mac_valid   <= 1'b0;
            for (i = 0; i < 40; i = i + 1)
                log_mel_buf[i] <= 16'd0;
        end else begin
            done_o       <= 1'b0;
            mfcc_valid_o <= 1'b0;
            mac_valid    <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start_i) begin
                        collect_cnt <= 6'd0;
                        state       <= S_COLLECT;
                    end
                end

                S_COLLECT: begin
                    // Collect 40 log-mel values as they stream in
                    if (log_valid_i) begin
                        log_mel_buf[log_idx_i] <= log_data_i;
                        collect_cnt <= collect_cnt + 6'd1;
                    end
                    if (collect_cnt == 6'd40) begin
                        c_cnt     <= 4'd0;
                        m_cnt     <= 6'd0;
                        accumulator <= 32'd0;
                        state     <= S_COMPUTE;
                    end
                end

                S_COMPUTE: begin
                    // Request ROM coefficient and prepare log_mel value
                    rom_c_idx <= c_cnt;
                    rom_m_idx <= m_cnt;
                    state     <= S_MAC;
                end

                S_MAC: begin
                    // ROM has 1-cycle latency, so coeff is ready now
                    // MAC: accumulate log_mel[m] * coeff[c][m]
                    accumulator <= accumulator +
                        ($signed(log_mel_buf[m_cnt]) * $signed(rom_coeff));

                    if (m_cnt == 6'd39) begin
                        state <= S_OUTPUT;
                    end else begin
                        m_cnt     <= m_cnt + 6'd1;
                        rom_c_idx <= c_cnt;
                        rom_m_idx <= m_cnt + 6'd1;
                    end
                end

                S_OUTPUT: begin
                    // Output MFCC coefficient: accumulator is Q8.8 * Q1.15 = Q9.23
                    // Shift right by 15 to get Q8.8 result
                    mfcc_data_o  <= accumulator[30:15];
                    mfcc_idx_o   <= c_cnt;
                    mfcc_valid_o <= 1'b1;

                    if (c_cnt == 4'd9) begin
                        state <= S_DONE;
                    end else begin
                        c_cnt       <= c_cnt + 4'd1;
                        m_cnt       <= 6'd0;
                        accumulator <= 32'd0;
                        state       <= S_COMPUTE;
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
