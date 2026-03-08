`timescale 1ns/1ps
//============================================================================
// Testbench: tb_axilite_fabric
// Project:   AI_GLASSES — AXI Interconnect
// Description: Self-checking testbench for axilite_fabric top-level
//============================================================================

module tb_axilite_fabric;

    parameter DW = 32;
    parameter AW = 32;
    parameter IW = 6;
    parameter NP = 11;

    reg  clk, rst_n;

    // AXI4 slave (from crossbar)
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

    // Peripheral ports
    wire [NP*AW-1:0]     m_awaddr, m_araddr;
    wire [NP*3-1:0]      m_awprot, m_arprot;
    wire [NP-1:0]        m_awvalid, m_arvalid;
    reg  [NP-1:0]        m_awready, m_arready;
    wire [NP*DW-1:0]     m_wdata;
    wire [NP*(DW/8)-1:0] m_wstrb;
    wire [NP-1:0]        m_wvalid;
    reg  [NP-1:0]        m_wready;
    reg  [NP*2-1:0]      m_bresp, m_rresp;
    reg  [NP-1:0]        m_bvalid, m_rvalid;
    wire [NP-1:0]        m_bready, m_rready;
    reg  [NP*DW-1:0]     m_rdata;

    integer pass_count, fail_count;
    integer i;

    axilite_fabric #(
        .DATA_WIDTH(DW), .ADDR_WIDTH(AW), .ID_WIDTH(IW), .NUM_PERIPHS(NP)
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

    // Peripheral responders
    always @(posedge clk) begin
        if (!rst_n) begin
            m_awready <= {NP{1'b1}};
            m_wready  <= {NP{1'b1}};
            m_arready <= {NP{1'b1}};
            m_bvalid  <= {NP{1'b0}};
            m_rvalid  <= {NP{1'b0}};
            m_bresp   <= {(NP*2){1'b0}};
            m_rresp   <= {(NP*2){1'b0}};
        end else begin
            for (i = 0; i < NP; i = i + 1) begin
                if (m_awvalid[i] && m_awready[i] && m_wvalid[i] && m_wready[i]) begin
                    m_bresp[i*2 +: 2] <= 2'b00;
                    m_bvalid[i] <= 1'b1;
                end
                if (m_bvalid[i] && m_bready[i])
                    m_bvalid[i] <= 1'b0;
                if (m_arvalid[i] && m_arready[i]) begin
                    m_rdata[i*DW +: DW] <= 32'hFACE_0000 + i;
                    m_rresp[i*2 +: 2] <= 2'b00;
                    m_rvalid[i] <= 1'b1;
                end
                if (m_rvalid[i] && m_rready[i])
                    m_rvalid[i] <= 1'b0;
            end
        end
    end

    initial begin
        $display("=== tb_axilite_fabric START ===");
        pass_count = 0; fail_count = 0;
        rst_n = 0;
        s_awid = 0; s_awaddr = 0; s_awlen = 0; s_awsize = 0; s_awburst = 0; s_awvalid = 0;
        s_wdata = 0; s_wstrb = 0; s_wlast = 0; s_wvalid = 0; s_bready = 1;
        s_arid = 0; s_araddr = 0; s_arlen = 0; s_arsize = 0; s_arburst = 0; s_arvalid = 0;
        s_rready = 1;
        m_rdata = 0;
        for (i = 0; i < NP; i = i + 1)
            m_rdata[i*DW +: DW] = 32'hFACE_0000 + i;
        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // Write to UART (P0) at 0x2000_0000
        s_awid = 6'd1; s_awaddr = 32'h2000_0000; s_awlen = 0;
        s_awsize = 3'd2; s_awburst = 2'b01; s_awvalid = 1;
        wait (s_awready && s_awvalid);
        @(posedge clk); s_awvalid = 0;

        s_wdata = 32'h00000041; // 'A'
        s_wstrb = 4'hF; s_wlast = 1; s_wvalid = 1;
        wait (s_wready && s_wvalid);
        @(posedge clk); s_wvalid = 0;

        wait (s_bvalid);
        @(posedge clk);
        if (s_bid === 6'd1 && s_bresp === 2'b00) begin
            pass_count = pass_count + 1;
            $display("PASS: Write to UART (P0) completed");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: UART write bid=%0d bresp=%b", s_bid, s_bresp);
        end

        repeat (5) @(posedge clk);

        // Read from SPI (P7) at 0x2000_0700
        s_arid = 6'd2; s_araddr = 32'h2000_0700; s_arlen = 0;
        s_arsize = 3'd2; s_arburst = 2'b01; s_arvalid = 1;
        wait (s_arready && s_arvalid);
        @(posedge clk); s_arvalid = 0;

        wait (s_rvalid);
        @(posedge clk);
        if (s_rid === 6'd2 && s_rlast === 1'b1 && s_rresp === 2'b00) begin
            pass_count = pass_count + 1;
            $display("PASS: Read from SPI (P7) data=0x%08h", s_rdata);
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: SPI read rid=%0d rresp=%b rlast=%b", s_rid, s_rresp, s_rlast);
        end

        repeat (5) @(posedge clk);

        // Read from NPU (P8) at 0x3000_0000
        s_arid = 6'd3; s_araddr = 32'h3000_0000; s_arlen = 0;
        s_arsize = 3'd2; s_arburst = 2'b01; s_arvalid = 1;
        wait (s_arready && s_arvalid);
        @(posedge clk); s_arvalid = 0;

        wait (s_rvalid);
        @(posedge clk);
        if (s_rid === 6'd3 && s_rresp === 2'b00) begin
            pass_count = pass_count + 1;
            $display("PASS: Read from NPU (P8) data=0x%08h", s_rdata);
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: NPU read rid=%0d rresp=%b", s_rid, s_rresp);
        end

        repeat (10) @(posedge clk);
        $display("=== tb_axilite_fabric DONE ===");
        $display("PASSED: %0d  FAILED: %0d", pass_count, fail_count);
        if (fail_count == 0) $display("*** ALL TESTS PASSED ***");
        else $display("*** SOME TESTS FAILED ***");
        $finish;
    end

endmodule
