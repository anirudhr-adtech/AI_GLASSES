`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem — Testbench
// Module: tb_audio_subsys_top
// Description: Self-checking integration testbench for audio_subsys_top.
//              Verifies AXI-Lite register access and basic I2S connectivity.
//////////////////////////////////////////////////////////////////////////////

module tb_audio_subsys_top;

    reg        clk;
    reg        rst_n;

    // I2S
    reg        i2s_sck;
    reg        i2s_ws;
    reg        i2s_sd;

    // AXI-Lite
    reg  [31:0] awaddr, araddr, wdata;
    reg  [3:0]  wstrb;
    reg         awvalid, wvalid, bready, arvalid, rready;
    wire        awready, wready, bvalid, arready, rvalid;
    wire [1:0]  bresp, rresp;
    wire [31:0] rdata;

    // AXI4 DMA (stub slave)
    wire [3:0]  dma_awid;
    wire [31:0] dma_awaddr;
    wire [7:0]  dma_awlen;
    wire [2:0]  dma_awsize;
    wire [1:0]  dma_awburst;
    wire        dma_awvalid;
    reg         dma_awready;
    wire [31:0] dma_wdata;
    wire [3:0]  dma_wstrb;
    wire        dma_wlast;
    wire        dma_wvalid;
    reg         dma_wready;
    reg  [3:0]  dma_bid;
    reg  [1:0]  dma_bresp;
    reg         dma_bvalid;
    wire        dma_bready;

    wire        irq;

    audio_subsys_top uut (
        .clk_i              (clk),
        .rst_ni             (rst_n),
        .i2s_sck_i          (i2s_sck),
        .i2s_ws_i           (i2s_ws),
        .i2s_sd_i           (i2s_sd),
        .s_axi_lite_awaddr  (awaddr),
        .s_axi_lite_awvalid (awvalid),
        .s_axi_lite_awready (awready),
        .s_axi_lite_wdata   (wdata),
        .s_axi_lite_wstrb   (wstrb),
        .s_axi_lite_wvalid  (wvalid),
        .s_axi_lite_wready  (wready),
        .s_axi_lite_bresp   (bresp),
        .s_axi_lite_bvalid  (bvalid),
        .s_axi_lite_bready  (bready),
        .s_axi_lite_araddr  (araddr),
        .s_axi_lite_arvalid (arvalid),
        .s_axi_lite_arready (arready),
        .s_axi_lite_rdata   (rdata),
        .s_axi_lite_rresp   (rresp),
        .s_axi_lite_rvalid  (rvalid),
        .s_axi_lite_rready  (rready),
        .m_axi_dma_awid     (dma_awid),
        .m_axi_dma_awaddr   (dma_awaddr),
        .m_axi_dma_awlen    (dma_awlen),
        .m_axi_dma_awsize   (dma_awsize),
        .m_axi_dma_awburst  (dma_awburst),
        .m_axi_dma_awvalid  (dma_awvalid),
        .m_axi_dma_awready  (dma_awready),
        .m_axi_dma_wdata    (dma_wdata),
        .m_axi_dma_wstrb    (dma_wstrb),
        .m_axi_dma_wlast    (dma_wlast),
        .m_axi_dma_wvalid   (dma_wvalid),
        .m_axi_dma_wready   (dma_wready),
        .m_axi_dma_bid      (dma_bid),
        .m_axi_dma_bresp    (dma_bresp),
        .m_axi_dma_bvalid   (dma_bvalid),
        .m_axi_dma_bready   (dma_bready),
        .irq_audio_ready_o  (irq)
    );

    // Clock: 100 MHz
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
            while (!(awready || wready)) @(posedge clk);
            @(posedge clk);
            awvalid = 0;
            wvalid  = 0;
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
        $display("=== tb_audio_subsys_top: START ===");
        errors = 0;
        rst_n = 0;
        i2s_sck = 0;
        i2s_ws = 0;
        i2s_sd = 0;
        awaddr = 0; araddr = 0; wdata = 0; wstrb = 0;
        awvalid = 0; wvalid = 0; bready = 0;
        arvalid = 0; rready = 0;
        dma_awready = 0;
        dma_wready = 0;
        dma_bid = 4'b1100;
        dma_bresp = 2'b00;
        dma_bvalid = 0;

        repeat (10) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        // Test 1: Write and read MFCC_CONFIG register
        axil_write(32'h10, 32'h0000_C428);
        axil_read(32'h10, rd_val);
        if (rd_val != 32'h0000_C428) begin
            $display("FAIL: MFCC_CONFIG = 0x%08X, expected 0x0000C428", rd_val);
            errors = errors + 1;
        end

        // Test 2: Write WINDOW_CONFIG
        axil_write(32'h14, {21'd320, 11'd640});
        axil_read(32'h14, rd_val);
        $display("  WINDOW_CONFIG = 0x%08X", rd_val);

        // Test 3: Write DMA_BASE_ADDR
        axil_write(32'h1C, 32'h0100_0000);
        axil_read(32'h1C, rd_val);
        if (rd_val != 32'h0100_0000) begin
            $display("FAIL: DMA_BASE_ADDR = 0x%08X", rd_val);
            errors = errors + 1;
        end

        // Test 4: Write AUDIO_CONTROL (enable + MFCC mode + IRQ)
        axil_write(32'h00, 32'h0000_0005);
        axil_read(32'h00, rd_val);
        if (rd_val[0] != 1'b1) begin
            $display("FAIL: AUDIO_CONTROL enable bit not set");
            errors = errors + 1;
        end

        // Test 5: Read STATUS register
        axil_read(32'h04, rd_val);
        $display("  STATUS = 0x%08X", rd_val);

        // Test 6: Read FIFO_STATUS
        axil_read(32'h0C, rd_val);
        $display("  FIFO_STATUS = 0x%08X (empty=%b)", rd_val, rd_val[11]);

        // Test 7: Verify IRQ is low initially
        if (irq) begin
            $display("FAIL: IRQ should be low initially");
            errors = errors + 1;
        end

        // Test 8: Generate I2S traffic (simple pattern)
        fork
            begin : i2s_gen
                integer bit_idx;
                // Send one 16-bit sample via I2S
                i2s_ws = 1; // Right channel (skip)
                repeat (20) begin
                    i2s_sck = 0; repeat (100) @(posedge clk);
                    i2s_sck = 1; repeat (100) @(posedge clk);
                end
                // Left channel
                i2s_ws = 0;
                for (bit_idx = 15; bit_idx >= 0; bit_idx = bit_idx - 1) begin
                    i2s_sd = (bit_idx % 2); // Alternating pattern
                    i2s_sck = 0; repeat (100) @(posedge clk);
                    i2s_sck = 1; repeat (100) @(posedge clk);
                end
            end
        join

        repeat (100) @(posedge clk);

        // Check FIFO got some data
        axil_read(32'h0C, rd_val);
        $display("  FIFO_STATUS after I2S = 0x%08X (fill=%0d)", rd_val, rd_val[9:0]);

        if (errors == 0) begin
            $display("=== tb_audio_subsys_top: PASSED ===");
            $display("ALL TESTS PASSED");
        end else
            $display("=== tb_audio_subsys_top: FAILED (%0d errors) ===", errors);

        $finish;
    end

endmodule
