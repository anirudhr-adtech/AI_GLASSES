`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem
// Module: audio_subsys_top
// Description: Top-level wrapper. Instantiates all audio modules:
//              I2S RX, FIFO, Window, FFT, Power Spectrum, Mel Filterbank,
//              Log Compress, DCT, MFCC Buffer, DMA, Regfile, Controller.
//////////////////////////////////////////////////////////////////////////////

module audio_subsys_top (
    input  wire        clk_i,
    input  wire        rst_ni,
    // I2S interface
    input  wire        i2s_sck_i,
    input  wire        i2s_ws_i,
    input  wire        i2s_sd_i,
    // AXI4-Lite slave (CPU register access)
    input  wire [31:0] s_axi_lite_awaddr,
    input  wire        s_axi_lite_awvalid,
    output wire        s_axi_lite_awready,
    input  wire [31:0] s_axi_lite_wdata,
    input  wire [3:0]  s_axi_lite_wstrb,
    input  wire        s_axi_lite_wvalid,
    output wire        s_axi_lite_wready,
    output wire [1:0]  s_axi_lite_bresp,
    output wire        s_axi_lite_bvalid,
    input  wire        s_axi_lite_bready,
    input  wire [31:0] s_axi_lite_araddr,
    input  wire        s_axi_lite_arvalid,
    output wire        s_axi_lite_arready,
    output wire [31:0] s_axi_lite_rdata,
    output wire [1:0]  s_axi_lite_rresp,
    output wire        s_axi_lite_rvalid,
    input  wire        s_axi_lite_rready,
    // AXI4 master (DMA writes to DDR)
    output wire [3:0]  m_axi_dma_awid,
    output wire [31:0] m_axi_dma_awaddr,
    output wire [7:0]  m_axi_dma_awlen,
    output wire [2:0]  m_axi_dma_awsize,
    output wire [1:0]  m_axi_dma_awburst,
    output wire        m_axi_dma_awvalid,
    input  wire        m_axi_dma_awready,
    output wire [31:0] m_axi_dma_wdata,
    output wire [3:0]  m_axi_dma_wstrb,
    output wire        m_axi_dma_wlast,
    output wire        m_axi_dma_wvalid,
    input  wire        m_axi_dma_wready,
    input  wire [3:0]  m_axi_dma_bid,
    input  wire [1:0]  m_axi_dma_bresp,
    input  wire        m_axi_dma_bvalid,
    output wire        m_axi_dma_bready,
    // Interrupt
    output wire        irq_audio_ready_o
);

    // ====================================================================
    // Internal wires
    // ====================================================================

    // I2S -> FIFO
    wire [15:0] i2s_sample;
    wire        i2s_sample_valid;

    // FIFO interface
    wire        fifo_rd_en;
    wire [15:0] fifo_rd_data;
    wire        fifo_full, fifo_empty;
    wire [10:0] fifo_fill_level;
    wire        fifo_overrun;

    // Window interface
    wire        window_start, window_done;
    wire        window_fifo_rd;
    wire [15:0] window_out_data;
    wire        window_out_valid;
    wire [9:0]  window_out_addr;

    // FFT interface
    wire        fft_start, fft_done;
    wire [15:0] fft_out_re, fft_out_im;
    wire [9:0]  fft_out_addr;
    wire        fft_out_rd_en;

    // Power spectrum interface
    wire        pwr_start, pwr_done;
    wire [31:0] pwr_data;
    wire [9:0]  pwr_addr;
    wire        pwr_valid;

    // Power spectrum BRAM (holds 513 x 32-bit values)
    (* ram_style = "block" *)
    reg [31:0] pwr_bram [0:511];
    reg [31:0] pwr_bram_rd;

    always @(posedge clk_i) begin
        if (pwr_valid)
            pwr_bram[pwr_addr[8:0]] <= pwr_data;
    end

    // Mel filterbank power read
    wire [9:0]  mel_pwr_addr;
    wire        mel_pwr_rd_en;
    reg  [31:0] mel_pwr_data;

    always @(posedge clk_i) begin
        if (mel_pwr_rd_en)
            mel_pwr_data <= pwr_bram[mel_pwr_addr[8:0]];
    end

    // Mel filterbank interface
    wire        mel_start, mel_done;
    wire [31:0] mel_data;
    wire [5:0]  mel_idx;
    wire        mel_valid;

    // Log compress interface
    wire        log_start, log_done;
    wire [15:0] log_data;
    wire [5:0]  log_idx;
    wire        log_valid;

    // DCT interface
    wire        dct_start, dct_done;
    wire [15:0] mfcc_data;
    wire [3:0]  mfcc_idx;
    wire        mfcc_valid;

    // MFCC buffer interface
    wire        mfcc_frame_ready;
    wire        mfcc_bank_swap;
    wire        mfcc_buf_rd_en;
    wire [8:0]  mfcc_buf_rd_addr;
    wire [15:0] mfcc_buf_rd_data;

    // DMA interface
    wire        dma_start, dma_done;
    wire        dma_mode;
    wire [31:0] dma_base_addr, dma_length;
    wire [31:0] dma_wr_ptr;
    wire [31:0] dma_src_data;
    wire        dma_src_valid;
    wire        dma_src_ready;

    // Controller <-> Regfile
    wire [31:0] reg_audio_control;
    wire [31:0] reg_mfcc_config;
    wire [31:0] reg_window_config;
    wire [31:0] reg_fft_config;
    wire [31:0] reg_dma_base_addr;
    wire [31:0] reg_dma_length;
    wire [31:0] reg_gain_control;
    wire [31:0] reg_noise_floor;
    wire [31:0] reg_sample_rate_div;
    wire        reg_start_pulse;
    wire        reg_irq_clear_frame;
    wire        reg_irq_clear_dma;
    wire [31:0] ctrl_status;
    wire [31:0] ctrl_perf_cycles;
    wire [31:0] ctrl_frame_energy;

    // FIFO status for regfile
    wire [31:0] fifo_status_word = {19'd0, fifo_overrun, fifo_empty, fifo_full, fifo_fill_level[9:0]};

    // ====================================================================
    // Module Instantiations
    // ====================================================================

    // 1. I2S Receiver
    i2s_rx u_i2s_rx (
        .clk            (clk_i),
        .rst_n          (rst_ni),
        .i2s_sck_i      (i2s_sck_i),
        .i2s_ws_i       (i2s_ws_i),
        .i2s_sd_i       (i2s_sd_i),
        .sample_o       (i2s_sample),
        .sample_valid_o (i2s_sample_valid)
    );

    // 2. Audio FIFO
    audio_fifo u_fifo (
        .clk        (clk_i),
        .rst_n      (rst_ni),
        .wr_en      (i2s_sample_valid),
        .wr_data    (i2s_sample),
        .rd_en      (fifo_rd_en),
        .rd_data    (fifo_rd_data),
        .full       (fifo_full),
        .empty      (fifo_empty),
        .fill_level (fifo_fill_level),
        .overrun    (fifo_overrun)
    );

    // 3. Audio Window
    assign fifo_rd_en = window_fifo_rd;

    audio_window u_window (
        .clk            (clk_i),
        .rst_n          (rst_ni),
        .start_i        (window_start),
        .fifo_rd_en_o   (window_fifo_rd),
        .fifo_rd_data_i (fifo_rd_data),
        .done_o         (window_done),
        .out_data_o     (window_out_data),
        .out_valid_o    (window_out_valid),
        .out_addr_o     (window_out_addr)
    );

    // 4. FFT Engine
    fft_engine u_fft (
        .clk         (clk_i),
        .rst_n       (rst_ni),
        .start_i     (fft_start),
        .in_data_i   (window_out_data),
        .in_addr_i   (window_out_addr),
        .in_wr_en_i  (window_out_valid),
        .done_o      (fft_done),
        .out_re_o    (fft_out_re),
        .out_im_o    (fft_out_im),
        .out_addr_i  (fft_out_addr),
        .out_rd_en_i (fft_out_rd_en)
    );

    // 5. Power Spectrum
    assign fft_out_addr  = pwr_fft_addr;
    assign fft_out_rd_en = pwr_fft_rd_en;

    wire [9:0] pwr_fft_addr;
    wire       pwr_fft_rd_en;

    power_spectrum u_pwr (
        .clk         (clk_i),
        .rst_n       (rst_ni),
        .start_i     (pwr_start),
        .fft_re_i    (fft_out_re),
        .fft_im_i    (fft_out_im),
        .fft_addr_o  (pwr_fft_addr),
        .fft_rd_en_o (pwr_fft_rd_en),
        .done_o      (pwr_done),
        .pwr_data_o  (pwr_data),
        .pwr_addr_o  (pwr_addr),
        .pwr_valid_o (pwr_valid)
    );

    // 6. Mel Filterbank
    mel_filterbank u_mel (
        .clk         (clk_i),
        .rst_n       (rst_ni),
        .start_i     (mel_start),
        .pwr_data_i  (mel_pwr_data),
        .pwr_addr_o  (mel_pwr_addr),
        .pwr_rd_en_o (mel_pwr_rd_en),
        .done_o      (mel_done),
        .mel_data_o  (mel_data),
        .mel_idx_o   (mel_idx),
        .mel_valid_o (mel_valid)
    );

    // 7. Log Compress
    log_compress u_log (
        .clk         (clk_i),
        .rst_n       (rst_ni),
        .start_i     (log_start),
        .mel_data_i  (mel_data),
        .mel_idx_i   (mel_idx),
        .mel_valid_i (mel_valid),
        .done_o      (log_done),
        .log_data_o  (log_data),
        .log_idx_o   (log_idx),
        .log_valid_o (log_valid)
    );

    // 8. DCT Unit
    dct_unit u_dct (
        .clk          (clk_i),
        .rst_n        (rst_ni),
        .start_i      (dct_start),
        .log_data_i   (log_data),
        .log_idx_i    (log_idx),
        .log_valid_i  (log_valid),
        .done_o       (dct_done),
        .mfcc_data_o  (mfcc_data),
        .mfcc_idx_o   (mfcc_idx),
        .mfcc_valid_o (mfcc_valid)
    );

    // 9. MFCC Output Buffer
    mfcc_out_buf u_mfcc_buf (
        .clk           (clk_i),
        .rst_n         (rst_ni),
        .wr_en         (mfcc_valid),
        .wr_data       (mfcc_data),
        .wr_idx        (mfcc_idx),
        .frame_ready_o (mfcc_frame_ready),
        .bank_swap_i   (mfcc_bank_swap),
        .rd_en         (mfcc_buf_rd_en),
        .rd_addr       (mfcc_buf_rd_addr),
        .rd_data       (mfcc_buf_rd_data)
    );

    // DMA source data: read from MFCC buffer (inactive bank)
    // Simple sequencer: when DMA requests data, read from MFCC buffer
    reg [8:0] dma_rd_addr_cnt;
    reg       dma_rd_active;

    assign mfcc_buf_rd_en   = dma_src_ready && dma_rd_active;
    assign mfcc_buf_rd_addr = dma_rd_addr_cnt;
    assign dma_src_data     = {16'd0, mfcc_buf_rd_data};
    assign dma_src_valid    = dma_rd_active;

    always @(posedge clk_i) begin
        if (!rst_ni) begin
            dma_rd_addr_cnt <= 9'd0;
            dma_rd_active   <= 1'b0;
        end else begin
            if (dma_start) begin
                dma_rd_addr_cnt <= 9'd0;
                dma_rd_active   <= 1'b1;
            end else if (dma_src_ready && dma_rd_active) begin
                if (dma_rd_addr_cnt == 9'd489) begin // 49*10 - 1
                    dma_rd_active <= 1'b0;
                end else begin
                    dma_rd_addr_cnt <= dma_rd_addr_cnt + 9'd1;
                end
            end
            if (dma_done)
                dma_rd_active <= 1'b0;
        end
    end

    // 10. Audio DMA
    audio_dma u_dma (
        .clk             (clk_i),
        .rst_n           (rst_ni),
        .start_i         (dma_start),
        .mode_i          (dma_mode),
        .base_addr_i     (dma_base_addr),
        .length_i        (dma_length),
        .src_data_i      (dma_src_data),
        .src_valid_i     (dma_src_valid),
        .src_ready_o     (dma_src_ready),
        .done_o          (dma_done),
        .dma_wr_ptr_o    (dma_wr_ptr),
        .m_axi_awid      (m_axi_dma_awid),
        .m_axi_awaddr    (m_axi_dma_awaddr),
        .m_axi_awlen     (m_axi_dma_awlen),
        .m_axi_awsize    (m_axi_dma_awsize),
        .m_axi_awburst   (m_axi_dma_awburst),
        .m_axi_awvalid   (m_axi_dma_awvalid),
        .m_axi_awready   (m_axi_dma_awready),
        .m_axi_wdata     (m_axi_dma_wdata),
        .m_axi_wstrb     (m_axi_dma_wstrb),
        .m_axi_wlast     (m_axi_dma_wlast),
        .m_axi_wvalid    (m_axi_dma_wvalid),
        .m_axi_wready    (m_axi_dma_wready),
        .m_axi_bid       (m_axi_dma_bid),
        .m_axi_bresp     (m_axi_dma_bresp),
        .m_axi_bvalid    (m_axi_dma_bvalid),
        .m_axi_bready    (m_axi_dma_bready)
    );

    // 11. Audio Register File
    audio_regfile u_regfile (
        .clk               (clk_i),
        .rst_n             (rst_ni),
        .s_axil_awaddr     (s_axi_lite_awaddr),
        .s_axil_awvalid    (s_axi_lite_awvalid),
        .s_axil_awready    (s_axi_lite_awready),
        .s_axil_wdata      (s_axi_lite_wdata),
        .s_axil_wstrb      (s_axi_lite_wstrb),
        .s_axil_wvalid     (s_axi_lite_wvalid),
        .s_axil_wready     (s_axi_lite_wready),
        .s_axil_bresp      (s_axi_lite_bresp),
        .s_axil_bvalid     (s_axi_lite_bvalid),
        .s_axil_bready     (s_axi_lite_bready),
        .s_axil_araddr     (s_axi_lite_araddr),
        .s_axil_arvalid    (s_axi_lite_arvalid),
        .s_axil_arready    (s_axi_lite_arready),
        .s_axil_rdata      (s_axi_lite_rdata),
        .s_axil_rresp      (s_axi_lite_rresp),
        .s_axil_rvalid     (s_axi_lite_rvalid),
        .s_axil_rready     (s_axi_lite_rready),
        .reg_audio_control (reg_audio_control),
        .reg_audio_status  (),
        .reg_sample_rate_div (reg_sample_rate_div),
        .reg_fifo_status   (),
        .reg_mfcc_config   (reg_mfcc_config),
        .reg_window_config (reg_window_config),
        .reg_fft_config    (reg_fft_config),
        .reg_dma_base_addr (reg_dma_base_addr),
        .reg_dma_length    (reg_dma_length),
        .reg_dma_wr_ptr    (),
        .reg_gain_control  (reg_gain_control),
        .reg_noise_floor   (reg_noise_floor),
        .reg_start_pulse   (reg_start_pulse),
        .reg_irq_clear_frame (reg_irq_clear_frame),
        .reg_irq_clear_dma   (reg_irq_clear_dma),
        .reg_perf_cycles   (),
        .reg_frame_energy  (),
        .status_i          (ctrl_status),
        .fifo_status_i     (fifo_status_word),
        .dma_wr_ptr_i      (dma_wr_ptr),
        .perf_cycles_i     (ctrl_perf_cycles),
        .frame_energy_i    (ctrl_frame_energy)
    );

    // 12. Audio Controller
    audio_controller u_ctrl (
        .clk                (clk_i),
        .rst_n              (rst_ni),
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
        .status_o           (ctrl_status),
        .perf_cycles_o      (ctrl_perf_cycles),
        .frame_energy_o     (ctrl_frame_energy),
        .fifo_fill_level    (fifo_fill_level),
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
        .irq_o              (irq_audio_ready_o)
    );

endmodule
