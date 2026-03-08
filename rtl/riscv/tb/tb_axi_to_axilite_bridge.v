`timescale 1ns/1ps
//============================================================================
// Testbench : tb_axi_to_axilite_bridge
// Project   : AI_GLASSES — RISC-V Subsystem
// Description : Self-checking testbench for axi_to_axilite_bridge
//============================================================================

module tb_axi_to_axilite_bridge;

    reg clk, rst_n;
    integer pass_cnt, fail_cnt;

    // AXI4 slave side (stimulus)
    reg  [31:0] s_awaddr;  reg        s_awvalid;  wire       s_awready;
    reg  [3:0]  s_awid;    reg [7:0]  s_awlen;    reg [2:0]  s_awsize;
    reg  [1:0]  s_awburst;
    reg  [31:0] s_wdata;   reg [3:0]  s_wstrb;    reg        s_wvalid;
    reg         s_wlast;   wire       s_wready;
    wire [3:0]  s_bid;     wire [1:0] s_bresp;    wire       s_bvalid;
    reg         s_bready;
    reg  [31:0] s_araddr;  reg        s_arvalid;  wire       s_arready;
    reg  [3:0]  s_arid;    reg [7:0]  s_arlen;    reg [2:0]  s_arsize;
    reg  [1:0]  s_arburst;
    wire [31:0] s_rdata;   wire [1:0] s_rresp;    wire       s_rvalid;
    wire [3:0]  s_rid;     wire       s_rlast;    reg        s_rready;

    // AXI-Lite master side (behavioral slave)
    wire [31:0] m_awaddr;  wire       m_awvalid;  reg        m_awready;
    wire [31:0] m_wdata;   wire [3:0] m_wstrb;    wire       m_wvalid;
    reg         m_wready;
    reg  [1:0]  m_bresp;   reg        m_bvalid;   wire       m_bready;
    wire [31:0] m_araddr;  wire       m_arvalid;  reg        m_arready;
    reg  [31:0] m_rdata;   reg [1:0]  m_rresp;    reg        m_rvalid;
    wire        m_rready;

    riscv_axi_to_axilite_bridge #(
        .ADDR_WIDTH(32), .DATA_WIDTH(32), .ID_WIDTH(4)
    ) uut (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(s_awaddr), .s_axi_awvalid(s_awvalid), .s_axi_awready(s_awready),
        .s_axi_awid(s_awid), .s_axi_awlen(s_awlen), .s_axi_awsize(s_awsize),
        .s_axi_awburst(s_awburst),
        .s_axi_wdata(s_wdata), .s_axi_wstrb(s_wstrb), .s_axi_wvalid(s_wvalid),
        .s_axi_wlast(s_wlast), .s_axi_wready(s_wready),
        .s_axi_bid(s_bid), .s_axi_bresp(s_bresp), .s_axi_bvalid(s_bvalid),
        .s_axi_bready(s_bready),
        .s_axi_araddr(s_araddr), .s_axi_arvalid(s_arvalid), .s_axi_arready(s_arready),
        .s_axi_arid(s_arid), .s_axi_arlen(s_arlen), .s_axi_arsize(s_arsize),
        .s_axi_arburst(s_arburst),
        .s_axi_rdata(s_rdata), .s_axi_rresp(s_rresp), .s_axi_rvalid(s_rvalid),
        .s_axi_rid(s_rid), .s_axi_rlast(s_rlast), .s_axi_rready(s_rready),
        .m_axil_awaddr(m_awaddr), .m_axil_awvalid(m_awvalid), .m_axil_awready(m_awready),
        .m_axil_wdata(m_wdata), .m_axil_wstrb(m_wstrb), .m_axil_wvalid(m_wvalid),
        .m_axil_wready(m_wready),
        .m_axil_bresp(m_bresp), .m_axil_bvalid(m_bvalid), .m_axil_bready(m_bready),
        .m_axil_araddr(m_araddr), .m_axil_arvalid(m_arvalid), .m_axil_arready(m_arready),
        .m_axil_rdata(m_rdata), .m_axil_rresp(m_rresp), .m_axil_rvalid(m_rvalid),
        .m_axil_rready(m_rready)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Behavioral AXI-Lite slave
    always @(posedge clk) begin
        if (!rst_n) begin
            m_awready <= 1'b1;
            m_wready  <= 1'b1;
            m_bvalid  <= 1'b0;
            m_bresp   <= 2'b00;
            m_arready <= 1'b1;
            m_rvalid  <= 1'b0;
            m_rdata   <= 32'd0;
            m_rresp   <= 2'b00;
        end else begin
            // Write response
            if (m_awvalid && m_awready && m_wvalid && m_wready) begin
                m_bvalid <= 1'b1;
                m_bresp  <= 2'b00;
            end
            if (m_bvalid && m_bready)
                m_bvalid <= 1'b0;
            // Read response
            if (m_arvalid && m_arready) begin
                m_rvalid <= 1'b1;
                m_rdata  <= 32'hCAFE_BABE;
                m_rresp  <= 2'b00;
            end
            if (m_rvalid && m_rready)
                m_rvalid <= 1'b0;
        end
    end

    initial begin
        pass_cnt = 0; fail_cnt = 0;
        rst_n = 0;
        s_awaddr = 0; s_awvalid = 0; s_awid = 0; s_awlen = 0;
        s_awsize = 3'b010; s_awburst = 2'b01;
        s_wdata = 0; s_wstrb = 4'hF; s_wvalid = 0; s_wlast = 0;
        s_bready = 1;
        s_araddr = 0; s_arvalid = 0; s_arid = 0; s_arlen = 0;
        s_arsize = 3'b010; s_arburst = 2'b01;
        s_rready = 1;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (3) @(posedge clk);

        // Test 1: Single write (len=0)
        $display("Test 1: Single write pass-through");
        s_awaddr  = 32'h2000_0000;
        s_awid    = 4'hA;
        s_awlen   = 8'd0;
        s_awvalid = 1;
        @(posedge clk);
        while (!s_awready) @(posedge clk);
        s_awvalid = 0;
        // Provide write data
        s_wdata  = 32'h1234_5678;
        s_wstrb  = 4'hF;
        s_wvalid = 1;
        s_wlast  = 1;
        @(posedge clk);
        while (!s_wready) @(posedge clk);
        s_wvalid = 0;
        // Wait for response
        while (!s_bvalid) @(posedge clk);
        if (s_bid == 4'hA && s_bresp == 2'b00) begin
            $display("PASS: Write resp bid=0x%h bresp=%b", s_bid, s_bresp);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL: Write resp bid=0x%h bresp=%b", s_bid, s_bresp);
            fail_cnt = fail_cnt + 1;
        end
        @(posedge clk);

        repeat (3) @(posedge clk);

        // Test 2: Single read (len=0)
        $display("Test 2: Single read pass-through");
        s_araddr  = 32'h2000_0004;
        s_arid    = 4'hB;
        s_arlen   = 8'd0;
        s_arvalid = 1;
        @(posedge clk);
        while (!s_arready) @(posedge clk);
        s_arvalid = 0;
        while (!s_rvalid) @(posedge clk);
        if (s_rid == 4'hB && s_rdata == 32'hCAFE_BABE && s_rresp == 2'b00 && s_rlast == 1'b1) begin
            $display("PASS: Read resp rid=0x%h data=0x%08h rlast=%b", s_rid, s_rdata, s_rlast);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL: Read resp rid=0x%h data=0x%08h resp=%b rlast=%b",
                     s_rid, s_rdata, s_rresp, s_rlast);
            fail_cnt = fail_cnt + 1;
        end
        @(posedge clk);

        repeat (3) @(posedge clk);

        // Test 3: Burst write rejection (len=3)
        $display("Test 3: Burst write rejection");
        s_awaddr  = 32'h2000_0010;
        s_awid    = 4'hC;
        s_awlen   = 8'd3;
        s_awvalid = 1;
        @(posedge clk);
        while (!s_awready) @(posedge clk);
        s_awvalid = 0;
        // Send wlast beat to allow completion
        s_wdata  = 32'hDEAD;
        s_wvalid = 1;
        s_wlast  = 1;
        @(posedge clk);
        while (!s_wready) @(posedge clk);
        s_wvalid = 0;
        while (!s_bvalid) @(posedge clk);
        if (s_bresp == 2'b10) begin
            $display("PASS: Burst write rejected with SLVERR");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL: Burst write bresp=%b (expected SLVERR=10)", s_bresp);
            fail_cnt = fail_cnt + 1;
        end
        @(posedge clk);

        repeat (3) @(posedge clk);

        // Test 4: Burst read rejection (len=2)
        $display("Test 4: Burst read rejection");
        s_araddr  = 32'h2000_0020;
        s_arid    = 4'hD;
        s_arlen   = 8'd2;
        s_arvalid = 1;
        @(posedge clk);
        while (!s_arready) @(posedge clk);
        s_arvalid = 0;
        while (!s_rvalid) @(posedge clk);
        if (s_rresp == 2'b10) begin
            $display("PASS: Burst read rejected with SLVERR");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("FAIL: Burst read rresp=%b (expected SLVERR=10)", s_rresp);
            fail_cnt = fail_cnt + 1;
        end
        @(posedge clk);

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

    initial begin
        #20000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
