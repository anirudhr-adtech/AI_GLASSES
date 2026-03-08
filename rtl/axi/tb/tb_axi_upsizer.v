`timescale 1ns/1ps
//============================================================================
// Testbench: tb_axi_upsizer
// Project:   AI_GLASSES — AXI Interconnect
// Description: Self-checking testbench for axi_upsizer (32->128 bit)
//============================================================================

module tb_axi_upsizer;

    parameter NARROW = 32;
    parameter WIDE   = 128;
    parameter AW     = 32;
    parameter IW     = 6;

    reg  clk, rst_n;
    // Narrow slave interface
    reg  [IW-1:0]     s_awid, s_arid;
    reg  [AW-1:0]     s_awaddr, s_araddr;
    reg  [7:0]        s_awlen, s_arlen;
    reg  [2:0]        s_awsize, s_arsize;
    reg  [1:0]        s_awburst, s_arburst;
    reg               s_awvalid, s_arvalid;
    wire              s_awready, s_arready;
    reg  [NARROW-1:0] s_wdata;
    reg  [3:0]        s_wstrb;
    reg               s_wlast, s_wvalid;
    wire              s_wready;
    wire [IW-1:0]     s_bid, s_rid;
    wire [1:0]        s_bresp, s_rresp;
    wire              s_bvalid, s_rvalid, s_rlast;
    wire [NARROW-1:0] s_rdata;
    reg               s_bready, s_rready;

    // Wide master interface - simple memory responder
    wire [IW-1:0]     m_awid, m_arid;
    wire [AW-1:0]     m_awaddr, m_araddr;
    wire [7:0]        m_awlen, m_arlen;
    wire [2:0]        m_awsize, m_arsize;
    wire [1:0]        m_awburst, m_arburst;
    wire              m_awvalid, m_arvalid;
    reg               m_awready, m_arready;
    wire [WIDE-1:0]   m_wdata;
    wire [15:0]       m_wstrb;
    wire              m_wlast, m_wvalid;
    reg               m_wready;
    reg  [IW-1:0]     m_bid, m_rid;
    reg  [1:0]        m_bresp, m_rresp;
    reg               m_bvalid, m_rvalid;
    wire              m_bready, m_rready;
    reg  [WIDE-1:0]   m_rdata;
    reg               m_rlast;

    integer pass_count, fail_count;
    integer timeout_cnt;

    axi_upsizer #(
        .NARROW_WIDTH(NARROW), .WIDE_WIDTH(WIDE),
        .ADDR_WIDTH(AW), .ID_WIDTH(IW)
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

    // Saved AW id for B channel response
    reg [IW-1:0] saved_awid;

    // Wide-side slave responder — combinational ready, registered responses
    // Keep ready signals always high to avoid deadlocks
    always @(*) begin
        m_awready = 1'b1;
        m_wready  = 1'b1;
        m_arready = 1'b1;
    end

    // B channel: respond after W last beat accepted
    always @(posedge clk) begin
        if (!rst_n) begin
            m_bvalid  <= 1'b0;
            m_bid     <= {IW{1'b0}};
            m_bresp   <= 2'b00;
            saved_awid <= {IW{1'b0}};
        end else begin
            // Capture AW id when AW handshakes
            if (m_awvalid && m_awready)
                saved_awid <= m_awid;

            if (m_bvalid && m_bready) begin
                m_bvalid <= 1'b0;
            end else if (m_wvalid && m_wready && m_wlast) begin
                m_bid    <= saved_awid;
                m_bresp  <= 2'b00;
                m_bvalid <= 1'b1;
            end
        end
    end

    // R channel: respond after AR accepted
    always @(posedge clk) begin
        if (!rst_n) begin
            m_rvalid <= 1'b0;
            m_rid    <= {IW{1'b0}};
            m_rdata  <= {WIDE{1'b0}};
            m_rresp  <= 2'b00;
            m_rlast  <= 1'b0;
        end else begin
            if (m_rvalid && m_rready) begin
                m_rvalid <= 1'b0;
            end else if (m_arvalid && m_arready) begin
                m_rid    <= m_arid;
                m_rdata  <= 128'hDDDD_CCCC_BBBB_AAAA_4444_3333_2222_1111;
                m_rresp  <= 2'b00;
                m_rlast  <= 1'b1;
                m_rvalid <= 1'b1;
            end
        end
    end

    // Timeout guard
    initial begin
        #50000;
        $display("FAIL: TIMEOUT at %0t", $time);
        $finish;
    end

    initial begin
        $display("=== tb_axi_upsizer START ===");
        pass_count = 0; fail_count = 0;
        rst_n = 0;
        s_awid = 0; s_awaddr = 0; s_awlen = 0; s_awsize = 0; s_awburst = 0; s_awvalid = 0;
        s_wdata = 0; s_wstrb = 0; s_wlast = 0; s_wvalid = 0;
        s_arid = 0; s_araddr = 0; s_arlen = 0; s_arsize = 0; s_arburst = 0; s_arvalid = 0;
        s_bready = 1; s_rready = 1;
        repeat (4) @(posedge clk);
        rst_n = 1;
        // Wait for RTL to reach IDLE (awready/arready go high)
        repeat (4) @(posedge clk); #1;

        // ---- Write test: 32-bit write to addr[3:2]=2 (lane 2) ----
        s_awid = 6'd5; s_awaddr = 32'h8000_0008; // addr[3:2]=2
        s_awlen = 8'd0; s_awsize = 3'd2; s_awburst = 2'b01; s_awvalid = 1;
        // Wait for AW handshake
        timeout_cnt = 0;
        while (!(s_awready && s_awvalid)) begin
            @(posedge clk); #1;
            timeout_cnt = timeout_cnt + 1;
            if (timeout_cnt > 100) begin
                $display("FAIL: AW handshake timeout"); $finish;
            end
        end
        @(posedge clk); #1;
        s_awvalid = 0;

        // Send W data
        s_wdata = 32'hDEAD_BEEF; s_wstrb = 4'hF; s_wlast = 1; s_wvalid = 1;
        timeout_cnt = 0;
        while (!(s_wready && s_wvalid)) begin
            @(posedge clk); #1;
            timeout_cnt = timeout_cnt + 1;
            if (timeout_cnt > 100) begin
                $display("FAIL: W handshake timeout"); $finish;
            end
        end
        @(posedge clk); #1;
        s_wvalid = 0; s_wlast = 0;

        // Wait for B response
        timeout_cnt = 0;
        while (!s_bvalid) begin
            @(posedge clk); #1;
            timeout_cnt = timeout_cnt + 1;
            if (timeout_cnt > 100) begin
                $display("FAIL: B response timeout"); $finish;
            end
        end

        if (s_bresp === 2'b00 && s_bid === 6'd5) begin
            pass_count = pass_count + 1;
            $display("PASS: Upsized write completed OK");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Write bresp=%b bid=%0d", s_bresp, s_bid);
        end
        @(posedge clk); #1;

        // Let state machine return to IDLE
        repeat (4) @(posedge clk); #1;

        // ---- Read test: 32-bit read from addr[3:2]=0 (lane 0) ----
        s_arid = 6'd7; s_araddr = 32'h8000_0000; // addr[3:2]=0
        s_arlen = 8'd0; s_arsize = 3'd2; s_arburst = 2'b01; s_arvalid = 1;
        // Wait for AR handshake
        timeout_cnt = 0;
        while (!(s_arready && s_arvalid)) begin
            @(posedge clk); #1;
            timeout_cnt = timeout_cnt + 1;
            if (timeout_cnt > 100) begin
                $display("FAIL: AR handshake timeout"); $finish;
            end
        end
        @(posedge clk); #1;
        s_arvalid = 0;

        // Wait for R response
        timeout_cnt = 0;
        while (!s_rvalid) begin
            @(posedge clk); #1;
            timeout_cnt = timeout_cnt + 1;
            if (timeout_cnt > 100) begin
                $display("FAIL: R response timeout"); $finish;
            end
        end

        // Lane 0 of 128'h...2222_1111 = 32'h2222_1111
        if (s_rdata === 32'h2222_1111 && s_rlast === 1'b1 && s_rresp === 2'b00) begin
            pass_count = pass_count + 1;
            $display("PASS: Upsized read lane 0 = 0x%08h", s_rdata);
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Read data=0x%08h rlast=%b rresp=%b", s_rdata, s_rlast, s_rresp);
        end

        repeat (5) @(posedge clk);
        $display("=== tb_axi_upsizer DONE ===");
        $display("PASSED: %0d  FAILED: %0d", pass_count, fail_count);
        if (fail_count == 0) $display("ALL TESTS PASSED");
        else $display("*** SOME TESTS FAILED ***");
        $finish;
    end

endmodule
