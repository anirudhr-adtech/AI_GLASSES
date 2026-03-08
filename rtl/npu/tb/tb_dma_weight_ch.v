`timescale 1ns/1ps
//============================================================================
// Testbench: tb_dma_weight_ch
// Basic stimulus for weight DMA channel — verifies FSM progression
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

    initial begin
        rst_n = 0; start = 0;
        src_addr = 0; xfer_len = 0;
        arready = 0; rdata = 0; rresp = 0; rlast = 0; rvalid = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Start a small DMA transfer: 64 bytes = 4 AXI beats of 16 bytes
        src_addr = 32'h8000_0000;
        xfer_len = 32'd64;
        start = 1;
        @(posedge clk);
        start = 0;

        // Wait for AR
        repeat (5) @(posedge clk);
        if (arvalid) begin
            $display("AR issued: addr=%h, len=%0d", araddr, arlen);
            arready = 1;
            @(posedge clk);
            arready = 0;
        end

        // Provide 4 read data beats
        @(posedge clk);
        for (beat_count = 0; beat_count < 4; beat_count = beat_count + 1) begin
            rvalid = 1;
            rdata = {32'h0000_0003, 32'h0000_0002, 32'h0000_0001, 32'h0000_0000} + {4{beat_count[31:0] * 32'd4}};
            rlast = (beat_count == 3);
            @(posedge clk);
            while (!rready) @(posedge clk);
        end
        rvalid = 0; rlast = 0;

        // Wait for done
        repeat (20) @(posedge clk);
        if (done) $display("DMA transfer completed successfully");
        else $display("WARNING: DMA did not assert done");

        repeat (3) @(posedge clk);
        $display("========================================");
        $display("tb_dma_weight_ch: basic test complete");
        $display("========================================");
        $finish;
    end

endmodule
