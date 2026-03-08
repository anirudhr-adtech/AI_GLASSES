`timescale 1ns/1ps
//============================================================================
// Testbench: tb_axi_to_axilite_bridge
// Project:   AI_GLASSES — AXI Interconnect
// Description: Self-checking testbench for axi_to_axilite_bridge
//============================================================================

module tb_axi_to_axilite_bridge;

    parameter DW = 32;
    parameter AW = 32;
    parameter IW = 6;

    reg  clk, rst_n;
    // AXI4 slave
    reg  [IW-1:0] s_awid, s_arid;
    reg  [AW-1:0] s_awaddr, s_araddr;
    reg  [7:0]    s_awlen, s_arlen;
    reg  [2:0]    s_awsize, s_arsize;
    reg  [1:0]    s_awburst, s_arburst;
    reg           s_awvalid, s_arvalid;
    wire          s_awready, s_arready;
    reg  [DW-1:0] s_wdata;
    reg  [3:0]    s_wstrb;
    reg           s_wlast, s_wvalid;
    wire          s_wready;
    wire [IW-1:0] s_bid, s_rid;
    wire [1:0]    s_bresp, s_rresp;
    wire          s_bvalid, s_rvalid, s_rlast;
    wire [DW-1:0] s_rdata;
    reg           s_bready, s_rready;

    // AXI-Lite master
    wire [AW-1:0] m_awaddr, m_araddr;
    wire [2:0]    m_awprot, m_arprot;
    wire          m_awvalid, m_arvalid;
    reg           m_awready, m_arready;
    wire [DW-1:0] m_wdata;
    wire [3:0]    m_wstrb;
    wire          m_wvalid;
    reg           m_wready;
    reg  [1:0]    m_bresp, m_rresp;
    reg           m_bvalid, m_rvalid;
    wire          m_bready, m_rready;
    reg  [DW-1:0] m_rdata;

    integer pass_count, fail_count;

    axi_to_axilite_bridge #(
        .DATA_WIDTH(DW), .ADDR_WIDTH(AW), .ID_WIDTH(IW)
    ) dut (
        .clk(clk), .rst_n(rst_n),
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
        .m_axil_awaddr(m_awaddr), .m_axil_awprot(m_awprot),
        .m_axil_awvalid(m_awvalid), .m_axil_awready(m_awready),
        .m_axil_wdata(m_wdata), .m_axil_wstrb(m_wstrb),
        .m_axil_wvalid(m_wvalid), .m_axil_wready(m_wready),
        .m_axil_bresp(m_bresp), .m_axil_bvalid(m_bvalid), .m_axil_bready(m_bready),
        .m_axil_araddr(m_araddr), .m_axil_arprot(m_arprot),
        .m_axil_arvalid(m_arvalid), .m_axil_arready(m_arready),
        .m_axil_rdata(m_rdata), .m_axil_rresp(m_rresp),
        .m_axil_rvalid(m_rvalid), .m_axil_rready(m_rready)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // AXI-Lite responder
    always @(posedge clk) begin
        if (!rst_n) begin
            m_awready <= 1; m_wready <= 1; m_arready <= 1;
            m_bvalid <= 0; m_rvalid <= 0;
            m_bresp <= 0; m_rresp <= 0; m_rdata <= 0;
        end else begin
            if (m_awvalid && m_awready && m_wvalid && m_wready) begin
                m_bresp  <= 2'b00;
                m_bvalid <= 1'b1;
            end
            if (m_bvalid && m_bready)
                m_bvalid <= 1'b0;

            if (m_arvalid && m_arready) begin
                m_rdata  <= 32'hBEEF_DEAD;
                m_rresp  <= 2'b00;
                m_rvalid <= 1'b1;
            end
            if (m_rvalid && m_rready)
                m_rvalid <= 1'b0;
        end
    end

    initial begin
        $display("=== tb_axi_to_axilite_bridge START ===");
        pass_count = 0; fail_count = 0;
        rst_n = 0;
        s_awid = 0; s_awaddr = 0; s_awlen = 0; s_awsize = 0; s_awburst = 0; s_awvalid = 0;
        s_wdata = 0; s_wstrb = 0; s_wlast = 0; s_wvalid = 0; s_bready = 1;
        s_arid = 0; s_araddr = 0; s_arlen = 0; s_arsize = 0; s_arburst = 0; s_arvalid = 0;
        s_rready = 1;
        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // Test 1: Single-beat write pass-through
        s_awid = 6'd5; s_awaddr = 32'h2000_0000; s_awlen = 0;
        s_awsize = 3'd2; s_awburst = 2'b01; s_awvalid = 1;
        wait (s_awready && s_awvalid);
        @(posedge clk); s_awvalid = 0;

        s_wdata = 32'h1234_5678; s_wstrb = 4'hF; s_wlast = 1; s_wvalid = 1;
        wait (s_wready && s_wvalid);
        @(posedge clk); s_wvalid = 0;

        wait (s_bvalid);
        @(posedge clk);
        if (s_bresp === 2'b00 && s_bid === 6'd5) begin
            pass_count = pass_count + 1;
            $display("PASS: Single-beat write pass-through OK");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Write bresp=%b bid=%0d", s_bresp, s_bid);
        end

        repeat (5) @(posedge clk);

        // Test 2: Single-beat read pass-through
        s_arid = 6'd10; s_araddr = 32'h2000_0100; s_arlen = 0;
        s_arsize = 3'd2; s_arburst = 2'b01; s_arvalid = 1;
        wait (s_arready && s_arvalid);
        @(posedge clk); s_arvalid = 0;

        wait (s_rvalid);
        @(posedge clk);
        if (s_rdata === 32'hBEEF_DEAD && s_rlast === 1'b1 && s_rid === 6'd10) begin
            pass_count = pass_count + 1;
            $display("PASS: Single-beat read pass-through OK");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Read data=0x%08h rlast=%b rid=%0d", s_rdata, s_rlast, s_rid);
        end

        repeat (5) @(posedge clk);

        // Test 3: Burst write -> SLVERR rejection
        s_awid = 6'd20; s_awaddr = 32'h2000_0000; s_awlen = 8'd3; // burst of 4
        s_awsize = 3'd2; s_awburst = 2'b01; s_awvalid = 1;
        wait (s_awready && s_awvalid);
        @(posedge clk); s_awvalid = 0;

        // Send 4 W beats
        s_wdata = 32'h0; s_wstrb = 4'hF;
        begin : wr_burst
            integer i;
            for (i = 0; i < 4; i = i + 1) begin
                s_wdata = i;
                s_wlast = (i == 3) ? 1'b1 : 1'b0;
                s_wvalid = 1;
                wait (s_wready && s_wvalid);
                @(posedge clk);
            end
        end
        s_wvalid = 0;

        wait (s_bvalid);
        @(posedge clk);
        if (s_bresp === 2'b10 && s_bid === 6'd20) begin
            pass_count = pass_count + 1;
            $display("PASS: Burst write rejected with SLVERR");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Burst write bresp=%b bid=%0d", s_bresp, s_bid);
        end

        repeat (5) @(posedge clk);
        $display("=== tb_axi_to_axilite_bridge DONE ===");
        $display("PASSED: %0d  FAILED: %0d", pass_count, fail_count);
        if (fail_count == 0) $display("*** ALL TESTS PASSED ***");
        else $display("*** SOME TESTS FAILED ***");
        $finish;
    end

endmodule
