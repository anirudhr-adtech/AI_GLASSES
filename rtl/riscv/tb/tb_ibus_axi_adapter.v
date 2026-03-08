`timescale 1ns/1ps
//============================================================================
// Module : tb_ibus_axi_adapter
// Project : AI_GLASSES — RISC-V Subsystem
// Description : Self-checking testbench for ibus_axi_adapter
//============================================================================

module tb_ibus_axi_adapter;

    reg        clk;
    reg        rst_n;

    // Ibex side
    reg        instr_req_i;
    wire       instr_gnt_o;
    wire       instr_rvalid_o;
    reg [31:0] instr_addr_i;
    wire [31:0] instr_rdata_o;
    wire       instr_err_o;

    // AXI side
    wire       m_axi_arvalid;
    reg        m_axi_arready;
    wire [31:0] m_axi_araddr;
    wire [7:0] m_axi_arlen;
    wire [2:0] m_axi_arsize;
    wire [1:0] m_axi_arburst;
    wire [3:0] m_axi_arid;

    reg        m_axi_rvalid;
    wire       m_axi_rready;
    reg [31:0] m_axi_rdata;
    reg [1:0]  m_axi_rresp;
    reg [3:0]  m_axi_rid;
    reg        m_axi_rlast;

    // Counters
    integer pass_count;
    integer fail_count;

    ibus_axi_adapter uut (
        .clk             (clk),
        .rst_n           (rst_n),
        .instr_req_i     (instr_req_i),
        .instr_gnt_o     (instr_gnt_o),
        .instr_rvalid_o  (instr_rvalid_o),
        .instr_addr_i    (instr_addr_i),
        .instr_rdata_o   (instr_rdata_o),
        .instr_err_o     (instr_err_o),
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

    // Helper tasks
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
            rst_n        = 1'b0;
            instr_req_i  = 1'b0;
            instr_addr_i = 32'd0;
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

    // Issue a single fetch request (pulse for 1 cycle)
    task issue_fetch;
        input [31:0] addr;
        begin
            @(posedge clk);
            instr_req_i  = 1'b1;
            instr_addr_i = addr;
            @(posedge clk);
            instr_req_i  = 1'b0;
        end
    endtask

    // AXI slave: accept AR after delay cycles, then return rdata after delay
    task axi_respond;
        input integer ar_delay;
        input [31:0]  rdata;
        input [1:0]   rresp;
        input integer r_delay;
        integer i;
        begin
            // Wait for arvalid
            while (!m_axi_arvalid) @(posedge clk);
            // AR delay
            for (i = 0; i < ar_delay; i = i + 1) @(posedge clk);
            m_axi_arready = 1'b1;
            @(posedge clk);
            m_axi_arready = 1'b0;
            // R delay
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

    initial begin
        $dumpfile("tb_ibus_axi_adapter.vcd");
        $dumpvars(0, tb_ibus_axi_adapter);

        pass_count = 0;
        fail_count = 0;

        // ============================================================
        // Test 1: Reset values
        // ============================================================
        reset_dut;
        check("Reset: arvalid deasserted", m_axi_arvalid == 1'b0);
        check("Reset: gnt deasserted",     instr_gnt_o == 1'b0);
        check("Reset: rvalid deasserted",  instr_rvalid_o == 1'b0);

        // ============================================================
        // Test 2: Single fetch, immediate AR accept
        // ============================================================
        reset_dut;
        fork
            issue_fetch(32'h0000_1000);
            axi_respond(0, 32'hDEAD_BEEF, 2'b00, 1);
        join
        @(posedge clk);
        check("Single fetch: correct rdata", instr_rdata_o == 32'hDEAD_BEEF);
        check("Single fetch: no error",      instr_err_o == 1'b0);

        // ============================================================
        // Test 3: Single fetch with AR delay
        // ============================================================
        reset_dut;
        fork
            issue_fetch(32'h0000_2000);
            axi_respond(2, 32'hCAFE_BABE, 2'b00, 2);
        join
        @(posedge clk);
        check("Delayed AR: correct rdata", instr_rdata_o == 32'hCAFE_BABE);

        // ============================================================
        // Test 4: Bus error response
        // ============================================================
        reset_dut;
        fork
            issue_fetch(32'h0000_3000);
            axi_respond(0, 32'h0000_0000, 2'b10, 1); // SLVERR
        join
        @(posedge clk);
        check("Bus error: err asserted", instr_err_o == 1'b1);

        // ============================================================
        // Test 5: Fixed AXI parameters
        // ============================================================
        reset_dut;
        check("AXI arlen=0",        m_axi_arlen == 8'd0);
        check("AXI arsize=010",     m_axi_arsize == 3'b010);
        check("AXI arburst=INCR",   m_axi_arburst == 2'b01);
        check("AXI rready=1",       m_axi_rready == 1'b1);

        // ============================================================
        // Test 6: Address pass-through
        // ============================================================
        reset_dut;
        @(posedge clk);
        instr_req_i  = 1'b1;
        instr_addr_i = 32'hABCD_EF00;
        @(posedge clk);
        @(posedge clk); // registered output
        check("Addr pass-through", m_axi_araddr == 32'hABCD_EF00);
        instr_req_i = 1'b0;
        // Clean up: accept the outstanding AR and R
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
        // Test 7: Back-to-back fetches (pipelined)
        // ============================================================
        reset_dut;
        fork
            begin
                // Issue two fetches back-to-back
                @(posedge clk);
                instr_req_i  = 1'b1;
                instr_addr_i = 32'h0000_4000;
                @(posedge clk);
                instr_addr_i = 32'h0000_4004;
                @(posedge clk);
                instr_req_i  = 1'b0;
            end
            begin
                // Respond to first
                axi_respond(0, 32'h1111_1111, 2'b00, 1);
                // Respond to second
                axi_respond(0, 32'h2222_2222, 2'b00, 1);
            end
        join
        @(posedge clk);
        check("Pipeline: second rdata correct", instr_rdata_o == 32'h2222_2222);

        // ============================================================
        // Summary
        // ============================================================
        $display("");
        $display("==============================================");
        $display("  IBUS AXI ADAPTER TESTBENCH SUMMARY");
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
        #50000;
        $display("[TIMEOUT] Simulation exceeded 50us");
        $finish;
    end

endmodule
