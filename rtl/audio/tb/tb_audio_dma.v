`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem — Testbench
// Module: tb_audio_dma
// Description: Self-checking testbench for audio_dma.
//////////////////////////////////////////////////////////////////////////////

module tb_audio_dma;

    reg        clk;
    reg        rst_n;
    reg        start;
    reg        mode;
    reg [31:0] base_addr;
    reg [31:0] length;
    reg [31:0] src_data;
    reg        src_valid;
    wire       src_ready;
    wire       done;
    wire [31:0] dma_wr_ptr;

    // AXI signals
    wire [3:0]  awid;
    wire [31:0] awaddr;
    wire [7:0]  awlen;
    wire [2:0]  awsize;
    wire [1:0]  awburst;
    wire        awvalid;
    reg         awready;
    wire [31:0] wdata;
    wire [3:0]  wstrb;
    wire        wlast;
    wire        wvalid;
    reg         wready;
    reg  [3:0]  bid;
    reg  [1:0]  bresp;
    reg         bvalid;
    wire        bready;

    audio_dma uut (
        .clk             (clk),
        .rst_n           (rst_n),
        .start_i         (start),
        .mode_i          (mode),
        .base_addr_i     (base_addr),
        .length_i        (length),
        .src_data_i      (src_data),
        .src_valid_i     (src_valid),
        .src_ready_o     (src_ready),
        .done_o          (done),
        .dma_wr_ptr_o    (dma_wr_ptr),
        .m_axi_awid      (awid),
        .m_axi_awaddr    (awaddr),
        .m_axi_awlen     (awlen),
        .m_axi_awsize    (awsize),
        .m_axi_awburst   (awburst),
        .m_axi_awvalid   (awvalid),
        .m_axi_awready   (awready),
        .m_axi_wdata     (wdata),
        .m_axi_wstrb     (wstrb),
        .m_axi_wlast     (wlast),
        .m_axi_wvalid    (wvalid),
        .m_axi_wready    (wready),
        .m_axi_bid       (bid),
        .m_axi_bresp     (bresp),
        .m_axi_bvalid    (bvalid),
        .m_axi_bready    (bready)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer errors;
    integer beat_count;

    // Global timeout guard
    initial begin
        #200000;
        $display("FAIL: Global timeout reached");
        $finish;
    end

    // Track done pulse in concurrent always block
    reg done_seen;
    always @(posedge clk) begin
        #1;
        if (done) done_seen = 1;
    end

    // Track beats transferred (concurrent always block)
    always @(posedge clk) begin
        #1;
        if (wvalid && wready)
            beat_count = beat_count + 1;
    end

    initial begin
        $display("=== tb_audio_dma: START ===");
        errors = 0;
        rst_n = 0;
        start = 0;
        mode = 0;
        base_addr = 0;
        length = 0;
        src_data = 0;
        src_valid = 0;
        awready = 1;  // Always ready for address phase
        wready = 1;   // Always ready for data phase
        bid = 4'b1100;
        bresp = 2'b00;
        bvalid = 0;
        beat_count = 0;
        done_seen = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (3) @(posedge clk);

        // Test 1: Small MFCC transfer (16 bytes = 4 words)
        base_addr = 32'h0100_0000;
        length    = 32'd16;
        mode      = 0;

        // Assert src_valid with data before starting DMA
        src_valid = 1;
        src_data  = 32'hDEAD_BEEF;

        start = 1;
        @(posedge clk); #1;
        start = 0;

        // Wait for awvalid to check AXI address signals
        begin : addr_check_blk
            integer countdown;
            countdown = 100;
            while (!awvalid && countdown > 0) begin
                @(posedge clk); #1;
                countdown = countdown - 1;
            end

            if (countdown == 0) begin
                $display("FAIL: Timeout waiting for awvalid");
                errors = errors + 1;
            end else begin
                if (awid != 4'b1100) begin
                    $display("FAIL: AWID = 0x%01X, expected 0xC", awid);
                    errors = errors + 1;
                end
                if (awaddr != 32'h0100_0000) begin
                    $display("FAIL: AWADDR = 0x%08X, expected 0x01000000", awaddr);
                    errors = errors + 1;
                end
                if (awsize != 3'b010) begin
                    $display("FAIL: AWSIZE = %0d, expected 2 (4 bytes)", awsize);
                    errors = errors + 1;
                end
                if (awburst != 2'b01) begin
                    $display("FAIL: AWBURST = %0d, expected 1 (INCR)", awburst);
                    errors = errors + 1;
                end
            end
        end

        // Wait for bready (DMA finishes data phase and enters S_RESP)
        begin : resp_blk
            integer countdown;
            countdown = 1000;
            while (!bready && countdown > 0) begin
                @(posedge clk); #1;
                countdown = countdown - 1;
            end

            if (countdown == 0) begin
                $display("FAIL: Timeout waiting for bready");
                errors = errors + 1;
            end else begin
                // Complete write response handshake
                bvalid = 1;
                bresp  = 2'b00;
                @(posedge clk); #1;
                bvalid = 0;
            end
        end

        src_valid = 0;

        // Wait for done
        begin : done_blk
            integer countdown;
            countdown = 100;
            while (!done_seen && countdown > 0) begin
                @(posedge clk); #1;
                countdown = countdown - 1;
            end
        end

        @(posedge clk); #1;

        // Check results
        if (beat_count < 1) begin
            $display("FAIL: No data beats transferred");
            errors = errors + 1;
        end

        if (dma_wr_ptr <= 32'h0100_0000) begin
            $display("FAIL: DMA write pointer not advanced");
            errors = errors + 1;
        end

        $display("  DMA transferred %0d beats, wr_ptr = 0x%08X", beat_count, dma_wr_ptr);

        if (errors == 0) begin
            $display("=== tb_audio_dma: PASSED ===");
            $display("ALL TESTS PASSED");
        end else
            $display("=== tb_audio_dma: FAILED (%0d errors) ===", errors);

        $finish;
    end

endmodule
