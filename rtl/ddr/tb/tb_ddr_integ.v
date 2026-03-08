`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — DDR Subsystem
// Testbench: tb_ddr_integ (L2 Integration)
// Description: L2 integration testbench for ddr_wrapper.
//              TB acts as AXI4 128-bit master on s_axi4_* ports.
//              axi_mem_model (64-bit) acts as AXI3 slave on m_axi3_* ports
//              (simulates Zynq HP0 DDR). Tests end-to-end data path:
//              AXI4 128b -> burst_splitter -> qos_mapper -> width_128to64 -> AXI3 64b -> mem
//////////////////////////////////////////////////////////////////////////////

module tb_ddr_integ;

    // -----------------------------------------------------------------------
    // Parameters
    // -----------------------------------------------------------------------
    parameter ADDR_WIDTH   = 32;
    parameter WIDE_DATA    = 128;
    parameter NARROW_DATA  = 64;
    parameter ID_WIDTH     = 6;
    parameter WIDE_STRB    = WIDE_DATA / 8;
    parameter NARROW_STRB  = NARROW_DATA / 8;
    parameter MEM_SIZE     = 65536;  // 64KB for sim

    // -----------------------------------------------------------------------
    // Clock and reset
    // -----------------------------------------------------------------------
    reg clk;
    reg rst_n;

    initial clk = 0;
    always #5 clk = ~clk;  // 100 MHz

    // -----------------------------------------------------------------------
    // AXI4 Slave signals (TB drives these — master side)
    // -----------------------------------------------------------------------
    reg  [ID_WIDTH-1:0]      s_axi4_awid;
    reg  [ADDR_WIDTH-1:0]    s_axi4_awaddr;
    reg  [7:0]               s_axi4_awlen;
    reg  [2:0]               s_axi4_awsize;
    reg  [1:0]               s_axi4_awburst;
    reg                      s_axi4_awvalid;
    wire                     s_axi4_awready;

    reg  [WIDE_DATA-1:0]     s_axi4_wdata;
    reg  [WIDE_STRB-1:0]     s_axi4_wstrb;
    reg                      s_axi4_wlast;
    reg                      s_axi4_wvalid;
    wire                     s_axi4_wready;

    wire [ID_WIDTH-1:0]      s_axi4_bid;
    wire [1:0]               s_axi4_bresp;
    wire                     s_axi4_bvalid;
    reg                      s_axi4_bready;

    reg  [ID_WIDTH-1:0]      s_axi4_arid;
    reg  [ADDR_WIDTH-1:0]    s_axi4_araddr;
    reg  [7:0]               s_axi4_arlen;
    reg  [2:0]               s_axi4_arsize;
    reg  [1:0]               s_axi4_arburst;
    reg                      s_axi4_arvalid;
    wire                     s_axi4_arready;

    wire [ID_WIDTH-1:0]      s_axi4_rid;
    wire [WIDE_DATA-1:0]     s_axi4_rdata;
    wire [1:0]               s_axi4_rresp;
    wire                     s_axi4_rlast;
    wire                     s_axi4_rvalid;
    reg                      s_axi4_rready;

    // -----------------------------------------------------------------------
    // AXI3 Master wires (DUT output -> axi_mem_model)
    // -----------------------------------------------------------------------
    wire [ID_WIDTH-1:0]      m_axi3_awid;
    wire [ADDR_WIDTH-1:0]    m_axi3_awaddr;
    wire [3:0]               m_axi3_awlen;
    wire [2:0]               m_axi3_awsize;
    wire [1:0]               m_axi3_awburst;
    wire [3:0]               m_axi3_awqos;
    wire                     m_axi3_awvalid;
    wire                     m_axi3_awready;

    wire [NARROW_DATA-1:0]   m_axi3_wdata;
    wire [NARROW_STRB-1:0]   m_axi3_wstrb;
    wire                     m_axi3_wlast;
    wire                     m_axi3_wvalid;
    wire                     m_axi3_wready;

    wire [ID_WIDTH-1:0]      m_axi3_bid;
    wire [1:0]               m_axi3_bresp;
    wire                     m_axi3_bvalid;
    wire                     m_axi3_bready;

    wire [ID_WIDTH-1:0]      m_axi3_arid;
    wire [ADDR_WIDTH-1:0]    m_axi3_araddr;
    wire [3:0]               m_axi3_arlen;
    wire [2:0]               m_axi3_arsize;
    wire [1:0]               m_axi3_arburst;
    wire [3:0]               m_axi3_arqos;
    wire                     m_axi3_arvalid;
    wire                     m_axi3_arready;

    wire [ID_WIDTH-1:0]      m_axi3_rid;
    wire [NARROW_DATA-1:0]   m_axi3_rdata;
    wire [1:0]               m_axi3_rresp;
    wire                     m_axi3_rlast;
    wire                     m_axi3_rvalid;
    wire                     m_axi3_rready;

    // -----------------------------------------------------------------------
    // Test infrastructure
    // -----------------------------------------------------------------------
    integer pass_count;
    integer fail_count;
    integer i, j;

    // Data buffers for burst transfers
    reg [127:0] wr_buf [0:255];
    reg [15:0]  ws_buf [0:255];
    reg [127:0] rd_buf [0:255];

    // -----------------------------------------------------------------------
    // DUT: ddr_wrapper
    // -----------------------------------------------------------------------
    ddr_wrapper #(
        .ADDR_WIDTH  (ADDR_WIDTH),
        .WIDE_DATA   (WIDE_DATA),
        .NARROW_DATA (NARROW_DATA),
        .ID_WIDTH    (ID_WIDTH)
    ) u_ddr_wrapper (
        .clk             (clk),
        .rst_n           (rst_n),
        // AXI4 Slave (128-bit, from TB master)
        .s_axi4_awid     (s_axi4_awid),
        .s_axi4_awaddr   (s_axi4_awaddr),
        .s_axi4_awlen    (s_axi4_awlen),
        .s_axi4_awsize   (s_axi4_awsize),
        .s_axi4_awburst  (s_axi4_awburst),
        .s_axi4_awvalid  (s_axi4_awvalid),
        .s_axi4_awready  (s_axi4_awready),
        .s_axi4_wdata    (s_axi4_wdata),
        .s_axi4_wstrb    (s_axi4_wstrb),
        .s_axi4_wlast    (s_axi4_wlast),
        .s_axi4_wvalid   (s_axi4_wvalid),
        .s_axi4_wready   (s_axi4_wready),
        .s_axi4_bid      (s_axi4_bid),
        .s_axi4_bresp    (s_axi4_bresp),
        .s_axi4_bvalid   (s_axi4_bvalid),
        .s_axi4_bready   (s_axi4_bready),
        .s_axi4_arid     (s_axi4_arid),
        .s_axi4_araddr   (s_axi4_araddr),
        .s_axi4_arlen    (s_axi4_arlen),
        .s_axi4_arsize   (s_axi4_arsize),
        .s_axi4_arburst  (s_axi4_arburst),
        .s_axi4_arvalid  (s_axi4_arvalid),
        .s_axi4_arready  (s_axi4_arready),
        .s_axi4_rid      (s_axi4_rid),
        .s_axi4_rdata    (s_axi4_rdata),
        .s_axi4_rresp    (s_axi4_rresp),
        .s_axi4_rlast    (s_axi4_rlast),
        .s_axi4_rvalid   (s_axi4_rvalid),
        .s_axi4_rready   (s_axi4_rready),
        // AXI3 Master (64-bit, to mem model)
        .m_axi3_awid     (m_axi3_awid),
        .m_axi3_awaddr   (m_axi3_awaddr),
        .m_axi3_awlen    (m_axi3_awlen),
        .m_axi3_awsize   (m_axi3_awsize),
        .m_axi3_awburst  (m_axi3_awburst),
        .m_axi3_awqos    (m_axi3_awqos),
        .m_axi3_awvalid  (m_axi3_awvalid),
        .m_axi3_awready  (m_axi3_awready),
        .m_axi3_wdata    (m_axi3_wdata),
        .m_axi3_wstrb    (m_axi3_wstrb),
        .m_axi3_wlast    (m_axi3_wlast),
        .m_axi3_wvalid   (m_axi3_wvalid),
        .m_axi3_wready   (m_axi3_wready),
        .m_axi3_bid      (m_axi3_bid),
        .m_axi3_bresp    (m_axi3_bresp),
        .m_axi3_bvalid   (m_axi3_bvalid),
        .m_axi3_bready   (m_axi3_bready),
        .m_axi3_arid     (m_axi3_arid),
        .m_axi3_araddr   (m_axi3_araddr),
        .m_axi3_arlen    (m_axi3_arlen),
        .m_axi3_arsize   (m_axi3_arsize),
        .m_axi3_arburst  (m_axi3_arburst),
        .m_axi3_arqos    (m_axi3_arqos),
        .m_axi3_arvalid  (m_axi3_arvalid),
        .m_axi3_arready  (m_axi3_arready),
        .m_axi3_rid      (m_axi3_rid),
        .m_axi3_rdata    (m_axi3_rdata),
        .m_axi3_rresp    (m_axi3_rresp),
        .m_axi3_rlast    (m_axi3_rlast),
        .m_axi3_rvalid   (m_axi3_rvalid),
        .m_axi3_rready   (m_axi3_rready)
    );

    // -----------------------------------------------------------------------
    // AXI3 Slave: axi_mem_model (64-bit)
    // Note: axi_mem_model has 8-bit awlen (AXI4). DDR wrapper outputs 4-bit
    //       awlen (AXI3). We zero-extend the 4-bit len to 8-bit for connection.
    // -----------------------------------------------------------------------
    axi_mem_model #(
        .MEM_SIZE_BYTES    (MEM_SIZE),
        .DATA_WIDTH        (NARROW_DATA),
        .ADDR_WIDTH        (ADDR_WIDTH),
        .ID_WIDTH          (ID_WIDTH),
        .READ_LATENCY      (2),
        .WRITE_LATENCY     (1),
        .BACKPRESSURE_MODE (0)
    ) u_mem (
        .clk             (clk),
        .rst_n           (rst_n),
        .s_axi_awid      (m_axi3_awid),
        .s_axi_awaddr    (m_axi3_awaddr),
        .s_axi_awlen     ({4'd0, m_axi3_awlen}),  // zero-extend 4-bit to 8-bit
        .s_axi_awsize    (m_axi3_awsize),
        .s_axi_awburst   (m_axi3_awburst),
        .s_axi_awvalid   (m_axi3_awvalid),
        .s_axi_awready   (m_axi3_awready),
        .s_axi_wdata     (m_axi3_wdata),
        .s_axi_wstrb     (m_axi3_wstrb),
        .s_axi_wlast     (m_axi3_wlast),
        .s_axi_wvalid    (m_axi3_wvalid),
        .s_axi_wready    (m_axi3_wready),
        .s_axi_bid       (m_axi3_bid),
        .s_axi_bresp     (m_axi3_bresp),
        .s_axi_bvalid    (m_axi3_bvalid),
        .s_axi_bready    (m_axi3_bready),
        .s_axi_arid      (m_axi3_arid),
        .s_axi_araddr    (m_axi3_araddr),
        .s_axi_arlen     ({4'd0, m_axi3_arlen}),  // zero-extend 4-bit to 8-bit
        .s_axi_arsize    (m_axi3_arsize),
        .s_axi_arburst   (m_axi3_arburst),
        .s_axi_arvalid   (m_axi3_arvalid),
        .s_axi_arready   (m_axi3_arready),
        .s_axi_rid       (m_axi3_rid),
        .s_axi_rdata     (m_axi3_rdata),
        .s_axi_rresp     (m_axi3_rresp),
        .s_axi_rlast     (m_axi3_rlast),
        .s_axi_rvalid    (m_axi3_rvalid),
        .s_axi_rready    (m_axi3_rready),
        .error_inject_i  (1'b0)
    );

    // -----------------------------------------------------------------------
    // AXI4 Master Write Burst Task
    // -----------------------------------------------------------------------
    task axi4_write_burst;
        input [5:0]  id;
        input [31:0] addr;
        input [7:0]  len;
        input [2:0]  size;
        integer beat, timeout;
    begin
        // AW phase — drive signals at #1, check handshake at posedge (pre-NBA)
        @(posedge clk); #1;
        s_axi4_awid    = id;
        s_axi4_awaddr  = addr;
        s_axi4_awlen   = len;
        s_axi4_awsize  = size;
        s_axi4_awburst = 2'b01;  // INCR
        s_axi4_awvalid = 1;
        timeout = 1000;
        while (timeout > 0) begin
            @(posedge clk);
            if (s_axi4_awready) timeout = 0;
            else timeout = timeout - 1;
            #1;
        end
        s_axi4_awvalid = 0;

        // W phase — check wready at posedge (pre-NBA) to catch single-cycle ready
        for (beat = 0; beat <= len; beat = beat + 1) begin
            @(posedge clk); #1;
            s_axi4_wdata  = wr_buf[beat];
            s_axi4_wstrb  = ws_buf[beat];
            s_axi4_wlast  = (beat == len);
            s_axi4_wvalid = 1;
            timeout = 1000;
            while (timeout > 0) begin
                @(posedge clk);
                if (s_axi4_wready) timeout = 0;
                else timeout = timeout - 1;
                #1;
            end
        end
        s_axi4_wvalid = 0;
        s_axi4_wlast  = 0;

        // B phase — check bvalid at posedge (pre-NBA)
        s_axi4_bready = 1;
        timeout = 1000;
        while (timeout > 0) begin
            @(posedge clk);
            if (s_axi4_bvalid) timeout = 0;
            else timeout = timeout - 1;
            #1;
        end
        s_axi4_bready = 0;
    end
    endtask

    // -----------------------------------------------------------------------
    // AXI4 Master Read Burst Task
    // -----------------------------------------------------------------------
    task axi4_read_burst;
        input [5:0]  id;
        input [31:0] addr;
        input [7:0]  len;
        input [2:0]  size;
        integer beat, timeout;
    begin
        // AR phase — check arready at posedge (pre-NBA)
        @(posedge clk); #1;
        s_axi4_arid    = id;
        s_axi4_araddr  = addr;
        s_axi4_arlen   = len;
        s_axi4_arsize  = size;
        s_axi4_arburst = 2'b01;  // INCR
        s_axi4_arvalid = 1;
        timeout = 1000;
        while (timeout > 0) begin
            @(posedge clk);
            if (s_axi4_arready) timeout = 0;
            else timeout = timeout - 1;
            #1;
        end
        s_axi4_arvalid = 0;

        // R phase — check rvalid and capture rdata at posedge (pre-NBA)
        s_axi4_rready = 1;
        for (beat = 0; beat <= len; beat = beat + 1) begin
            timeout = 1000;
            while (timeout > 0) begin
                @(posedge clk);
                if (s_axi4_rvalid) begin
                    rd_buf[beat] = s_axi4_rdata;
                    timeout = 0;
                end else begin
                    timeout = timeout - 1;
                end
                #1;
            end
        end
        s_axi4_rready = 0;
    end
    endtask

    // -----------------------------------------------------------------------
    // Check helper: compare wr_buf vs rd_buf for 'count' beats
    // -----------------------------------------------------------------------
    task check_data;
        input [31:0] count;
        input [255:0] test_name;  // up to 32 chars
        integer k;
        reg test_ok;
    begin
        test_ok = 1;
        for (k = 0; k < count; k = k + 1) begin
            if (rd_buf[k] !== wr_buf[k]) begin
                $display("  FAIL %0s: beat %0d expected %032h got %032h",
                         test_name, k, wr_buf[k], rd_buf[k]);
                test_ok = 0;
            end
        end
        if (test_ok) begin
            $display("  PASS %0s: %0d beats match", test_name, count);
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
        end
    end
    endtask

    // -----------------------------------------------------------------------
    // Signal initialization
    // -----------------------------------------------------------------------
    task init_signals;
    begin
        s_axi4_awid    = 0;
        s_axi4_awaddr  = 0;
        s_axi4_awlen   = 0;
        s_axi4_awsize  = 0;
        s_axi4_awburst = 0;
        s_axi4_awvalid = 0;
        s_axi4_wdata   = 0;
        s_axi4_wstrb   = 0;
        s_axi4_wlast   = 0;
        s_axi4_wvalid  = 0;
        s_axi4_bready  = 0;
        s_axi4_arid    = 0;
        s_axi4_araddr  = 0;
        s_axi4_arlen   = 0;
        s_axi4_arsize  = 0;
        s_axi4_arburst = 0;
        s_axi4_arvalid = 0;
        s_axi4_rready  = 0;
    end
    endtask

    // -----------------------------------------------------------------------
    // Fill write buffer with deterministic pattern
    // -----------------------------------------------------------------------
    task fill_wr_buf;
        input [31:0] base_val;
        input [31:0] count;
        input [15:0] strb_val;
        integer k;
    begin
        for (k = 0; k < count; k = k + 1) begin
            wr_buf[k] = {base_val + k*4 + 3, base_val + k*4 + 2,
                         base_val + k*4 + 1, base_val + k*4 + 0};
            ws_buf[k] = strb_val;
        end
    end
    endtask

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    initial begin
        $display("============================================================");
        $display("  TB: tb_ddr_integ — DDR Wrapper L2 Integration Test");
        $display("============================================================");
        pass_count = 0;
        fail_count = 0;

        init_signals;
        rst_n = 0;
        repeat (20) @(posedge clk);
        rst_n = 1;
        repeat (10) @(posedge clk);

        // ==============================================================
        // D1: Single Beat Write+Read (16B at addr 0x0000)
        // ==============================================================
        $display("\n--- D1: Single Beat Write+Read ---");
        fill_wr_buf(32'hA0A0_0000, 1, 16'hFFFF);
        axi4_write_burst(6'd1, 32'h0000_0000, 8'd0, 3'd4);
        repeat (5) @(posedge clk);
        axi4_read_burst(6'd1, 32'h0000_0000, 8'd0, 3'd4);
        check_data(1, "D1_single_beat");

        // ==============================================================
        // D2: Short Burst Write+Read (4 beats x 16B = 64B at addr 0x100)
        // ==============================================================
        $display("\n--- D2: Short Burst (4 beats) ---");
        fill_wr_buf(32'hB0B0_0000, 4, 16'hFFFF);
        axi4_write_burst(6'd1, 32'h0000_0100, 8'd3, 3'd4);
        repeat (10) @(posedge clk);
        axi4_read_burst(6'd1, 32'h0000_0100, 8'd3, 3'd4);
        check_data(4, "D2_short_burst");

        // ==============================================================
        // D3: Long Burst (16 beats = 256B)
        // AXI3 max burst = 16 beats, should pass without splitting
        // ==============================================================
        $display("\n--- D3: Long Burst (16 beats) ---");
        fill_wr_buf(32'hC0C0_0000, 16, 16'hFFFF);
        axi4_write_burst(6'd1, 32'h0000_0200, 8'd15, 3'd4);
        repeat (20) @(posedge clk);
        axi4_read_burst(6'd1, 32'h0000_0200, 8'd15, 3'd4);
        check_data(16, "D3_long_burst");

        // ==============================================================
        // D4: Width Conversion Check
        // Write 128-bit data, verify end-to-end through 128->64 converter
        // ==============================================================
        $display("\n--- D4: Width Conversion Check ---");
        // Use specific patterns that exercise all byte lanes
        wr_buf[0] = 128'hDEAD_BEEF_CAFE_BABE_1234_5678_ABCD_EF01;
        ws_buf[0] = 16'hFFFF;
        wr_buf[1] = 128'h0102_0304_0506_0708_090A_0B0C_0D0E_0F10;
        ws_buf[1] = 16'hFFFF;
        axi4_write_burst(6'd1, 32'h0000_0400, 8'd1, 3'd4);
        repeat (10) @(posedge clk);
        axi4_read_burst(6'd1, 32'h0000_0400, 8'd1, 3'd4);
        check_data(2, "D4_width_conv");

        // ==============================================================
        // D5: Narrow Write (4-byte strobe)
        // Only bytes 0-3 written (strb=0x000F)
        // ==============================================================
        $display("\n--- D5: Narrow Write (4-byte strobe) ---");
        // First, write all-FF to the location
        wr_buf[0] = 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF;
        ws_buf[0] = 16'hFFFF;
        axi4_write_burst(6'd1, 32'h0000_0500, 8'd0, 3'd4);
        repeat (5) @(posedge clk);

        // Now write narrow — only bytes 0-3
        wr_buf[0] = 128'h0000_0000_0000_0000_0000_0000_DEAD_BEEF;
        ws_buf[0] = 16'h000F;
        axi4_write_burst(6'd1, 32'h0000_0500, 8'd0, 3'd4);
        repeat (5) @(posedge clk);

        // Read back and verify
        axi4_read_burst(6'd1, 32'h0000_0500, 8'd0, 3'd4);
        // Expected: bytes 0-3 = DEAD_BEEF, bytes 4-15 = all FF
        begin : d5_check
            reg [127:0] expected;
            expected = 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_DEAD_BEEF;
            if (rd_buf[0] === expected) begin
                $display("  PASS D5_narrow_write: got %032h", rd_buf[0]);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL D5_narrow_write: expected %032h got %032h",
                         expected, rd_buf[0]);
                fail_count = fail_count + 1;
            end
        end

        // ==============================================================
        // D6: Back-to-Back Bursts (4 x 8 beats = 4 x 128B)
        // ==============================================================
        $display("\n--- D6: Back-to-Back Bursts ---");
        begin : d6_block
            reg d6_ok;
            d6_ok = 1;
            // Write 4 consecutive bursts
            for (i = 0; i < 4; i = i + 1) begin
                fill_wr_buf(32'hE000_0000 + i * 32'h0100_0000, 8, 16'hFFFF);
                axi4_write_burst(6'd1, 32'h0000_1000 + i * 32'h80,
                                 8'd7, 3'd4);
            end
            repeat (20) @(posedge clk);

            // Read back and verify each burst
            for (i = 0; i < 4; i = i + 1) begin
                // Re-fill expected data
                fill_wr_buf(32'hE000_0000 + i * 32'h0100_0000, 8, 16'hFFFF);
                axi4_read_burst(6'd1, 32'h0000_1000 + i * 32'h80,
                                8'd7, 3'd4);
                for (j = 0; j < 8; j = j + 1) begin
                    if (rd_buf[j] !== wr_buf[j]) begin
                        $display("  FAIL D6: burst %0d beat %0d expected %032h got %032h",
                                 i, j, wr_buf[j], rd_buf[j]);
                        d6_ok = 0;
                    end
                end
            end
            if (d6_ok) begin
                $display("  PASS D6_b2b_bursts: 4 bursts x 8 beats verified");
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
            end
        end

        // ==============================================================
        // D7: Different AXI IDs (NPU=0x02, Camera=0x03)
        // ==============================================================
        $display("\n--- D7: Different AXI IDs ---");
        begin : d7_block
            reg d7_ok;
            d7_ok = 1;

            // Write with NPU ID = 0x02
            fill_wr_buf(32'hF0F0_0000, 2, 16'hFFFF);
            axi4_write_burst(6'h02, 32'h0000_2000, 8'd1, 3'd4);
            // Verify write response ID
            if (s_axi4_bid !== 6'h02) begin
                $display("  FAIL D7: NPU write BID expected 0x02 got 0x%02h", s_axi4_bid);
                d7_ok = 0;
            end
            repeat (5) @(posedge clk);

            // Write with Camera ID = 0x03
            fill_wr_buf(32'hF1F1_0000, 2, 16'hFFFF);
            axi4_write_burst(6'h03, 32'h0000_2020, 8'd1, 3'd4);
            if (s_axi4_bid !== 6'h03) begin
                $display("  FAIL D7: CAM write BID expected 0x03 got 0x%02h", s_axi4_bid);
                d7_ok = 0;
            end
            repeat (5) @(posedge clk);

            // Read with NPU ID
            axi4_read_burst(6'h02, 32'h0000_2000, 8'd1, 3'd4);
            if (s_axi4_rid !== 6'h02) begin
                $display("  FAIL D7: NPU read RID expected 0x02 got 0x%02h", s_axi4_rid);
                d7_ok = 0;
            end
            // Verify data from NPU write
            fill_wr_buf(32'hF0F0_0000, 2, 16'hFFFF);
            for (j = 0; j < 2; j = j + 1) begin
                if (rd_buf[j] !== wr_buf[j]) begin
                    $display("  FAIL D7: NPU data beat %0d expected %032h got %032h",
                             j, wr_buf[j], rd_buf[j]);
                    d7_ok = 0;
                end
            end

            // Read with Camera ID
            axi4_read_burst(6'h03, 32'h0000_2020, 8'd1, 3'd4);
            if (s_axi4_rid !== 6'h03) begin
                $display("  FAIL D7: CAM read RID expected 0x03 got 0x%02h", s_axi4_rid);
                d7_ok = 0;
            end
            fill_wr_buf(32'hF1F1_0000, 2, 16'hFFFF);
            for (j = 0; j < 2; j = j + 1) begin
                if (rd_buf[j] !== wr_buf[j]) begin
                    $display("  FAIL D7: CAM data beat %0d expected %032h got %032h",
                             j, wr_buf[j], rd_buf[j]);
                    d7_ok = 0;
                end
            end

            if (d7_ok) begin
                $display("  PASS D7_different_ids: NPU(0x02) and CAM(0x03) IDs preserved");
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
            end
        end

        // ==============================================================
        // D8: Read After Write — write pattern, immediately read back
        // Exercises full pipeline roundtrip
        // ==============================================================
        $display("\n--- D8: Read After Write Roundtrip ---");
        begin : d8_block
            reg d8_ok;
            d8_ok = 1;

            // Write 8 beats to addr 0x3000
            fill_wr_buf(32'hAAAA_0000, 8, 16'hFFFF);
            axi4_write_burst(6'd5, 32'h0000_3000, 8'd7, 3'd4);
            // Immediately read back (no idle gap)
            axi4_read_burst(6'd5, 32'h0000_3000, 8'd7, 3'd4);

            for (j = 0; j < 8; j = j + 1) begin
                if (rd_buf[j] !== wr_buf[j]) begin
                    $display("  FAIL D8: beat %0d expected %032h got %032h",
                             j, wr_buf[j], rd_buf[j]);
                    d8_ok = 0;
                end
            end
            if (d8_ok) begin
                $display("  PASS D8_raw_roundtrip: 8-beat immediate readback OK");
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
            end
        end

        // ==============================================================
        // Summary
        // ==============================================================
        $display("\n============================================================");
        $display("  TB SUMMARY: %0d PASSED, %0d FAILED", pass_count, fail_count);
        if (fail_count == 0)
            $display("  >>> ALL TESTS PASSED <<<");
        else
            $display("  >>> SOME TESTS FAILED <<<");
        $display("============================================================");
        $finish;
    end

    // -----------------------------------------------------------------------
    // Watchdog timer
    // -----------------------------------------------------------------------
    initial begin
        #2000000;
        $display("ERROR: Watchdog timeout at %0t ns", $time);
        $finish;
    end

endmodule
