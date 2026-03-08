`timescale 1ns/1ps
//============================================================================
// Testbench: tb_axi_timeout
// Project:   AI_GLASSES — AXI Interconnect
// Description: Self-checking testbench for axi_timeout
//============================================================================

module tb_axi_timeout;

    parameter TIMEOUT_CYCLES = 64; // Short for simulation
    parameter DATA_WIDTH     = 32;
    parameter ID_WIDTH       = 6;

    reg  clk, rst_n;

    // From master side
    reg  [ID_WIDTH-1:0]   s_awid, s_arid;
    reg  [31:0]           s_awaddr, s_araddr;
    reg  [7:0]            s_awlen, s_arlen;
    reg  [2:0]            s_awsize, s_arsize;
    reg  [1:0]            s_awburst, s_arburst;
    reg                   s_awvalid, s_arvalid;
    wire                  s_awready, s_arready;
    reg  [DATA_WIDTH-1:0] s_wdata;
    reg  [3:0]            s_wstrb;
    reg                   s_wlast, s_wvalid;
    wire                  s_wready;
    wire [ID_WIDTH-1:0]   s_bid, s_rid;
    wire [1:0]            s_bresp, s_rresp;
    wire                  s_bvalid, s_rvalid, s_rlast;
    wire [DATA_WIDTH-1:0] s_rdata;
    reg                   s_bready, s_rready;

    // To slave (hung slave - never responds)
    wire [ID_WIDTH-1:0]   m_awid, m_arid;
    wire [31:0]           m_awaddr, m_araddr;
    wire [7:0]            m_awlen, m_arlen;
    wire [2:0]            m_awsize, m_arsize;
    wire [1:0]            m_awburst, m_arburst;
    wire                  m_awvalid, m_arvalid;
    wire [DATA_WIDTH-1:0] m_wdata;
    wire [3:0]            m_wstrb;
    wire                  m_wlast, m_wvalid;
    wire                  m_bready, m_rready;

    // Hung slave: accepts AW/AR/W but never responds with B/R
    reg                   m_awready_r, m_arready_r, m_wready_r;
    wire                  m_awready = m_awready_r;
    wire                  m_arready = m_arready_r;
    wire                  m_wready  = m_wready_r;
    wire [ID_WIDTH-1:0]   m_bid_w = {ID_WIDTH{1'b0}};
    wire [1:0]            m_bresp_w = 2'b00;
    wire                  m_bvalid_w = 1'b0; // Never responds
    wire [ID_WIDTH-1:0]   m_rid_w = {ID_WIDTH{1'b0}};
    wire [DATA_WIDTH-1:0] m_rdata_w = {DATA_WIDTH{1'b0}};
    wire [1:0]            m_rresp_w = 2'b00;
    wire                  m_rlast_w = 1'b0;
    wire                  m_rvalid_w = 1'b0; // Never responds

    wire timeout_event, timeout_sticky;

    integer pass_count, fail_count;

    axi_timeout #(
        .TIMEOUT_CYCLES(TIMEOUT_CYCLES),
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH)
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
        .m_axi_awid(m_awid), .m_axi_awaddr(m_awaddr), .m_axi_awlen(m_awlen),
        .m_axi_awsize(m_awsize), .m_axi_awburst(m_awburst),
        .m_axi_awvalid(m_awvalid), .m_axi_awready(m_awready),
        .m_axi_wdata(m_wdata), .m_axi_wstrb(m_wstrb),
        .m_axi_wlast(m_wlast), .m_axi_wvalid(m_wvalid), .m_axi_wready(m_wready),
        .m_axi_bid(m_bid_w), .m_axi_bresp(m_bresp_w),
        .m_axi_bvalid(m_bvalid_w), .m_axi_bready(m_bready),
        .m_axi_arid(m_arid), .m_axi_araddr(m_araddr), .m_axi_arlen(m_arlen),
        .m_axi_arsize(m_arsize), .m_axi_arburst(m_arburst),
        .m_axi_arvalid(m_arvalid), .m_axi_arready(m_arready),
        .m_axi_rid(m_rid_w), .m_axi_rdata(m_rdata_w),
        .m_axi_rresp(m_rresp_w), .m_axi_rlast(m_rlast_w),
        .m_axi_rvalid(m_rvalid_w), .m_axi_rready(m_rready),
        .timeout_event_o(timeout_event), .timeout_sticky_o(timeout_sticky)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        m_awready_r = 1; m_arready_r = 1; m_wready_r = 1;
    end

    initial begin
        $display("=== tb_axi_timeout START ===");
        pass_count = 0; fail_count = 0;
        rst_n = 0;
        s_awid = 0; s_awaddr = 0; s_awlen = 0; s_awsize = 0; s_awburst = 0; s_awvalid = 0;
        s_wdata = 0; s_wstrb = 0; s_wlast = 0; s_wvalid = 0;
        s_arid = 0; s_araddr = 0; s_arlen = 0; s_arsize = 0; s_arburst = 0; s_arvalid = 0;
        s_bready = 0; s_rready = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // Issue a write that will never get B response
        s_awid = 6'd1; s_awaddr = 32'h8000_0000; s_awlen = 0;
        s_awsize = 3'd2; s_awburst = 2'b01; s_awvalid = 1;
        wait (s_awready && s_awvalid);
        @(posedge clk); s_awvalid = 0;

        s_wdata = 32'hDEADBEEF; s_wstrb = 4'hF; s_wlast = 1; s_wvalid = 1;
        wait (s_wready && s_wvalid);
        @(posedge clk); s_wvalid = 0;

        // Wait for timeout
        repeat (TIMEOUT_CYCLES + 20) @(posedge clk);

        // Check for forced SLVERR — bready is 0, so response should be held
        if (s_bvalid && s_bresp === 2'b10) begin
            pass_count = pass_count + 1;
            $display("PASS: Timeout SLVERR on write");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: bvalid=%b bresp=%b (exp SLVERR)", s_bvalid, s_bresp);
        end
        // Consume the B response
        s_bready = 1;
        @(posedge clk);
        s_bready = 0;

        // Check sticky bit
        if (timeout_sticky === 1'b1) begin
            pass_count = pass_count + 1;
            $display("PASS: Timeout sticky bit set");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: timeout_sticky=%b", timeout_sticky);
        end

        repeat (10) @(posedge clk);
        $display("=== tb_axi_timeout DONE ===");
        $display("PASSED: %0d  FAILED: %0d", pass_count, fail_count);
        if (fail_count == 0) $display("*** ALL TESTS PASSED ***");
        else $display("*** SOME TESTS FAILED ***");
        $finish;
    end

endmodule
