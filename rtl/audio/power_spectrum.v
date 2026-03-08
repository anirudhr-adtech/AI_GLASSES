`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem
// Module: power_spectrum
// Description: Computes |X(k)|^2 = Re^2 + Im^2 for 513 bins (DC..Nyquist).
//              Reads FFT output bins 0-512, uses 2 multiplies + 1 add.
//////////////////////////////////////////////////////////////////////////////

module power_spectrum (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start_i,
    // FFT read interface
    input  wire [15:0] fft_re_i,
    input  wire [15:0] fft_im_i,
    output reg  [9:0]  fft_addr_o,
    output reg         fft_rd_en_o,
    // Status
    output reg         done_o,
    // Power output
    output reg  [31:0] pwr_data_o,
    output reg  [9:0]  pwr_addr_o,
    output reg         pwr_valid_o
);

    // FSM states
    localparam S_IDLE    = 3'd0;
    localparam S_READ    = 3'd1;
    localparam S_WAIT    = 3'd2;
    localparam S_COMPUTE = 3'd3;
    localparam S_DONE    = 3'd4;

    reg [2:0]  state;
    reg [9:0]  bin_cnt;
    reg signed [15:0] re_reg, im_reg;

    // Squaring
    wire signed [31:0] re_sq = re_reg * re_reg;
    wire signed [31:0] im_sq = im_reg * im_reg;

    always @(posedge clk) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            bin_cnt     <= 10'd0;
            fft_addr_o  <= 10'd0;
            fft_rd_en_o <= 1'b0;
            done_o      <= 1'b0;
            pwr_data_o  <= 32'd0;
            pwr_addr_o  <= 10'd0;
            pwr_valid_o <= 1'b0;
            re_reg      <= 16'd0;
            im_reg      <= 16'd0;
        end else begin
            fft_rd_en_o <= 1'b0;
            pwr_valid_o <= 1'b0;
            done_o      <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start_i) begin
                        bin_cnt <= 10'd0;
                        state   <= S_READ;
                    end
                end

                S_READ: begin
                    if (bin_cnt <= 10'd512) begin
                        fft_addr_o  <= bin_cnt;
                        fft_rd_en_o <= 1'b1;
                        state       <= S_WAIT;
                    end else begin
                        state <= S_DONE;
                    end
                end

                S_WAIT: begin
                    // Wait for BRAM read latency
                    re_reg <= fft_re_i;
                    im_reg <= fft_im_i;
                    state  <= S_COMPUTE;
                end

                S_COMPUTE: begin
                    pwr_data_o  <= re_sq[31:0] + im_sq[31:0];
                    pwr_addr_o  <= bin_cnt;
                    pwr_valid_o <= 1'b1;
                    bin_cnt     <= bin_cnt + 10'd1;
                    state       <= S_READ;
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
