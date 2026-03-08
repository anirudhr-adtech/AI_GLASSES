`timescale 1ns/1ps
//============================================================================
// AI_GLASSES — DDR Subsystem (Simulation Model)
// Testbench: tb_axi_mem_ar_channel
//============================================================================

module tb_axi_mem_ar_channel;

    parameter ADDR_WIDTH = 32;
    parameter ID_WIDTH   = 6;

    reg                    clk;
    reg                    rst_n;
    reg  [ID_WIDTH-1:0]    s_axi_arid;
    reg  [ADDR_WIDTH-1:0]  s_axi_araddr;
    reg  [7:0]             s_axi_arlen;
    reg  [2:0]             s_axi_arsize;
    reg  [1:0]             s_axi_arburst;
    reg                    s_axi_arvalid;
    wire                   s_axi_arready;
    wire                   ar_valid_o;
    wire [ADDR_WIDTH-1:0]  ar_addr_o;
    wire [7:0]             ar_len_o;
    wire [2:0]             ar_size_o;
    wire [ID_WIDTH-1:0]    ar_id_o;
    reg                    ar_ready_i;

    integer pass_count, fail_count;

    axi_mem_ar_channel #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .s_axi_arid     (s_axi_arid),
        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arlen    (s_axi_arlen),
        .s_axi_arsize   (s_axi_arsize),
        .s_axi_arburst  (s_axi_arburst),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),
        .ar_valid_o     (ar_valid_o),
        .ar_addr_o      (ar_addr_o),
        .ar_len_o       (ar_len_o),
        .ar_size_o      (ar_size_o),
        .ar_id_o        (ar_id_o),
        .ar_ready_i     (ar_ready_i)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        pass_count = 0;
        fail_count = 0;
        rst_n = 0;
        s_axi_arid = 0; s_axi_araddr = 0; s_axi_arlen = 0;
        s_axi_arsize = 0; s_axi_arburst = 0; s_axi_arvalid = 0;
        ar_ready_i = 0;

        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // ---------------------------------------------------------------
        // Test 1: AR transaction with downstream NOT ready (holds ar_valid_o)
        // ---------------------------------------------------------------
        @(negedge clk);
        ar_ready_i    = 0;
        s_axi_arvalid = 1;
        s_axi_arid    = 6'd12;
        s_axi_araddr  = 32'h0000_3000;
        s_axi_arlen   = 8'd7;
        s_axi_arsize  = 3'd4;
        s_axi_arburst = 2'd1;

        // Wait for arready at negedge
        begin : wait_ar1
            integer wt;
            wt = 0;
            @(negedge clk);
            while (!s_axi_arready && wt < 100) begin
                @(negedge clk);
                wt = wt + 1;
            end
        end
        @(posedge clk); #1; // handshake fires at this posedge
        @(negedge clk);
        s_axi_arvalid = 0;

        // Check captured values at next negedge (ar_ready_i=0, so ar_valid_o holds)
        @(negedge clk);
        if (ar_valid_o && ar_addr_o == 32'h0000_3000 && ar_len_o == 8'd7 &&
            ar_size_o == 3'd4 && ar_id_o == 6'd12) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: AR capture v=%b a=%h l=%h s=%h id=%h",
                     ar_valid_o, ar_addr_o, ar_len_o, ar_size_o, ar_id_o);
        end

        // Consume it: assert ar_ready_i at negedge so DUT sees it cleanly on posedge
        @(negedge clk);
        ar_ready_i = 1;
        @(posedge clk); #1;  // DUT consumes: ar_valid_o <= 0
        @(negedge clk);
        ar_ready_i = 0;

        // Wait for DUT to re-assert arready
        @(posedge clk); @(posedge clk);

        // ---------------------------------------------------------------
        // Test 2: Stalled downstream (ar_ready_i = 0)
        // ---------------------------------------------------------------
        @(negedge clk);
        ar_ready_i    = 0;
        s_axi_arvalid = 1;
        s_axi_arid    = 6'd25;
        s_axi_araddr  = 32'h0000_4000;
        s_axi_arlen   = 8'd0;
        s_axi_arsize  = 3'd4;

        // Wait for arready at negedge
        begin : wait_ar2
            integer wt;
            wt = 0;
            @(negedge clk);
            while (!s_axi_arready && wt < 100) begin
                @(negedge clk);
                wt = wt + 1;
            end
        end
        @(posedge clk); #1; // handshake fires
        @(negedge clk);
        s_axi_arvalid = 0;

        @(negedge clk);
        if (ar_valid_o && ar_id_o == 6'd25) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Stall AR v=%b id=%h", ar_valid_o, ar_id_o);
        end

        // Clean up: consume Test 2
        @(negedge clk);
        ar_ready_i = 1;
        @(posedge clk); @(posedge clk);

        // ---------------------------------------------------------------
        // Test 3: Reset clears ar_valid
        // ---------------------------------------------------------------
        rst_n = 0;
        @(posedge clk); #1;
        if (!ar_valid_o) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Reset should clear ar_valid");
        end
        rst_n = 1;

        @(posedge clk); @(posedge clk);
        $display("========================================");
        $display("tb_axi_mem_ar_channel: %0d PASSED, %0d FAILED", pass_count, fail_count);
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
        $dumpfile("tb_axi_mem_ar_channel.vcd");
        $dumpvars(0, tb_axi_mem_ar_channel);
    end

endmodule
