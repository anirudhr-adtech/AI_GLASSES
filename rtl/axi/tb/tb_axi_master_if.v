`timescale 1ns/1ps
//============================================================================
// Testbench: tb_axi_master_if
// Project:   AI_GLASSES — AXI Interconnect
// Description: Self-checking testbench for axi_master_if
//============================================================================

module tb_axi_master_if;

    parameter IW = 6;
    parameter AW = 32;
    parameter DW = 32;

    reg  clk, rst_n;

    // External master
    reg  [2:0]    ext_awid, ext_arid;
    reg  [AW-1:0] ext_awaddr, ext_araddr;
    reg  [7:0]    ext_awlen, ext_arlen;
    reg  [2:0]    ext_awsize, ext_arsize;
    reg  [1:0]    ext_awburst, ext_arburst;
    reg           ext_awvalid, ext_arvalid;
    wire          ext_awready, ext_arready;
    reg  [DW-1:0] ext_wdata;
    reg  [3:0]    ext_wstrb;
    reg           ext_wlast, ext_wvalid;
    wire          ext_wready;
    wire [2:0]    ext_bid, ext_rid;
    wire [1:0]    ext_bresp, ext_rresp;
    wire          ext_bvalid, ext_rvalid, ext_rlast;
    wire [DW-1:0] ext_rdata;
    reg           ext_bready, ext_rready;

    // Internal crossbar
    wire [IW-1:0]  int_awid, int_arid;
    wire [AW-1:0]  int_awaddr, int_araddr;
    wire [7:0]     int_awlen, int_arlen;
    wire [2:0]     int_awsize, int_arsize;
    wire [1:0]     int_awburst, int_arburst;
    wire           int_awvalid, int_arvalid;
    reg            int_awready, int_arready;
    wire [DW-1:0]  int_wdata;
    wire [3:0]     int_wstrb;
    wire           int_wlast, int_wvalid;
    reg            int_wready;
    reg  [IW-1:0]  int_bid, int_rid;
    reg  [1:0]     int_bresp, int_rresp;
    reg            int_bvalid, int_rvalid;
    wire           int_bready, int_rready;
    reg  [DW-1:0]  int_rdata;
    reg            int_rlast;

    wire [4:0] slave_sel;
    wire       addr_error;

    integer pass_count, fail_count;

    axi_master_if #(
        .MASTER_ID(2), .NUM_SLAVES(5), .DATA_WIDTH(DW),
        .ADDR_WIDTH(AW), .ID_WIDTH(IW), .OUTSTANDING(4)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .ext_awid(ext_awid), .ext_awaddr(ext_awaddr), .ext_awlen(ext_awlen),
        .ext_awsize(ext_awsize), .ext_awburst(ext_awburst),
        .ext_awvalid(ext_awvalid), .ext_awready(ext_awready),
        .ext_wdata(ext_wdata), .ext_wstrb(ext_wstrb),
        .ext_wlast(ext_wlast), .ext_wvalid(ext_wvalid), .ext_wready(ext_wready),
        .ext_bid(ext_bid), .ext_bresp(ext_bresp),
        .ext_bvalid(ext_bvalid), .ext_bready(ext_bready),
        .ext_arid(ext_arid), .ext_araddr(ext_araddr), .ext_arlen(ext_arlen),
        .ext_arsize(ext_arsize), .ext_arburst(ext_arburst),
        .ext_arvalid(ext_arvalid), .ext_arready(ext_arready),
        .ext_rid(ext_rid), .ext_rdata(ext_rdata),
        .ext_rresp(ext_rresp), .ext_rlast(ext_rlast),
        .ext_rvalid(ext_rvalid), .ext_rready(ext_rready),
        .int_awid(int_awid), .int_awaddr(int_awaddr), .int_awlen(int_awlen),
        .int_awsize(int_awsize), .int_awburst(int_awburst),
        .int_awvalid(int_awvalid), .int_awready(int_awready),
        .int_wdata(int_wdata), .int_wstrb(int_wstrb),
        .int_wlast(int_wlast), .int_wvalid(int_wvalid), .int_wready(int_wready),
        .int_bid(int_bid), .int_bresp(int_bresp),
        .int_bvalid(int_bvalid), .int_bready(int_bready),
        .int_arid(int_arid), .int_araddr(int_araddr), .int_arlen(int_arlen),
        .int_arsize(int_arsize), .int_arburst(int_arburst),
        .int_arvalid(int_arvalid), .int_arready(int_arready),
        .int_rid(int_rid), .int_rdata(int_rdata),
        .int_rresp(int_rresp), .int_rlast(int_rlast),
        .int_rvalid(int_rvalid), .int_rready(int_rready),
        .slave_sel_o(slave_sel), .addr_error_o(addr_error)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $display("=== tb_axi_master_if START ===");
        pass_count = 0; fail_count = 0;
        rst_n = 0;
        ext_awid = 0; ext_awaddr = 0; ext_awlen = 0; ext_awsize = 0; ext_awburst = 0; ext_awvalid = 0;
        ext_wdata = 0; ext_wstrb = 0; ext_wlast = 0; ext_wvalid = 0;
        ext_arid = 0; ext_araddr = 0; ext_arlen = 0; ext_arsize = 0; ext_arburst = 0; ext_arvalid = 0;
        ext_bready = 1; ext_rready = 1;
        int_awready = 1; int_wready = 1; int_arready = 1;
        int_bid = 0; int_bresp = 0; int_bvalid = 0;
        int_rid = 0; int_rdata = 0; int_rresp = 0; int_rlast = 0; int_rvalid = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // Test ID prefix insertion: MASTER_ID=2 -> prefix=3'b010
        ext_awid = 3'b101; ext_awaddr = 32'h8000_0000;
        ext_awlen = 0; ext_awsize = 3'd2; ext_awburst = 2'b01;
        ext_awvalid = 1;

        wait (int_awvalid);
        @(posedge clk);
        // ID should be {3'b010, 3'b101} = 6'b010_101 = 6'd21
        if (int_awid === 6'b010_101) begin
            pass_count = pass_count + 1;
            $display("PASS: ID prefix insertion correct: int_awid=6'b%b", int_awid);
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: ID prefix exp=6'b010101 got=6'b%b", int_awid);
        end
        ext_awvalid = 0;

        // Test address decode: 0x8000_0000 -> S3 (DDR)
        repeat (3) @(posedge clk);
        if (slave_sel[3] === 1'b1) begin
            pass_count = pass_count + 1;
            $display("PASS: Address decoded to S3 (DDR)");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: slave_sel=0x%02h (exp S3)", slave_sel);
        end

        // Test B response ID stripping
        int_bid = 6'b010_101; int_bresp = 2'b00; int_bvalid = 1;
        wait (ext_bvalid);
        @(posedge clk);
        if (ext_bid === 3'b101) begin
            pass_count = pass_count + 1;
            $display("PASS: B response ID stripped correctly");
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: ext_bid=%b (exp 101)", ext_bid);
        end
        int_bvalid = 0;

        repeat (5) @(posedge clk);
        $display("=== tb_axi_master_if DONE ===");
        $display("PASSED: %0d  FAILED: %0d", pass_count, fail_count);
        if (fail_count == 0) $display("*** ALL TESTS PASSED ***");
        else $display("*** SOME TESTS FAILED ***");
        $finish;
    end

endmodule
