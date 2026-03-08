`timescale 1ns/1ps
//============================================================================
// Testbench: tb_axi_wr_mux
// Project:   AI_GLASSES — AXI Interconnect
// Description: Self-checking testbench for axi_wr_mux
//============================================================================

module tb_axi_wr_mux;

    parameter NUM_MASTERS = 5;
    parameter DATA_WIDTH  = 32;
    parameter ADDR_WIDTH  = 32;
    parameter ID_WIDTH    = 6;

    reg  clk, rst_n;
    reg  [NUM_MASTERS-1:0]              grant_i;
    reg  [NUM_MASTERS*ID_WIDTH-1:0]     m_awid_i;
    reg  [NUM_MASTERS*ADDR_WIDTH-1:0]   m_awaddr_i;
    reg  [NUM_MASTERS*8-1:0]            m_awlen_i;
    reg  [NUM_MASTERS*3-1:0]            m_awsize_i;
    reg  [NUM_MASTERS*2-1:0]            m_awburst_i;
    reg  [NUM_MASTERS-1:0]              m_awvalid_i;
    wire [NUM_MASTERS-1:0]              m_awready_o;
    reg  [NUM_MASTERS*DATA_WIDTH-1:0]   m_wdata_i;
    reg  [NUM_MASTERS*(DATA_WIDTH/8)-1:0] m_wstrb_i;
    reg  [NUM_MASTERS-1:0]              m_wlast_i;
    reg  [NUM_MASTERS-1:0]              m_wvalid_i;
    wire [NUM_MASTERS-1:0]              m_wready_o;

    wire [ID_WIDTH-1:0]    s_awid_o;
    wire [ADDR_WIDTH-1:0]  s_awaddr_o;
    wire [7:0]             s_awlen_o;
    wire [2:0]             s_awsize_o;
    wire [1:0]             s_awburst_o;
    wire                   s_awvalid_o;
    reg                    s_awready_i;
    wire [DATA_WIDTH-1:0]  s_wdata_o;
    wire [(DATA_WIDTH/8)-1:0] s_wstrb_o;
    wire                   s_wlast_o;
    wire                   s_wvalid_o;
    reg                    s_wready_i;

    integer pass_count, fail_count;

    axi_wr_mux #(
        .NUM_MASTERS(NUM_MASTERS), .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH), .ID_WIDTH(ID_WIDTH)
    ) dut (
        .clk(clk), .rst_n(rst_n), .grant_i(grant_i),
        .m_awid_i(m_awid_i), .m_awaddr_i(m_awaddr_i),
        .m_awlen_i(m_awlen_i), .m_awsize_i(m_awsize_i),
        .m_awburst_i(m_awburst_i), .m_awvalid_i(m_awvalid_i),
        .m_awready_o(m_awready_o),
        .m_wdata_i(m_wdata_i), .m_wstrb_i(m_wstrb_i),
        .m_wlast_i(m_wlast_i), .m_wvalid_i(m_wvalid_i),
        .m_wready_o(m_wready_o),
        .s_awid_o(s_awid_o), .s_awaddr_o(s_awaddr_o),
        .s_awlen_o(s_awlen_o), .s_awsize_o(s_awsize_o),
        .s_awburst_o(s_awburst_o), .s_awvalid_o(s_awvalid_o),
        .s_awready_i(s_awready_i),
        .s_wdata_o(s_wdata_o), .s_wstrb_o(s_wstrb_o),
        .s_wlast_o(s_wlast_o), .s_wvalid_o(s_wvalid_o),
        .s_wready_i(s_wready_i)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer i;
    initial begin
        $display("=== tb_axi_wr_mux START ===");
        pass_count = 0; fail_count = 0;
        rst_n = 0; grant_i = 0;
        m_awid_i = 0; m_awaddr_i = 0; m_awlen_i = 0;
        m_awsize_i = 0; m_awburst_i = 0; m_awvalid_i = 0;
        m_wdata_i = 0; m_wstrb_i = 0; m_wlast_i = 0; m_wvalid_i = 0;
        s_awready_i = 1; s_wready_i = 1;
        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Setup master 2 with specific data
        m_awid_i[2*ID_WIDTH +: ID_WIDTH]        = 6'd42;
        m_awaddr_i[2*ADDR_WIDTH +: ADDR_WIDTH]  = 32'hDEAD_BEEF;
        m_awlen_i[2*8 +: 8]                     = 8'd0;
        m_awsize_i[2*3 +: 3]                    = 3'd2;
        m_awburst_i[2*2 +: 2]                   = 2'b01;
        m_awvalid_i[2]                          = 1'b1;
        m_wdata_i[2*DATA_WIDTH +: DATA_WIDTH]   = 32'hCAFE_BABE;
        m_wstrb_i[2*(DATA_WIDTH/8) +: (DATA_WIDTH/8)] = 4'hF;
        m_wlast_i[2]                            = 1'b1;
        m_wvalid_i[2]                           = 1'b1;

        // Grant master 2
        grant_i = 5'b00100;
        repeat (3) @(posedge clk);

        // Check AW mux output
        if (s_awid_o === 6'd42 && s_awaddr_o === 32'hDEAD_BEEF && s_awvalid_o === 1'b1) begin
            pass_count = pass_count + 1;
            $display("PASS: AW mux correct for M2");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: AW mux awid=%0d addr=0x%08h valid=%b", s_awid_o, s_awaddr_o, s_awvalid_o);
        end

        // Check W mux output
        if (s_wdata_o === 32'hCAFE_BABE && s_wlast_o === 1'b1 && s_wvalid_o === 1'b1) begin
            pass_count = pass_count + 1;
            $display("PASS: W mux correct for M2");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: W mux wdata=0x%08h wlast=%b valid=%b", s_wdata_o, s_wlast_o, s_wvalid_o);
        end

        // Check ready routing
        if (m_awready_o[2] === 1'b1) begin
            pass_count = pass_count + 1;
            $display("PASS: awready routed to M2");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: m_awready_o=0x%02h", m_awready_o);
        end

        // Test no grant -> no output
        grant_i = 5'b00000;
        repeat (3) @(posedge clk);
        if (s_awvalid_o === 1'b0 && s_wvalid_o === 1'b0) begin
            pass_count = pass_count + 1;
            $display("PASS: No grant, no output");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Output still valid with no grant");
        end

        $display("=== tb_axi_wr_mux DONE ===");
        $display("PASSED: %0d  FAILED: %0d", pass_count, fail_count);
        if (fail_count == 0) $display("*** ALL TESTS PASSED ***");
        else $display("*** SOME TESTS FAILED ***");
        $finish;
    end

endmodule
