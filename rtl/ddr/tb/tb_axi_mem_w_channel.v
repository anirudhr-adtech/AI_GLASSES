`timescale 1ns/1ps
//============================================================================
// AI_GLASSES — DDR Subsystem (Simulation Model)
// Testbench: tb_axi_mem_w_channel
//============================================================================

module tb_axi_mem_w_channel;

    parameter DATA_WIDTH = 128;
    parameter ADDR_WIDTH = 32;
    parameter MEM_SIZE   = 4096;
    localparam STRB_WIDTH = DATA_WIDTH / 8;

    reg                     clk;
    reg                     rst_n;
    reg  [DATA_WIDTH-1:0]   s_axi_wdata;
    reg  [STRB_WIDTH-1:0]   s_axi_wstrb;
    reg                     s_axi_wlast;
    reg                     s_axi_wvalid;
    wire                    s_axi_wready;

    reg                     aw_valid_i;
    reg  [ADDR_WIDTH-1:0]   aw_addr_i;
    reg  [7:0]              aw_len_i;
    reg  [2:0]              aw_size_i;
    wire                    aw_consumed_o;
    wire                    wlast_done_o;

    wire                    wr_en;
    wire [ADDR_WIDTH-1:0]   wr_addr;
    wire [DATA_WIDTH-1:0]   wr_data;
    wire [STRB_WIDTH-1:0]   wr_strb;

    integer pass_count, fail_count;

    // Instantiate mem_array to verify writes
    wire [DATA_WIDTH-1:0] rd_data;
    reg                   rd_en;
    reg  [ADDR_WIDTH-1:0] rd_addr;

    mem_array #(.MEM_SIZE_BYTES(MEM_SIZE)) u_mem (
        .clk     (clk),
        .wr_en   (wr_en),
        .wr_addr (wr_addr),
        .wr_data (wr_data),
        .wr_strb (wr_strb),
        .rd_en   (rd_en),
        .rd_addr (rd_addr),
        .rd_data (rd_data)
    );

    axi_mem_w_channel #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .s_axi_wdata   (s_axi_wdata),
        .s_axi_wstrb   (s_axi_wstrb),
        .s_axi_wlast   (s_axi_wlast),
        .s_axi_wvalid  (s_axi_wvalid),
        .s_axi_wready  (s_axi_wready),
        .aw_valid_i    (aw_valid_i),
        .aw_addr_i     (aw_addr_i),
        .aw_len_i      (aw_len_i),
        .aw_size_i     (aw_size_i),
        .aw_consumed_o (aw_consumed_o),
        .wlast_done_o  (wlast_done_o),
        .wr_en         (wr_en),
        .wr_addr       (wr_addr),
        .wr_data       (wr_data),
        .wr_strb       (wr_strb)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        pass_count = 0;
        fail_count = 0;
        rst_n = 0;
        s_axi_wdata = 0; s_axi_wstrb = 0; s_axi_wlast = 0; s_axi_wvalid = 0;
        aw_valid_i = 0; aw_addr_i = 0; aw_len_i = 0; aw_size_i = 0;
        rd_en = 0; rd_addr = 0;

        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Test 1: Single beat write (len=0)
        aw_valid_i = 1;
        aw_addr_i  = 32'h0000_0000;
        aw_len_i   = 8'd0;
        aw_size_i  = 3'd4;  // 16 bytes
        @(posedge clk);
        while (!aw_consumed_o) @(posedge clk);
        aw_valid_i = 0;

        // Send W beat
        s_axi_wvalid = 1;
        s_axi_wdata  = 128'hDEADBEEF_CAFEBABE_12345678_AABBCCDD;
        s_axi_wstrb  = 16'hFFFF;
        s_axi_wlast  = 1;
        @(posedge clk);
        while (!s_axi_wready) @(posedge clk);
        @(posedge clk);
        s_axi_wvalid = 0;
        s_axi_wlast  = 0;

        // Check wlast_done
        if (wlast_done_o) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: wlast_done not asserted after single beat");
        end

        // Verify memory content
        repeat (2) @(posedge clk);
        rd_en = 1; rd_addr = 32'h0000_0000;
        @(posedge clk); rd_en = 0;
        @(posedge clk);
        if (rd_data == 128'hDEADBEEF_CAFEBABE_12345678_AABBCCDD) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Memory content mismatch: %h", rd_data);
        end

        // Test 2: 4-beat burst write (len=3, size=4 -> 16 bytes per beat)
        @(posedge clk);
        aw_valid_i = 1;
        aw_addr_i  = 32'h0000_0100;
        aw_len_i   = 8'd3;
        aw_size_i  = 3'd4;
        @(posedge clk);
        while (!aw_consumed_o) @(posedge clk);
        aw_valid_i = 0;

        // Beat 0
        s_axi_wvalid = 1; s_axi_wstrb = 16'hFFFF; s_axi_wlast = 0;
        s_axi_wdata = 128'h11111111_11111111_11111111_11111111;
        @(posedge clk);
        while (!s_axi_wready) @(posedge clk);
        // Beat 1
        s_axi_wdata = 128'h22222222_22222222_22222222_22222222;
        @(posedge clk);
        // Beat 2
        s_axi_wdata = 128'h33333333_33333333_33333333_33333333;
        @(posedge clk);
        // Beat 3 (last)
        s_axi_wdata = 128'h44444444_44444444_44444444_44444444;
        s_axi_wlast = 1;
        @(posedge clk);
        s_axi_wvalid = 0; s_axi_wlast = 0;

        repeat (3) @(posedge clk);

        // Verify burst in memory
        rd_en = 1; rd_addr = 32'h0000_0100;
        @(posedge clk); rd_en = 0;
        @(posedge clk);
        if (rd_data == 128'h11111111_11111111_11111111_11111111) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Burst beat 0 mismatch: %h", rd_data);
        end

        rd_en = 1; rd_addr = 32'h0000_0110;
        @(posedge clk); rd_en = 0;
        @(posedge clk);
        if (rd_data == 128'h22222222_22222222_22222222_22222222) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Burst beat 1 mismatch: %h", rd_data);
        end

        @(posedge clk); @(posedge clk);
        $display("========================================");
        $display("tb_axi_mem_w_channel: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        if (fail_count == 0) $display("ALL TESTS PASSED");
        $finish;
    end

    initial begin
        $dumpfile("tb_axi_mem_w_channel.vcd");
        $dumpvars(0, tb_axi_mem_w_channel);
    end

endmodule
