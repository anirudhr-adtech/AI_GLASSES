`timescale 1ns/1ps
//============================================================================
// Testbench: tb_axi_rd_mux
// Project:   AI_GLASSES — AXI Interconnect
// Description: Self-checking testbench for axi_rd_mux
//============================================================================

module tb_axi_rd_mux;

    parameter NUM_MASTERS = 5;
    parameter DATA_WIDTH  = 32;
    parameter ADDR_WIDTH  = 32;
    parameter ID_WIDTH    = 6;

    reg  clk, rst_n;
    reg  [NUM_MASTERS-1:0]              grant_i;
    reg  [NUM_MASTERS*ID_WIDTH-1:0]     m_arid_i;
    reg  [NUM_MASTERS*ADDR_WIDTH-1:0]   m_araddr_i;
    reg  [NUM_MASTERS*8-1:0]            m_arlen_i;
    reg  [NUM_MASTERS*3-1:0]            m_arsize_i;
    reg  [NUM_MASTERS*2-1:0]            m_arburst_i;
    reg  [NUM_MASTERS-1:0]              m_arvalid_i;
    wire [NUM_MASTERS-1:0]              m_arready_o;

    wire [ID_WIDTH-1:0]    s_arid_o;
    wire [ADDR_WIDTH-1:0]  s_araddr_o;
    wire [7:0]             s_arlen_o;
    wire [2:0]             s_arsize_o;
    wire [1:0]             s_arburst_o;
    wire                   s_arvalid_o;
    reg                    s_arready_i;

    integer pass_count, fail_count;

    axi_rd_mux #(
        .NUM_MASTERS(NUM_MASTERS), .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH), .ID_WIDTH(ID_WIDTH)
    ) dut (
        .clk(clk), .rst_n(rst_n), .grant_i(grant_i),
        .m_arid_i(m_arid_i), .m_araddr_i(m_araddr_i),
        .m_arlen_i(m_arlen_i), .m_arsize_i(m_arsize_i),
        .m_arburst_i(m_arburst_i), .m_arvalid_i(m_arvalid_i),
        .m_arready_o(m_arready_o),
        .s_arid_o(s_arid_o), .s_araddr_o(s_araddr_o),
        .s_arlen_o(s_arlen_o), .s_arsize_o(s_arsize_o),
        .s_arburst_o(s_arburst_o), .s_arvalid_o(s_arvalid_o),
        .s_arready_i(s_arready_i)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $display("=== tb_axi_rd_mux START ===");
        pass_count = 0; fail_count = 0;
        rst_n = 0; grant_i = 0;
        m_arid_i = 0; m_araddr_i = 0; m_arlen_i = 0;
        m_arsize_i = 0; m_arburst_i = 0; m_arvalid_i = 0;
        s_arready_i = 1;
        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Setup master 1
        m_arid_i[1*ID_WIDTH +: ID_WIDTH]       = 6'd17;
        m_araddr_i[1*ADDR_WIDTH +: ADDR_WIDTH] = 32'h8000_1000;
        m_arlen_i[1*8 +: 8]                    = 8'd15;
        m_arsize_i[1*3 +: 3]                   = 3'd2;
        m_arburst_i[1*2 +: 2]                  = 2'b01;
        m_arvalid_i[1]                         = 1'b1;

        // Grant master 1
        grant_i = 5'b00010;
        repeat (3) @(posedge clk);

        if (s_arid_o === 6'd17 && s_araddr_o === 32'h8000_1000 && s_arlen_o === 8'd15) begin
            pass_count = pass_count + 1;
            $display("PASS: AR mux correct for M1");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: AR mux arid=%0d araddr=0x%08h arlen=%0d", s_arid_o, s_araddr_o, s_arlen_o);
        end

        if (m_arready_o[1] === 1'b1) begin
            pass_count = pass_count + 1;
            $display("PASS: arready routed to M1");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: m_arready_o=0x%02h", m_arready_o);
        end

        // Switch grant to M4
        m_arid_i[4*ID_WIDTH +: ID_WIDTH]       = 6'd33;
        m_araddr_i[4*ADDR_WIDTH +: ADDR_WIDTH] = 32'hA000_0000;
        m_arlen_i[4*8 +: 8]                    = 8'd7;
        m_arvalid_i[4]                         = 1'b1;
        grant_i = 5'b10000;
        repeat (3) @(posedge clk);

        if (s_arid_o === 6'd33 && s_araddr_o === 32'hA000_0000) begin
            pass_count = pass_count + 1;
            $display("PASS: AR mux switched to M4");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: AR mux after switch arid=%0d", s_arid_o);
        end

        $display("=== tb_axi_rd_mux DONE ===");
        $display("PASSED: %0d  FAILED: %0d", pass_count, fail_count);
        if (fail_count == 0) $display("*** ALL TESTS PASSED ***");
        else $display("*** SOME TESTS FAILED ***");
        $finish;
    end

endmodule
