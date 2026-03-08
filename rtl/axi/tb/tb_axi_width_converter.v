`timescale 1ns/1ps
//============================================================================
// Testbench: tb_axi_width_converter
// Project:   AI_GLASSES — AXI Interconnect
// Description: Self-checking testbench for axi_width_converter
//============================================================================

module tb_axi_width_converter;

    parameter AW = 32;
    parameter IW = 6;
    parameter NARROW = 32;
    parameter WIDE = 128;

    reg  clk, rst_n;
    reg  [1:0] src_width, dst_width;

    // Slave interface
    reg  [IW-1:0]     s_awid; reg [AW-1:0] s_awaddr;
    reg  [7:0] s_awlen; reg [2:0] s_awsize; reg [1:0] s_awburst;
    reg  s_awvalid; wire s_awready;
    reg  [WIDE-1:0] s_wdata; reg [WIDE/8-1:0] s_wstrb;
    reg  s_wlast, s_wvalid; wire s_wready;
    wire [IW-1:0] s_bid; wire [1:0] s_bresp; wire s_bvalid;
    reg  s_bready;
    reg  [IW-1:0] s_arid; reg [AW-1:0] s_araddr;
    reg  [7:0] s_arlen; reg [2:0] s_arsize; reg [1:0] s_arburst;
    reg  s_arvalid; wire s_arready;
    wire [IW-1:0] s_rid; wire [WIDE-1:0] s_rdata;
    wire [1:0] s_rresp; wire s_rlast, s_rvalid;
    reg  s_rready;

    // Master interface
    wire [IW-1:0] m_awid; wire [AW-1:0] m_awaddr;
    wire [7:0] m_awlen; wire [2:0] m_awsize; wire [1:0] m_awburst;
    wire m_awvalid; reg m_awready;
    wire [WIDE-1:0] m_wdata; wire [WIDE/8-1:0] m_wstrb;
    wire m_wlast, m_wvalid; reg m_wready;
    reg  [IW-1:0] m_bid; reg [1:0] m_bresp; reg m_bvalid;
    wire m_bready;
    wire [IW-1:0] m_arid; wire [AW-1:0] m_araddr;
    wire [7:0] m_arlen; wire [2:0] m_arsize; wire [1:0] m_arburst;
    wire m_arvalid; reg m_arready;
    reg  [IW-1:0] m_rid; reg [WIDE-1:0] m_rdata;
    reg  [1:0] m_rresp; reg m_rlast, m_rvalid;
    wire m_rready;

    integer pass_count, fail_count;

    axi_width_converter #(
        .NARROW_WIDTH(NARROW), .WIDE_WIDTH(WIDE),
        .ADDR_WIDTH(AW), .ID_WIDTH(IW)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .src_width_i(src_width), .dst_width_i(dst_width),
        .s_axi_awid(s_awid), .s_axi_awaddr(s_awaddr), .s_axi_awlen(s_awlen),
        .s_axi_awsize(s_awsize), .s_axi_awburst(s_awburst),
        .s_axi_awvalid(s_awvalid), .s_axi_awready(s_awready),
        .s_axi_wdata(s_wdata), .s_axi_wstrb(s_wstrb),
        .s_axi_wlast(s_wlast), .s_axi_wvalid(s_wvalid), .s_axi_wready(s_wready),
        .s_axi_bid(s_bid), .s_axi_bresp(s_bresp),
        .s_axi_bvalid(s_bvalid), .s_axi_bready(s_bready),
        .s_axi_arid(s_arid), .s_axi_araddr(s_araddr), .s_axi_arlen(s_arlen),
        .s_axi_arsize(s_arsize), .s_axi_arburst(s_arburst),
        .s_axi_arvalid(s_arvalid), .s_axi_arready(s_arready),
        .s_axi_rid(s_rid), .s_axi_rdata(s_rdata),
        .s_axi_rresp(s_rresp), .s_axi_rlast(s_rlast),
        .s_axi_rvalid(s_rvalid), .s_axi_rready(s_rready),
        .m_axi_awid(m_awid), .m_axi_awaddr(m_awaddr), .m_axi_awlen(m_awlen),
        .m_axi_awsize(m_awsize), .m_axi_awburst(m_awburst),
        .m_axi_awvalid(m_awvalid), .m_axi_awready(m_awready),
        .m_axi_wdata(m_wdata), .m_axi_wstrb(m_wstrb),
        .m_axi_wlast(m_wlast), .m_axi_wvalid(m_wvalid), .m_axi_wready(m_wready),
        .m_axi_bid(m_bid), .m_axi_bresp(m_bresp),
        .m_axi_bvalid(m_bvalid), .m_axi_bready(m_bready),
        .m_axi_arid(m_arid), .m_axi_araddr(m_araddr), .m_axi_arlen(m_arlen),
        .m_axi_arsize(m_arsize), .m_axi_arburst(m_arburst),
        .m_axi_arvalid(m_arvalid), .m_axi_arready(m_arready),
        .m_axi_rid(m_rid), .m_axi_rdata(m_rdata),
        .m_axi_rresp(m_rresp), .m_axi_rlast(m_rlast),
        .m_axi_rvalid(m_rvalid), .m_axi_rready(m_rready)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $display("=== tb_axi_width_converter START ===");
        pass_count = 0; fail_count = 0;
        rst_n = 0;
        src_width = 0; dst_width = 0;
        s_awid = 0; s_awaddr = 0; s_awlen = 0; s_awsize = 0; s_awburst = 0; s_awvalid = 0;
        s_wdata = 0; s_wstrb = 0; s_wlast = 0; s_wvalid = 0; s_bready = 1;
        s_arid = 0; s_araddr = 0; s_arlen = 0; s_arsize = 0; s_arburst = 0; s_arvalid = 0;
        s_rready = 1;
        m_awready = 1; m_wready = 1; m_arready = 1;
        m_bid = 0; m_bresp = 0; m_bvalid = 0;
        m_rid = 0; m_rdata = 0; m_rresp = 0; m_rlast = 0; m_rvalid = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Test passthrough mode (same width)
        src_width = 2'b10; dst_width = 2'b10; // 128==128
        s_awid = 6'd1; s_awaddr = 32'h8000_0000;
        s_awlen = 0; s_awsize = 3'd4; s_awburst = 2'b01;
        s_awvalid = 1;
        @(posedge clk);
        if (m_awvalid === 1'b1 && m_awaddr === 32'h8000_0000) begin
            pass_count = pass_count + 1;
            $display("PASS: Passthrough AW forwarded");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Passthrough AW valid=%b addr=0x%08h", m_awvalid, m_awaddr);
        end
        s_awvalid = 0;

        repeat (5) @(posedge clk);

        $display("=== tb_axi_width_converter DONE ===");
        $display("PASSED: %0d  FAILED: %0d", pass_count, fail_count);
        if (fail_count == 0) $display("*** ALL TESTS PASSED ***");
        else $display("*** SOME TESTS FAILED ***");
        $finish;
    end

endmodule
