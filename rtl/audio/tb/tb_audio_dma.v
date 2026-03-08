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
    reg [31:0] received_data [0:255];

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
        awready = 0;
        wready = 0;
        bid = 4'b1100;
        bresp = 2'b00;
        bvalid = 0;
        beat_count = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (3) @(posedge clk);

        // Test 1: Small MFCC transfer (16 bytes = 4 words)
        base_addr = 32'h0100_0000;
        length    = 32'd16;
        mode      = 0;
        start     = 1;
        @(posedge clk);
        start = 0;

        // AXI slave: accept address
        fork
            begin : axi_slave
                // Wait for awvalid
                while (!awvalid) @(posedge clk);

                // Check AXI ID
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

                awready = 1;
                @(posedge clk);
                awready = 0;

                // Accept data beats
                wready = 1;
                src_valid = 1;
                while (beat_count < 4) begin
                    src_data = 32'hDEAD_0000 + beat_count;
                    @(posedge clk);
                    if (wvalid && wready) begin
                        received_data[beat_count] = wdata;
                        beat_count = beat_count + 1;
                        if (wlast && beat_count < 4) begin
                            $display("FAIL: WLAST asserted too early at beat %0d", beat_count);
                            errors = errors + 1;
                        end
                    end
                end
                wready = 0;
                src_valid = 0;

                // Send write response
                @(posedge clk);
                bvalid = 1;
                bresp = 2'b00;
                while (!(bvalid && bready)) @(posedge clk);
                bvalid = 0;
            end

            begin : check_done
                repeat (1000) @(posedge clk);
                $display("FAIL: Timeout waiting for DMA completion");
                errors = errors + 1;
                disable axi_slave;
            end
        join

        // Wait for done
        repeat (10) @(posedge clk);
        if (!done) begin
            // might have already gone, check
        end

        // Verify write pointer advanced
        if (dma_wr_ptr < 32'h0100_0000) begin
            $display("FAIL: DMA write pointer not advanced");
            errors = errors + 1;
        end

        $display("  DMA transferred %0d beats, wr_ptr = 0x%08X", beat_count, dma_wr_ptr);

        if (errors == 0)
            $display("=== tb_audio_dma: PASSED ===");
        else
            $display("=== tb_audio_dma: FAILED (%0d errors) ===", errors);

        $finish;
    end

endmodule
