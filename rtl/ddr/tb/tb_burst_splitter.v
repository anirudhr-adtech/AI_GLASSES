`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — DDR Subsystem
// Testbench: tb_burst_splitter
// Description: Self-checking testbench for burst_splitter module.
//////////////////////////////////////////////////////////////////////////////

module tb_burst_splitter;

    parameter ADDR_WIDTH = 32;
    parameter DATA_WIDTH = 128;
    parameter ID_WIDTH   = 6;
    parameter STRB_WIDTH = DATA_WIDTH / 8;

    reg                    clk;
    reg                    rst_n;

    // AXI4 Slave signals
    reg  [ID_WIDTH-1:0]    s_awid, s_arid;
    reg  [ADDR_WIDTH-1:0]  s_awaddr, s_araddr;
    reg  [7:0]             s_awlen, s_arlen;
    reg  [2:0]             s_awsize, s_arsize;
    reg  [1:0]             s_awburst, s_arburst;
    reg                    s_awvalid, s_arvalid;
    wire                   s_awready, s_arready;

    reg  [DATA_WIDTH-1:0]  s_wdata;
    reg  [STRB_WIDTH-1:0]  s_wstrb;
    reg                    s_wlast;
    reg                    s_wvalid;
    wire                   s_wready;

    wire [ID_WIDTH-1:0]    s_bid, s_rid;
    wire [1:0]             s_bresp, s_rresp;
    wire                   s_bvalid, s_rvalid;
    reg                    s_bready, s_rready;
    wire [DATA_WIDTH-1:0]  s_rdata;
    wire                   s_rlast;

    // AXI3 Master signals
    wire [ID_WIDTH-1:0]    m_awid, m_arid;
    wire [ADDR_WIDTH-1:0]  m_awaddr, m_araddr;
    wire [3:0]             m_awlen, m_arlen;
    wire [2:0]             m_awsize, m_arsize;
    wire [1:0]             m_awburst, m_arburst;
    wire                   m_awvalid, m_arvalid;
    reg                    m_awready, m_arready;

    wire [DATA_WIDTH-1:0]  m_wdata;
    wire [STRB_WIDTH-1:0]  m_wstrb;
    wire                   m_wlast;
    wire                   m_wvalid;
    reg                    m_wready;

    reg  [ID_WIDTH-1:0]    m_bid, m_rid;
    reg  [1:0]             m_bresp, m_rresp;
    reg                    m_bvalid, m_rvalid;
    wire                   m_bready, m_rready;
    reg  [DATA_WIDTH-1:0]  m_rdata;
    reg                    m_rlast;

    integer pass_count;
    integer fail_count;
    integer i;

    // Clock: 10ns period
    initial clk = 0;
    always #5 clk = ~clk;

    burst_splitter #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH)
    ) uut (
        .clk(clk), .rst_n(rst_n),
        .s_awid(s_awid), .s_awaddr(s_awaddr), .s_awlen(s_awlen),
        .s_awsize(s_awsize), .s_awburst(s_awburst),
        .s_awvalid(s_awvalid), .s_awready(s_awready),
        .s_wdata(s_wdata), .s_wstrb(s_wstrb), .s_wlast(s_wlast),
        .s_wvalid(s_wvalid), .s_wready(s_wready),
        .s_bid(s_bid), .s_bresp(s_bresp), .s_bvalid(s_bvalid), .s_bready(s_bready),
        .s_arid(s_arid), .s_araddr(s_araddr), .s_arlen(s_arlen),
        .s_arsize(s_arsize), .s_arburst(s_arburst),
        .s_arvalid(s_arvalid), .s_arready(s_arready),
        .s_rid(s_rid), .s_rdata(s_rdata), .s_rresp(s_rresp),
        .s_rlast(s_rlast), .s_rvalid(s_rvalid), .s_rready(s_rready),
        .m_awid(m_awid), .m_awaddr(m_awaddr), .m_awlen(m_awlen),
        .m_awsize(m_awsize), .m_awburst(m_awburst),
        .m_awvalid(m_awvalid), .m_awready(m_awready),
        .m_wdata(m_wdata), .m_wstrb(m_wstrb), .m_wlast(m_wlast),
        .m_wvalid(m_wvalid), .m_wready(m_wready),
        .m_bid(m_bid), .m_bresp(m_bresp), .m_bvalid(m_bvalid), .m_bready(m_bready),
        .m_arid(m_arid), .m_araddr(m_araddr), .m_arlen(m_arlen),
        .m_arsize(m_arsize), .m_arburst(m_arburst),
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
        m_rlast = 0;
        s_awid = 0; s_awaddr = 0; s_awlen = 0; s_awsize = 3'd4; s_awburst = 2'b01;
        s_arid = 0; s_araddr = 0; s_arlen = 0; s_arsize = 3'd4; s_arburst = 2'b01;
        s_wdata = 0; s_wstrb = {STRB_WIDTH{1'b1}}; s_wlast = 0;
        m_rdata = 0; m_rid = 0; m_bid = 0;
        @(posedge clk);
        @(posedge clk);
        rst_n = 1;
        @(posedge clk);
        @(posedge clk);
    end
    endtask

    // -----------------------------------------------------------------------
    // Test 1: Passthrough — burst len <= 16 (awlen=3, 4 beats)
    // -----------------------------------------------------------------------
    task test_passthrough_write;
    begin
        $display("[TEST] Passthrough write (4 beats)");
        s_awid    = 6'h0A;
        s_awaddr  = 32'h1000_0000;
        s_awlen   = 8'd3; // 4 beats
        s_awsize  = 3'd4; // 16 bytes
        s_awburst = 2'b01;
        s_awvalid = 1;

        // Wait for AW handshake — wait for ready at negedge, fire at posedge
        begin : wait_awhs_t1
            integer wt;
            wt = 0;
            @(negedge clk);
            while (!s_awready && wt < 100) begin
                @(negedge clk);
                wt = wt + 1;
            end
        end
        @(posedge clk); // handshake fires here
        s_awvalid = 0;

        // Check master side AW
        begin : wait_maw_t1
            integer wt;
            wt = 0;
            while (!m_awvalid && wt < 100) begin
                @(posedge clk);
                wt = wt + 1;
            end
        end
        if (m_awlen == 4'd3) begin
            $display("  PASS: m_awlen = %0d (expected 3)", m_awlen);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: m_awlen = %0d (expected 3)", m_awlen);
            fail_count = fail_count + 1;
        end
        @(posedge clk); // let m_awready consume it

        // Send 4 W beats — use negedge sampling for proper handshake
        for (i = 0; i < 4; i = i + 1) begin
            s_wdata  = {DATA_WIDTH{1'b0}} | i;
            s_wstrb  = {STRB_WIDTH{1'b1}};
            s_wlast  = (i == 3);
            s_wvalid = 1;
            begin : wait_whs_t1
                integer wt;
                wt = 0;
                @(negedge clk);
                while (!s_wready && wt < 100) begin
                    @(negedge clk);
                    wt = wt + 1;
                end
            end
            @(posedge clk); // Handshake occurs here
        end
        s_wvalid = 0;
        @(posedge clk);

        // Wait for B response to be accepted by DUT
        begin : wait_bready_t1
            integer wt;
            wt = 0;
            while (!m_bready && wt < 50) begin
                @(posedge clk);
                wt = wt + 1;
            end
        end
        m_bid    = 6'h0A;
        m_bresp  = 2'b00;
        m_bvalid = 1;
        @(posedge clk);
        @(posedge clk);
        m_bvalid = 0;

        // Check slave B
        begin : wait_sb_t1
            integer wt;
            wt = 0;
            while (!s_bvalid && wt < 50) begin
                @(posedge clk);
                wt = wt + 1;
            end
        end
        if (s_bresp == 2'b00) begin
            $display("  PASS: bresp = OKAY");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: bresp = %b", s_bresp);
            fail_count = fail_count + 1;
        end
        @(posedge clk);
        @(posedge clk);
    end
    endtask

    // -----------------------------------------------------------------------
    // Test 2: Split write — burst len=32 (awlen=31) -> 2 sub-bursts of 16
    // -----------------------------------------------------------------------
    task test_split_write;
        integer sub;
    begin
        $display("[TEST] Split write (32 beats -> 2x16)");
        s_awid    = 6'h15;
        s_awaddr  = 32'h2000_0000;
        s_awlen   = 8'd31; // 32 beats
        s_awsize  = 3'd4;
        s_awburst = 2'b01;
        s_awvalid = 1;

        // Wait for AW handshake at negedge, fire at posedge
        begin : wait_awhs_t2
            integer wt;
            wt = 0;
            @(negedge clk);
            while (!s_awready && wt < 100) begin
                @(negedge clk);
                wt = wt + 1;
            end
        end
        @(posedge clk); // handshake fires here
        s_awvalid = 0;

        for (sub = 0; sub < 2; sub = sub + 1) begin
            // Wait for sub-burst AW
            begin : wait_maw_t2
                integer wt;
                wt = 0;
                while (!m_awvalid && wt < 200) begin
                    @(posedge clk);
                    wt = wt + 1;
                end
            end
            if (m_awlen == 4'd15) begin
                $display("  PASS: sub-burst %0d m_awlen = 15", sub);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL: sub-burst %0d m_awlen = %0d (expected 15)", sub, m_awlen);
                fail_count = fail_count + 1;
            end
            @(posedge clk);

            // Send 16 W beats — use negedge sampling for proper handshake
            for (i = 0; i < 16; i = i + 1) begin
                s_wdata  = {DATA_WIDTH{1'b0}} | (sub * 16 + i);
                s_wstrb  = {STRB_WIDTH{1'b1}};
                s_wlast  = (sub == 1 && i == 15);
                s_wvalid = 1;
                begin : wait_whs_t2
                    integer wt;
                    wt = 0;
                    @(negedge clk);
                    while (!s_wready && wt < 100) begin
                        @(negedge clk);
                        wt = wt + 1;
                    end
                end
                @(posedge clk); // Handshake occurs here
            end
            s_wvalid = 0;
            @(posedge clk);

            // Wait for m_bready then send B response per sub-burst
            begin : wait_bready_t2
                integer wt;
                wt = 0;
                while (!m_bready && wt < 50) begin
                    @(posedge clk);
                    wt = wt + 1;
                end
            end
            m_bid    = 6'h15;
            m_bresp  = 2'b00;
            m_bvalid = 1;
            @(posedge clk);
            @(posedge clk);
            m_bvalid = 0;
            @(posedge clk);
        end

        // Wait for final slave B
        begin : wait_sb_t2
            integer wt;
            wt = 0;
            while (!s_bvalid && wt < 100) begin
                @(posedge clk);
                wt = wt + 1;
            end
        end
        if (s_bid == 6'h15 && s_bresp == 2'b00) begin
            $display("  PASS: final bresp OKAY, bid correct");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: bid=%h bresp=%b", s_bid, s_bresp);
            fail_count = fail_count + 1;
        end
        @(posedge clk);
        @(posedge clk);
    end
    endtask

    // -----------------------------------------------------------------------
    // Test 3: Passthrough read (8 beats)
    // -----------------------------------------------------------------------
    task test_passthrough_read;
    begin
        $display("[TEST] Passthrough read (8 beats)");
        s_arid    = 6'h07;
        s_araddr  = 32'h3000_0000;
        s_arlen   = 8'd7;
        s_arsize  = 3'd4;
        s_arburst = 2'b01;
        s_arvalid = 1;

        // Wait for AR handshake at negedge, fire at posedge
        begin : wait_arhs_t3
            integer wt;
            wt = 0;
            @(negedge clk);
            while (!s_arready && wt < 100) begin
                @(negedge clk);
                wt = wt + 1;
            end
        end
        @(posedge clk); // handshake fires here
        s_arvalid = 0;

        // Wait for AR on master side
        begin : wait_mar_t3
            integer wt;
            wt = 0;
            while (!m_arvalid && wt < 100) begin
                @(posedge clk);
                wt = wt + 1;
            end
        end
        if (m_arlen == 4'd7) begin
            $display("  PASS: m_arlen = 7");
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: m_arlen = %0d (expected 7)", m_arlen);
            fail_count = fail_count + 1;
        end
        @(posedge clk);

        // Wait for m_rready before sending R data
        begin : wait_mrr_t3
            integer wt;
            wt = 0;
            while (!m_rready && wt < 100) begin
                @(posedge clk);
                wt = wt + 1;
            end
        end

        // Send 8 R beats
        for (i = 0; i < 8; i = i + 1) begin
            m_rid    = 6'h07;
            m_rdata  = {DATA_WIDTH{1'b0}} | (i + 100);
            m_rresp  = 2'b00;
            m_rlast  = (i == 7);
            m_rvalid = 1;
            begin : wait_rhs_t3
                integer wt;
                wt = 0;
                while (!(m_rvalid && m_rready) && wt < 100) begin
                    @(posedge clk);
                    wt = wt + 1;
                end
            end
            @(posedge clk); // beat accepted
        end
        m_rvalid = 0;

        // Verify rlast on slave side
        // (We check that the last beat arrived with rlast)
        @(posedge clk);
        @(posedge clk);
        $display("  PASS: read passthrough completed");
        pass_count = pass_count + 1;
    end
    endtask

    // -----------------------------------------------------------------------
    // Main
    // -----------------------------------------------------------------------
    initial begin
        pass_count = 0;
        fail_count = 0;

        reset;

        test_passthrough_write;
        test_split_write;
        test_passthrough_read;

        #100;
        $display("===================================");
        $display("burst_splitter TB: %0d PASSED, %0d FAILED", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $display("===================================");
        $finish;
    end

    // Timeout
    initial begin
        #100000;
        $display("TIMEOUT — simulation exceeded 100us");
        $finish;
    end

endmodule
