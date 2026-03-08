`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Camera Subsystem
// Testbench: tb_cam_regfile
//////////////////////////////////////////////////////////////////////////////

module tb_cam_regfile;

    reg        clk;
    reg        rst_n;

    // AXI-Lite signals
    reg  [7:0]  awaddr;
    reg         awvalid;
    wire        awready;
    reg  [31:0] wdata;
    reg  [3:0]  wstrb;
    reg         wvalid;
    wire        wready;
    wire [1:0]  bresp;
    wire        bvalid;
    reg         bready;
    reg  [7:0]  araddr;
    reg         arvalid;
    wire        arready;
    wire [31:0] rdata;
    wire [1:0]  rresp;
    wire        rvalid;
    reg         rready;

    // Register outputs (selected)
    wire [31:0] cam_control;
    wire [31:0] isp_scale_x;
    wire [31:0] frame_buf_a;

    // Read-only inputs
    reg [31:0] cam_status;
    reg [31:0] perf_capture;
    reg [31:0] perf_isp;
    reg [31:0] perf_crop;

    integer err_count;

    cam_regfile uut (
        .clk              (clk),
        .rst_n            (rst_n),
        .s_axil_awaddr    (awaddr),
        .s_axil_awvalid   (awvalid),
        .s_axil_awready   (awready),
        .s_axil_wdata     (wdata),
        .s_axil_wstrb     (wstrb),
        .s_axil_wvalid    (wvalid),
        .s_axil_wready    (wready),
        .s_axil_bresp     (bresp),
        .s_axil_bvalid    (bvalid),
        .s_axil_bready    (bready),
        .s_axil_araddr    (araddr),
        .s_axil_arvalid   (arvalid),
        .s_axil_arready   (arready),
        .s_axil_rdata     (rdata),
        .s_axil_rresp     (rresp),
        .s_axil_rvalid    (rvalid),
        .s_axil_rready    (rready),
        .cam_control_o    (cam_control),
        .cam_status_i     (cam_status),
        .sensor_config_o  (),
        .isp_config_o     (),
        .isp_scale_x_o   (isp_scale_x),
        .isp_scale_y_o   (),
        .frame_buf_a_addr_o (frame_buf_a),
        .frame_buf_b_addr_o (),
        .active_buf_o     (),
        .capture_start_o  (),
        .crop_x_o         (),
        .crop_y_o         (),
        .crop_width_o     (),
        .crop_height_o    (),
        .crop_out_width_o (),
        .crop_out_height_o(),
        .crop_buf_addr_o  (),
        .crop_start_o     (),
        .irq_clear_o      (),
        .raw_frame_addr_o (),
        .frame_size_bytes_o(),
        .perf_capture_cyc_i (perf_capture),
        .perf_isp_cyc_i     (perf_isp),
        .perf_crop_cyc_i    (perf_crop)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // AXI-Lite write task
    task axil_write;
        input [7:0]  addr;
        input [31:0] data;
        begin
            @(posedge clk);
            awaddr  = addr;
            awvalid = 1;
            wdata   = data;
            wstrb   = 4'hF;
            wvalid  = 1;
            bready  = 1;

            // Wait for both handshakes
            fork
                begin : wait_aw
                    while (!(awvalid && awready)) @(posedge clk);
                    awvalid = 0;
                end
                begin : wait_w
                    while (!(wvalid && wready)) @(posedge clk);
                    wvalid = 0;
                end
            join

            // Wait for write response
            while (!bvalid) @(posedge clk);
            @(posedge clk);
            bready = 0;
        end
    endtask

    // AXI-Lite read task
    task axil_read;
        input  [7:0]  addr;
        output [31:0] data;
        begin
            @(posedge clk);
            araddr  = addr;
            arvalid = 1;
            rready  = 1;

            while (!(arvalid && arready)) @(posedge clk);
            arvalid = 0;

            while (!rvalid) @(posedge clk);
            data = rdata;
            @(posedge clk);
            rready = 0;
        end
    endtask

    reg [31:0] read_val;

    initial begin
        err_count    = 0;
        rst_n        = 0;
        awaddr       = 0;
        awvalid      = 0;
        wdata        = 0;
        wstrb        = 0;
        wvalid       = 0;
        bready       = 0;
        araddr       = 0;
        arvalid      = 0;
        rready       = 0;
        cam_status   = 32'hDEAD_BEEF;
        perf_capture = 32'h0000_1234;
        perf_isp     = 32'h0000_5678;
        perf_crop    = 32'h0000_9ABC;

        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // Test 1: Write CAM_CONTROL (0x00) and read back
        $display("Test 1: Write/Read CAM_CONTROL");
        axil_write(8'h00, 32'h0000_0001);
        axil_read(8'h00, read_val);
        if (read_val !== 32'h0000_0001) begin
            $display("FAIL: CAM_CONTROL = %h, expected 00000001", read_val);
            err_count = err_count + 1;
        end

        // Test 2: Write ISP_SCALE_X (0x10) and read back
        $display("Test 2: Write/Read ISP_SCALE_X");
        axil_write(8'h10, 32'h0002_0000);
        axil_read(8'h10, read_val);
        if (read_val !== 32'h0002_0000) begin
            $display("FAIL: ISP_SCALE_X = %h, expected 00020000", read_val);
            err_count = err_count + 1;
        end

        // Test 3: Write FRAME_BUF_A_ADDR (0x18)
        $display("Test 3: Write/Read FRAME_BUF_A_ADDR");
        axil_write(8'h18, 32'h1000_0000);
        axil_read(8'h18, read_val);
        if (read_val !== 32'h1000_0000) begin
            $display("FAIL: FRAME_BUF_A = %h, expected 10000000", read_val);
            err_count = err_count + 1;
        end

        // Test 4: Read read-only CAM_STATUS (0x04)
        $display("Test 4: Read CAM_STATUS (read-only)");
        axil_read(8'h04, read_val);
        if (read_val !== 32'hDEAD_BEEF) begin
            $display("FAIL: CAM_STATUS = %h, expected DEADBEEF", read_val);
            err_count = err_count + 1;
        end

        // Test 5: Read PERF_CAPTURE_CYC (0x54)
        $display("Test 5: Read PERF_CAPTURE_CYC");
        axil_read(8'h54, read_val);
        if (read_val !== 32'h0000_1234) begin
            $display("FAIL: PERF_CAPTURE_CYC = %h, expected 00001234", read_val);
            err_count = err_count + 1;
        end

        // Test 6: Default value of ISP_SCALE_Y should be 1.0 (0x00010000)
        $display("Test 6: Check ISP_SCALE_Y default");
        axil_read(8'h14, read_val);
        if (read_val !== 32'h0001_0000) begin
            $display("FAIL: ISP_SCALE_Y default = %h, expected 00010000", read_val);
            err_count = err_count + 1;
        end

        // Summary
        if (err_count == 0)
            $display("PASS: tb_cam_regfile — all tests passed");
        else
            $display("FAIL: tb_cam_regfile — %0d errors", err_count);

        $finish;
    end

endmodule
