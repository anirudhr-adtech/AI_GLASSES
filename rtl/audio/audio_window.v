`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem
// Module: audio_window
// Description: Frame extraction + Hamming window multiply.
//              Reads 640 samples from FIFO, multiplies by Hamming coefficients
//              (16x16->32, take upper 16), zero-pads to 1024 for FFT.
//////////////////////////////////////////////////////////////////////////////

module audio_window (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start_i,
    // FIFO read interface
    output reg         fifo_rd_en_o,
    input  wire [15:0] fifo_rd_data_i,
    // Output
    output reg         done_o,
    output reg  [15:0] out_data_o,
    output reg         out_valid_o,
    output reg  [9:0]  out_addr_o
);

    // FSM states
    localparam S_IDLE     = 3'd0;
    localparam S_READ     = 3'd1;
    localparam S_WAIT     = 3'd2;
    localparam S_MULTIPLY = 3'd3;
    localparam S_ZERO_PAD = 3'd4;
    localparam S_DONE     = 3'd5;

    reg [2:0]  state;
    reg [10:0] cnt;
    reg [15:0] sample_reg;
    reg [15:0] coeff_reg;

    // Hamming ROM
    wire [15:0] ham_data;
    reg  [9:0]  ham_addr;

    hamming_rom u_hamming (
        .clk    (clk),
        .addr_i (ham_addr),
        .data_o (ham_data)
    );

    // Signed multiply: sample (signed 16-bit) * coefficient (unsigned Q1.15)
    // Result is 32-bit, take upper 16 as Q-format output
    wire signed [31:0] mult_result;
    assign mult_result = $signed(sample_reg) * $signed({1'b0, coeff_reg[14:0]});

    always @(posedge clk) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            cnt          <= 10'd0;
            fifo_rd_en_o <= 1'b0;
            done_o       <= 1'b0;
            out_data_o   <= 16'd0;
            out_valid_o  <= 1'b0;
            out_addr_o   <= 10'd0;
            ham_addr     <= 10'd0;
            sample_reg   <= 16'd0;
            coeff_reg    <= 16'd0;
        end else begin
            fifo_rd_en_o <= 1'b0;
            out_valid_o  <= 1'b0;
            done_o       <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start_i) begin
                        cnt      <= 10'd0;
                        ham_addr <= 10'd0;
                        state    <= S_READ;
                    end
                end

                S_READ: begin
                    if (cnt < 11'd640) begin
                        fifo_rd_en_o <= 1'b1;
                        ham_addr     <= cnt;
                        state        <= S_WAIT;
                    end else begin
                        // Done with windowed samples, start zero-padding
                        state <= S_ZERO_PAD;
                    end
                end

                S_WAIT: begin
                    // 1 cycle for FIFO read + ROM read latency
                    sample_reg <= fifo_rd_data_i;
                    coeff_reg  <= ham_data;
                    state      <= S_MULTIPLY;
                end

                S_MULTIPLY: begin
                    out_data_o  <= mult_result[30:15];
                    out_addr_o  <= cnt[9:0];
                    out_valid_o <= 1'b1;
                    cnt         <= cnt + 11'd1;
                    state       <= S_READ;
                end

                S_ZERO_PAD: begin
                    if (cnt < 11'd1024) begin
                        out_data_o  <= 16'd0;
                        out_addr_o  <= cnt[9:0];
                        out_valid_o <= 1'b1;
                        cnt         <= cnt + 11'd1;
                    end else begin
                        state <= S_DONE;
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
