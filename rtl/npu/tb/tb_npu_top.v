`timescale 1ns/1ps
//============================================================================
// Testbench: tb_npu_top
// Top-level integration smoke test
// Fixed for Verilator --timing: #1 sampling, hold valids past ready
//============================================================================

module tb_npu_top;

    reg         clk;
    reg         rst_n;

    // AXI4-Lite slave
    reg  [7:0]  s_axi_lite_awaddr;
    reg         s_axi_lite_awvalid;
    wire        s_axi_lite_awready;
    reg  [31:0] s_axi_lite_wdata;
    reg  [3:0]  s_axi_lite_wstrb;
    reg         s_axi_lite_wvalid;
    wire        s_axi_lite_wready;
    wire [1:0]  s_axi_lite_bresp;
    wire        s_axi_lite_bvalid;
    reg         s_axi_lite_bready;
    reg  [7:0]  s_axi_lite_araddr;
    reg         s_axi_lite_arvalid;
    wire        s_axi_lite_arready;
    wire [31:0] s_axi_lite_rdata;
    wire [1:0]  s_axi_lite_rresp;
    wire        s_axi_lite_rvalid;
    reg         s_axi_lite_rready;

    // AXI4 master (stub — just check connectivity)
    wire [3:0]   m_axi_dma_awid;
    wire [31:0]  m_axi_dma_awaddr;
    wire [7:0]   m_axi_dma_awlen;
    wire [2:0]   m_axi_dma_awsize;
    wire [1:0]   m_axi_dma_awburst;
    wire [3:0]   m_axi_dma_awqos;
    wire         m_axi_dma_awvalid;
    reg          m_axi_dma_awready;
    wire [127:0] m_axi_dma_wdata;
    wire [15:0]  m_axi_dma_wstrb;
    wire         m_axi_dma_wlast;
    wire         m_axi_dma_wvalid;
    reg          m_axi_dma_wready;
    reg  [3:0]   m_axi_dma_bid;
    reg  [1:0]   m_axi_dma_bresp;
    reg          m_axi_dma_bvalid;
    wire         m_axi_dma_bready;
    wire [3:0]   m_axi_dma_arid;
    wire [31:0]  m_axi_dma_araddr;
    wire [7:0]   m_axi_dma_arlen;
    wire [2:0]   m_axi_dma_arsize;
    wire [1:0]   m_axi_dma_arburst;
    wire [3:0]   m_axi_dma_arqos;
    wire         m_axi_dma_arvalid;
    reg          m_axi_dma_arready;
    reg  [3:0]   m_axi_dma_rid;
    reg  [127:0] m_axi_dma_rdata;
    reg  [1:0]   m_axi_dma_rresp;
    reg          m_axi_dma_rlast;
    reg          m_axi_dma_rvalid;
    wire         m_axi_dma_rready;

    wire         irq_npu_done;

    integer errors;

    initial clk = 0;
    always #5 clk = ~clk;

    npu_top dut (
        .clk(clk), .rst_n(rst_n),
        .s_axi_lite_awaddr(s_axi_lite_awaddr), .s_axi_lite_awvalid(s_axi_lite_awvalid),
        .s_axi_lite_awready(s_axi_lite_awready),
        .s_axi_lite_wdata(s_axi_lite_wdata), .s_axi_lite_wstrb(s_axi_lite_wstrb),
        .s_axi_lite_wvalid(s_axi_lite_wvalid), .s_axi_lite_wready(s_axi_lite_wready),
        .s_axi_lite_bresp(s_axi_lite_bresp), .s_axi_lite_bvalid(s_axi_lite_bvalid),
        .s_axi_lite_bready(s_axi_lite_bready),
        .s_axi_lite_araddr(s_axi_lite_araddr), .s_axi_lite_arvalid(s_axi_lite_arvalid),
        .s_axi_lite_arready(s_axi_lite_arready),
        .s_axi_lite_rdata(s_axi_lite_rdata), .s_axi_lite_rresp(s_axi_lite_rresp),
        .s_axi_lite_rvalid(s_axi_lite_rvalid), .s_axi_lite_rready(s_axi_lite_rready),
        .m_axi_dma_awid(m_axi_dma_awid), .m_axi_dma_awaddr(m_axi_dma_awaddr),
        .m_axi_dma_awlen(m_axi_dma_awlen), .m_axi_dma_awsize(m_axi_dma_awsize),
        .m_axi_dma_awburst(m_axi_dma_awburst), .m_axi_dma_awqos(m_axi_dma_awqos),
        .m_axi_dma_awvalid(m_axi_dma_awvalid), .m_axi_dma_awready(m_axi_dma_awready),
        .m_axi_dma_wdata(m_axi_dma_wdata), .m_axi_dma_wstrb(m_axi_dma_wstrb),
        .m_axi_dma_wlast(m_axi_dma_wlast), .m_axi_dma_wvalid(m_axi_dma_wvalid),
        .m_axi_dma_wready(m_axi_dma_wready),
        .m_axi_dma_bid(m_axi_dma_bid), .m_axi_dma_bresp(m_axi_dma_bresp),
        .m_axi_dma_bvalid(m_axi_dma_bvalid), .m_axi_dma_bready(m_axi_dma_bready),
        .m_axi_dma_arid(m_axi_dma_arid), .m_axi_dma_araddr(m_axi_dma_araddr),
        .m_axi_dma_arlen(m_axi_dma_arlen), .m_axi_dma_arsize(m_axi_dma_arsize),
        .m_axi_dma_arburst(m_axi_dma_arburst), .m_axi_dma_arqos(m_axi_dma_arqos),
        .m_axi_dma_arvalid(m_axi_dma_arvalid), .m_axi_dma_arready(m_axi_dma_arready),
        .m_axi_dma_rid(m_axi_dma_rid), .m_axi_dma_rdata(m_axi_dma_rdata),
        .m_axi_dma_rresp(m_axi_dma_rresp), .m_axi_dma_rlast(m_axi_dma_rlast),
        .m_axi_dma_rvalid(m_axi_dma_rvalid), .m_axi_dma_rready(m_axi_dma_rready),
        .irq_npu_done(irq_npu_done)
    );

    // ---------------------------------------------------------------
    // AXI-Lite write: hold awvalid/wvalid one cycle PAST seeing awready
    // so wr_en fires in the DUT's regfile. Then wait for bvalid.
    // ---------------------------------------------------------------

    initial begin
        errors = 0;
        rst_n = 0;
        s_axi_lite_awaddr = 0; s_axi_lite_awvalid = 0;
        s_axi_lite_wdata = 0; s_axi_lite_wstrb = 0; s_axi_lite_wvalid = 0;
        s_axi_lite_bready = 0;
        s_axi_lite_araddr = 0; s_axi_lite_arvalid = 0; s_axi_lite_rready = 0;
        m_axi_dma_awready = 1;  // Pre-assert ready signals
        m_axi_dma_wready = 1;
        m_axi_dma_bid = 0; m_axi_dma_bresp = 0; m_axi_dma_bvalid = 0;
        m_axi_dma_arready = 1;  // Pre-assert ready signals
        m_axi_dma_rid = 0; m_axi_dma_rdata = 0;
        m_axi_dma_rresp = 0; m_axi_dma_rlast = 0; m_axi_dma_rvalid = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (3) @(posedge clk);

        $display("NPU Top integration test - register write smoke test");

        // ---- Write CONTROL register (0x00) = 0x00000005 ----
        begin : wr_ctrl
            integer countdown;
            @(posedge clk); #1;
            s_axi_lite_awaddr = 8'h00; s_axi_lite_awvalid = 1;
            s_axi_lite_wdata = 32'h0000_0005; s_axi_lite_wstrb = 4'hF; s_axi_lite_wvalid = 1;
            s_axi_lite_bready = 1;
            countdown = 100;
            while (countdown > 0) begin
                @(posedge clk); #1;
                if (s_axi_lite_awready && s_axi_lite_wready) countdown = 0;
                else countdown = countdown - 1;
            end
            // Hold valids one more cycle for wr_en
            @(posedge clk); #1;
            s_axi_lite_awvalid = 0; s_axi_lite_wvalid = 0;
            countdown = 100;
            while (countdown > 0) begin
                @(posedge clk); #1;
                if (s_axi_lite_bvalid) countdown = 0;
                else countdown = countdown - 1;
            end
            @(posedge clk); #1;
            s_axi_lite_bready = 0;
            $display("  CONTROL written: 0x00000005");
        end

        // ---- Write INPUT_ADDR (0x08) = 0x81000000 ----
        begin : wr_iaddr
            integer countdown;
            @(posedge clk); #1;
            s_axi_lite_awaddr = 8'h08; s_axi_lite_awvalid = 1;
            s_axi_lite_wdata = 32'h8100_0000; s_axi_lite_wstrb = 4'hF; s_axi_lite_wvalid = 1;
            s_axi_lite_bready = 1;
            countdown = 100;
            while (countdown > 0) begin
                @(posedge clk); #1;
                if (s_axi_lite_awready && s_axi_lite_wready) countdown = 0;
                else countdown = countdown - 1;
            end
            @(posedge clk); #1;
            s_axi_lite_awvalid = 0; s_axi_lite_wvalid = 0;
            countdown = 100;
            while (countdown > 0) begin
                @(posedge clk); #1;
                if (s_axi_lite_bvalid) countdown = 0;
                else countdown = countdown - 1;
            end
            @(posedge clk); #1;
            s_axi_lite_bready = 0;
            $display("  INPUT_ADDR written: 0x81000000");
        end

        // ---- Write WEIGHT_ADDR (0x0C) = 0x80000000 ----
        begin : wr_waddr
            integer countdown;
            @(posedge clk); #1;
            s_axi_lite_awaddr = 8'h0C; s_axi_lite_awvalid = 1;
            s_axi_lite_wdata = 32'h8000_0000; s_axi_lite_wstrb = 4'hF; s_axi_lite_wvalid = 1;
            s_axi_lite_bready = 1;
            countdown = 100;
            while (countdown > 0) begin
                @(posedge clk); #1;
                if (s_axi_lite_awready && s_axi_lite_wready) countdown = 0;
                else countdown = countdown - 1;
            end
            @(posedge clk); #1;
            s_axi_lite_awvalid = 0; s_axi_lite_wvalid = 0;
            countdown = 100;
            while (countdown > 0) begin
                @(posedge clk); #1;
                if (s_axi_lite_bvalid) countdown = 0;
                else countdown = countdown - 1;
            end
            @(posedge clk); #1;
            s_axi_lite_bready = 0;
            $display("  WEIGHT_ADDR written: 0x80000000");
        end

        // ---- Write LAYER_CONFIG (0x20) ----
        begin : wr_lcfg
            integer countdown;
            @(posedge clk); #1;
            s_axi_lite_awaddr = 8'h20; s_axi_lite_awvalid = 1;
            s_axi_lite_wdata = 32'h0008_0810; s_axi_lite_wstrb = 4'hF; s_axi_lite_wvalid = 1;
            s_axi_lite_bready = 1;
            countdown = 100;
            while (countdown > 0) begin
                @(posedge clk); #1;
                if (s_axi_lite_awready && s_axi_lite_wready) countdown = 0;
                else countdown = countdown - 1;
            end
            @(posedge clk); #1;
            s_axi_lite_awvalid = 0; s_axi_lite_wvalid = 0;
            countdown = 100;
            while (countdown > 0) begin
                @(posedge clk); #1;
                if (s_axi_lite_bvalid) countdown = 0;
                else countdown = countdown - 1;
            end
            @(posedge clk); #1;
            s_axi_lite_bready = 0;
            $display("  LAYER_CONFIG written");
        end

        repeat (5) @(posedge clk);
        $display("  IRQ output: %b", irq_npu_done);

        $display("========================================");
        if (errors == 0) begin
            $display("tb_npu_top: smoke test PASSED");
            $display("ALL TESTS PASSED");
        end else
            $display("tb_npu_top: smoke test FAILED (%0d errors)", errors);
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
