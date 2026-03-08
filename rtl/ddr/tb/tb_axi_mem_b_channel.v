`timescale 1ns/1ps
//============================================================================
// AI_GLASSES — DDR Subsystem (Simulation Model)
// Testbench: tb_axi_mem_b_channel
//============================================================================

module tb_axi_mem_b_channel;

    parameter WRITE_LATENCY = 3;  // Short for fast sim
    parameter ID_WIDTH      = 6;

    reg                 clk;
    reg                 rst_n;
    reg                 wlast_done_i;
    reg [ID_WIDTH-1:0]  aw_id_i;
    wire [ID_WIDTH-1:0] s_axi_bid;
    wire [1:0]          s_axi_bresp;
    wire                s_axi_bvalid;
    reg                 s_axi_bready;
    reg                 error_inject_i;

    integer pass_count, fail_count;

    axi_mem_b_channel #(
        .WRITE_LATENCY (WRITE_LATENCY),
        .ID_WIDTH      (ID_WIDTH)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .wlast_done_i   (wlast_done_i),
        .aw_id_i        (aw_id_i),
        .s_axi_bid      (s_axi_bid),
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),
        .error_inject_i (error_inject_i)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        pass_count = 0;
        fail_count = 0;
        rst_n = 0;
        wlast_done_i = 0; aw_id_i = 0;
        s_axi_bready = 1; error_inject_i = 0;

        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Test 1: Normal write response
        wlast_done_i = 1; aw_id_i = 6'd5;
        @(posedge clk);
        wlast_done_i = 0;

        // Wait for bvalid (latency pipeline + 1 register stage)
        begin : wait_bvalid_t1
            integer wt;
            wt = 0;
            while (!s_axi_bvalid && wt < 50) begin
                @(posedge clk);
                wt = wt + 1;
            end
        end

        if (s_axi_bvalid && s_axi_bid == 6'd5 && s_axi_bresp == 2'b00) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Normal B resp v=%b id=%h resp=%b", s_axi_bvalid, s_axi_bid, s_axi_bresp);
        end
        @(posedge clk);

        // Test 2: Error injection -> SLVERR
        wlast_done_i = 1; aw_id_i = 6'd10; error_inject_i = 1;
        @(posedge clk);
        wlast_done_i = 0; error_inject_i = 0;

        begin : wait_bvalid_t2
            integer wt;
            wt = 0;
            while (!s_axi_bvalid && wt < 50) begin
                @(posedge clk);
                wt = wt + 1;
            end
        end

        if (s_axi_bvalid && s_axi_bid == 6'd10 && s_axi_bresp == 2'b10) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Error inject resp v=%b id=%h resp=%b", s_axi_bvalid, s_axi_bid, s_axi_bresp);
        end
        @(posedge clk);

        // Test 3: Stall BREADY
        s_axi_bready = 0;
        wlast_done_i = 1; aw_id_i = 6'd20;
        @(posedge clk);
        wlast_done_i = 0;

        begin : wait_bvalid_t3
            integer wt;
            wt = 0;
            while (!s_axi_bvalid && wt < 50) begin
                @(posedge clk);
                wt = wt + 1;
            end
        end

        if (s_axi_bvalid) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: B should be valid even with BREADY=0");
        end

        // Release BREADY
        s_axi_bready = 1;
        @(posedge clk); @(posedge clk);
        if (!s_axi_bvalid) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: B should deassert after BREADY handshake");
        end

        @(posedge clk);
        $display("========================================");
        $display("tb_axi_mem_b_channel: %0d PASSED, %0d FAILED", pass_count, fail_count);
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
        $dumpfile("tb_axi_mem_b_channel.vcd");
        $dumpvars(0, tb_axi_mem_b_channel);
    end

endmodule
