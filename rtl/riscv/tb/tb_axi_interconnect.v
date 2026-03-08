`timescale 1ns/1ps
//============================================================================
// Testbench : tb_axi_interconnect
// Project   : AI_GLASSES — RISC-V Subsystem
// Description : Self-checking testbench for axi_interconnect
//============================================================================

module tb_axi_interconnect;

    reg clk, rst_n;
    integer pass_cnt, fail_cnt;

    // M0 (iBus, read-only) signals
    reg  [31:0] m0_araddr;  reg        m0_arvalid;  wire       m0_arready;
    reg  [3:0]  m0_arid;    reg [7:0]  m0_arlen;    reg [2:0]  m0_arsize;
    reg  [1:0]  m0_arburst;
    wire [31:0] m0_rdata;   wire       m0_rvalid;   reg        m0_rready;
    wire [1:0]  m0_rresp;   wire [3:0] m0_rid;      wire       m0_rlast;

    // M1 (dBus) signals
    reg  [31:0] m1_awaddr;  reg        m1_awvalid;  wire       m1_awready;
    reg  [3:0]  m1_awid;    reg [7:0]  m1_awlen;    reg [2:0]  m1_awsize;
    reg  [1:0]  m1_awburst;
    reg  [31:0] m1_wdata;   reg [3:0]  m1_wstrb;    reg        m1_wvalid;
    reg         m1_wlast;   wire       m1_wready;
    wire [3:0]  m1_bid;     wire [1:0] m1_bresp;    wire       m1_bvalid;
    reg         m1_bready;
    reg  [31:0] m1_araddr;  reg        m1_arvalid;  wire       m1_arready;
    reg  [3:0]  m1_arid;    reg [7:0]  m1_arlen;    reg [2:0]  m1_arsize;
    reg  [1:0]  m1_arburst;
    wire [31:0] m1_rdata;   wire       m1_rvalid;   reg        m1_rready;
    wire [1:0]  m1_rresp;   wire [3:0] m1_rid;      wire       m1_rlast;

    // M2 — tie off for now
    wire       m2_awready, m2_wready, m2_bvalid, m2_arready, m2_rvalid, m2_rlast;
    wire [3:0] m2_bid, m2_rid;
    wire [1:0] m2_bresp, m2_rresp;
    wire [31:0] m2_rdata;

    // S0 — behavioral slave (Boot ROM region)
    wire [31:0] s0_araddr;  wire       s0_arvalid;
    wire [3:0]  s0_arid;    wire [7:0] s0_arlen;
    wire [2:0]  s0_arsize;  wire [1:0] s0_arburst;
    reg         s0_arready_r;
    reg  [31:0] s0_rdata_r;   reg       s0_rvalid_r;
    reg  [1:0]  s0_rresp_r;   reg [3:0] s0_rid_r;
    reg         s0_rlast_r;
    wire [31:0] s0_awaddr;  wire       s0_awvalid;
    reg         s0_awready_r;
    wire [3:0]  s0_awid;    wire [7:0] s0_awlen;
    wire [2:0]  s0_awsize;  wire [1:0] s0_awburst;
    wire [31:0] s0_wdata;   wire [3:0] s0_wstrb;
    wire        s0_wvalid, s0_wlast;
    reg         s0_wready_r;
    reg  [3:0]  s0_bid_r;   reg [1:0]  s0_bresp_r;
    reg         s0_bvalid_r;
    wire        s0_bready, s0_rready;

    // S1-S3: stub slaves (just accept and respond)
    // For simplicity, wire tie-offs with always-ready
    reg s1_arready, s1_awready, s1_wready;
    reg [31:0] s1_rdata; reg s1_rvalid; reg [1:0] s1_rresp; reg [3:0] s1_rid; reg s1_rlast;
    reg [3:0] s1_bid; reg [1:0] s1_bresp; reg s1_bvalid;
    wire s1_bready, s1_rready;
    wire [31:0] s1_araddr, s1_awaddr, s1_wdata_w;
    wire s1_arvalid, s1_awvalid, s1_wvalid, s1_wlast_w;
    wire [3:0] s1_wstrb_w, s1_arid_w, s1_awid_w;
    wire [7:0] s1_arlen_w, s1_awlen_w;
    wire [2:0] s1_arsize_w, s1_awsize_w;
    wire [1:0] s1_arburst_w, s1_awburst_w;

    // S2, S3 stubs
    reg s2_arready, s2_awready, s2_wready;
    reg [31:0] s2_rdata; reg s2_rvalid; reg [1:0] s2_rresp; reg [3:0] s2_rid; reg s2_rlast;
    reg [3:0] s2_bid; reg [1:0] s2_bresp; reg s2_bvalid;
    wire s2_bready, s2_rready;

    reg s3_arready, s3_awready, s3_wready;
    reg [31:0] s3_rdata; reg s3_rvalid; reg [1:0] s3_rresp; reg [3:0] s3_rid; reg s3_rlast;
    reg [3:0] s3_bid; reg [1:0] s3_bresp; reg s3_bvalid;
    wire s3_bready, s3_rready;

    axi_interconnect uut (
        .clk(clk), .rst_n(rst_n),
        // M0
        .s_axi_0_araddr(m0_araddr), .s_axi_0_arvalid(m0_arvalid), .s_axi_0_arready(m0_arready),
        .s_axi_0_arid(m0_arid), .s_axi_0_arlen(m0_arlen), .s_axi_0_arsize(m0_arsize),
        .s_axi_0_arburst(m0_arburst),
        .s_axi_0_rdata(m0_rdata), .s_axi_0_rvalid(m0_rvalid), .s_axi_0_rready(m0_rready),
        .s_axi_0_rresp(m0_rresp), .s_axi_0_rid(m0_rid), .s_axi_0_rlast(m0_rlast),
        // M1
        .s_axi_1_awaddr(m1_awaddr), .s_axi_1_awvalid(m1_awvalid), .s_axi_1_awready(m1_awready),
        .s_axi_1_awid(m1_awid), .s_axi_1_awlen(m1_awlen), .s_axi_1_awsize(m1_awsize),
        .s_axi_1_awburst(m1_awburst),
        .s_axi_1_wdata(m1_wdata), .s_axi_1_wstrb(m1_wstrb), .s_axi_1_wvalid(m1_wvalid),
        .s_axi_1_wlast(m1_wlast), .s_axi_1_wready(m1_wready),
        .s_axi_1_bid(m1_bid), .s_axi_1_bresp(m1_bresp), .s_axi_1_bvalid(m1_bvalid),
        .s_axi_1_bready(m1_bready),
        .s_axi_1_araddr(m1_araddr), .s_axi_1_arvalid(m1_arvalid), .s_axi_1_arready(m1_arready),
        .s_axi_1_arid(m1_arid), .s_axi_1_arlen(m1_arlen), .s_axi_1_arsize(m1_arsize),
        .s_axi_1_arburst(m1_arburst),
        .s_axi_1_rdata(m1_rdata), .s_axi_1_rvalid(m1_rvalid), .s_axi_1_rready(m1_rready),
        .s_axi_1_rresp(m1_rresp), .s_axi_1_rid(m1_rid), .s_axi_1_rlast(m1_rlast),
        // M2 (tied off)
        .s_axi_2_awaddr(32'd0), .s_axi_2_awvalid(1'b0), .s_axi_2_awready(m2_awready),
        .s_axi_2_awid(4'd0), .s_axi_2_awlen(8'd0), .s_axi_2_awsize(3'd0), .s_axi_2_awburst(2'd0),
        .s_axi_2_wdata(32'd0), .s_axi_2_wstrb(4'd0), .s_axi_2_wvalid(1'b0),
        .s_axi_2_wlast(1'b0), .s_axi_2_wready(m2_wready),
        .s_axi_2_bid(m2_bid), .s_axi_2_bresp(m2_bresp), .s_axi_2_bvalid(m2_bvalid),
        .s_axi_2_bready(1'b0),
        .s_axi_2_araddr(32'd0), .s_axi_2_arvalid(1'b0), .s_axi_2_arready(m2_arready),
        .s_axi_2_arid(4'd0), .s_axi_2_arlen(8'd0), .s_axi_2_arsize(3'd0), .s_axi_2_arburst(2'd0),
        .s_axi_2_rdata(m2_rdata), .s_axi_2_rvalid(m2_rvalid), .s_axi_2_rready(1'b0),
        .s_axi_2_rresp(m2_rresp), .s_axi_2_rid(m2_rid), .s_axi_2_rlast(m2_rlast),
        // S0
        .m_axi_0_araddr(s0_araddr), .m_axi_0_arvalid(s0_arvalid), .m_axi_0_arready(s0_arready_r),
        .m_axi_0_arid(s0_arid), .m_axi_0_arlen(s0_arlen), .m_axi_0_arsize(s0_arsize),
        .m_axi_0_arburst(s0_arburst),
        .m_axi_0_rdata(s0_rdata_r), .m_axi_0_rvalid(s0_rvalid_r), .m_axi_0_rready(s0_rready),
        .m_axi_0_rresp(s0_rresp_r), .m_axi_0_rid(s0_rid_r), .m_axi_0_rlast(s0_rlast_r),
        .m_axi_0_awaddr(s0_awaddr), .m_axi_0_awvalid(s0_awvalid), .m_axi_0_awready(s0_awready_r),
        .m_axi_0_awid(s0_awid), .m_axi_0_awlen(s0_awlen), .m_axi_0_awsize(s0_awsize),
        .m_axi_0_awburst(s0_awburst),
        .m_axi_0_wdata(s0_wdata), .m_axi_0_wstrb(s0_wstrb), .m_axi_0_wvalid(s0_wvalid),
        .m_axi_0_wlast(s0_wlast), .m_axi_0_wready(s0_wready_r),
        .m_axi_0_bid(s0_bid_r), .m_axi_0_bresp(s0_bresp_r), .m_axi_0_bvalid(s0_bvalid_r),
        .m_axi_0_bready(s0_bready),
        // S1
        .m_axi_1_araddr(s1_araddr), .m_axi_1_arvalid(s1_arvalid), .m_axi_1_arready(s1_arready),
        .m_axi_1_arid(s1_arid_w), .m_axi_1_arlen(s1_arlen_w), .m_axi_1_arsize(s1_arsize_w),
        .m_axi_1_arburst(s1_arburst_w),
        .m_axi_1_rdata(s1_rdata), .m_axi_1_rvalid(s1_rvalid), .m_axi_1_rready(s1_rready),
        .m_axi_1_rresp(s1_rresp), .m_axi_1_rid(s1_rid), .m_axi_1_rlast(s1_rlast),
        .m_axi_1_awaddr(s1_awaddr), .m_axi_1_awvalid(s1_awvalid), .m_axi_1_awready(s1_awready),
        .m_axi_1_awid(s1_awid_w), .m_axi_1_awlen(s1_awlen_w), .m_axi_1_awsize(s1_awsize_w),
        .m_axi_1_awburst(s1_awburst_w),
        .m_axi_1_wdata(s1_wdata_w), .m_axi_1_wstrb(s1_wstrb_w), .m_axi_1_wvalid(s1_wvalid),
        .m_axi_1_wlast(s1_wlast_w), .m_axi_1_wready(s1_wready),
        .m_axi_1_bid(s1_bid), .m_axi_1_bresp(s1_bresp), .m_axi_1_bvalid(s1_bvalid),
        .m_axi_1_bready(s1_bready),
        // S2
        .m_axi_2_araddr(), .m_axi_2_arvalid(), .m_axi_2_arready(s2_arready),
        .m_axi_2_arid(), .m_axi_2_arlen(), .m_axi_2_arsize(), .m_axi_2_arburst(),
        .m_axi_2_rdata(s2_rdata), .m_axi_2_rvalid(s2_rvalid), .m_axi_2_rready(s2_rready),
        .m_axi_2_rresp(s2_rresp), .m_axi_2_rid(s2_rid), .m_axi_2_rlast(s2_rlast),
        .m_axi_2_awaddr(), .m_axi_2_awvalid(), .m_axi_2_awready(s2_awready),
        .m_axi_2_awid(), .m_axi_2_awlen(), .m_axi_2_awsize(), .m_axi_2_awburst(),
        .m_axi_2_wdata(), .m_axi_2_wstrb(), .m_axi_2_wvalid(), .m_axi_2_wlast(),
        .m_axi_2_wready(s2_wready),
        .m_axi_2_bid(s2_bid), .m_axi_2_bresp(s2_bresp), .m_axi_2_bvalid(s2_bvalid),
        .m_axi_2_bready(s2_bready),
        // S3
        .m_axi_3_araddr(), .m_axi_3_arvalid(), .m_axi_3_arready(s3_arready),
        .m_axi_3_arid(), .m_axi_3_arlen(), .m_axi_3_arsize(), .m_axi_3_arburst(),
        .m_axi_3_rdata(s3_rdata), .m_axi_3_rvalid(s3_rvalid), .m_axi_3_rready(s3_rready),
        .m_axi_3_rresp(s3_rresp), .m_axi_3_rid(s3_rid), .m_axi_3_rlast(s3_rlast),
        .m_axi_3_awaddr(), .m_axi_3_awvalid(), .m_axi_3_awready(s3_awready),
        .m_axi_3_awid(), .m_axi_3_awlen(), .m_axi_3_awsize(), .m_axi_3_awburst(),
        .m_axi_3_wdata(), .m_axi_3_wstrb(), .m_axi_3_wvalid(), .m_axi_3_wlast(),
        .m_axi_3_wready(s3_wready),
        .m_axi_3_bid(s3_bid), .m_axi_3_bresp(s3_bresp), .m_axi_3_bvalid(s3_bvalid),
        .m_axi_3_bready(s3_bready)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Behavioral S0 slave: accepts AR, returns data after 1 cycle
    always @(posedge clk) begin
        if (!rst_n) begin
            s0_arready_r <= 1'b1;
            s0_rvalid_r  <= 1'b0;
            s0_rdata_r   <= 32'd0;
            s0_rresp_r   <= 2'b00;
            s0_rid_r     <= 4'd0;
            s0_rlast_r   <= 1'b0;
            s0_awready_r <= 1'b1;
            s0_wready_r  <= 1'b1;
            s0_bvalid_r  <= 1'b0;
            s0_bid_r     <= 4'd0;
            s0_bresp_r   <= 2'b00;
        end else begin
            if (s0_arvalid && s0_arready_r) begin
                s0_arready_r <= 1'b0;
                s0_rdata_r   <= {16'hBEEF, s0_araddr[15:0]};
                s0_rid_r     <= s0_arid;
                s0_rresp_r   <= 2'b00;
                s0_rlast_r   <= 1'b1;
                s0_rvalid_r  <= 1'b1;
            end
            if (s0_rvalid_r && s0_rready) begin
                s0_rvalid_r  <= 1'b0;
                s0_rlast_r   <= 1'b0;
                s0_arready_r <= 1'b1;
            end
        end
    end

    // Stub S1-S3: never active in this test, default tie-off
    initial begin
        s1_arready = 0; s1_awready = 0; s1_wready = 0;
        s1_rvalid = 0; s1_rdata = 0; s1_rresp = 0; s1_rid = 0; s1_rlast = 0;
        s1_bvalid = 0; s1_bid = 0; s1_bresp = 0;
        s2_arready = 0; s2_awready = 0; s2_wready = 0;
        s2_rvalid = 0; s2_rdata = 0; s2_rresp = 0; s2_rid = 0; s2_rlast = 0;
        s2_bvalid = 0; s2_bid = 0; s2_bresp = 0;
        s3_arready = 0; s3_awready = 0; s3_wready = 0;
        s3_rvalid = 0; s3_rdata = 0; s3_rresp = 0; s3_rid = 0; s3_rlast = 0;
        s3_bvalid = 0; s3_bid = 0; s3_bresp = 0;
    end

    initial begin
        pass_cnt = 0; fail_cnt = 0;
        rst_n = 0;
        m0_araddr = 0; m0_arvalid = 0; m0_arid = 0; m0_arlen = 0;
        m0_arsize = 3'b010; m0_arburst = 2'b01; m0_rready = 1;
        m1_awaddr = 0; m1_awvalid = 0; m1_awid = 0; m1_awlen = 0;
        m1_awsize = 3'b010; m1_awburst = 2'b01;
        m1_wdata = 0; m1_wstrb = 4'hF; m1_wvalid = 0; m1_wlast = 0;
        m1_bready = 1;
        m1_araddr = 0; m1_arvalid = 0; m1_arid = 0; m1_arlen = 0;
        m1_arsize = 3'b010; m1_arburst = 2'b01; m1_rready = 1;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // Test 1: M0 read from Boot ROM (addr 0x0000_0100)
        $display("Test 1: M0 read from S0 (Boot ROM)");
        m0_araddr  = 32'h0000_0100;
        m0_arid    = 4'h0;
        m0_arvalid = 1;

        // Wait for response
        repeat (20) begin : test1_loop
            @(posedge clk);
            if (m0_arready) m0_arvalid = 0;
            if (m0_rvalid) begin
                if (m0_rdata == {16'hBEEF, 16'h0100} && m0_rresp == 2'b00) begin
                    $display("PASS: M0 read data=0x%08h resp=%b", m0_rdata, m0_rresp);
                    pass_cnt = pass_cnt + 1;
                end else begin
                    $display("FAIL: M0 read data=0x%08h (expected 0xBEEF0100)", m0_rdata);
                    fail_cnt = fail_cnt + 1;
                end
                m0_arvalid = 0;
            end
            if (m0_rvalid && m0_rready) begin
                // done
                @(posedge clk);
                disable test1_loop;
            end
        end

        repeat (5) @(posedge clk);

        $display("");
        $display("========================================");
        $display("  Results: %0d passed, %0d failed", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("  ALL TESTS PASSED");
        else
            $display("  SOME TESTS FAILED");
        $display("========================================");
        $finish;
    end

    // Timeout
    initial begin
        #10000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
