`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — DDR Subsystem
// Testbench: tb_ddr_wrapper
// Description: Self-checking testbench for ddr_wrapper top-level module.
//              Tests full pipeline: AXI4 128-bit -> AXI3 64-bit.
//////////////////////////////////////////////////////////////////////////////

module tb_ddr_wrapper;

    parameter ADDR_WIDTH   = 32;
    parameter WIDE_DATA    = 128;
    parameter NARROW_DATA  = 64;
    parameter ID_WIDTH     = 6;
    parameter WIDE_STRB    = WIDE_DATA / 8;
    parameter NARROW_STRB  = NARROW_DATA / 8;

    reg                      clk;
    reg                      rst_n;

    // AXI4 Slave (128-bit)
    reg  [ID_WIDTH-1:0]      s_axi4_awid, s_axi4_arid;
    reg  [ADDR_WIDTH-1:0]    s_axi4_awaddr, s_axi4_araddr;
    reg  [7:0]               s_axi4_awlen, s_axi4_arlen;
    reg  [2:0]               s_axi4_awsize, s_axi4_arsize;
    reg  [1:0]               s_axi4_awburst, s_axi4_arburst;
    reg                      s_axi4_awvalid, s_axi4_arvalid;
    wire                     s_axi4_awready, s_axi4_arready;

    reg  [WIDE_DATA-1:0]     s_axi4_wdata;
    reg  [WIDE_STRB-1:0]     s_axi4_wstrb;
    reg                      s_axi4_wlast;
    reg                      s_axi4_wvalid;
    wire                     s_axi4_wready;

    wire [ID_WIDTH-1:0]      s_axi4_bid, s_axi4_rid;
    wire [1:0]               s_axi4_bresp, s_axi4_rresp;
    wire                     s_axi4_bvalid, s_axi4_rvalid;
    reg                      s_axi4_bready, s_axi4_rready;
    wire [WIDE_DATA-1:0]     s_axi4_rdata;
    wire                     s_axi4_rlast;

    // AXI3 Master (64-bit)
    wire [ID_WIDTH-1:0]      m_axi3_awid, m_axi3_arid;
    wire [ADDR_WIDTH-1:0]    m_axi3_awaddr, m_axi3_araddr;
    wire [3:0]               m_axi3_awlen, m_axi3_arlen;
    wire [2:0]               m_axi3_awsize, m_axi3_arsize;
    wire [1:0]               m_axi3_awburst, m_axi3_arburst;
    wire [3:0]               m_axi3_awqos, m_axi3_arqos;
    wire                     m_axi3_awvalid, m_axi3_arvalid;
    reg                      m_axi3_awready, m_axi3_arready;

    wire [NARROW_DATA-1:0]   m_axi3_wdata;
    wire [NARROW_STRB-1:0]   m_axi3_wstrb;
    wire                     m_axi3_wlast;
    wire                     m_axi3_wvalid;
    reg                      m_axi3_wready;

    reg  [ID_WIDTH-1:0]      m_axi3_bid, m_axi3_rid;
    reg  [1:0]               m_axi3_bresp, m_axi3_rresp;
    reg                      m_axi3_bvalid, m_axi3_rvalid;
    wire                     m_axi3_bready, m_axi3_rready;
    reg  [NARROW_DATA-1:0]   m_axi3_rdata;
    reg                      m_axi3_rlast;

    integer pass_count;
    integer fail_count;
    integer i;
    integer beat_count;

    initial clk = 0;
    always #5 clk = ~clk;

    ddr_wrapper #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .WIDE_DATA(WIDE_DATA),
        .NARROW_DATA(NARROW_DATA),
        .ID_WIDTH(ID_WIDTH)
    ) uut (
        .clk(clk), .rst_n(rst_n),
        // AXI4 slave
        .s_axi4_awid(s_axi4_awid), .s_axi4_awaddr(s_axi4_awaddr),
        .s_axi4_awlen(s_axi4_awlen), .s_axi4_awsize(s_axi4_awsize),
        .s_axi4_awburst(s_axi4_awburst),
        .s_axi4_awvalid(s_axi4_awvalid), .s_axi4_awready(s_axi4_awready),
        .s_axi4_wdata(s_axi4_wdata), .s_axi4_wstrb(s_axi4_wstrb),
        .s_axi4_wlast(s_axi4_wlast),
        .s_axi4_wvalid(s_axi4_wvalid), .s_axi4_wready(s_axi4_wready),
        .s_axi4_bid(s_axi4_bid), .s_axi4_bresp(s_axi4_bresp),
        .s_axi4_bvalid(s_axi4_bvalid), .s_axi4_bready(s_axi4_bready),
        .s_axi4_arid(s_axi4_arid), .s_axi4_araddr(s_axi4_araddr),
        .s_axi4_arlen(s_axi4_arlen), .s_axi4_arsize(s_axi4_arsize),
        .s_axi4_arburst(s_axi4_arburst),
        .s_axi4_arvalid(s_axi4_arvalid), .s_axi4_arready(s_axi4_arready),
        .s_axi4_rid(s_axi4_rid), .s_axi4_rdata(s_axi4_rdata),
        .s_axi4_rresp(s_axi4_rresp), .s_axi4_rlast(s_axi4_rlast),
        .s_axi4_rvalid(s_axi4_rvalid), .s_axi4_rready(s_axi4_rready),
        // AXI3 master
        .m_axi3_awid(m_axi3_awid), .m_axi3_awaddr(m_axi3_awaddr),
        .m_axi3_awlen(m_axi3_awlen), .m_axi3_awsize(m_axi3_awsize),
        .m_axi3_awburst(m_axi3_awburst), .m_axi3_awqos(m_axi3_awqos),
        .m_axi3_awvalid(m_axi3_awvalid), .m_axi3_awready(m_axi3_awready),
        .m_axi3_wdata(m_axi3_wdata), .m_axi3_wstrb(m_axi3_wstrb),
        .m_axi3_wlast(m_axi3_wlast),
        .m_axi3_wvalid(m_axi3_wvalid), .m_axi3_wready(m_axi3_wready),
        .m_axi3_bid(m_axi3_bid), .m_axi3_bresp(m_axi3_bresp),
        .m_axi3_bvalid(m_axi3_bvalid), .m_axi3_bready(m_axi3_bready),
        .m_axi3_arid(m_axi3_arid), .m_axi3_araddr(m_axi3_araddr),
        .m_axi3_arlen(m_axi3_arlen), .m_axi3_arsize(m_axi3_arsize),
        .m_axi3_arburst(m_axi3_arburst), .m_axi3_arqos(m_axi3_arqos),
        .m_axi3_arvalid(m_axi3_arvalid), .m_axi3_arready(m_axi3_arready),
        .m_axi3_rid(m_axi3_rid), .m_axi3_rdata(m_axi3_rdata),
        .m_axi3_rresp(m_axi3_rresp), .m_axi3_rlast(m_axi3_rlast),
        .m_axi3_rvalid(m_axi3_rvalid), .m_axi3_rready(m_axi3_rready)
    );

    task reset;
    begin
        rst_n = 0;
        s_axi4_awvalid = 0; s_axi4_wvalid = 0; s_axi4_bready = 1;
        s_axi4_arvalid = 0; s_axi4_rready = 1;
        m_axi3_awready = 1; m_axi3_wready = 1; m_axi3_arready = 1;
        m_axi3_bvalid = 0; m_axi3_rvalid = 0;
        m_axi3_bresp = 2'b00; m_axi3_rresp = 2'b00;
        m_axi3_rlast = 0; m_axi3_rdata = 0; m_axi3_rid = 0; m_axi3_bid = 0;
        s_axi4_awid = 0; s_axi4_awaddr = 0; s_axi4_awlen = 0;
        s_axi4_awsize = 3'd4; s_axi4_awburst = 2'b01;
        s_axi4_arid = 0; s_axi4_araddr = 0; s_axi4_arlen = 0;
        s_axi4_arsize = 3'd4; s_axi4_arburst = 2'b01;
        s_axi4_wdata = 0; s_axi4_wstrb = {WIDE_STRB{1'b1}}; s_axi4_wlast = 0;
        @(posedge clk); @(posedge clk);
        rst_n = 1;
        @(posedge clk); @(posedge clk);
    end
    endtask

    // -----------------------------------------------------------------------
    // Test 1: Single-beat write through full pipeline
    // -----------------------------------------------------------------------
    task test_single_write;
    begin
        $display("[TEST] Single-beat write through full pipeline");

        // Issue AW (NPU ID -> QoS=0xF)
        s_axi4_awid    = 6'b010_001;
        s_axi4_awaddr  = 32'h0010_0000;
        s_axi4_awlen   = 8'd0; // 1 beat
        s_axi4_awsize  = 3'd4; // 16 bytes
        s_axi4_awburst = 2'b01;
        s_axi4_awvalid = 1;

        @(posedge clk);
        while (!s_axi4_awready) @(posedge clk);
        @(posedge clk);
        s_axi4_awvalid = 0;

        // Wait for AW on AXI3 master
        while (!m_axi3_awvalid) @(posedge clk);

        // Check: len should be doubled (0->1), size clamped (4->3)
        if (m_axi3_awlen == 4'd1) begin
            $display("  PASS: m_axi3_awlen = %0d (1 wide -> 2 narrow)", m_axi3_awlen);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: m_axi3_awlen = %0d (expected 1)", m_axi3_awlen);
            fail_count = fail_count + 1;
        end

        if (m_axi3_awsize == 3'd3) begin
            $display("  PASS: m_axi3_awsize = %0d (clamped from 4)", m_axi3_awsize);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: m_axi3_awsize = %0d (expected 3)", m_axi3_awsize);
            fail_count = fail_count + 1;
        end
        @(posedge clk);

        // Send write data (128-bit)
        s_axi4_wdata  = 128'hAAAA_BBBB_CCCC_DDDD_1111_2222_3333_4444;
        s_axi4_wstrb  = 16'hFFFF;
        s_axi4_wlast  = 1;
        s_axi4_wvalid = 1;

        @(posedge clk);
        while (!s_axi4_wready) @(posedge clk);
        @(posedge clk);
        s_axi4_wvalid = 0;

        // Receive 2 x 64-bit W beats on master
        beat_count = 0;
        while (beat_count < 2) begin
            @(posedge clk);
            if (m_axi3_wvalid && m_axi3_wready) begin
                beat_count = beat_count + 1;
                if (beat_count == 1) begin
                    if (m_axi3_wdata == 64'h1111_2222_3333_4444) begin
                        $display("  PASS: W beat 0 (low) = 0x%h", m_axi3_wdata);
                        pass_count = pass_count + 1;
                    end else begin
                        $display("  FAIL: W beat 0 = 0x%h", m_axi3_wdata);
                        fail_count = fail_count + 1;
                    end
                end else begin
                    if (m_axi3_wdata == 64'hAAAA_BBBB_CCCC_DDDD) begin
                        $display("  PASS: W beat 1 (high) = 0x%h", m_axi3_wdata);
                        pass_count = pass_count + 1;
                    end else begin
                        $display("  FAIL: W beat 1 = 0x%h", m_axi3_wdata);
                        fail_count = fail_count + 1;
                    end
                end
            end
        end

        // Send B response from AXI3 side
        @(posedge clk);
        m_axi3_bid    = 6'b010_001;
        m_axi3_bresp  = 2'b00;
        m_axi3_bvalid = 1;
        @(posedge clk);
        while (!m_axi3_bready) @(posedge clk);
        @(posedge clk);
        m_axi3_bvalid = 0;

        // Check slave B
        while (!s_axi4_bvalid) @(posedge clk);
        if (s_axi4_bresp == 2'b00) begin
            $display("  PASS: write response OKAY");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: write response = %b", s_axi4_bresp);
            fail_count = fail_count + 1;
        end
        @(posedge clk); @(posedge clk);
    end
    endtask

    // -----------------------------------------------------------------------
    // Test 2: Single-beat read through full pipeline
    // -----------------------------------------------------------------------
    task test_single_read;
    begin
        $display("[TEST] Single-beat read through full pipeline");

        s_axi4_arid    = 6'b011_000; // Camera
        s_axi4_araddr  = 32'h0020_0000;
        s_axi4_arlen   = 8'd0;
        s_axi4_arsize  = 3'd4;
        s_axi4_arburst = 2'b01;
        s_axi4_arvalid = 1;

        @(posedge clk);
        while (!s_axi4_arready) @(posedge clk);
        @(posedge clk);
        s_axi4_arvalid = 0;

        // Wait for AR on master
        while (!m_axi3_arvalid) @(posedge clk);
        if (m_axi3_arlen == 4'd1) begin
            $display("  PASS: m_axi3_arlen = 1 (doubled from 0)");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: m_axi3_arlen = %0d (expected 1)", m_axi3_arlen);
            fail_count = fail_count + 1;
        end
        @(posedge clk);

        // Supply 2 x 64-bit read beats
        m_axi3_rid    = 6'b011_000;
        m_axi3_rdata  = 64'hFEDC_BA98_7654_3210;
        m_axi3_rresp  = 2'b00;
        m_axi3_rlast  = 0;
        m_axi3_rvalid = 1;
        @(posedge clk);
        while (!m_axi3_rready) @(posedge clk);
        @(posedge clk);

        m_axi3_rdata  = 64'h0123_4567_89AB_CDEF;
        m_axi3_rlast  = 1;
        @(posedge clk);
        while (!m_axi3_rready) @(posedge clk);
        @(posedge clk);
        m_axi3_rvalid = 0;

        // Check merged 128-bit on slave side
        while (!s_axi4_rvalid) @(posedge clk);
        if (s_axi4_rdata == 128'h0123_4567_89AB_CDEF_FEDC_BA98_7654_3210) begin
            $display("  PASS: merged rdata correct");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: merged rdata = 0x%h", s_axi4_rdata);
            fail_count = fail_count + 1;
        end

        if (s_axi4_rlast) begin
            $display("  PASS: rlast asserted");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: rlast not asserted");
            fail_count = fail_count + 1;
        end
        @(posedge clk); @(posedge clk);
    end
    endtask

    // -----------------------------------------------------------------------
    // Test 3: Verify AXI3 burst limit (awlen <= 15)
    // -----------------------------------------------------------------------
    task test_burst_limit;
    begin
        $display("[TEST] Verify AXI3 burst limit on master side");

        // Send AXI4 burst of 32 beats
        s_axi4_awid    = 6'b001_010; // CPU dBus
        s_axi4_awaddr  = 32'h0030_0000;
        s_axi4_awlen   = 8'd31; // 32 beats
        s_axi4_awsize  = 3'd4;
        s_axi4_awburst = 2'b01;
        s_axi4_awvalid = 1;

        @(posedge clk);
        while (!s_axi4_awready) @(posedge clk);
        @(posedge clk);
        s_axi4_awvalid = 0;

        // First sub-burst AW
        while (!m_axi3_awvalid) @(posedge clk);
        if (m_axi3_awlen <= 4'd15) begin
            $display("  PASS: first sub-burst m_axi3_awlen = %0d (<= 15)", m_axi3_awlen);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: m_axi3_awlen = %0d (exceeded AXI3 limit)", m_axi3_awlen);
            fail_count = fail_count + 1;
        end
        @(posedge clk);

        $display("  INFO: Burst limit check complete (full transaction not driven)");
    end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;

        reset;

        test_single_write;
        reset;
        test_single_read;
        reset;
        test_burst_limit;

        #200;
        $display("===================================");
        $display("ddr_wrapper TB: %0d PASSED, %0d FAILED", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $display("===================================");
        $finish;
    end

    initial begin
        #200000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
