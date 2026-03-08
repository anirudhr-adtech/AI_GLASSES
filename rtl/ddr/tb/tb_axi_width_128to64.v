`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — DDR Subsystem
// Testbench: tb_axi_width_128to64
// Description: Self-checking testbench for axi_width_128to64 module.
//////////////////////////////////////////////////////////////////////////////

module tb_axi_width_128to64;

    parameter ADDR_WIDTH   = 32;
    parameter ID_WIDTH     = 6;
    parameter WIDE_DATA    = 128;
    parameter NARROW_DATA  = 64;
    parameter WIDE_STRB    = WIDE_DATA / 8;
    parameter NARROW_STRB  = NARROW_DATA / 8;

    reg                      clk;
    reg                      rst_n;

    // Wide slave (128-bit)
    reg  [ID_WIDTH-1:0]      s_awid, s_arid;
    reg  [ADDR_WIDTH-1:0]    s_awaddr, s_araddr;
    reg  [3:0]               s_awlen, s_arlen;
    reg  [2:0]               s_awsize, s_arsize;
    reg  [1:0]               s_awburst, s_arburst;
    reg  [3:0]               s_awqos, s_arqos;
    reg                      s_awvalid, s_arvalid;
    wire                     s_awready, s_arready;

    reg  [WIDE_DATA-1:0]     s_wdata;
    reg  [WIDE_STRB-1:0]     s_wstrb;
    reg                      s_wlast;
    reg                      s_wvalid;
    wire                     s_wready;

    wire [ID_WIDTH-1:0]      s_bid, s_rid;
    wire [1:0]               s_bresp, s_rresp;
    wire                     s_bvalid, s_rvalid;
    reg                      s_bready, s_rready;
    wire [WIDE_DATA-1:0]     s_rdata;
    wire                     s_rlast;

    // Narrow master (64-bit)
    wire [ID_WIDTH-1:0]      m_awid, m_arid;
    wire [ADDR_WIDTH-1:0]    m_awaddr, m_araddr;
    wire [3:0]               m_awlen, m_arlen;
    wire [2:0]               m_awsize, m_arsize;
    wire [1:0]               m_awburst, m_arburst;
    wire [3:0]               m_awqos, m_arqos;
    wire                     m_awvalid, m_arvalid;
    reg                      m_awready, m_arready;

    wire [NARROW_DATA-1:0]   m_wdata;
    wire [NARROW_STRB-1:0]   m_wstrb;
    wire                     m_wlast;
    wire                     m_wvalid;
    reg                      m_wready;

    reg  [ID_WIDTH-1:0]      m_bid, m_rid;
    reg  [1:0]               m_bresp, m_rresp;
    reg                      m_bvalid, m_rvalid;
    wire                     m_bready, m_rready;
    reg  [NARROW_DATA-1:0]   m_rdata;
    reg                      m_rlast;

    integer pass_count;
    integer fail_count;
    integer i;

    initial clk = 0;
    always #5 clk = ~clk;

    axi_width_128to64 #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .ID_WIDTH(ID_WIDTH),
        .WIDE_DATA(WIDE_DATA),
        .NARROW_DATA(NARROW_DATA)
    ) uut (
        .clk(clk), .rst_n(rst_n),
        .s_awid(s_awid), .s_awaddr(s_awaddr), .s_awlen(s_awlen),
        .s_awsize(s_awsize), .s_awburst(s_awburst), .s_awqos(s_awqos),
        .s_awvalid(s_awvalid), .s_awready(s_awready),
        .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wlast(s_wlast),
        .s_wvalid(s_wvalid), .s_wready(s_wready),
        .s_bid(s_bid), .s_bresp(s_bresp), .s_bvalid(s_bvalid), .s_bready(s_bready),
        .s_arid(s_arid), .s_araddr(s_araddr), .s_arlen(s_arlen),
        .s_arsize(s_arsize), .s_arburst(s_arburst), .s_arqos(s_arqos),
        .s_arvalid(s_arvalid), .s_arready(s_arready),
        .s_rid(s_rid), .s_rdata(s_rdata), .s_rresp(s_rresp),
        .s_rlast(s_rlast), .s_rvalid(s_rvalid), .s_rready(s_rready),
        .m_awid(m_awid), .m_awaddr(m_awaddr), .m_awlen(m_awlen),
        .m_awsize(m_awsize), .m_awburst(m_awburst), .m_awqos(m_awqos),
        .m_awvalid(m_awvalid), .m_awready(m_awready),
        .m_wdata(m_wdata), .m_wstrb(m_wstrb), .m_wlast(m_wlast),
        .m_wvalid(m_wvalid), .m_wready(m_wready),
        .m_bid(m_bid), .m_bresp(m_bresp), .m_bvalid(m_bvalid), .m_bready(m_bready),
        .m_arid(m_arid), .m_araddr(m_araddr), .m_arlen(m_arlen),
        .m_arsize(m_arsize), .m_arburst(m_arburst), .m_arqos(m_arqos),
        .m_arvalid(m_arvalid), .m_arready(m_arready),
        .m_rid(m_rid), .m_rdata(m_rdata), .m_rresp(m_rresp),
        .m_rlast(m_rlast), .m_rvalid(m_rvalid), .m_rready(m_rready)
    );

    task reset;
    begin
        rst_n = 0;
        s_awvalid = 0; s_wvalid = 0; s_bready = 1;
        s_arvalid = 0; s_rready = 1;
        m_awready = 1; m_wready = 1; m_arready = 1;
        m_bvalid = 0; m_rvalid = 0;
        m_bresp = 2'b00; m_rresp = 2'b00;
        m_rlast = 0; m_rdata = 0; m_rid = 0; m_bid = 0;
        s_awid = 0; s_awaddr = 0; s_awlen = 0; s_awsize = 3'd4; s_awburst = 2'b01;
        s_arid = 0; s_araddr = 0; s_arlen = 0; s_arsize = 3'd4; s_arburst = 2'b01;
        s_awqos = 0; s_arqos = 0;
        s_wdata = 0; s_wstrb = {WIDE_STRB{1'b1}}; s_wlast = 0;
        @(posedge clk); @(posedge clk);
        rst_n = 1;
        @(posedge clk); @(posedge clk);
    end
    endtask

    // -----------------------------------------------------------------------
    // Test 1: Write AW channel — len doubling and size clamping
    // -----------------------------------------------------------------------
    task test_aw_conversion;
    begin
        $display("[TEST] Write AW: len doubling, size clamping");
        s_awid    = 6'h0A;
        s_awaddr  = 32'hA000_0000;
        s_awlen   = 4'd3;  // 4 beats of 128-bit
        s_awsize  = 3'd4;  // 16 bytes
        s_awburst = 2'b01;
        s_awqos   = 4'hC;
        s_awvalid = 1;

        @(posedge clk);
        while (!s_awready) @(posedge clk);
        @(posedge clk);
        s_awvalid = 0;

        while (!m_awvalid) @(posedge clk);
        // Expected: len = (3+1)*2-1 = 7, size = 3 (clamped)
        if (m_awlen == 4'd7) begin
            $display("  PASS: m_awlen = %0d (expected 7)", m_awlen);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: m_awlen = %0d (expected 7)", m_awlen);
            fail_count = fail_count + 1;
        end

        if (m_awsize == 3'd3) begin
            $display("  PASS: m_awsize = %0d (clamped to 3)", m_awsize);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: m_awsize = %0d (expected 3)", m_awsize);
            fail_count = fail_count + 1;
        end

        if (m_awqos == 4'hC) begin
            $display("  PASS: m_awqos = 0x%h (passthrough)", m_awqos);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: m_awqos = 0x%h (expected 0xC)", m_awqos);
            fail_count = fail_count + 1;
        end
        @(posedge clk);
    end
    endtask

    // -----------------------------------------------------------------------
    // Test 2: Write data splitting — 1x128 -> 2x64
    // -----------------------------------------------------------------------
    task test_write_data_split;
        reg [NARROW_DATA-1:0] low_half;
        reg [NARROW_DATA-1:0] high_half;
        reg                   got_low;
        reg                   got_high;
    begin
        $display("[TEST] Write data: 128->64 split");
        // Send 1 beat of 128-bit data
        s_wdata  = 128'hDEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0;
        s_wstrb  = 16'hFFFF;
        s_wlast  = 1;
        s_wvalid = 1;

        got_low  = 0;
        got_high = 0;

        // Expect 2 beats on narrow side
        while (!(got_low && got_high)) begin
            @(posedge clk);
            if (s_wready && s_wvalid) begin
                s_wvalid = 0;
            end
            if (m_wvalid && m_wready) begin
                if (!got_low) begin
                    low_half = m_wdata;
                    got_low  = 1;
                    if (m_wdata == 64'h1234_5678_9ABC_DEF0) begin
                        $display("  PASS: low half = 0x%h", m_wdata);
                        pass_count = pass_count + 1;
                    end else begin
                        $display("  FAIL: low half = 0x%h (expected 0x12345678_9ABCDEF0)", m_wdata);
                        fail_count = fail_count + 1;
                    end
                end else begin
                    high_half = m_wdata;
                    got_high  = 1;
                    if (m_wdata == 64'hDEAD_BEEF_CAFE_BABE) begin
                        $display("  PASS: high half = 0x%h", m_wdata);
                        pass_count = pass_count + 1;
                    end else begin
                        $display("  FAIL: high half = 0x%h (expected 0xDEADBEEF_CAFEBABE)", m_wdata);
                        fail_count = fail_count + 1;
                    end
                    if (m_wlast == 1) begin
                        $display("  PASS: wlast on high half");
                        pass_count = pass_count + 1;
                    end else begin
                        $display("  FAIL: wlast not set on high half");
                        fail_count = fail_count + 1;
                    end
                end
            end
        end

        // Send B response
        @(posedge clk); @(posedge clk);
        m_bid = 6'h0A; m_bresp = 2'b00; m_bvalid = 1;
        @(posedge clk);
        while (!m_bready) @(posedge clk);
        @(posedge clk);
        m_bvalid = 0;
        @(posedge clk);
    end
    endtask

    // -----------------------------------------------------------------------
    // Test 3: Read data merging — 2x64 -> 1x128
    // -----------------------------------------------------------------------
    task test_read_data_merge;
    begin
        $display("[TEST] Read data: 64->128 merge");
        // Issue AR
        s_arid    = 6'h05;
        s_araddr  = 32'hB000_0000;
        s_arlen   = 4'd0;  // 1 beat of 128-bit = 2 beats of 64-bit
        s_arsize  = 3'd4;
        s_arburst = 2'b01;
        s_arqos   = 4'h8;
        s_arvalid = 1;

        @(posedge clk);
        while (!s_arready) @(posedge clk);
        @(posedge clk);
        s_arvalid = 0;

        // Wait for AR to propagate to master
        while (!m_arvalid) @(posedge clk);
        @(posedge clk);

        // Send 2 x 64-bit read beats
        // Beat 0 (low)
        m_rid    = 6'h05;
        m_rdata  = 64'hAAAA_BBBB_CCCC_DDDD;
        m_rresp  = 2'b00;
        m_rlast  = 0;
        m_rvalid = 1;
        @(posedge clk);
        while (!m_rready) @(posedge clk);
        @(posedge clk);

        // Beat 1 (high)
        m_rdata  = 64'h1111_2222_3333_4444;
        m_rresp  = 2'b00;
        m_rlast  = 1;
        @(posedge clk);
        while (!m_rready) @(posedge clk);
        @(posedge clk);
        m_rvalid = 0;

        // Check merged 128-bit data on slave side
        while (!s_rvalid) @(posedge clk);
        if (s_rdata == 128'h1111_2222_3333_4444_AAAA_BBBB_CCCC_DDDD) begin
            $display("  PASS: merged rdata = 0x%h", s_rdata);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: merged rdata = 0x%h", s_rdata);
            fail_count = fail_count + 1;
        end

        if (s_rlast == 1) begin
            $display("  PASS: rlast asserted on merged beat");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: rlast not asserted");
            fail_count = fail_count + 1;
        end
        @(posedge clk); @(posedge clk);
    end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;

        reset;

        test_aw_conversion;
        test_write_data_split;
        test_read_data_merge;

        #200;
        $display("===================================");
        $display("axi_width_128to64 TB: %0d PASSED, %0d FAILED", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $display("===================================");
        $finish;
    end

    initial begin
        #100000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
