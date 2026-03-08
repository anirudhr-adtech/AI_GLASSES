`timescale 1ns/1ps
//============================================================================
// AI_GLASSES — DDR Subsystem (Simulation Model)
// Testbench: tb_axi_mem_r_channel
//============================================================================

module tb_axi_mem_r_channel;

    parameter DATA_WIDTH   = 128;
    parameter ADDR_WIDTH   = 32;
    parameter ID_WIDTH     = 6;
    parameter READ_LATENCY = 3;
    parameter MEM_SIZE     = 4096;
    localparam STRB_WIDTH  = DATA_WIDTH / 8;

    reg                    clk;
    reg                    rst_n;
    reg                    ar_valid_i;
    reg  [ADDR_WIDTH-1:0]  ar_addr_i;
    reg  [7:0]             ar_len_i;
    reg  [2:0]             ar_size_i;
    reg  [ID_WIDTH-1:0]    ar_id_i;
    wire                   ar_ready_o;
    wire [ID_WIDTH-1:0]    s_axi_rid;
    wire [DATA_WIDTH-1:0]  s_axi_rdata;
    wire [1:0]             s_axi_rresp;
    wire                   s_axi_rlast;
    wire                   s_axi_rvalid;
    reg                    s_axi_rready;

    // Memory interface
    wire                   rd_en;
    wire [ADDR_WIDTH-1:0]  rd_addr;
    wire [DATA_WIDTH-1:0]  rd_data;

    // Also need write port to pre-fill memory
    reg                    mem_wr_en;
    reg  [ADDR_WIDTH-1:0]  mem_wr_addr;
    reg  [DATA_WIDTH-1:0]  mem_wr_data;
    reg  [STRB_WIDTH-1:0]  mem_wr_strb;

    integer pass_count, fail_count;
    integer beat_count;

    mem_array #(.MEM_SIZE_BYTES(MEM_SIZE)) u_mem (
        .clk     (clk),
        .wr_en   (mem_wr_en),
        .wr_addr (mem_wr_addr),
        .wr_data (mem_wr_data),
        .wr_strb (mem_wr_strb),
        .rd_en   (rd_en),
        .rd_addr (rd_addr),
        .rd_data (rd_data)
    );

    axi_mem_r_channel #(
        .DATA_WIDTH   (DATA_WIDTH),
        .ADDR_WIDTH   (ADDR_WIDTH),
        .ID_WIDTH     (ID_WIDTH),
        .READ_LATENCY (READ_LATENCY)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .ar_valid_i   (ar_valid_i),
        .ar_addr_i    (ar_addr_i),
        .ar_len_i     (ar_len_i),
        .ar_size_i    (ar_size_i),
        .ar_id_i      (ar_id_i),
        .ar_ready_o   (ar_ready_o),
        .s_axi_rid    (s_axi_rid),
        .s_axi_rdata  (s_axi_rdata),
        .s_axi_rresp  (s_axi_rresp),
        .s_axi_rlast  (s_axi_rlast),
        .s_axi_rvalid (s_axi_rvalid),
        .s_axi_rready (s_axi_rready),
        .rd_en        (rd_en),
        .rd_addr      (rd_addr),
        .rd_data      (rd_data)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        pass_count = 0;
        fail_count = 0;
        rst_n = 0;
        ar_valid_i = 0; ar_addr_i = 0; ar_len_i = 0; ar_size_i = 0; ar_id_i = 0;
        s_axi_rready = 1;
        mem_wr_en = 0; mem_wr_addr = 0; mem_wr_data = 0; mem_wr_strb = 0;

        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Pre-fill memory at addr 0x0000 with known pattern
        mem_wr_en = 1; mem_wr_strb = 16'hFFFF;
        mem_wr_addr = 32'h0000_0000; mem_wr_data = 128'hAAAAAAAA_BBBBBBBB_CCCCCCCC_DDDDDDDD;
        @(posedge clk);
        mem_wr_addr = 32'h0000_0010; mem_wr_data = 128'h11111111_22222222_33333333_44444444;
        @(posedge clk);
        mem_wr_addr = 32'h0000_0020; mem_wr_data = 128'h55555555_66666666_77777777_88888888;
        @(posedge clk);
        mem_wr_addr = 32'h0000_0030; mem_wr_data = 128'h99999999_AAAAAAAA_BBBBBBBB_CCCCCCCC;
        @(posedge clk);
        mem_wr_en = 0;
        @(posedge clk);

        // Test 1: Single beat read (len=0)
        ar_valid_i = 1;
        ar_addr_i  = 32'h0000_0000;
        ar_len_i   = 8'd0;
        ar_size_i  = 3'd4;
        ar_id_i    = 6'd3;
        @(posedge clk);
        while (!ar_ready_o) @(posedge clk);
        @(posedge clk);
        ar_valid_i = 0;

        // Wait for data through latency pipe
        beat_count = 0;
        repeat (READ_LATENCY + 10) begin
            @(posedge clk);
            if (s_axi_rvalid && s_axi_rready) begin
                beat_count = beat_count + 1;
                if (s_axi_rdata == 128'hAAAAAAAA_BBBBBBBB_CCCCCCCC_DDDDDDDD &&
                    s_axi_rid == 6'd3 && s_axi_rlast) begin
                    pass_count = pass_count + 1;
                end else begin
                    fail_count = fail_count + 1;
                    $display("FAIL: Single read data=%h id=%h last=%b",
                             s_axi_rdata, s_axi_rid, s_axi_rlast);
                end
            end
        end

        if (beat_count == 1) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Expected 1 beat, got %0d", beat_count);
        end

        // Test 2: 4-beat burst read
        repeat (3) @(posedge clk);
        ar_valid_i = 1;
        ar_addr_i  = 32'h0000_0000;
        ar_len_i   = 8'd3;
        ar_size_i  = 3'd4;
        ar_id_i    = 6'd7;
        @(posedge clk);
        while (!ar_ready_o) @(posedge clk);
        @(posedge clk);
        ar_valid_i = 0;

        beat_count = 0;
        repeat (READ_LATENCY + 30) begin
            @(posedge clk);
            if (s_axi_rvalid && s_axi_rready) begin
                beat_count = beat_count + 1;
                if (beat_count == 4 && s_axi_rlast) begin
                    pass_count = pass_count + 1;
                end
            end
        end

        if (beat_count == 4) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Burst expected 4 beats, got %0d", beat_count);
        end

        @(posedge clk); @(posedge clk);
        $display("========================================");
        $display("tb_axi_mem_r_channel: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        if (fail_count == 0) $display("ALL TESTS PASSED");
        $finish;
    end

    initial begin
        $dumpfile("tb_axi_mem_r_channel.vcd");
        $dumpvars(0, tb_axi_mem_r_channel);
    end

endmodule
