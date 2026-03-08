`timescale 1ns/1ps
//============================================================================
// Testbench: tb_axi_resp_demux
// Project:   AI_GLASSES — AXI Interconnect
// Description: Self-checking testbench for axi_resp_demux
//============================================================================

module tb_axi_resp_demux;

    parameter NUM_MASTERS = 5;
    parameter DATA_WIDTH  = 32;
    parameter ID_WIDTH    = 6;

    reg  clk, rst_n;
    reg  [ID_WIDTH-1:0]    s_bid_i, s_rid_i;
    reg  [1:0]             s_bresp_i, s_rresp_i;
    reg                    s_bvalid_i, s_rvalid_i;
    wire                   s_bready_o, s_rready_o;
    reg  [DATA_WIDTH-1:0]  s_rdata_i;
    reg                    s_rlast_i;

    wire [NUM_MASTERS*ID_WIDTH-1:0]   m_bid_o, m_rid_o;
    wire [NUM_MASTERS*2-1:0]          m_bresp_o, m_rresp_o;
    wire [NUM_MASTERS-1:0]            m_bvalid_o, m_rvalid_o, m_rlast_o;
    wire [NUM_MASTERS*DATA_WIDTH-1:0] m_rdata_o;
    reg  [NUM_MASTERS-1:0]            m_bready_i, m_rready_i;

    integer pass_count, fail_count;

    axi_resp_demux #(
        .NUM_MASTERS(NUM_MASTERS), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .s_bid_i(s_bid_i), .s_bresp_i(s_bresp_i),
        .s_bvalid_i(s_bvalid_i), .s_bready_o(s_bready_o),
        .s_rid_i(s_rid_i), .s_rdata_i(s_rdata_i),
        .s_rresp_i(s_rresp_i), .s_rlast_i(s_rlast_i),
        .s_rvalid_i(s_rvalid_i), .s_rready_o(s_rready_o),
        .m_bid_o(m_bid_o), .m_bresp_o(m_bresp_o),
        .m_bvalid_o(m_bvalid_o), .m_bready_i(m_bready_i),
        .m_rid_o(m_rid_o), .m_rdata_o(m_rdata_o),
        .m_rresp_o(m_rresp_o), .m_rlast_o(m_rlast_o),
        .m_rvalid_o(m_rvalid_o), .m_rready_i(m_rready_i)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task check_b_route;
        input [ID_WIDTH-1:0] id;
        input integer exp_master;
        begin
            s_bid_i = id; s_bresp_i = 2'b00; s_bvalid_i = 1;
            @(posedge clk); @(posedge clk);
            if (m_bvalid_o[exp_master] === 1'b1) begin
                pass_count = pass_count + 1;
                $display("PASS: B response routed to M%0d (id=%0d)", exp_master, id);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: B response bvalid=0x%02h exp M%0d (id=%0d)", m_bvalid_o, exp_master, id);
            end
            s_bvalid_i = 0;
            @(posedge clk);
        end
    endtask

    task check_r_route;
        input [ID_WIDTH-1:0] id;
        input [DATA_WIDTH-1:0] data;
        input integer exp_master;
        begin
            s_rid_i = id; s_rdata_i = data; s_rresp_i = 2'b00;
            s_rlast_i = 1; s_rvalid_i = 1;
            @(posedge clk); @(posedge clk);
            if (m_rvalid_o[exp_master] === 1'b1 &&
                m_rdata_o[exp_master*DATA_WIDTH +: DATA_WIDTH] === data) begin
                pass_count = pass_count + 1;
                $display("PASS: R response routed to M%0d data=0x%08h", exp_master, data);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: R response rvalid=0x%02h exp M%0d", m_rvalid_o, exp_master);
            end
            s_rvalid_i = 0;
            @(posedge clk);
        end
    endtask

    initial begin
        $display("=== tb_axi_resp_demux START ===");
        pass_count = 0; fail_count = 0;
        rst_n = 0;
        s_bid_i = 0; s_bresp_i = 0; s_bvalid_i = 0;
        s_rid_i = 0; s_rdata_i = 0; s_rresp_i = 0;
        s_rlast_i = 0; s_rvalid_i = 0;
        m_bready_i = {NUM_MASTERS{1'b1}};
        m_rready_i = {NUM_MASTERS{1'b1}};
        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // ID prefix routing: top 3 bits
        // 000xxx -> M0, 001xxx -> M1, 010xxx -> M2, 011xxx -> M3, 100xxx -> M4
        check_b_route(6'b000_001, 0);  // M0
        check_b_route(6'b001_010, 1);  // M1
        check_b_route(6'b010_011, 2);  // M2
        check_b_route(6'b011_100, 3);  // M3
        check_b_route(6'b100_101, 4);  // M4

        // R channel routing
        check_r_route(6'b000_000, 32'hAAAA_BBBB, 0);
        check_r_route(6'b010_111, 32'hCCCC_DDDD, 2);
        check_r_route(6'b100_000, 32'h1234_5678, 4);

        $display("=== tb_axi_resp_demux DONE ===");
        $display("PASSED: %0d  FAILED: %0d", pass_count, fail_count);
        if (fail_count == 0) $display("*** ALL TESTS PASSED ***");
        else $display("*** SOME TESTS FAILED ***");
        $finish;
    end

endmodule
