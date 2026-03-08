`timescale 1ns/1ps
//============================================================================
// Testbench: tb_axi_error_slave
// Project:   AI_GLASSES — AXI Interconnect
// Description: Self-checking testbench for axi_error_slave
//============================================================================

module tb_axi_error_slave;

    parameter DATA_WIDTH = 32;
    parameter ID_WIDTH   = 6;

    reg                    clk, rst_n;
    reg  [ID_WIDTH-1:0]    awid, arid;
    reg  [31:0]            awaddr, araddr;
    reg  [7:0]             awlen, arlen;
    reg  [2:0]             awsize, arsize;
    reg  [1:0]             awburst, arburst;
    reg                    awvalid, arvalid;
    wire                   awready, arready;
    reg  [DATA_WIDTH-1:0]  wdata;
    reg  [DATA_WIDTH/8-1:0] wstrb;
    reg                    wlast, wvalid;
    wire                   wready;
    wire [ID_WIDTH-1:0]    bid, rid;
    wire [1:0]             bresp, rresp;
    wire                   bvalid, rvalid, rlast;
    wire [DATA_WIDTH-1:0]  rdata;
    reg                    bready, rready;

    integer pass_count, fail_count;

    axi_error_slave #(
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awid(awid), .s_axi_awaddr(awaddr), .s_axi_awlen(awlen),
        .s_axi_awsize(awsize), .s_axi_awburst(awburst),
        .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb),
        .s_axi_wlast(wlast), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bid(bid), .s_axi_bresp(bresp),
        .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_arid(arid), .s_axi_araddr(araddr), .s_axi_arlen(arlen),
        .s_axi_arsize(arsize), .s_axi_arburst(arburst),
        .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rid(rid), .s_axi_rdata(rdata),
        .s_axi_rresp(rresp), .s_axi_rlast(rlast),
        .s_axi_rvalid(rvalid), .s_axi_rready(rready)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task axi_write;
        input [ID_WIDTH-1:0] id;
        input [7:0] len;
        integer i;
        begin
            @(posedge clk);
            awid = id; awaddr = 32'h5000_0000; awlen = len;
            awsize = 3'd2; awburst = 2'b01; awvalid = 1;
            wait (awready && awvalid);
            @(posedge clk);
            awvalid = 0;
            // Send W beats
            for (i = 0; i <= len; i = i + 1) begin
                wdata = i; wstrb = 4'hF;
                wlast = (i == len) ? 1'b1 : 1'b0;
                wvalid = 1;
                wait (wready && wvalid);
                @(posedge clk);
            end
            wvalid = 0;
            // Wait for B
            bready = 1;
            wait (bvalid);
            @(posedge clk);
            if (bresp === 2'b11 && bid === id) begin
                pass_count = pass_count + 1;
                $display("PASS: Write DECERR, id=%0d len=%0d", id, len);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: Write bresp=%b bid=%0d (exp DECERR, id=%0d)", bresp, bid, id);
            end
            bready = 0;
        end
    endtask

    task axi_read;
        input [ID_WIDTH-1:0] id;
        input [7:0] len;
        integer i;
        integer beats;
        reg [1:0] sampled_rresp;
        reg       sampled_rlast;
        begin
            @(posedge clk);
            arid = id; araddr = 32'hDEAD_BEEF; arlen = len;
            arsize = 3'd2; arburst = 2'b01; arvalid = 1;
            wait (arready && arvalid);
            @(posedge clk);
            arvalid = 0;
            // Receive R beats
            rready = 1;
            beats = 0;
            while (beats <= len) begin
                wait (rvalid);
                sampled_rlast = rlast;
                sampled_rresp = rresp;
                @(posedge clk);
                if (sampled_rresp !== 2'b11) begin
                    fail_count = fail_count + 1;
                    $display("FAIL: Read beat %0d rresp=%b (exp DECERR)", beats, sampled_rresp);
                end
                if (beats == len) begin
                    if (sampled_rlast !== 1'b1) begin
                        fail_count = fail_count + 1;
                        $display("FAIL: RLAST not set on last beat %0d", beats);
                    end
                end
                beats = beats + 1;
            end
            rready = 0;
            if (rid === id) begin
                pass_count = pass_count + 1;
                $display("PASS: Read DECERR, id=%0d len=%0d", id, len);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: Read rid=%0d (exp %0d)", rid, id);
            end
        end
    endtask

    initial begin
        $display("=== tb_axi_error_slave START ===");
        pass_count = 0; fail_count = 0;
        rst_n = 0; awvalid = 0; wvalid = 0; arvalid = 0;
        bready = 0; rready = 0; wlast = 0;
        awid = 0; arid = 0; awaddr = 0; araddr = 0;
        awlen = 0; arlen = 0; awsize = 0; arsize = 0;
        awburst = 0; arburst = 0; wdata = 0; wstrb = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // Single-beat write
        axi_write(6'd5, 8'd0);
        repeat (2) @(posedge clk);

        // Burst write (len=3, 4 beats)
        axi_write(6'd10, 8'd3);
        repeat (2) @(posedge clk);

        // Single-beat read
        axi_read(6'd7, 8'd0);
        repeat (2) @(posedge clk);

        // Burst read (len=3, 4 beats)
        axi_read(6'd15, 8'd3);
        repeat (2) @(posedge clk);

        $display("=== tb_axi_error_slave DONE ===");
        $display("PASSED: %0d  FAILED: %0d", pass_count, fail_count);
        if (fail_count == 0) $display("*** ALL TESTS PASSED ***");
        else $display("*** SOME TESTS FAILED ***");
        $finish;
    end

endmodule
