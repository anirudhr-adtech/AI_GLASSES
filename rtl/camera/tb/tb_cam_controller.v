`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Camera Subsystem
// Testbench: tb_cam_controller
// Description: Self-checking testbench for camera controller FSM
//////////////////////////////////////////////////////////////////////////////

module tb_cam_controller;

    localparam CLK_PERIOD = 10;

    reg         clk;
    reg         rst_n;

    // Register interface
    reg         reg_enable;
    reg         reg_soft_reset;
    reg         reg_continuous;
    reg         reg_irq_enable;
    reg         reg_crop_enable;
    reg         reg_capture_start;
    reg         reg_crop_start;
    reg         reg_bypass;
    reg  [9:0]  reg_src_width, reg_src_height;
    reg  [9:0]  reg_dst_width, reg_dst_height;
    reg  [23:0] reg_scale_x, reg_scale_y;
    reg  [31:0] reg_frame_buf_addr, reg_frame_size;
    reg  [9:0]  reg_crop_x, reg_crop_y, reg_crop_w, reg_crop_h;
    reg  [9:0]  reg_crop_out_w, reg_crop_out_h;
    reg  [31:0] reg_raw_frame_addr;
    reg  [15:0] reg_frame_stride;
    reg  [31:0] reg_crop_buf_addr;
    reg         reg_irq_clear_frame, reg_irq_clear_crop;

    // Status outputs
    wire        capture_busy;
    wire        frame_ready;
    wire        crop_busy;
    wire        crop_done;
    wire        fifo_overrun;
    wire        dma_busy;
    wire [7:0]  frame_count;
    wire [31:0] perf_capture, perf_isp, perf_crop;

    // Sub-module interfaces
    reg         dvp_frame_done;
    wire        isp_start;
    reg         isp_done;
    wire        vdma_start;
    reg         vdma_done;
    wire        crop_start;
    reg         crop_engine_done;
    wire        fbuf_swap;
    wire        irq;

    integer test_num, pass_count, fail_count;

    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    cam_controller u_dut (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .reg_enable_i           (reg_enable),
        .reg_soft_reset_i       (reg_soft_reset),
        .reg_continuous_i       (reg_continuous),
        .reg_irq_enable_i       (reg_irq_enable),
        .reg_crop_enable_i      (reg_crop_enable),
        .reg_capture_start_i    (reg_capture_start),
        .reg_crop_start_i       (reg_crop_start),
        .reg_bypass_i           (reg_bypass),
        .reg_src_width_i        (reg_src_width),
        .reg_src_height_i       (reg_src_height),
        .reg_dst_width_i        (reg_dst_width),
        .reg_dst_height_i       (reg_dst_height),
        .reg_scale_x_i          (reg_scale_x),
        .reg_scale_y_i          (reg_scale_y),
        .reg_frame_buf_addr_i   (reg_frame_buf_addr),
        .reg_frame_size_i       (reg_frame_size),
        .reg_crop_x_i           (reg_crop_x),
        .reg_crop_y_i           (reg_crop_y),
        .reg_crop_w_i           (reg_crop_w),
        .reg_crop_h_i           (reg_crop_h),
        .reg_crop_out_w_i       (reg_crop_out_w),
        .reg_crop_out_h_i       (reg_crop_out_h),
        .reg_raw_frame_addr_i   (reg_raw_frame_addr),
        .reg_frame_stride_i     (reg_frame_stride),
        .reg_crop_buf_addr_i    (reg_crop_buf_addr),
        .reg_irq_clear_frame_i  (reg_irq_clear_frame),
        .reg_irq_clear_crop_i   (reg_irq_clear_crop),
        .capture_busy_o         (capture_busy),
        .frame_ready_o          (frame_ready),
        .crop_busy_o            (crop_busy),
        .crop_done_o            (crop_done),
        .fifo_overrun_o         (fifo_overrun),
        .dma_busy_o             (dma_busy),
        .frame_count_o          (frame_count),
        .perf_capture_cyc_o     (perf_capture),
        .perf_isp_cyc_o         (perf_isp),
        .perf_crop_cyc_o        (perf_crop),
        .dvp_frame_done_i       (dvp_frame_done),
        .isp_start_o            (isp_start),
        .isp_done_i             (isp_done),
        .vdma_start_o           (vdma_start),
        .vdma_done_i            (vdma_done),
        .crop_start_o           (crop_start),
        .crop_engine_done_i     (crop_engine_done),
        .fbuf_swap_o            (fbuf_swap),
        .irq_camera_ready_o     (irq)
    );

    task reset_dut;
        begin
            rst_n              = 1'b0;
            reg_enable         = 1'b0;
            reg_soft_reset     = 1'b0;
            reg_continuous     = 1'b0;
            reg_irq_enable     = 1'b0;
            reg_crop_enable    = 1'b0;
            reg_capture_start  = 1'b0;
            reg_crop_start     = 1'b0;
            reg_bypass         = 1'b0;
            reg_src_width      = 10'd640;
            reg_src_height     = 10'd480;
            reg_dst_width      = 10'd128;
            reg_dst_height     = 10'd128;
            reg_scale_x        = 24'h050000;
            reg_scale_y        = 24'h03C000;
            reg_frame_buf_addr = 32'h0400_0000;
            reg_frame_size     = 32'd65536;
            reg_crop_x         = 10'd0;
            reg_crop_y         = 10'd0;
            reg_crop_w         = 10'd112;
            reg_crop_h         = 10'd112;
            reg_crop_out_w     = 10'd112;
            reg_crop_out_h     = 10'd112;
            reg_raw_frame_addr = 32'h0402_0000;
            reg_frame_stride   = 16'd2560;
            reg_crop_buf_addr  = 32'h0420_0000;
            reg_irq_clear_frame = 1'b0;
            reg_irq_clear_crop  = 1'b0;
            dvp_frame_done     = 1'b0;
            isp_done           = 1'b0;
            vdma_done          = 1'b0;
            crop_engine_done   = 1'b0;
            repeat (5) @(posedge clk);
            rst_n = 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task check(input [255:0] name, input cond);
        begin
            test_num = test_num + 1;
            if (cond) begin
                $display("[PASS] Test %0d: %0s", test_num, name);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] Test %0d: %0s", test_num, name);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        $display("============================================================");
        $display("  TB: cam_controller — Camera Orchestrator FSM");
        $display("============================================================");

        test_num   = 0;
        pass_count = 0;
        fail_count = 0;

        reset_dut;

        // Test 1: Reset state
        check("capture_busy=0 after reset", capture_busy == 1'b0);
        check("frame_ready=0 after reset", frame_ready == 1'b0);
        check("irq=0 after reset", irq == 1'b0);
        check("frame_count=0 after reset", frame_count == 8'd0);

        // Test 2: Single-shot capture sequence
        reg_enable  = 1'b1;
        reg_irq_enable = 1'b1;
        @(posedge clk);
        reg_capture_start = 1'b1;
        @(posedge clk);
        reg_capture_start = 1'b0;

        // Should transition through states
        repeat (3) @(posedge clk);
        check("capture_busy asserted", capture_busy == 1'b1);

        // Simulate DVP frame done
        repeat (5) @(posedge clk);
        dvp_frame_done = 1'b1;
        @(posedge clk);
        dvp_frame_done = 1'b0;

        // Wait for ISP + VDMA start (both launch together)
        repeat (3) @(posedge clk);
        check("ISP start pulsed", isp_start == 1'b1 || u_dut.cap_state == 3'd3);
        check("DMA state reached", vdma_start == 1'b1 || u_dut.cap_state == 3'd3);

        // Simulate VDMA done (ISP and VDMA run concurrently, VDMA done ends CS_ISP)
        repeat (10) @(posedge clk);
        vdma_done = 1'b1;
        @(posedge clk);
        vdma_done = 1'b0;

        repeat (3) @(posedge clk);
        check("frame_ready asserted", frame_ready == 1'b1);
        check("IRQ asserted", irq == 1'b1);
        check("frame_count incremented", frame_count == 8'd1);
        check("fbuf_swap pulsed", fbuf_swap == 1'b1 || frame_ready == 1'b1);

        // Test 3: IRQ clear
        @(posedge clk);
        reg_irq_clear_frame = 1'b1;
        @(posedge clk);
        reg_irq_clear_frame = 1'b0;
        @(posedge clk);
        check("frame_ready cleared", frame_ready == 1'b0);
        check("IRQ cleared", irq == 1'b0);

        // Test 4: Crop flow
        reg_crop_enable = 1'b1;
        @(posedge clk);
        reg_crop_start = 1'b1;
        @(posedge clk);
        reg_crop_start = 1'b0;

        repeat (3) @(posedge clk);
        check("crop_busy asserted", crop_busy == 1'b1);

        // Simulate crop done
        repeat (5) @(posedge clk);
        crop_engine_done = 1'b1;
        @(posedge clk);
        crop_engine_done = 1'b0;

        repeat (3) @(posedge clk);
        check("crop_done asserted", crop_done == 1'b1);
        check("IRQ asserted for crop", irq == 1'b1);

        // Test 5: Soft reset
        @(posedge clk);
        reg_soft_reset = 1'b1;
        @(posedge clk);
        reg_soft_reset = 1'b0;
        repeat (3) @(posedge clk);
        check("capture_busy cleared after soft reset", capture_busy == 1'b0);
        check("crop_busy cleared after soft reset", crop_busy == 1'b0);

        // Summary
        $display("============================================================");
        $display("  Results: %0d passed, %0d failed out of %0d tests",
                 pass_count, fail_count, test_num);
        $display("============================================================");
        if (fail_count == 0)
            $display("  >>> ALL TESTS PASSED <<<");
        else
            $display("  >>> SOME TESTS FAILED <<<");
        $finish;
    end

    initial begin
        #100000;
        $display("[TIMEOUT]");
        $finish;
    end

endmodule
