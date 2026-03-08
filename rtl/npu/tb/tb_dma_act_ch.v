`timescale 1ns/1ps
//============================================================================
// Testbench: tb_dma_act_ch
// Basic stimulus for activation DMA channel (read direction: DDR -> buffer)
// Fixed for Verilator --timing: #1 sampling after posedge, RTL rlast_latch fix
//============================================================================

module tb_dma_act_ch;

    reg         clk;
    reg         rst_n;
    reg         start;
    reg  [31:0] src_addr;
    reg  [31:0] dst_addr;
    reg  [31:0] xfer_len;
    reg         direction;
    wire        done;

    // Buffer write
    wire        buf_we;
    wire [14:0] buf_addr;
    wire [31:0] buf_wdata;

    // Buffer read
    wire        buf_re;
    wire [14:0] buf_raddr;
    reg  [31:0] buf_rdata;

    // AXI read channel
    wire [31:0]  araddr;
    wire [7:0]   arlen;
    wire [2:0]   arsize;
    wire [1:0]   arburst;
    wire         arvalid;
    reg          arready;
    reg  [127:0] rdata;
    reg  [1:0]   rresp;
    reg          rlast;
    reg          rvalid;
    wire         rready;

    // AXI write channel
    wire [31:0]  awaddr;
    wire [7:0]   awlen;
    wire [2:0]   awsize;
    wire [1:0]   awburst;
    wire         awvalid;
    reg          awready;
    wire [127:0] wdata_axi;
    wire [15:0]  wstrb;
    wire         wlast;
    wire         wvalid;
    reg          wready;
    reg  [1:0]   bresp;
    reg          bvalid;
    wire         bready;

    initial clk = 0;
    always #5 clk = ~clk;

    dma_act_ch dut (
        .clk(clk), .rst_n(rst_n),
        .start(start), .src_addr(src_addr), .dst_addr(dst_addr),
        .xfer_len(xfer_len), .direction(direction), .done(done),
        .buf_we(buf_we), .buf_addr(buf_addr), .buf_wdata(buf_wdata),
        .buf_re(buf_re), .buf_raddr(buf_raddr), .buf_rdata(buf_rdata),
        .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize),
        .m_axi_arburst(arburst), .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rdata(rdata), .m_axi_rresp(rresp), .m_axi_rlast(rlast),
        .m_axi_rvalid(rvalid), .m_axi_rready(rready),
        .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize),
        .m_axi_awburst(awburst), .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata_axi), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast),
        .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bresp(bresp), .m_axi_bvalid(bvalid), .m_axi_bready(bready)
    );

    integer beat_count;
    integer errors;

    initial begin
        errors = 0;
        rst_n = 0; start = 0;
        src_addr = 0; dst_addr = 0; xfer_len = 0; direction = 0;
        arready = 0;
        rdata = 0; rresp = 0; rlast = 0; rvalid = 0;
        awready = 1;   // Pre-assert awready
        wready = 0; bresp = 0; bvalid = 0;
        buf_rdata = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Test 1: Read direction (DDR -> buffer), 32 bytes = 2 AXI beats
        $display("Test 1: DDR -> Buffer (read direction)");
        direction = 0;
        src_addr = 32'h8100_0000;
        xfer_len = 32'd32;
        start = 1;
        @(posedge clk);
        start = 0;

        // Wait for arvalid, then accept
        begin : ar_wait_blk
            integer countdown;
            countdown = 1000;
            forever begin
                @(posedge clk);
                #1;
                if (arvalid) begin
                    arready = 1;
                    @(posedge clk);
                    #1;
                    arready = 0;
                    $display("  AR issued: addr=%h, len=%0d", araddr, arlen);
                    countdown = -1;
                end
                countdown = countdown - 1;
                if (countdown == 0) begin
                    $display("FAIL: Timeout waiting for arvalid");
                    errors = errors + 1;
                end
                if (countdown <= 0) disable ar_wait_blk;
            end
        end

        // Serve 2 read data beats reactively
        for (beat_count = 0; beat_count < 2; beat_count = beat_count + 1) begin : beat_loop
            integer countdown;
            countdown = 2000;
            forever begin
                @(posedge clk);
                #1;
                if (rready && !rvalid) begin
                    rvalid = 1;
                    rdata = {4{beat_count[31:0]}};
                    rlast = (beat_count == 1);
                    @(posedge clk);
                    #1;
                    rvalid = 0;
                    rlast  = 0;
                    countdown = -1;
                end
                countdown = countdown - 1;
                if (countdown == 0) begin
                    $display("FAIL: Timeout waiting for rready at beat %0d", beat_count);
                    errors = errors + 1;
                end
                if (countdown <= 0) disable beat_loop;
            end
        end

        // Wait for done
        begin : done_wait_blk
            integer countdown;
            countdown = 1000;
            while (countdown > 0) begin
                @(posedge clk);
                #1;
                if (done) begin
                    $display("  Read DMA done");
                    countdown = -1;
                end
                countdown = countdown - 1;
            end
            if (countdown == 0) begin
                $display("FAIL: Timeout waiting for done");
                errors = errors + 1;
            end
        end

        repeat (5) @(posedge clk);
        $display("========================================");
        if (errors == 0) begin
            $display("tb_dma_act_ch: basic test PASSED");
            $display("ALL TESTS PASSED");
        end else
            $display("tb_dma_act_ch: FAILED (%0d errors)", errors);
        $display("========================================");
        $finish;
    end

    // Global watchdog
    initial begin
        #200000;
        $display("FAIL: Global watchdog timeout");
        $finish;
    end

endmodule
