`timescale 1ns/1ps
//============================================================================
// Testbench: tb_dma_weight_ch
// Basic stimulus for weight DMA channel — verifies FSM progression
// Fixed for Verilator --timing: #1 sampling after posedge
//============================================================================

module tb_dma_weight_ch;

    reg         clk;
    reg         rst_n;
    reg         start;
    reg  [31:0] src_addr;
    reg  [31:0] xfer_len;
    wire        done;
    wire        buf_we;
    wire [14:0] buf_addr;
    wire [31:0] buf_wdata;

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

    initial clk = 0;
    always #5 clk = ~clk;

    dma_weight_ch dut (
        .clk(clk), .rst_n(rst_n),
        .start(start), .src_addr(src_addr), .xfer_len(xfer_len), .done(done),
        .buf_we(buf_we), .buf_addr(buf_addr), .buf_wdata(buf_wdata),
        .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize),
        .m_axi_arburst(arburst), .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rdata(rdata), .m_axi_rresp(rresp), .m_axi_rlast(rlast),
        .m_axi_rvalid(rvalid), .m_axi_rready(rready)
    );

    integer beat_count;
    integer errors;

    initial begin
        errors = 0;
        rst_n = 0; start = 0;
        src_addr = 0; xfer_len = 0;
        arready = 0;
        rdata = 0; rresp = 0; rlast = 0; rvalid = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Start a small DMA transfer: 64 bytes = 4 AXI beats of 16 bytes
        src_addr = 32'h8000_0000;
        xfer_len = 32'd64;
        start = 1;
        @(posedge clk);
        start = 0;

        // Wait for arvalid, then accept immediately
        begin : ar_wait_blk
            integer countdown;
            countdown = 1000;
            forever begin
                @(posedge clk);
                #1;
                if (arvalid) begin
                    arready = 1;
                    @(posedge clk); // handshake completes on this edge
                    #1;
                    arready = 0;
                    $display("AR issued: addr=%h, len=%0d", araddr, arlen);
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

        // Serve 4 read data beats reactively.
        // The DUT holds rready=1 when waiting for a beat in S_R_DATA (sub_word_r==0).
        // We present rvalid+rdata, the handshake occurs on the next posedge,
        // then we must hold rvalid through that edge.
        for (beat_count = 0; beat_count < 4; beat_count = beat_count + 1) begin : beat_loop
            integer countdown;
            countdown = 2000;
            // Wait until DUT is ready (rready=1)
            forever begin
                @(posedge clk);
                #1;
                if (rready) begin
                    // Present data — DUT will sample on next posedge
                    rvalid = 1;
                    rdata = {32'h0000_0003, 32'h0000_0002, 32'h0000_0001, 32'h0000_0000}
                            + {4{beat_count[31:0] * 32'd4}};
                    rlast = (beat_count == 3);
                    // $display("  Beat %0d: presenting data, rlast=%0b", beat_count, rlast);
                    // Hold through the sampling edge
                    @(posedge clk);
                    #1;
                    // DUT has sampled rvalid+rdata on this edge (rready was high)
                    // Deassert rvalid
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

        // Wait for done with timeout
        begin : done_wait_blk
            integer countdown;
            countdown = 1000;
            while (countdown > 0) begin
                @(posedge clk);
                #1;
                if (done) begin
                    $display("DMA transfer completed successfully");
                    countdown = -1;
                end
                countdown = countdown - 1;
            end
            if (countdown == 0) begin
                $display("FAIL: Timeout waiting for done");
                errors = errors + 1;
            end
        end

        repeat (3) @(posedge clk);
        $display("========================================");
        if (errors == 0) begin
            $display("tb_dma_weight_ch: basic test PASSED");
            $display("ALL TESTS PASSED");
        end else
            $display("tb_dma_weight_ch: FAILED (%0d errors)", errors);
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
