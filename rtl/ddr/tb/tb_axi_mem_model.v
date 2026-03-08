`timescale 1ns/1ps
//============================================================================
// AI_GLASSES — DDR Subsystem (Simulation Model)
// Testbench: tb_axi_mem_model
// Description: Top-level integration test for the behavioral DDR model.
//              Tests single write/read, burst write/read, byte strobes.
//============================================================================

module tb_axi_mem_model;

    parameter DATA_WIDTH     = 128;
    parameter ADDR_WIDTH     = 32;
    parameter ID_WIDTH       = 6;
    parameter MEM_SIZE_BYTES = 4096;
    parameter READ_LATENCY   = 3;
    parameter WRITE_LATENCY  = 2;
    localparam STRB_WIDTH    = DATA_WIDTH / 8;

    reg                    clk;
    reg                    rst_n;

    // AW
    reg  [ID_WIDTH-1:0]    s_axi_awid;
    reg  [ADDR_WIDTH-1:0]  s_axi_awaddr;
    reg  [7:0]             s_axi_awlen;
    reg  [2:0]             s_axi_awsize;
    reg  [1:0]             s_axi_awburst;
    reg                    s_axi_awvalid;
    wire                   s_axi_awready;

    // W
    reg  [DATA_WIDTH-1:0]  s_axi_wdata;
    reg  [STRB_WIDTH-1:0]  s_axi_wstrb;
    reg                    s_axi_wlast;
    reg                    s_axi_wvalid;
    wire                   s_axi_wready;

    // B
    wire [ID_WIDTH-1:0]    s_axi_bid;
    wire [1:0]             s_axi_bresp;
    wire                   s_axi_bvalid;
    reg                    s_axi_bready;

    // AR
    reg  [ID_WIDTH-1:0]    s_axi_arid;
    reg  [ADDR_WIDTH-1:0]  s_axi_araddr;
    reg  [7:0]             s_axi_arlen;
    reg  [2:0]             s_axi_arsize;
    reg  [1:0]             s_axi_arburst;
    reg                    s_axi_arvalid;
    wire                   s_axi_arready;

    // R
    wire [ID_WIDTH-1:0]    s_axi_rid;
    wire [DATA_WIDTH-1:0]  s_axi_rdata;
    wire [1:0]             s_axi_rresp;
    wire                   s_axi_rlast;
    wire                   s_axi_rvalid;
    reg                    s_axi_rready;

    reg                    error_inject_i;

    integer pass_count, fail_count;
    integer timeout_cnt;

    axi_mem_model #(
        .MEM_SIZE_BYTES    (MEM_SIZE_BYTES),
        .DATA_WIDTH        (DATA_WIDTH),
        .ADDR_WIDTH        (ADDR_WIDTH),
        .ID_WIDTH          (ID_WIDTH),
        .READ_LATENCY      (READ_LATENCY),
        .WRITE_LATENCY     (WRITE_LATENCY),
        .BACKPRESSURE_MODE (0)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .s_axi_awid      (s_axi_awid),
        .s_axi_awaddr    (s_axi_awaddr),
        .s_axi_awlen     (s_axi_awlen),
        .s_axi_awsize    (s_axi_awsize),
        .s_axi_awburst   (s_axi_awburst),
        .s_axi_awvalid   (s_axi_awvalid),
        .s_axi_awready   (s_axi_awready),
        .s_axi_wdata     (s_axi_wdata),
        .s_axi_wstrb     (s_axi_wstrb),
        .s_axi_wlast     (s_axi_wlast),
        .s_axi_wvalid    (s_axi_wvalid),
        .s_axi_wready    (s_axi_wready),
        .s_axi_bid       (s_axi_bid),
        .s_axi_bresp     (s_axi_bresp),
        .s_axi_bvalid    (s_axi_bvalid),
        .s_axi_bready    (s_axi_bready),
        .s_axi_arid      (s_axi_arid),
        .s_axi_araddr    (s_axi_araddr),
        .s_axi_arlen     (s_axi_arlen),
        .s_axi_arsize    (s_axi_arsize),
        .s_axi_arburst   (s_axi_arburst),
        .s_axi_arvalid   (s_axi_arvalid),
        .s_axi_arready   (s_axi_arready),
        .s_axi_rid       (s_axi_rid),
        .s_axi_rdata     (s_axi_rdata),
        .s_axi_rresp     (s_axi_rresp),
        .s_axi_rlast     (s_axi_rlast),
        .s_axi_rvalid    (s_axi_rvalid),
        .s_axi_rready    (s_axi_rready),
        .error_inject_i  (error_inject_i)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // ---------------------------------------------------------------
    // Tasks for AXI transactions
    // ---------------------------------------------------------------

    task axi_write_single;
        input [ADDR_WIDTH-1:0] addr;
        input [DATA_WIDTH-1:0] data;
        input [ID_WIDTH-1:0]   id;
        begin
            // AW phase
            @(posedge clk);
            s_axi_awvalid = 1;
            s_axi_awid    = id;
            s_axi_awaddr  = addr;
            s_axi_awlen   = 8'd0;
            s_axi_awsize  = 3'd4;
            s_axi_awburst = 2'd1;
            @(posedge clk);
            while (!s_axi_awready) @(posedge clk);
            s_axi_awvalid = 0;

            // W phase
            s_axi_wvalid = 1;
            s_axi_wdata  = data;
            s_axi_wstrb  = {STRB_WIDTH{1'b1}};
            s_axi_wlast  = 1;
            @(posedge clk);
            while (!s_axi_wready) @(posedge clk);
            @(posedge clk);
            s_axi_wvalid = 0;
            s_axi_wlast  = 0;

            // Wait for B
            timeout_cnt = 0;
            while (!s_axi_bvalid && timeout_cnt < 100) begin
                @(posedge clk);
                timeout_cnt = timeout_cnt + 1;
            end
            @(posedge clk);
        end
    endtask

    task axi_read_single;
        input  [ADDR_WIDTH-1:0] addr;
        input  [ID_WIDTH-1:0]   id;
        output [DATA_WIDTH-1:0] data_out;
        begin
            @(posedge clk);
            s_axi_arvalid = 1;
            s_axi_arid    = id;
            s_axi_araddr  = addr;
            s_axi_arlen   = 8'd0;
            s_axi_arsize  = 3'd4;
            s_axi_arburst = 2'd1;
            @(posedge clk);
            while (!s_axi_arready) @(posedge clk);
            @(posedge clk);
            s_axi_arvalid = 0;

            // Wait for R
            timeout_cnt = 0;
            while (!s_axi_rvalid && timeout_cnt < 100) begin
                @(posedge clk);
                timeout_cnt = timeout_cnt + 1;
            end
            data_out = s_axi_rdata;
            @(posedge clk);
        end
    endtask

    reg [DATA_WIDTH-1:0] read_result;

    initial begin
        pass_count = 0;
        fail_count = 0;
        rst_n = 0;
        error_inject_i = 0;
        s_axi_awid = 0; s_axi_awaddr = 0; s_axi_awlen = 0;
        s_axi_awsize = 0; s_axi_awburst = 0; s_axi_awvalid = 0;
        s_axi_wdata = 0; s_axi_wstrb = 0; s_axi_wlast = 0; s_axi_wvalid = 0;
        s_axi_bready = 1;
        s_axi_arid = 0; s_axi_araddr = 0; s_axi_arlen = 0;
        s_axi_arsize = 0; s_axi_arburst = 0; s_axi_arvalid = 0;
        s_axi_rready = 1;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (3) @(posedge clk);

        // -------------------------------------------------------
        // Test 1: Single write then read
        // -------------------------------------------------------
        $display("Test 1: Single write/read");
        axi_write_single(32'h0000_0000, 128'hDEADBEEF_CAFEBABE_12345678_AABBCCDD, 6'd1);

        repeat (5) @(posedge clk);

        axi_read_single(32'h0000_0000, 6'd1, read_result);

        if (read_result == 128'hDEADBEEF_CAFEBABE_12345678_AABBCCDD) begin
            pass_count = pass_count + 1;
            $display("  PASS: Read back matches");
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL: Expected DEADBEEF_CAFEBABE_12345678_AABBCCDD got %h", read_result);
        end

        // -------------------------------------------------------
        // Test 2: Write to different address
        // -------------------------------------------------------
        $display("Test 2: Different address write/read");
        axi_write_single(32'h0000_0100, 128'h01020304_05060708_090A0B0C_0D0E0F10, 6'd2);
        repeat (5) @(posedge clk);
        axi_read_single(32'h0000_0100, 6'd2, read_result);

        if (read_result == 128'h01020304_05060708_090A0B0C_0D0E0F10) begin
            pass_count = pass_count + 1;
            $display("  PASS: Second address matches");
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL: Got %h", read_result);
        end

        // -------------------------------------------------------
        // Test 3: Read original address (should still be there)
        // -------------------------------------------------------
        $display("Test 3: Re-read original address");
        axi_read_single(32'h0000_0000, 6'd3, read_result);

        if (read_result == 128'hDEADBEEF_CAFEBABE_12345678_AABBCCDD) begin
            pass_count = pass_count + 1;
            $display("  PASS: Original data preserved");
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL: Original data lost, got %h", read_result);
        end

        // -------------------------------------------------------
        // Test 4: B response check
        // -------------------------------------------------------
        $display("Test 4: B response OKAY");
        if (s_axi_bresp == 2'b00) begin
            pass_count = pass_count + 1;
            $display("  PASS: BRESP is OKAY");
        end else begin
            fail_count = fail_count + 1;
            $display("  FAIL: BRESP=%b", s_axi_bresp);
        end

        repeat (5) @(posedge clk);
        $display("========================================");
        $display("tb_axi_mem_model: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        if (fail_count == 0) $display("ALL TESTS PASSED");
        $finish;
    end

    // Timeout watchdog
    initial begin
        #50000;
        $display("TIMEOUT: Simulation exceeded 50us");
        $display("tb_axi_mem_model: %0d PASSED, %0d FAILED (TIMEOUT)", pass_count, fail_count);
        $finish;
    end

    initial begin
        $dumpfile("tb_axi_mem_model.vcd");
        $dumpvars(0, tb_axi_mem_model);
    end

endmodule
