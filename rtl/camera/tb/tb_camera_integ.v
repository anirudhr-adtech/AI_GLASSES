`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Camera Subsystem L2 Integration Testbench
// File: tb_camera_integ.v
// Description: End-to-end validation of DVP capture -> pixel FIFO -> ISP ->
//              resize -> crop -> VDMA to DDR. Uses dvp_camera_model BFM and
//              axi_mem_model as DDR back-end.
//////////////////////////////////////////////////////////////////////////////

module tb_camera_integ;

    // ================================================================
    // Parameters
    // ================================================================
    localparam CLK_PERIOD  = 10;    // 100 MHz sys_clk
    localparam PCLK_PERIOD = 40;    // 25 MHz pixel clock

    // Small frame for fast simulation
    localparam DVP_H_ACTIVE = 64;
    localparam DVP_V_ACTIVE = 48;

    // ISP output dimensions
    localparam ISP_OUT_W = 32;
    localparam ISP_OUT_H = 32;

    // Register byte offsets
    localparam REG_CAM_CONTROL      = 32'h00;
    localparam REG_CAM_STATUS       = 32'h04;
    localparam REG_SENSOR_CONFIG    = 32'h08;
    localparam REG_ISP_CONFIG       = 32'h0C;
    localparam REG_ISP_SCALE_X      = 32'h10;
    localparam REG_ISP_SCALE_Y      = 32'h14;
    localparam REG_FRAME_BUF_A_ADDR = 32'h18;
    localparam REG_FRAME_BUF_B_ADDR = 32'h1C;
    localparam REG_ACTIVE_BUF       = 32'h20;
    localparam REG_CAPTURE_START    = 32'h24;
    localparam REG_CROP_X           = 32'h28;
    localparam REG_CROP_Y           = 32'h2C;
    localparam REG_CROP_WIDTH       = 32'h30;
    localparam REG_CROP_HEIGHT      = 32'h34;
    localparam REG_CROP_OUT_WIDTH   = 32'h38;
    localparam REG_CROP_OUT_HEIGHT  = 32'h3C;
    localparam REG_CROP_BUF_ADDR   = 32'h40;
    localparam REG_CROP_START       = 32'h44;
    localparam REG_IRQ_CLEAR        = 32'h48;
    localparam REG_RAW_FRAME_ADDR   = 32'h4C;
    localparam REG_FRAME_SIZE_BYTES = 32'h50;
    localparam REG_PERF_CAPTURE_CYC = 32'h54;
    localparam REG_PERF_ISP_CYC     = 32'h58;
    localparam REG_PERF_CROP_CYC    = 32'h5C;

    // CAM_STATUS bit positions
    localparam STS_CAPTURE_BUSY = 0;
    localparam STS_FRAME_READY  = 1;
    localparam STS_CROP_BUSY    = 2;
    localparam STS_CROP_DONE    = 3;

    // Scale factors: (src << 16) / dst
    // X: (64 << 16) / 32 = 0x20000
    // Y: (48 << 16) / 32 = 0x18000
    localparam SCALE_X = 32'h0002_0000;
    localparam SCALE_Y = 32'h0001_8000;

    // Frame buffer addresses
    localparam FRAME_BUF_A = 32'h0001_0000;
    localparam FRAME_BUF_B = 32'h0002_0000;
    localparam CROP_BUF    = 32'h0003_0000;

    // ISP_CONFIG: width[9:0], height[19:10]
    localparam ISP_CONFIG_VAL = (ISP_OUT_H << 10) | ISP_OUT_W;

    // SENSOR_CONFIG: src_width[11:2], src_height[21:12]
    localparam SENSOR_CONFIG_VAL = (DVP_V_ACTIVE << 12) | (DVP_H_ACTIVE << 2);

    // Generous timeout for capture (in sys_clk cycles)
    localparam CAPTURE_TIMEOUT = 500000;
    localparam CROP_TIMEOUT    = 200000;

    // ================================================================
    // Signals
    // ================================================================
    reg         clk;
    reg         rst_n;
    reg         pclk;

    // DVP BFM signals
    reg         dvp_enable;
    wire        cam_vsync;
    wire        cam_href;
    wire [7:0]  cam_data;

    // AXI-Lite register interface
    reg  [31:0] s_axi_lite_awaddr;
    reg         s_axi_lite_awvalid;
    wire        s_axi_lite_awready;
    reg  [31:0] s_axi_lite_wdata;
    reg  [3:0]  s_axi_lite_wstrb;
    reg         s_axi_lite_wvalid;
    wire        s_axi_lite_wready;
    wire [1:0]  s_axi_lite_bresp;
    wire        s_axi_lite_bvalid;
    reg         s_axi_lite_bready;
    reg  [31:0] s_axi_lite_araddr;
    reg         s_axi_lite_arvalid;
    wire        s_axi_lite_arready;
    wire [31:0] s_axi_lite_rdata;
    wire [1:0]  s_axi_lite_rresp;
    wire        s_axi_lite_rvalid;
    reg         s_axi_lite_rready;

    // AXI4 VDMA master -> DDR model slave
    wire [3:0]   m_axi_vdma_awid;
    wire [31:0]  m_axi_vdma_awaddr;
    wire [7:0]   m_axi_vdma_awlen;
    wire [2:0]   m_axi_vdma_awsize;
    wire [1:0]   m_axi_vdma_awburst;
    wire         m_axi_vdma_awvalid;
    wire         m_axi_vdma_awready;
    wire [127:0] m_axi_vdma_wdata;
    wire [15:0]  m_axi_vdma_wstrb;
    wire         m_axi_vdma_wlast;
    wire         m_axi_vdma_wvalid;
    wire         m_axi_vdma_wready;
    wire [3:0]   m_axi_vdma_bid;
    wire [1:0]   m_axi_vdma_bresp;
    wire         m_axi_vdma_bvalid;
    wire         m_axi_vdma_bready;
    wire [3:0]   m_axi_vdma_arid;
    wire [31:0]  m_axi_vdma_araddr;
    wire [7:0]   m_axi_vdma_arlen;
    wire [2:0]   m_axi_vdma_arsize;
    wire [1:0]   m_axi_vdma_arburst;
    wire         m_axi_vdma_arvalid;
    wire         m_axi_vdma_arready;
    wire [3:0]   m_axi_vdma_rid;
    wire [127:0] m_axi_vdma_rdata;
    wire [1:0]   m_axi_vdma_rresp;
    wire         m_axi_vdma_rlast;
    wire         m_axi_vdma_rvalid;
    wire         m_axi_vdma_rready;

    wire         irq_camera_ready;

    // Test bookkeeping
    integer test_num;
    integer pass_count;
    integer fail_count;
    reg [31:0] read_data;

    // ================================================================
    // Clock Generation
    // ================================================================
    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    initial pclk = 1'b0;
    always #(PCLK_PERIOD / 2) pclk = ~pclk;

    // ================================================================
    // DUT: cam_subsys_top
    // ================================================================
    cam_subsys_top u_dut (
        .clk_i                  (clk),
        .rst_ni                 (rst_n),
        // DVP interface
        .cam_pclk_i             (pclk),
        .cam_vsync_i            (cam_vsync),
        .cam_href_i             (cam_href),
        .cam_data_i             (cam_data),
        // AXI-Lite slave
        .s_axi_lite_awaddr      (s_axi_lite_awaddr),
        .s_axi_lite_awvalid     (s_axi_lite_awvalid),
        .s_axi_lite_awready     (s_axi_lite_awready),
        .s_axi_lite_wdata       (s_axi_lite_wdata),
        .s_axi_lite_wstrb       (s_axi_lite_wstrb),
        .s_axi_lite_wvalid      (s_axi_lite_wvalid),
        .s_axi_lite_wready      (s_axi_lite_wready),
        .s_axi_lite_bresp       (s_axi_lite_bresp),
        .s_axi_lite_bvalid      (s_axi_lite_bvalid),
        .s_axi_lite_bready      (s_axi_lite_bready),
        .s_axi_lite_araddr      (s_axi_lite_araddr),
        .s_axi_lite_arvalid     (s_axi_lite_arvalid),
        .s_axi_lite_arready     (s_axi_lite_arready),
        .s_axi_lite_rdata       (s_axi_lite_rdata),
        .s_axi_lite_rresp       (s_axi_lite_rresp),
        .s_axi_lite_rvalid      (s_axi_lite_rvalid),
        .s_axi_lite_rready      (s_axi_lite_rready),
        // AXI4 VDMA master
        .m_axi_vdma_awid        (m_axi_vdma_awid),
        .m_axi_vdma_awaddr      (m_axi_vdma_awaddr),
        .m_axi_vdma_awlen       (m_axi_vdma_awlen),
        .m_axi_vdma_awsize      (m_axi_vdma_awsize),
        .m_axi_vdma_awburst     (m_axi_vdma_awburst),
        .m_axi_vdma_awvalid     (m_axi_vdma_awvalid),
        .m_axi_vdma_awready     (m_axi_vdma_awready),
        .m_axi_vdma_wdata       (m_axi_vdma_wdata),
        .m_axi_vdma_wstrb       (m_axi_vdma_wstrb),
        .m_axi_vdma_wlast       (m_axi_vdma_wlast),
        .m_axi_vdma_wvalid      (m_axi_vdma_wvalid),
        .m_axi_vdma_wready      (m_axi_vdma_wready),
        .m_axi_vdma_bid         (m_axi_vdma_bid),
        .m_axi_vdma_bresp       (m_axi_vdma_bresp),
        .m_axi_vdma_bvalid      (m_axi_vdma_bvalid),
        .m_axi_vdma_bready      (m_axi_vdma_bready),
        .m_axi_vdma_arid        (m_axi_vdma_arid),
        .m_axi_vdma_araddr      (m_axi_vdma_araddr),
        .m_axi_vdma_arlen       (m_axi_vdma_arlen),
        .m_axi_vdma_arsize      (m_axi_vdma_arsize),
        .m_axi_vdma_arburst     (m_axi_vdma_arburst),
        .m_axi_vdma_arvalid     (m_axi_vdma_arvalid),
        .m_axi_vdma_arready     (m_axi_vdma_arready),
        .m_axi_vdma_rid         (m_axi_vdma_rid),
        .m_axi_vdma_rdata       (m_axi_vdma_rdata),
        .m_axi_vdma_rresp       (m_axi_vdma_rresp),
        .m_axi_vdma_rlast       (m_axi_vdma_rlast),
        .m_axi_vdma_rvalid      (m_axi_vdma_rvalid),
        .m_axi_vdma_rready      (m_axi_vdma_rready),
        .irq_camera_ready_o     (irq_camera_ready)
    );

    // ================================================================
    // DVP Camera BFM (small 64x48 frame, color bars)
    // ================================================================
    dvp_camera_model #(
        .H_ACTIVE   (DVP_H_ACTIVE),
        .V_ACTIVE   (DVP_V_ACTIVE),
        .PIXEL_BITS (8)
    ) u_dvp (
        .rst_n      (rst_n),
        .enable     (dvp_enable),
        .pclk       (pclk),
        .vsync      (cam_vsync),
        .href       (cam_href),
        .data_o     (cam_data),
        .frame_done ()
    );

    // ================================================================
    // DDR Memory Model (AXI4 128-bit slave)
    // ================================================================
    axi_mem_model #(
        .MEM_SIZE_BYTES (1048576),
        .DATA_WIDTH     (128),
        .ADDR_WIDTH     (32),
        .ID_WIDTH       (4),
        .READ_LATENCY   (4),
        .WRITE_LATENCY  (2)
    ) u_ddr (
        .clk            (clk),
        .rst_n          (rst_n),
        // Write address
        .s_axi_awid     (m_axi_vdma_awid),
        .s_axi_awaddr   (m_axi_vdma_awaddr),
        .s_axi_awlen    (m_axi_vdma_awlen),
        .s_axi_awsize   (m_axi_vdma_awsize),
        .s_axi_awburst  (m_axi_vdma_awburst),
        .s_axi_awvalid  (m_axi_vdma_awvalid),
        .s_axi_awready  (m_axi_vdma_awready),
        // Write data
        .s_axi_wdata    (m_axi_vdma_wdata),
        .s_axi_wstrb    (m_axi_vdma_wstrb),
        .s_axi_wlast    (m_axi_vdma_wlast),
        .s_axi_wvalid   (m_axi_vdma_wvalid),
        .s_axi_wready   (m_axi_vdma_wready),
        // Write response
        .s_axi_bid      (m_axi_vdma_bid),
        .s_axi_bresp    (m_axi_vdma_bresp),
        .s_axi_bvalid   (m_axi_vdma_bvalid),
        .s_axi_bready   (m_axi_vdma_bready),
        // Read address
        .s_axi_arid     (m_axi_vdma_arid),
        .s_axi_araddr   (m_axi_vdma_araddr),
        .s_axi_arlen    (m_axi_vdma_arlen),
        .s_axi_arsize   (m_axi_vdma_arsize),
        .s_axi_arburst  (m_axi_vdma_arburst),
        .s_axi_arvalid  (m_axi_vdma_arvalid),
        .s_axi_arready  (m_axi_vdma_arready),
        // Read data
        .s_axi_rid      (m_axi_vdma_rid),
        .s_axi_rdata    (m_axi_vdma_rdata),
        .s_axi_rresp    (m_axi_vdma_rresp),
        .s_axi_rlast    (m_axi_vdma_rlast),
        .s_axi_rvalid   (m_axi_vdma_rvalid),
        .s_axi_rready   (m_axi_vdma_rready),
        // Error injection
        .error_inject_i (1'b0)
    );

    // ================================================================
    // AXI-Lite Write Task
    // ================================================================
    task axil_write;
        input [31:0] addr;
        input [31:0] data_in;
        integer timeout;
        begin
            @(posedge clk); #1;
            s_axi_lite_awaddr  = addr;
            s_axi_lite_awvalid = 1'b1;
            s_axi_lite_wdata   = data_in;
            s_axi_lite_wstrb   = 4'hF;
            s_axi_lite_wvalid  = 1'b1;
            s_axi_lite_bready  = 1'b1;
            timeout = 200;
            while (timeout > 0) begin
                @(posedge clk); #1;
                if (s_axi_lite_awready && s_axi_lite_wready)
                    timeout = 0;
                else
                    timeout = timeout - 1;
            end
            @(posedge clk); #1;
            s_axi_lite_awvalid = 1'b0;
            s_axi_lite_wvalid  = 1'b0;
            timeout = 200;
            while (timeout > 0) begin
                @(posedge clk); #1;
                if (s_axi_lite_bvalid)
                    timeout = 0;
                else
                    timeout = timeout - 1;
            end
            @(posedge clk); #1;
            s_axi_lite_bready = 1'b0;
        end
    endtask

    // ================================================================
    // AXI-Lite Read Task
    // ================================================================
    task axil_read;
        input  [31:0] addr;
        output [31:0] data_out;
        integer timeout;
        begin
            @(posedge clk); #1;
            s_axi_lite_araddr  = addr;
            s_axi_lite_arvalid = 1'b1;
            s_axi_lite_rready  = 1'b1;
            timeout = 200;
            while (timeout > 0) begin
                @(posedge clk); #1;
                if (s_axi_lite_arready)
                    timeout = 0;
                else
                    timeout = timeout - 1;
            end
            @(posedge clk); #1;
            s_axi_lite_arvalid = 1'b0;
            timeout = 200;
            while (timeout > 0) begin
                @(posedge clk); #1;
                if (s_axi_lite_rvalid)
                    timeout = 0;
                else
                    timeout = timeout - 1;
            end
            data_out = s_axi_lite_rdata;
            @(posedge clk); #1;
            s_axi_lite_rready = 1'b0;
        end
    endtask

    // ================================================================
    // Check Task
    // ================================================================
    task check;
        input [255:0] test_name;
        input [31:0]  actual;
        input [31:0]  expected;
        begin
            if (actual === expected) begin
                $display("[PASS] %0s: got 0x%08x", test_name, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %0s: expected 0x%08x, got 0x%08x",
                         test_name, expected, actual);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // ================================================================
    // Check Non-Zero Task
    // ================================================================
    task check_nonzero;
        input [255:0] test_name;
        input [31:0]  actual;
        begin
            if (actual !== 32'd0) begin
                $display("[PASS] %0s: got 0x%08x (non-zero)", test_name, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %0s: expected non-zero, got 0x%08x",
                         test_name, actual);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // ================================================================
    // Wait for IRQ or status bit with timeout
    // ================================================================
    task wait_for_irq;
        input integer max_cycles;
        output integer timed_out;
        integer cnt;
        begin
            timed_out = 0;
            cnt = 0;
            while (cnt < max_cycles) begin
                @(posedge clk);
                if (irq_camera_ready) begin
                    cnt = max_cycles; // exit loop
                end else begin
                    cnt = cnt + 1;
                end
            end
            if (!irq_camera_ready)
                timed_out = 1;
        end
    endtask

    task wait_for_status_bit;
        input integer bit_pos;
        input integer max_cycles;
        output integer timed_out;
        reg [31:0] status;
        integer cnt;
        begin
            timed_out = 0;
            cnt = 0;
            while (cnt < max_cycles) begin
                axil_read(REG_CAM_STATUS, status);
                if (status[bit_pos]) begin
                    cnt = max_cycles; // exit
                end else begin
                    cnt = cnt + 1;
                    repeat (100) @(posedge clk); // poll every 100 clks
                end
            end
            if (!status[bit_pos])
                timed_out = 1;
        end
    endtask

    // ================================================================
    // DDR memory read helper (byte-addressable, returns 128-bit word)
    // ================================================================
    function [127:0] ddr_read_128;
        input [31:0] byte_addr;
        integer i;
        reg [127:0] val;
        begin
            val = 128'd0;
            for (i = 0; i < 16; i = i + 1) begin
                val = val | ({{120{1'b0}}, u_ddr.u_mem_array.mem[byte_addr + i]} << (i * 8));
            end
            ddr_read_128 = val;
        end
    endfunction

    // ================================================================
    // Initial AXI-Lite signal state
    // ================================================================
    task init_axil_signals;
        begin
            s_axi_lite_awaddr  = 32'd0;
            s_axi_lite_awvalid = 1'b0;
            s_axi_lite_wdata   = 32'd0;
            s_axi_lite_wstrb   = 4'h0;
            s_axi_lite_wvalid  = 1'b0;
            s_axi_lite_bready  = 1'b0;
            s_axi_lite_araddr  = 32'd0;
            s_axi_lite_arvalid = 1'b0;
            s_axi_lite_rready  = 1'b0;
        end
    endtask

    // ================================================================
    // Main Test Sequence
    // ================================================================
    integer timeout_flag;
    reg [127:0] ddr_word;
    integer i;
    integer nonzero_count;

    initial begin
        $display("============================================================");
        $display("  Camera Subsystem L2 Integration Testbench");
        $display("  DVP: %0dx%0d  ISP output: %0dx%0d",
                 DVP_H_ACTIVE, DVP_V_ACTIVE, ISP_OUT_W, ISP_OUT_H);
        $display("============================================================");

        test_num   = 0;
        pass_count = 0;
        fail_count = 0;
        dvp_enable = 1'b0;
        rst_n      = 1'b1;

        init_axil_signals;

        // ---- Reset ----
        @(posedge clk); #1;
        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        #1; rst_n = 1'b1;
        repeat (10) @(posedge clk);

        // ============================================================
        // C1: Register Config — write and readback
        // ============================================================
        test_num = 1;
        $display("\n--- C1: Register Config Write/Readback ---");

        axil_write(REG_ISP_CONFIG, ISP_CONFIG_VAL);
        axil_read(REG_ISP_CONFIG, read_data);
        check("C1 ISP_CONFIG readback", read_data, ISP_CONFIG_VAL);

        axil_write(REG_ISP_SCALE_X, SCALE_X);
        axil_read(REG_ISP_SCALE_X, read_data);
        check("C1 ISP_SCALE_X readback", read_data, SCALE_X);

        axil_write(REG_ISP_SCALE_Y, SCALE_Y);
        axil_read(REG_ISP_SCALE_Y, read_data);
        check("C1 ISP_SCALE_Y readback", read_data, SCALE_Y);

        axil_write(REG_FRAME_BUF_A_ADDR, FRAME_BUF_A);
        axil_read(REG_FRAME_BUF_A_ADDR, read_data);
        check("C1 FRAME_BUF_A readback", read_data, FRAME_BUF_A);

        axil_write(REG_FRAME_BUF_B_ADDR, FRAME_BUF_B);
        axil_read(REG_FRAME_BUF_B_ADDR, read_data);
        check("C1 FRAME_BUF_B readback", read_data, FRAME_BUF_B);

        axil_write(REG_SENSOR_CONFIG, SENSOR_CONFIG_VAL);
        axil_read(REG_SENSOR_CONFIG, read_data);
        check("C1 SENSOR_CONFIG readback", read_data, SENSOR_CONFIG_VAL);

        axil_write(REG_CROP_X, 32'd0);
        axil_read(REG_CROP_X, read_data);
        check("C1 CROP_X readback", read_data, 32'd0);

        axil_write(REG_CROP_Y, 32'd0);
        axil_read(REG_CROP_Y, read_data);
        check("C1 CROP_Y readback", read_data, 32'd0);

        axil_write(REG_CROP_WIDTH, 32'd16);
        axil_read(REG_CROP_WIDTH, read_data);
        check("C1 CROP_WIDTH readback", read_data, 32'd16);

        axil_write(REG_CROP_HEIGHT, 32'd16);
        axil_read(REG_CROP_HEIGHT, read_data);
        check("C1 CROP_HEIGHT readback", read_data, 32'd16);

        axil_write(REG_CROP_OUT_WIDTH, 32'd8);
        axil_read(REG_CROP_OUT_WIDTH, read_data);
        check("C1 CROP_OUT_WIDTH readback", read_data, 32'd8);

        axil_write(REG_CROP_OUT_HEIGHT, 32'd8);
        axil_read(REG_CROP_OUT_HEIGHT, read_data);
        check("C1 CROP_OUT_HEIGHT readback", read_data, 32'd8);

        axil_write(REG_CROP_BUF_ADDR, CROP_BUF);
        axil_read(REG_CROP_BUF_ADDR, read_data);
        check("C1 CROP_BUF_ADDR readback", read_data, CROP_BUF);

        // ============================================================
        // C2: Status After Reset — all idle/zero
        // ============================================================
        test_num = 2;
        $display("\n--- C2: Status After Reset ---");

        axil_read(REG_CAM_STATUS, read_data);
        check("C2 CAM_STATUS idle", read_data, 32'd0);

        axil_read(REG_ACTIVE_BUF, read_data);
        check("C2 ACTIVE_BUF zero", read_data, 32'd0);

        axil_read(REG_PERF_CAPTURE_CYC, read_data);
        check("C2 PERF_CAPTURE_CYC zero", read_data, 32'd0);

        axil_read(REG_PERF_ISP_CYC, read_data);
        check("C2 PERF_ISP_CYC zero", read_data, 32'd0);

        axil_read(REG_PERF_CROP_CYC, read_data);
        check("C2 PERF_CROP_CYC zero", read_data, 32'd0);

        // ============================================================
        // C3: DVP Capture Start
        // ============================================================
        test_num = 3;
        $display("\n--- C3: DVP Capture Start ---");

        // Configure for capture
        axil_write(REG_SENSOR_CONFIG, SENSOR_CONFIG_VAL);
        axil_write(REG_ISP_CONFIG, ISP_CONFIG_VAL);
        axil_write(REG_ISP_SCALE_X, SCALE_X);
        axil_write(REG_ISP_SCALE_Y, SCALE_Y);
        axil_write(REG_FRAME_BUF_A_ADDR, FRAME_BUF_A);
        axil_write(REG_FRAME_BUF_B_ADDR, FRAME_BUF_B);
        axil_write(REG_RAW_FRAME_ADDR, FRAME_BUF_A);
        // Frame size: ISP_OUT_W * ISP_OUT_H * 4 bytes (RGBX)
        axil_write(REG_FRAME_SIZE_BYTES, ISP_OUT_W * ISP_OUT_H * 4);

        // Enable camera subsystem (bit0=enable, bit3=irq_enable)
        axil_write(REG_CAM_CONTROL, 32'h0000_0009);

        // Enable DVP BFM
        dvp_enable = 1'b1;

        // Trigger capture
        axil_write(REG_CAPTURE_START, 32'h0000_0001);

        $display("  Waiting for capture to complete...");

        // Wait for IRQ or frame_ready status
        wait_for_irq(CAPTURE_TIMEOUT, timeout_flag);

        if (timeout_flag) begin
            // Fallback: poll status register
            $display("  IRQ not seen, polling CAM_STATUS...");
            wait_for_status_bit(STS_FRAME_READY, 5000, timeout_flag);
        end

        if (timeout_flag) begin
            $display("[FAIL] C3: Capture timed out");
            fail_count = fail_count + 1;
        end else begin
            $display("[PASS] C3: Capture completed");
            pass_count = pass_count + 1;
        end

        // Verify status shows frame_ready
        axil_read(REG_CAM_STATUS, read_data);
        $display("  CAM_STATUS after capture: 0x%08x", read_data);
        if (read_data[STS_FRAME_READY]) begin
            $display("[PASS] C3: frame_ready asserted in status");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] C3: frame_ready not asserted (status=0x%08x)", read_data);
            fail_count = fail_count + 1;
        end

        // Disable DVP after first frame
        dvp_enable = 1'b0;

        // ============================================================
        // C4: IRQ Flow — verify assert and clear
        // ============================================================
        test_num = 4;
        $display("\n--- C4: IRQ Flow ---");

        if (irq_camera_ready) begin
            $display("[PASS] C4: irq_camera_ready asserted");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] C4: irq_camera_ready not asserted");
            fail_count = fail_count + 1;
        end

        // Clear IRQ
        axil_write(REG_IRQ_CLEAR, 32'h0000_0001);
        repeat (10) @(posedge clk);

        if (!irq_camera_ready) begin
            $display("[PASS] C4: irq_camera_ready deasserted after clear");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] C4: irq_camera_ready still asserted after clear");
            fail_count = fail_count + 1;
        end

        // ============================================================
        // C5: PERF Counters — should be > 0 after capture
        // ============================================================
        test_num = 5;
        $display("\n--- C5: PERF Counters ---");

        axil_read(REG_PERF_CAPTURE_CYC, read_data);
        $display("  PERF_CAPTURE_CYC = %0d (0x%08x)", read_data, read_data);
        check_nonzero("C5 PERF_CAPTURE_CYC", read_data);

        axil_read(REG_PERF_ISP_CYC, read_data);
        $display("  PERF_ISP_CYC = %0d (0x%08x)", read_data, read_data);
        check_nonzero("C5 PERF_ISP_CYC", read_data);

        // ============================================================
        // C6: DMA Write Verification — check DDR for non-zero data
        // ============================================================
        test_num = 6;
        $display("\n--- C6: DMA Write Verification ---");

        nonzero_count = 0;
        for (i = 0; i < 8; i = i + 1) begin
            ddr_word = ddr_read_128(FRAME_BUF_A + (i * 16));
            if (ddr_word !== 128'd0)
                nonzero_count = nonzero_count + 1;
            if (i < 4)
                $display("  DDR[0x%05x] = 0x%032x", FRAME_BUF_A + (i * 16), ddr_word);
        end

        if (nonzero_count > 0) begin
            $display("[PASS] C6: Found %0d/8 non-zero 128-bit words at FRAME_BUF_A",
                     nonzero_count);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] C6: All DDR words at FRAME_BUF_A are zero");
            fail_count = fail_count + 1;
        end

        // Also verify memory before frame buffer is still zero (untouched)
        ddr_word = ddr_read_128(32'h0000_0000);
        check("C6 DDR[0x0] untouched", ddr_word[31:0], 32'd0);

        // ============================================================
        // C7: Register Reconfigure — capture to different address
        // ============================================================
        test_num = 7;
        $display("\n--- C7: Register Reconfigure + Second Capture ---");

        // After first capture, active_buf swapped to 1 (write=B).
        // Set FRAME_BUF_B to new address for second capture.
        axil_write(REG_FRAME_BUF_B_ADDR, 32'h0004_0000);
        axil_read(REG_FRAME_BUF_B_ADDR, read_data);
        check("C7 new FRAME_BUF_B readback", read_data, 32'h0004_0000);

        // Update RAW_FRAME_ADDR too
        axil_write(REG_RAW_FRAME_ADDR, 32'h0004_0000);

        // Clear any pending IRQ
        axil_write(REG_IRQ_CLEAR, 32'h0000_0003);
        repeat (10) @(posedge clk);

        // Re-enable DVP and trigger second capture
        dvp_enable = 1'b1;
        axil_write(REG_CAPTURE_START, 32'h0000_0001);

        $display("  Waiting for second capture...");
        wait_for_irq(CAPTURE_TIMEOUT, timeout_flag);

        if (timeout_flag) begin
            wait_for_status_bit(STS_FRAME_READY, 5000, timeout_flag);
        end

        if (timeout_flag) begin
            $display("[FAIL] C7: Second capture timed out");
            fail_count = fail_count + 1;
        end else begin
            $display("[PASS] C7: Second capture completed");
            pass_count = pass_count + 1;
        end

        // Verify DMA writes to new address
        nonzero_count = 0;
        for (i = 0; i < 4; i = i + 1) begin
            ddr_word = ddr_read_128(32'h0004_0000 + (i * 16));
            if (ddr_word !== 128'd0)
                nonzero_count = nonzero_count + 1;
        end

        if (nonzero_count > 0) begin
            $display("[PASS] C7: Found %0d/4 non-zero words at new FRAME_BUF_A (0x40000)",
                     nonzero_count);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] C7: All DDR words at 0x40000 are zero");
            fail_count = fail_count + 1;
        end

        dvp_enable = 1'b0;

        // Clear IRQ for next test
        axil_write(REG_IRQ_CLEAR, 32'h0000_0003);
        repeat (10) @(posedge clk);

        // ============================================================
        // C8: Crop Engine
        // ============================================================
        test_num = 8;
        $display("\n--- C8: Crop Engine ---");

        // Configure crop: 16x16 region from (0,0), output 8x8
        axil_write(REG_CROP_X, 32'd0);
        axil_write(REG_CROP_Y, 32'd0);
        axil_write(REG_CROP_WIDTH, 32'd16);
        axil_write(REG_CROP_HEIGHT, 32'd16);
        axil_write(REG_CROP_OUT_WIDTH, 32'd8);
        axil_write(REG_CROP_OUT_HEIGHT, 32'd8);
        axil_write(REG_CROP_BUF_ADDR, CROP_BUF);

        // Set raw frame addr to the last capture buffer
        axil_write(REG_RAW_FRAME_ADDR, 32'h0004_0000);

        // Enable crop in CAM_CONTROL (bit4=crop_enable)
        axil_write(REG_CAM_CONTROL, 32'h0000_0019); // enable + irq_enable + crop_enable

        // Trigger crop
        axil_write(REG_CROP_START, 32'h0000_0001);

        $display("  Waiting for crop to complete...");

        // Poll for crop_done (status bit 3)
        wait_for_status_bit(STS_CROP_DONE, CROP_TIMEOUT, timeout_flag);

        if (timeout_flag) begin
            $display("[FAIL] C8: Crop timed out");
            fail_count = fail_count + 1;
        end else begin
            $display("[PASS] C8: Crop completed");
            pass_count = pass_count + 1;
        end

        // Read crop perf counter
        axil_read(REG_PERF_CROP_CYC, read_data);
        $display("  PERF_CROP_CYC = %0d (0x%08x)", read_data, read_data);
        check_nonzero("C8 PERF_CROP_CYC", read_data);

        // Verify crop output data in DDR
        nonzero_count = 0;
        for (i = 0; i < 4; i = i + 1) begin
            ddr_word = ddr_read_128(CROP_BUF + (i * 16));
            if (ddr_word !== 128'd0)
                nonzero_count = nonzero_count + 1;
            $display("  DDR[CROP 0x%05x] = 0x%032x", CROP_BUF + (i * 16), ddr_word);
        end

        if (nonzero_count > 0) begin
            $display("[PASS] C8: Found %0d/4 non-zero words at CROP_BUF",
                     nonzero_count);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] C8: All DDR words at CROP_BUF are zero");
            fail_count = fail_count + 1;
        end

        // ============================================================
        // Summary
        // ============================================================
        repeat (50) @(posedge clk);

        $display("\n============================================================");
        $display("  Camera L2 Integration Test Summary");
        $display("  Passed: %0d   Failed: %0d", pass_count, fail_count);
        $display("============================================================");
        if (fail_count == 0)
            $display(">>> ALL TESTS PASSED <<<");
        else
            $display(">>> SOME TESTS FAILED <<<");

        $finish;
    end

    // (Debug monitors removed after validation)

    // ================================================================
    // Simulation timeout watchdog
    // ================================================================
    initial begin
        #100_000_000; // 100ms absolute timeout
        $display("[TIMEOUT] Simulation exceeded 100ms, aborting");
        $display("  Passed: %0d   Failed: %0d", pass_count, fail_count);
        $display(">>> TIMEOUT — TESTS INCOMPLETE <<<");
        $finish;
    end

    // ================================================================
    // Optional VCD dump
    // ================================================================
    initial begin
        if ($test$plusargs("VCD")) begin
            $dumpfile("tb_camera_integ.vcd");
            $dumpvars(0, tb_camera_integ);
        end
    end

endmodule
