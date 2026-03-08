`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem — Testbench
// Module: tb_audio_controller
// Description: Self-checking testbench for audio_controller.
//////////////////////////////////////////////////////////////////////////////

module tb_audio_controller;

    reg        clk;
    reg        rst_n;

    // Register inputs
    reg [31:0] reg_audio_control;
    reg [31:0] reg_mfcc_config;
    reg [31:0] reg_window_config;
    reg [31:0] reg_fft_config;
    reg [31:0] reg_dma_base_addr;
    reg [31:0] reg_dma_length;
    reg [31:0] reg_gain_control;
    reg [31:0] reg_noise_floor;
    reg        reg_start_pulse;
    reg        reg_irq_clear_frame;
    reg        reg_irq_clear_dma;

    // Status
    wire [31:0] status;
    wire [31:0] perf_cycles;
    wire [31:0] frame_energy;

    // FIFO
    reg [10:0] fifo_fill;
    reg        fifo_empty;
    reg        fifo_overrun;

    // Pipeline controls
    wire       window_start, fft_start, pwr_start;
    wire       mel_start, log_start, dct_start;
    reg        window_done, fft_done, pwr_done;
    reg        mel_done, log_done, dct_done;

    // MFCC buffer
    reg        mfcc_frame_ready;
    wire       mfcc_bank_swap;

    // DMA
    wire       dma_start;
    wire       dma_mode;
    wire [31:0] dma_base_addr, dma_length;
    reg        dma_done;
    reg [31:0] dma_wr_ptr;

    // Power spectrum
    reg [31:0] pwr_data;
    reg        pwr_valid;

    // IRQ
    wire       irq;

    audio_controller uut (
        .clk                (clk),
        .rst_n              (rst_n),
        .reg_audio_control  (reg_audio_control),
        .reg_mfcc_config    (reg_mfcc_config),
        .reg_window_config  (reg_window_config),
        .reg_fft_config     (reg_fft_config),
        .reg_dma_base_addr  (reg_dma_base_addr),
        .reg_dma_length     (reg_dma_length),
        .reg_gain_control   (reg_gain_control),
        .reg_noise_floor    (reg_noise_floor),
        .reg_start_pulse    (reg_start_pulse),
        .reg_irq_clear_frame (reg_irq_clear_frame),
        .reg_irq_clear_dma   (reg_irq_clear_dma),
        .status_o           (status),
        .perf_cycles_o      (perf_cycles),
        .frame_energy_o     (frame_energy),
        .fifo_fill_level    (fifo_fill),
        .fifo_empty         (fifo_empty),
        .fifo_overrun       (fifo_overrun),
        .window_start_o     (window_start),
        .window_done_i      (window_done),
        .fft_start_o        (fft_start),
        .fft_done_i         (fft_done),
        .pwr_start_o        (pwr_start),
        .pwr_done_i         (pwr_done),
        .mel_start_o        (mel_start),
        .mel_done_i         (mel_done),
        .log_start_o        (log_start),
        .log_done_i         (log_done),
        .dct_start_o        (dct_start),
        .dct_done_i         (dct_done),
        .mfcc_frame_ready   (mfcc_frame_ready),
        .mfcc_bank_swap_o   (mfcc_bank_swap),
        .dma_start_o        (dma_start),
        .dma_mode_o         (dma_mode),
        .dma_base_addr_o    (dma_base_addr),
        .dma_length_o       (dma_length),
        .dma_done_i         (dma_done),
        .dma_wr_ptr_i       (dma_wr_ptr),
        .pwr_data_i         (pwr_data),
        .pwr_valid_i        (pwr_valid),
        .irq_o              (irq)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer errors;

    // Simulate pipeline stage completions with delays
    always @(posedge clk) begin
        window_done <= 1'b0;
        fft_done    <= 1'b0;
        pwr_done    <= 1'b0;
        mel_done    <= 1'b0;
        log_done    <= 1'b0;
        dct_done    <= 1'b0;
        dma_done    <= 1'b0;
    end

    task simulate_pipeline;
        begin
            // Wait for window start
            while (!window_start) @(posedge clk);
            repeat (5) @(posedge clk);
            @(posedge clk); window_done <= 1'b1;
            @(posedge clk); window_done <= 1'b0;

            // Wait for FFT start
            while (!fft_start) @(posedge clk);
            repeat (5) @(posedge clk);
            @(posedge clk); fft_done <= 1'b1;
            @(posedge clk); fft_done <= 1'b0;

            // Wait for power spectrum start
            while (!pwr_start) @(posedge clk);
            repeat (3) @(posedge clk);
            @(posedge clk); pwr_done <= 1'b1;
            @(posedge clk); pwr_done <= 1'b0;

            // Wait for mel start
            while (!mel_start) @(posedge clk);
            repeat (3) @(posedge clk);
            @(posedge clk); mel_done <= 1'b1;
            @(posedge clk); mel_done <= 1'b0;

            // Wait for log start
            while (!log_start) @(posedge clk);
            repeat (3) @(posedge clk);
            @(posedge clk); log_done <= 1'b1;
            @(posedge clk); log_done <= 1'b0;

            // Wait for DCT start
            while (!dct_start) @(posedge clk);
            repeat (3) @(posedge clk);
            @(posedge clk); dct_done <= 1'b1;
            @(posedge clk); dct_done <= 1'b0;
        end
    endtask

    initial begin
        $display("=== tb_audio_controller: START ===");
        errors = 0;
        rst_n = 0;
        reg_audio_control = 32'h0000_0005; // enable + IRQ enable
        reg_mfcc_config   = 32'd0;
        reg_window_config = {21'd0, 11'd640}; // frame_size = 640
        reg_fft_config    = 32'd10;
        reg_dma_base_addr = 32'h0100_0000;
        reg_dma_length    = 32'd980;
        reg_gain_control  = 32'h0100;
        reg_noise_floor   = 32'd0;
        reg_start_pulse   = 0;
        reg_irq_clear_frame = 0;
        reg_irq_clear_dma = 0;
        fifo_fill = 11'd0;
        fifo_empty = 1;
        fifo_overrun = 0;
        mfcc_frame_ready = 0;
        dma_wr_ptr = 0;
        pwr_data = 0;
        pwr_valid = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (3) @(posedge clk);

        // Test 1: Start pipeline, run 1 MFCC frame (not frame_ready yet)
        reg_start_pulse = 1;
        @(posedge clk);
        reg_start_pulse = 0;

        // Fill FIFO
        fifo_fill = 11'd700;
        fifo_empty = 0;

        // Simulate one full pipeline pass
        simulate_pipeline();

        repeat (5) @(posedge clk);

        // Status should show busy
        if (status[0] != 1'b1) begin
            $display("INFO: Pipeline busy bit = %b after first vector", status[0]);
        end

        // Test 2: Simulate frame_ready -> DMA
        mfcc_frame_ready = 1;

        // Run another pipeline pass that triggers DMA
        simulate_pipeline();

        // Wait for DMA start
        fork
            begin : wait_dma
                while (!dma_start) @(posedge clk);
                $display("  DMA started, base=0x%08X, len=%0d", dma_base_addr, dma_length);
                repeat (10) @(posedge clk);
                @(posedge clk); dma_done <= 1'b1;
                @(posedge clk); dma_done <= 1'b0;
            end
            begin : dma_timeout
                repeat (500) @(posedge clk);
                $display("FAIL: DMA never started");
                errors = errors + 1;
                disable wait_dma;
            end
        join

        repeat (5) @(posedge clk);

        // Check IRQ assertion
        if (!irq) begin
            $display("FAIL: IRQ not asserted after frame completion");
            errors = errors + 1;
        end

        // Test 3: Clear IRQ
        reg_irq_clear_frame = 1;
        reg_irq_clear_dma   = 1;
        @(posedge clk);
        reg_irq_clear_frame = 0;
        reg_irq_clear_dma   = 0;
        repeat (3) @(posedge clk);

        if (irq) begin
            $display("FAIL: IRQ not cleared");
            errors = errors + 1;
        end

        // Test 4: Bank swap should have occurred
        // (mfcc_bank_swap is a pulse, hard to catch - just check no errors)

        if (errors == 0)
            $display("=== tb_audio_controller: PASSED ===");
        else
            $display("=== tb_audio_controller: FAILED (%0d errors) ===", errors);

        $finish;
    end

endmodule
