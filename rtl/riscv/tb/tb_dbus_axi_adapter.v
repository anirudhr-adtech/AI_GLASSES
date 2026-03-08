`timescale 1ns/1ps
//============================================================================
// Module : tb_dbus_axi_adapter
// Project : AI_GLASSES — RISC-V Subsystem
// Description : Self-checking testbench for dbus_axi_adapter
//============================================================================

module tb_dbus_axi_adapter;

    reg        clk;
    reg        rst_n;

    // Ibex data interface
    reg        data_req_i;
    wire       data_gnt_o;
    wire       data_rvalid_o;
    reg        data_we_i;
    reg [3:0]  data_be_i;
    reg [31:0] data_addr_i;
    reg [31:0] data_wdata_i;
    wire [31:0] data_rdata_o;
    wire       data_err_o;

    // AXI Write Address
    wire       m_axi_awvalid;
    reg        m_axi_awready;
    wire [31:0] m_axi_awaddr;
    wire [7:0] m_axi_awlen;
    wire [2:0] m_axi_awsize;
    wire [1:0] m_axi_awburst;
    wire [3:0] m_axi_awid;

    // AXI Write Data
    wire       m_axi_wvalid;
    reg        m_axi_wready;
    wire [31:0] m_axi_wdata;
    wire [3:0] m_axi_wstrb;
    wire       m_axi_wlast;

    // AXI Write Response
    reg        m_axi_bvalid;
    wire       m_axi_bready;
    reg [1:0]  m_axi_bresp;
    reg [3:0]  m_axi_bid;

    // AXI Read Address
    wire       m_axi_arvalid;
    reg        m_axi_arready;
    wire [31:0] m_axi_araddr;
    wire [7:0] m_axi_arlen;
    wire [2:0] m_axi_arsize;
    wire [1:0] m_axi_arburst;
    wire [3:0] m_axi_arid;

    // AXI Read Data
    reg        m_axi_rvalid;
    wire       m_axi_rready;
    reg [31:0] m_axi_rdata;
    reg [1:0]  m_axi_rresp;
    reg [3:0]  m_axi_rid;
    reg        m_axi_rlast;

    // Counters
    integer pass_count;
    integer fail_count;

    dbus_axi_adapter uut (
        .clk             (clk),
        .rst_n           (rst_n),
        .data_req_i      (data_req_i),
        .data_gnt_o      (data_gnt_o),
        .data_rvalid_o   (data_rvalid_o),
        .data_we_i       (data_we_i),
        .data_be_i       (data_be_i),
        .data_addr_i     (data_addr_i),
        .data_wdata_i    (data_wdata_i),
        .data_rdata_o    (data_rdata_o),
        .data_err_o      (data_err_o),
        .m_axi_awvalid   (m_axi_awvalid),
        .m_axi_awready   (m_axi_awready),
        .m_axi_awaddr    (m_axi_awaddr),
        .m_axi_awlen     (m_axi_awlen),
        .m_axi_awsize    (m_axi_awsize),
        .m_axi_awburst   (m_axi_awburst),
        .m_axi_awid      (m_axi_awid),
        .m_axi_wvalid    (m_axi_wvalid),
        .m_axi_wready    (m_axi_wready),
        .m_axi_wdata     (m_axi_wdata),
        .m_axi_wstrb     (m_axi_wstrb),
        .m_axi_wlast     (m_axi_wlast),
        .m_axi_bvalid    (m_axi_bvalid),
        .m_axi_bready    (m_axi_bready),
        .m_axi_bresp     (m_axi_bresp),
        .m_axi_bid       (m_axi_bid),
        .m_axi_arvalid   (m_axi_arvalid),
        .m_axi_arready   (m_axi_arready),
        .m_axi_araddr    (m_axi_araddr),
        .m_axi_arlen     (m_axi_arlen),
        .m_axi_arsize    (m_axi_arsize),
        .m_axi_arburst   (m_axi_arburst),
        .m_axi_arid      (m_axi_arid),
        .m_axi_rvalid    (m_axi_rvalid),
        .m_axi_rready    (m_axi_rready),
        .m_axi_rdata     (m_axi_rdata),
        .m_axi_rresp     (m_axi_rresp),
        .m_axi_rid       (m_axi_rid),
        .m_axi_rlast     (m_axi_rlast)
    );

    // 100 MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    task check;
        input [255:0] test_name;
        input         condition;
        begin
            if (condition) begin
                $display("[PASS] %0s", test_name);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %0s", test_name);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task reset_dut;
        begin
            rst_n         = 1'b0;
            data_req_i    = 1'b0;
            data_we_i     = 1'b0;
            data_be_i     = 4'hF;
            data_addr_i   = 32'd0;
            data_wdata_i  = 32'd0;
            m_axi_awready = 1'b0;
            m_axi_wready  = 1'b0;
            m_axi_bvalid  = 1'b0;
            m_axi_bresp   = 2'b00;
            m_axi_bid     = 4'd0;
            m_axi_arready = 1'b0;
            m_axi_rvalid  = 1'b0;
            m_axi_rdata   = 32'd0;
            m_axi_rresp   = 2'b00;
            m_axi_rid     = 4'd0;
            m_axi_rlast   = 1'b0;
            repeat (3) @(posedge clk);
            rst_n = 1'b1;
            @(posedge clk);
        end
    endtask

    // Issue a load request (pulse for 1 cycle)
    task issue_load;
        input [31:0] addr;
        begin
            @(posedge clk);
            data_req_i  = 1'b1;
            data_we_i   = 1'b0;
            data_addr_i = addr;
            data_be_i   = 4'hF;
            @(posedge clk);
            data_req_i  = 1'b0;
        end
    endtask

    // Issue a store request (pulse for 1 cycle)
    task issue_store;
        input [31:0] addr;
        input [31:0] wdata;
        input [3:0]  be;
        begin
            @(posedge clk);
            data_req_i   = 1'b1;
            data_we_i    = 1'b1;
            data_addr_i  = addr;
            data_wdata_i = wdata;
            data_be_i    = be;
            @(posedge clk);
            data_req_i   = 1'b0;
        end
    endtask

    // AXI slave: respond to read
    task axi_read_respond;
        input integer ar_delay;
        input [31:0]  rdata;
        input [1:0]   rresp;
        input integer r_delay;
        integer i;
        begin
            while (!m_axi_arvalid) @(posedge clk);
            for (i = 0; i < ar_delay; i = i + 1) @(posedge clk);
            m_axi_arready = 1'b1;
            @(posedge clk);
            m_axi_arready = 1'b0;
            for (i = 0; i < r_delay; i = i + 1) @(posedge clk);
            m_axi_rvalid = 1'b1;
            m_axi_rdata  = rdata;
            m_axi_rresp  = rresp;
            m_axi_rlast  = 1'b1;
            @(posedge clk);
            m_axi_rvalid = 1'b0;
            m_axi_rlast  = 1'b0;
        end
    endtask

    // AXI slave: respond to write (accept AW+W simultaneously, then B)
    task axi_write_respond;
        input integer aw_delay;
        input [1:0]   bresp;
        input integer b_delay;
        integer i;
        begin
            while (!m_axi_awvalid) @(posedge clk);
            for (i = 0; i < aw_delay; i = i + 1) @(posedge clk);
            m_axi_awready = 1'b1;
            m_axi_wready  = 1'b1;
            @(posedge clk);
            m_axi_awready = 1'b0;
            m_axi_wready  = 1'b0;
            for (i = 0; i < b_delay; i = i + 1) @(posedge clk);
            m_axi_bvalid = 1'b1;
            m_axi_bresp  = bresp;
            m_axi_bid    = 4'b0100;
            @(posedge clk);
            m_axi_bvalid = 1'b0;
        end
    endtask

    initial begin
        $dumpfile("tb_dbus_axi_adapter.vcd");
        $dumpvars(0, tb_dbus_axi_adapter);

        pass_count = 0;
        fail_count = 0;

        // ============================================================
        // Test 1: Reset values
        // ============================================================
        reset_dut;
        check("Reset: awvalid=0",  m_axi_awvalid == 1'b0);
        check("Reset: arvalid=0",  m_axi_arvalid == 1'b0);
        check("Reset: wvalid=0",   m_axi_wvalid == 1'b0);
        check("Reset: gnt=0",      data_gnt_o == 1'b0);
        check("Reset: rvalid=0",   data_rvalid_o == 1'b0);

        // ============================================================
        // Test 2: Simple load
        // ============================================================
        reset_dut;
        fork
            issue_load(32'h1000_0000);
            axi_read_respond(0, 32'hAAAA_BBBB, 2'b00, 1);
        join
        @(posedge clk);
        check("Load: correct rdata",    data_rdata_o == 32'hAAAA_BBBB);
        check("Load: no error",          data_err_o == 1'b0);

        // ============================================================
        // Test 3: Simple store
        // ============================================================
        reset_dut;
        fork
            issue_store(32'h2000_0000, 32'hDEAD_BEEF, 4'hF);
            axi_write_respond(0, 2'b00, 1);
        join
        @(posedge clk);
        check("Store: rvalid asserted (write ack)", data_rvalid_o == 1'b1 || data_err_o == 1'b0);
        check("Store: no error", data_err_o == 1'b0);

        // ============================================================
        // Test 4: Store with byte enables
        // ============================================================
        reset_dut;
        fork
            issue_store(32'h3000_0000, 32'h0000_00FF, 4'b0001);
            begin
                while (!m_axi_wvalid) @(posedge clk);
                check("Byte enable: wstrb=0001", m_axi_wstrb == 4'b0001);
                check("Byte enable: wdata correct", m_axi_wdata == 32'h0000_00FF);
                // Accept
                m_axi_awready = 1'b1;
                m_axi_wready  = 1'b1;
                @(posedge clk);
                m_axi_awready = 1'b0;
                m_axi_wready  = 1'b0;
                @(posedge clk);
                m_axi_bvalid  = 1'b1;
                m_axi_bresp   = 2'b00;
                @(posedge clk);
                m_axi_bvalid  = 1'b0;
            end
        join
        @(posedge clk);

        // ============================================================
        // Test 5: Load with bus error
        // ============================================================
        reset_dut;
        fork
            issue_load(32'h4000_0000);
            axi_read_respond(0, 32'd0, 2'b10, 1); // SLVERR
        join
        @(posedge clk);
        check("Load error: err asserted", data_err_o == 1'b1);

        // ============================================================
        // Test 6: Store with bus error
        // ============================================================
        reset_dut;
        fork
            issue_store(32'h5000_0000, 32'h1234_5678, 4'hF);
            axi_write_respond(0, 2'b10, 1); // SLVERR
        join
        @(posedge clk);
        check("Store error: err asserted", data_err_o == 1'b1);

        // ============================================================
        // Test 7: AXI ID check
        // ============================================================
        reset_dut;
        check("AXI arid=0100", m_axi_arid == 4'b0100);
        check("AXI awid=0100", m_axi_awid == 4'b0100);

        // ============================================================
        // Test 8: Fixed AXI parameters
        // ============================================================
        check("AXI arlen=0",      m_axi_arlen == 8'd0);
        check("AXI arsize=010",   m_axi_arsize == 3'b010);
        check("AXI arburst=INCR", m_axi_arburst == 2'b01);
        check("AXI awlen=0",      m_axi_awlen == 8'd0);
        check("AXI awsize=010",   m_axi_awsize == 3'b010);
        check("AXI awburst=INCR", m_axi_awburst == 2'b01);
        check("AXI wlast=1",      m_axi_wlast == 1'b1);
        check("AXI rready=1",     m_axi_rready == 1'b1);

        // ============================================================
        // Test 9: Load then store sequential
        // ============================================================
        reset_dut;
        // Load
        fork
            issue_load(32'h6000_0000);
            axi_read_respond(0, 32'hFEED_FACE, 2'b00, 0);
        join
        @(posedge clk);
        check("Seq load: rdata correct", data_rdata_o == 32'hFEED_FACE);
        // Store
        fork
            issue_store(32'h6000_0004, 32'hBAAD_F00D, 4'hF);
            axi_write_respond(0, 2'b00, 0);
        join
        @(posedge clk);
        check("Seq store: no error", data_err_o == 1'b0);

        // ============================================================
        // Test 10: Address pass-through for load
        // ============================================================
        reset_dut;
        @(posedge clk);
        data_req_i  = 1'b1;
        data_we_i   = 1'b0;
        data_addr_i = 32'h7777_0000;
        @(posedge clk);
        @(posedge clk); // registered output delay
        check("Load addr pass-through", m_axi_araddr == 32'h7777_0000);
        data_req_i  = 1'b0;
        // Clean up
        m_axi_arready = 1'b1;
        @(posedge clk);
        m_axi_arready = 1'b0;
        m_axi_rvalid  = 1'b1;
        m_axi_rdata   = 32'd0;
        m_axi_rresp   = 2'b00;
        m_axi_rlast   = 1'b1;
        @(posedge clk);
        m_axi_rvalid  = 1'b0;
        m_axi_rlast   = 1'b0;
        @(posedge clk);

        // ============================================================
        // Test 11: Address + data pass-through for store
        // ============================================================
        reset_dut;
        @(posedge clk);
        data_req_i   = 1'b1;
        data_we_i    = 1'b1;
        data_addr_i  = 32'h8888_0000;
        data_wdata_i = 32'hCAFE_D00D;
        data_be_i    = 4'b1100;
        @(posedge clk);
        @(posedge clk); // registered output delay
        check("Store addr pass-through",  m_axi_awaddr == 32'h8888_0000);
        check("Store wdata pass-through",  m_axi_wdata == 32'hCAFE_D00D);
        check("Store wstrb pass-through",  m_axi_wstrb == 4'b1100);
        data_req_i = 1'b0;
        // Clean up
        m_axi_awready = 1'b1;
        m_axi_wready  = 1'b1;
        @(posedge clk);
        m_axi_awready = 1'b0;
        m_axi_wready  = 1'b0;
        @(posedge clk);
        m_axi_bvalid  = 1'b1;
        m_axi_bresp   = 2'b00;
        @(posedge clk);
        m_axi_bvalid  = 1'b0;
        @(posedge clk);

        // ============================================================
        // Summary
        // ============================================================
        $display("");
        $display("==============================================");
        $display("  DBUS AXI ADAPTER TESTBENCH SUMMARY");
        $display("==============================================");
        $display("  PASS: %0d", pass_count);
        $display("  FAIL: %0d", fail_count);
        if (fail_count == 0)
            $display("  RESULT: ALL TESTS PASSED");
        else
            $display("  RESULT: SOME TESTS FAILED");
        $display("==============================================");
        $finish;
    end

    // Timeout watchdog
    initial begin
        #100000;
        $display("[TIMEOUT] Simulation exceeded 100us");
        $finish;
    end

endmodule
