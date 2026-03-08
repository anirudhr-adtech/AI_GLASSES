`timescale 1ns/1ps
//============================================================================
// AI_GLASSES — DDR Subsystem (Simulation Model)
// Testbench: tb_axi_mem_aw_channel
//============================================================================

module tb_axi_mem_aw_channel;

    parameter ADDR_WIDTH = 32;
    parameter ID_WIDTH   = 6;

    reg                    clk;
    reg                    rst_n;
    reg  [ID_WIDTH-1:0]    s_axi_awid;
    reg  [ADDR_WIDTH-1:0]  s_axi_awaddr;
    reg  [7:0]             s_axi_awlen;
    reg  [2:0]             s_axi_awsize;
    reg  [1:0]             s_axi_awburst;
    reg                    s_axi_awvalid;
    wire                   s_axi_awready;
    wire                   aw_valid_o;
    wire [ADDR_WIDTH-1:0]  aw_addr_o;
    wire [7:0]             aw_len_o;
    wire [2:0]             aw_size_o;
    wire [ID_WIDTH-1:0]    aw_id_o;
    reg                    aw_ready_i;

    integer pass_count, fail_count;

    axi_mem_aw_channel #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .s_axi_awid     (s_axi_awid),
        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awlen    (s_axi_awlen),
        .s_axi_awsize   (s_axi_awsize),
        .s_axi_awburst  (s_axi_awburst),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),
        .aw_valid_o     (aw_valid_o),
        .aw_addr_o      (aw_addr_o),
        .aw_len_o       (aw_len_o),
        .aw_size_o      (aw_size_o),
        .aw_id_o        (aw_id_o),
        .aw_ready_i     (aw_ready_i)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        pass_count = 0;
        fail_count = 0;
        rst_n = 0;
        s_axi_awid = 0; s_axi_awaddr = 0; s_axi_awlen = 0;
        s_axi_awsize = 0; s_axi_awburst = 0; s_axi_awvalid = 0;
        aw_ready_i = 0;

        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // ---------------------------------------------------------------
        // Test 1: AW transaction with downstream NOT ready (holds aw_valid_o)
        // ---------------------------------------------------------------
        @(negedge clk);
        aw_ready_i    = 0;
        s_axi_awvalid = 1;
        s_axi_awid    = 6'd7;
        s_axi_awaddr  = 32'h0000_1000;
        s_axi_awlen   = 8'd3;
        s_axi_awsize  = 3'd4;
        s_axi_awburst = 2'd1;

        // Wait for awready at negedge
        begin : wait_aw1
            integer wt;
            wt = 0;
            @(negedge clk);
            while (!s_axi_awready && wt < 100) begin
                @(negedge clk);
                wt = wt + 1;
            end
        end
        @(posedge clk); #1; // handshake fires
        @(negedge clk);
        s_axi_awvalid = 0;

        // Check captured values (aw_ready_i=0, so aw_valid_o holds)
        @(negedge clk);
        if (aw_valid_o && aw_addr_o == 32'h0000_1000 && aw_len_o == 8'd3 &&
            aw_size_o == 3'd4 && aw_id_o == 6'd7) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: AW capture mismatch v=%b a=%h l=%h s=%h id=%h",
                     aw_valid_o, aw_addr_o, aw_len_o, aw_size_o, aw_id_o);
        end

        // Consume it
        @(negedge clk);
        aw_ready_i = 1;
        @(posedge clk); #1;
        @(negedge clk);
        aw_ready_i = 0;

        // Wait for DUT to re-assert awready
        @(posedge clk); @(posedge clk);

        // ---------------------------------------------------------------
        // Test 2: AW with downstream stall
        // ---------------------------------------------------------------
        @(negedge clk);
        aw_ready_i    = 0;
        s_axi_awvalid = 1;
        s_axi_awid    = 6'd15;
        s_axi_awaddr  = 32'h0000_2000;
        s_axi_awlen   = 8'd7;
        s_axi_awsize  = 3'd4;

        begin : wait_aw2
            integer wt;
            wt = 0;
            @(negedge clk);
            while (!s_axi_awready && wt < 100) begin
                @(negedge clk);
                wt = wt + 1;
            end
        end
        @(posedge clk); #1; // handshake fires
        @(negedge clk);
        s_axi_awvalid = 0;

        @(negedge clk);
        if (aw_valid_o && aw_id_o == 6'd15 && aw_addr_o == 32'h0000_2000) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Stall test mismatch v=%b id=%h a=%h", aw_valid_o, aw_id_o, aw_addr_o);
        end

        // Release downstream
        @(negedge clk);
        aw_ready_i = 1;
        @(posedge clk); @(posedge clk);

        // ---------------------------------------------------------------
        // Test 3: Reset clears valid
        // ---------------------------------------------------------------
        rst_n = 0;
        @(posedge clk); #1;
        if (!aw_valid_o) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Reset should clear valid");
        end
        rst_n = 1;

        @(posedge clk); @(posedge clk);
        $display("========================================");
        $display("tb_axi_mem_aw_channel: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        if (fail_count == 0) $display("ALL TESTS PASSED");
        $finish;
    end

    // Timeout watchdog
    initial begin
        #10000;
        $display("TIMEOUT: Simulation exceeded 10us");
        $finish;
    end

    initial begin
        $dumpfile("tb_axi_mem_aw_channel.vcd");
        $dumpvars(0, tb_axi_mem_aw_channel);
    end

endmodule
