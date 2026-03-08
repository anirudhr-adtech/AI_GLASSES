`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem
// Module: audio_controller
// Description: Top-level audio orchestrator FSM. Decodes mode from registers,
//              sequences pipeline stages: FIFO -> window -> FFT -> power
//              spectrum -> mel -> log -> DCT -> MFCC buffer -> DMA.
//              Tracks 49-vector frame count, asserts IRQ on completion.
//////////////////////////////////////////////////////////////////////////////

module audio_controller (
    input  wire        clk,
    input  wire        rst_n,
    // Register interface (from audio_regfile)
    input  wire [31:0] reg_audio_control,
    input  wire [31:0] reg_mfcc_config,
    input  wire [31:0] reg_window_config,
    input  wire [31:0] reg_fft_config,
    input  wire [31:0] reg_dma_base_addr,
    input  wire [31:0] reg_dma_length,
    input  wire [31:0] reg_gain_control,
    input  wire [31:0] reg_noise_floor,
    input  wire        reg_start_pulse,
    input  wire        reg_irq_clear_frame,
    input  wire        reg_irq_clear_dma,
    // Status output (to audio_regfile)
    output reg  [31:0] status_o,
    output reg  [31:0] perf_cycles_o,
    output reg  [31:0] frame_energy_o,
    // FIFO interface
    input  wire [10:0] fifo_fill_level,
    input  wire        fifo_empty,
    input  wire        fifo_overrun,
    // Pipeline control signals
    output reg         window_start_o,
    input  wire        window_done_i,
    output reg         fft_start_o,
    input  wire        fft_done_i,
    output reg         pwr_start_o,
    input  wire        pwr_done_i,
    output reg         mel_start_o,
    input  wire        mel_done_i,
    output reg         log_start_o,
    input  wire        log_done_i,
    output reg         dct_start_o,
    input  wire        dct_done_i,
    // MFCC buffer interface
    input  wire        mfcc_frame_ready,
    output reg         mfcc_bank_swap_o,
    // DMA interface
    output reg         dma_start_o,
    output reg         dma_mode_o,
    output reg  [31:0] dma_base_addr_o,
    output reg  [31:0] dma_length_o,
    input  wire        dma_done_i,
    input  wire [31:0] dma_wr_ptr_i,
    // Power spectrum energy (for frame_energy register)
    input  wire [31:0] pwr_data_i,
    input  wire        pwr_valid_i,
    // IRQ
    output reg         irq_o
);

    // Decode control register
    wire        audio_enable  = reg_audio_control[0];
    wire        soft_reset    = reg_audio_control[1];
    wire        irq_enable    = reg_audio_control[2];
    wire        mode_passthru = reg_audio_control[3]; // 0=MFCC, 1=passthrough

    // FIFO threshold: need at least 640 samples (frame size from config)
    wire [10:0] frame_size = reg_window_config[10:0];

    // Pipeline FSM states
    localparam P_IDLE      = 4'd0;
    localparam P_WAIT_FIFO = 4'd1;
    localparam P_WINDOW    = 4'd2;
    localparam P_FFT       = 4'd3;
    localparam P_POWER     = 4'd4;
    localparam P_MEL       = 4'd5;
    localparam P_LOG       = 4'd6;
    localparam P_DCT       = 4'd7;
    localparam P_MFCC_WAIT = 4'd8;
    localparam P_DMA       = 4'd9;
    localparam P_DMA_WAIT  = 4'd10;
    localparam P_PASSTHRU  = 4'd11;

    reg [3:0]  pipe_state;
    reg [5:0]  mfcc_vec_count; // 0-49
    reg        running;
    reg [31:0] cycle_counter;
    reg        irq_frame_r;
    reg        irq_dma_r;

    // Frame energy accumulator
    reg [31:0] energy_acc;

    always @(posedge clk) begin
        if (!rst_n || soft_reset) begin
            pipe_state      <= P_IDLE;
            running         <= 1'b0;
            mfcc_vec_count  <= 6'd0;
            cycle_counter   <= 32'd0;
            status_o        <= 32'd0;
            perf_cycles_o   <= 32'd0;
            frame_energy_o  <= 32'd0;
            energy_acc      <= 32'd0;
            irq_o           <= 1'b0;
            irq_frame_r     <= 1'b0;
            irq_dma_r       <= 1'b0;
            window_start_o  <= 1'b0;
            fft_start_o     <= 1'b0;
            pwr_start_o     <= 1'b0;
            mel_start_o     <= 1'b0;
            log_start_o     <= 1'b0;
            dct_start_o     <= 1'b0;
            mfcc_bank_swap_o <= 1'b0;
            dma_start_o     <= 1'b0;
            dma_mode_o      <= 1'b0;
            dma_base_addr_o <= 32'd0;
            dma_length_o    <= 32'd0;
        end else begin
            // Default pulse signals
            window_start_o   <= 1'b0;
            fft_start_o      <= 1'b0;
            pwr_start_o      <= 1'b0;
            mel_start_o      <= 1'b0;
            log_start_o      <= 1'b0;
            dct_start_o      <= 1'b0;
            mfcc_bank_swap_o <= 1'b0;
            dma_start_o      <= 1'b0;

            // IRQ clear
            if (reg_irq_clear_frame) irq_frame_r <= 1'b0;
            if (reg_irq_clear_dma)   irq_dma_r   <= 1'b0;
            irq_o <= irq_enable & (irq_frame_r | irq_dma_r);

            // Energy accumulation from power spectrum
            if (pwr_valid_i)
                energy_acc <= energy_acc + pwr_data_i;

            // Start trigger
            if (reg_start_pulse && audio_enable) begin
                running        <= 1'b1;
                mfcc_vec_count <= 6'd0;
                cycle_counter  <= 32'd0;
                if (mode_passthru)
                    pipe_state <= P_PASSTHRU;
                else
                    pipe_state <= P_WAIT_FIFO;
            end

            // Pipeline state machine
            case (pipe_state)
                P_IDLE: begin
                    status_o[0] <= 1'b0; // Not busy
                end

                P_WAIT_FIFO: begin
                    status_o[0] <= 1'b1; // Busy
                    if (fifo_fill_level >= frame_size) begin
                        window_start_o <= 1'b1;
                        cycle_counter  <= 32'd0;
                        energy_acc     <= 32'd0;
                        pipe_state     <= P_WINDOW;
                    end
                end

                P_WINDOW: begin
                    cycle_counter <= cycle_counter + 32'd1;
                    if (window_done_i) begin
                        fft_start_o <= 1'b1;
                        pipe_state  <= P_FFT;
                    end
                end

                P_FFT: begin
                    cycle_counter <= cycle_counter + 32'd1;
                    if (fft_done_i) begin
                        pwr_start_o <= 1'b1;
                        pipe_state  <= P_POWER;
                    end
                end

                P_POWER: begin
                    cycle_counter <= cycle_counter + 32'd1;
                    if (pwr_done_i) begin
                        frame_energy_o <= energy_acc;
                        // Start mel->log->DCT as a streaming chain
                        mel_start_o    <= 1'b1;
                        log_start_o    <= 1'b1;
                        dct_start_o    <= 1'b1;
                        pipe_state     <= P_DCT;
                    end
                end

                // P_MEL, P_LOG unused — mel/log/DCT run concurrently as streaming pipeline
                P_MEL: begin
                    pipe_state <= P_DCT;
                end

                P_LOG: begin
                    pipe_state <= P_DCT;
                end

                P_DCT: begin
                    cycle_counter <= cycle_counter + 32'd1;
                    if (dct_done_i) begin
                        perf_cycles_o  <= cycle_counter;
                        mfcc_vec_count <= mfcc_vec_count + 6'd1;
                        status_o[15:8] <= mfcc_vec_count + 6'd1;

                        if (mfcc_frame_ready) begin
                            // 49 vectors complete, start DMA
                            dma_start_o     <= 1'b1;
                            dma_mode_o      <= 1'b0; // MFCC mode
                            dma_base_addr_o <= reg_dma_base_addr;
                            dma_length_o    <= 32'd980; // 49*10*2 bytes
                            pipe_state      <= P_DMA_WAIT;
                        end else begin
                            // More vectors needed, wait for next frame
                            pipe_state <= P_WAIT_FIFO;
                        end
                    end
                end

                P_DMA_WAIT: begin
                    status_o[3] <= 1'b1; // DMA busy
                    if (dma_done_i) begin
                        status_o[3]      <= 1'b0;
                        status_o[4]      <= 1'b1; // DMA done
                        status_o[2]      <= 1'b1; // Frame ready
                        irq_frame_r      <= 1'b1;
                        irq_dma_r        <= 1'b1;
                        mfcc_bank_swap_o <= 1'b1;
                        mfcc_vec_count   <= 6'd0;

                        if (running && audio_enable)
                            pipe_state <= P_WAIT_FIFO;
                        else
                            pipe_state <= P_IDLE;
                    end
                end

                P_PASSTHRU: begin
                    // In passthrough mode, DMA streams raw PCM from FIFO to DDR
                    status_o[0] <= 1'b1;
                    if (!fifo_empty) begin
                        dma_start_o     <= 1'b1;
                        dma_mode_o      <= 1'b1; // Passthrough
                        dma_base_addr_o <= reg_dma_base_addr;
                        dma_length_o    <= reg_dma_length;
                        pipe_state      <= P_DMA_WAIT;
                    end
                end

                default: pipe_state <= P_IDLE;
            endcase

            // FIFO status passthrough
            status_o[1] <= fifo_overrun;

            // Stop command
            if (!audio_enable && running) begin
                running    <= 1'b0;
                pipe_state <= P_IDLE;
            end
        end
    end

endmodule
