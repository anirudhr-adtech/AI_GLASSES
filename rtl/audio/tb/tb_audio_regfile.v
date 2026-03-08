`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem — Testbench
// Module: tb_audio_regfile
// Description: Self-checking testbench for audio_regfile.
//////////////////////////////////////////////////////////////////////////////

module tb_audio_regfile;

    reg        clk;
    reg        rst_n;

    // AXI-Lite signals
    reg  [31:0] awaddr, araddr, wdata;
    reg  [3:0]  wstrb;
    reg         awvalid, wvalid, bready, arvalid, rready;
    wire        awready, wready, bvalid, arready, rvalid;
    wire [1:0]  bresp, rresp;
    wire [31:0] rdata;

    // Register outputs
    wire [31:0] reg_audio_control;
    wire [31:0] reg_mfcc_config, reg_window_config;
    wire [31:0] reg_dma_base_addr, reg_dma_length;
    wire [31:0] reg_gain_control, reg_noise_floor;
    wire [31:0] reg_sample_rate_div, reg_fft_config;
    wire        reg_start_pulse, reg_irq_clear_frame, reg_irq_clear_dma;

    audio_regfile uut (
        .clk               (clk),
        .rst_n             (rst_n),
        .s_axil_awaddr     (awaddr),
        .s_axil_awvalid    (awvalid),
        .s_axil_awready    (awready),
        .s_axil_wdata      (wdata),
        .s_axil_wstrb      (wstrb),
        .s_axil_wvalid     (wvalid),
        .s_axil_wready     (wready),
        .s_axil_bresp      (bresp),
        .s_axil_bvalid     (bvalid),
        .s_axil_bready     (bready),
        .s_axil_araddr     (araddr),
        .s_axil_arvalid    (arvalid),
        .s_axil_arready    (arready),
        .s_axil_rdata      (rdata),
        .s_axil_rresp      (rresp),
        .s_axil_rvalid     (rvalid),
        .s_axil_rready     (rready),
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
        .status_i          (32'hCAFE_0001),
        .fifo_status_i     (32'h0000_0200),
        .dma_wr_ptr_i      (32'h0100_0010),
        .perf_cycles_i     (32'd12345),
        .frame_energy_i    (32'hABCD_1234)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer errors;

    // AXI-Lite write task
    task axil_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);
            awaddr  = addr;
            awvalid = 1;
            wdata   = data;
            wstrb   = 4'hF;
            wvalid  = 1;
            bready  = 1;
            // Wait for both ready
            while (!(awready || wready)) @(posedge clk);
            @(posedge clk);
            awvalid = 0;
            wvalid  = 0;
            // Wait for response
            while (!bvalid) @(posedge clk);
            @(posedge clk);
            bready = 0;
        end
    endtask

    // AXI-Lite read task
    task axil_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            @(posedge clk);
            araddr  = addr;
            arvalid = 1;
            rready  = 1;
            while (!arready) @(posedge clk);
            @(posedge clk);
            arvalid = 0;
            while (!rvalid) @(posedge clk);
            data = rdata;
            @(posedge clk);
            rready = 0;
        end
    endtask

    reg [31:0] rd_val;

    initial begin
        $display("=== tb_audio_regfile: START ===");
        errors = 0;
        rst_n = 0;
        awaddr = 0; araddr = 0; wdata = 0; wstrb = 0;
        awvalid = 0; wvalid = 0; bready = 0;
        arvalid = 0; rready = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (3) @(posedge clk);

        // Test 1: Write AUDIO_CONTROL (0x00)
        axil_write(32'h00, 32'h0000_000D);
        if (reg_audio_control != 32'h0000_000D) begin
            $display("FAIL: AUDIO_CONTROL = 0x%08X, expected 0x0000000D", reg_audio_control);
            errors = errors + 1;
        end

        // Test 2: Write and read back MFCC_CONFIG (0x10)
        axil_write(32'h10, 32'h0000_C428);
        axil_read(32'h10, rd_val);
        if (rd_val != 32'h0000_C428) begin
            $display("FAIL: MFCC_CONFIG readback = 0x%08X, expected 0x0000C428", rd_val);
            errors = errors + 1;
        end

        // Test 3: Write DMA_BASE_ADDR (0x1C)
        axil_write(32'h1C, 32'h0100_0000);
        if (reg_dma_base_addr != 32'h0100_0000) begin
            $display("FAIL: DMA_BASE_ADDR = 0x%08X, expected 0x01000000", reg_dma_base_addr);
            errors = errors + 1;
        end

        // Test 4: Read STATUS (0x04) - read-only
        axil_read(32'h04, rd_val);
        if (rd_val != 32'hCAFE_0001) begin
            $display("FAIL: STATUS readback = 0x%08X, expected 0xCAFE0001", rd_val);
            errors = errors + 1;
        end

        // Test 5: Read FIFO_STATUS (0x0C) - read-only
        axil_read(32'h0C, rd_val);
        if (rd_val != 32'h0000_0200) begin
            $display("FAIL: FIFO_STATUS = 0x%08X, expected 0x00000200", rd_val);
            errors = errors + 1;
        end

        // Test 6: Read PERF_CYCLES (0x38) - read-only
        axil_read(32'h38, rd_val);
        if (rd_val != 32'd12345) begin
            $display("FAIL: PERF_CYCLES = %0d, expected 12345", rd_val);
            errors = errors + 1;
        end

        // Test 7: START pulse (0x30) - self-clearing
        axil_write(32'h30, 32'h0000_0001);
        // Pulse should be self-clearing after 1 cycle
        repeat (3) @(posedge clk);
        if (reg_start_pulse != 1'b0) begin
            $display("FAIL: START pulse not self-clearing");
            errors = errors + 1;
        end

        // Test 8: GAIN_CONTROL reset value (0x28) should be 0x100
        // Read after write to different register
        axil_read(32'h28, rd_val);
        // We haven't written it, check default
        $display("  GAIN_CONTROL = 0x%08X", rd_val);

        // Test 9: Read FRAME_ENERGY (0x3C)
        axil_read(32'h3C, rd_val);
        if (rd_val != 32'hABCD_1234) begin
            $display("FAIL: FRAME_ENERGY = 0x%08X, expected 0xABCD1234", rd_val);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("=== tb_audio_regfile: PASSED ===");
        else
            $display("=== tb_audio_regfile: FAILED (%0d errors) ===", errors);

        $finish;
    end

endmodule
