`timescale 1ns/1ps
//============================================================================
// Testbench: tb_axi_slave_port
// Project:   AI_GLASSES — AXI Interconnect
// Description: Self-checking testbench for axi_slave_port
//============================================================================

module tb_axi_slave_port;

    parameter NM = 5;
    parameter DW = 32;
    parameter AW = 32;
    parameter IW = 6;

    reg  clk, rst_n;
    reg  [2*NM-1:0] tier_i;

    // Master-side packed signals
    reg  [NM*IW-1:0]     m_awid, m_arid;
    reg  [NM*AW-1:0]     m_awaddr, m_araddr;
    reg  [NM*8-1:0]      m_awlen, m_arlen;
    reg  [NM*3-1:0]      m_awsize, m_arsize;
    reg  [NM*2-1:0]      m_awburst, m_arburst;
    reg  [NM-1:0]        m_awvalid, m_arvalid;
    wire [NM-1:0]        m_awready, m_arready;
    reg  [NM*DW-1:0]     m_wdata;
    reg  [NM*(DW/8)-1:0] m_wstrb;
    reg  [NM-1:0]        m_wlast, m_wvalid;
    wire [NM-1:0]        m_wready;

    wire [NM*IW-1:0]     m_bid, m_rid;
    wire [NM*2-1:0]      m_bresp, m_rresp;
    wire [NM-1:0]        m_bvalid, m_rvalid, m_rlast;
    wire [NM*DW-1:0]     m_rdata;
    reg  [NM-1:0]        m_bready, m_rready;

    // Slave-side signals (simple responder)
    wire [IW-1:0]    s_awid, s_arid;
    wire [AW-1:0]    s_awaddr, s_araddr;
    wire [7:0]       s_awlen, s_arlen;
    wire [2:0]       s_awsize, s_arsize;
    wire [1:0]       s_awburst, s_arburst;
    wire             s_awvalid, s_arvalid;
    reg              s_awready, s_arready;
    wire [DW-1:0]    s_wdata;
    wire [DW/8-1:0]  s_wstrb;
    wire             s_wlast, s_wvalid;
    reg              s_wready;
    reg  [IW-1:0]    s_bid, s_rid;
    reg  [1:0]       s_bresp, s_rresp;
    reg              s_bvalid, s_rvalid;
    wire             s_bready, s_rready;
    reg  [DW-1:0]    s_rdata;
    reg              s_rlast;

    integer pass_count, fail_count;

    axi_slave_port #(
        .NUM_MASTERS(NM), .DATA_WIDTH(DW), .ADDR_WIDTH(AW), .ID_WIDTH(IW)
    ) dut (
        .clk(clk), .rst_n(rst_n), .tier_i(tier_i),
        .m_awid_i(m_awid), .m_awaddr_i(m_awaddr), .m_awlen_i(m_awlen),
        .m_awsize_i(m_awsize), .m_awburst_i(m_awburst),
        .m_awvalid_i(m_awvalid), .m_awready_o(m_awready),
        .m_wdata_i(m_wdata), .m_wstrb_i(m_wstrb),
        .m_wlast_i(m_wlast), .m_wvalid_i(m_wvalid), .m_wready_o(m_wready),
        .m_bid_o(m_bid), .m_bresp_o(m_bresp),
        .m_bvalid_o(m_bvalid), .m_bready_i(m_bready),
        .m_arid_i(m_arid), .m_araddr_i(m_araddr), .m_arlen_i(m_arlen),
        .m_arsize_i(m_arsize), .m_arburst_i(m_arburst),
        .m_arvalid_i(m_arvalid), .m_arready_o(m_arready),
        .m_rid_o(m_rid), .m_rdata_o(m_rdata),
        .m_rresp_o(m_rresp), .m_rlast_o(m_rlast),
        .m_rvalid_o(m_rvalid), .m_rready_i(m_rready),
        .s_awid_o(s_awid), .s_awaddr_o(s_awaddr), .s_awlen_o(s_awlen),
        .s_awsize_o(s_awsize), .s_awburst_o(s_awburst),
        .s_awvalid_o(s_awvalid), .s_awready_i(s_awready),
        .s_wdata_o(s_wdata), .s_wstrb_o(s_wstrb),
        .s_wlast_o(s_wlast), .s_wvalid_o(s_wvalid), .s_wready_i(s_wready),
        .s_bid_i(s_bid), .s_bresp_i(s_bresp),
        .s_bvalid_i(s_bvalid), .s_bready_o(s_bready),
        .s_arid_o(s_arid), .s_araddr_o(s_araddr), .s_arlen_o(s_arlen),
        .s_arsize_o(s_arsize), .s_arburst_o(s_arburst),
        .s_arvalid_o(s_arvalid), .s_arready_i(s_arready),
        .s_rid_i(s_rid), .s_rdata_i(s_rdata),
        .s_rresp_i(s_rresp), .s_rlast_i(s_rlast),
        .s_rvalid_i(s_rvalid), .s_rready_o(s_rready)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Simple slave responder
    always @(posedge clk) begin
        if (!rst_n) begin
            s_awready <= 1'b1; s_wready <= 1'b1; s_arready <= 1'b1;
            s_bvalid <= 1'b0; s_rvalid <= 1'b0;
            s_bid <= 0; s_bresp <= 0;
            s_rid <= 0; s_rdata <= 0; s_rresp <= 0; s_rlast <= 0;
        end else begin
            // Accept writes, return B
            if (s_wvalid && s_wready && s_wlast) begin
                s_bid    <= s_awid;
                s_bresp  <= 2'b00;
                s_bvalid <= 1'b1;
            end
            if (s_bvalid && s_bready)
                s_bvalid <= 1'b0;

            // Accept reads, return R
            if (s_arvalid && s_arready) begin
                s_rid    <= s_arid;
                s_rdata  <= 32'hBEEF_CAFE;
                s_rresp  <= 2'b00;
                s_rlast  <= 1'b1;
                s_rvalid <= 1'b1;
            end
            if (s_rvalid && s_rready)
                s_rvalid <= 1'b0;
        end
    end

    initial begin
        $display("=== tb_axi_slave_port START ===");
        pass_count = 0; fail_count = 0;
        rst_n = 0;
        tier_i = {2'd2, 2'd1, 2'd0, 2'd2, 2'd2}; // M0=T2, M1=T2, M2=T0, M3=T1, M4=T2
        m_awid = 0; m_awaddr = 0; m_awlen = 0; m_awsize = 0; m_awburst = 0; m_awvalid = 0;
        m_wdata = 0; m_wstrb = 0; m_wlast = 0; m_wvalid = 0;
        m_arid = 0; m_araddr = 0; m_arlen = 0; m_arsize = 0; m_arburst = 0; m_arvalid = 0;
        m_bready = {NM{1'b1}}; m_rready = {NM{1'b1}};
        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // Master 0 issues a read
        m_arid[0*IW +: IW] = 6'b000_001; // M0 prefix
        m_araddr[0*AW +: AW] = 32'h0000_0100;
        m_arlen[0*8 +: 8] = 8'd0;
        m_arsize[0*3 +: 3] = 3'd2;
        m_arburst[0*2 +: 2] = 2'b01;
        m_arvalid[0] = 1;
        repeat (20) @(posedge clk);

        // Check slave_port connected correctly
        if (s_arvalid === 1'b1 || m_rvalid[0] === 1'b1) begin
            pass_count = pass_count + 1;
            $display("PASS: Slave port forwarded read request");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: No slave activity after M0 read request");
        end

        m_arvalid[0] = 0;
        repeat (10) @(posedge clk);

        $display("=== tb_axi_slave_port DONE ===");
        $display("PASSED: %0d  FAILED: %0d", pass_count, fail_count);
        if (fail_count == 0) $display("*** ALL TESTS PASSED ***");
        else $display("*** SOME TESTS FAILED ***");
        $finish;
    end

endmodule
