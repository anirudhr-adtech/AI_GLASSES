`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Camera Subsystem
// Module: cam_subsys_top
// Description: Top-level camera wrapper — instantiates all camera modules
//////////////////////////////////////////////////////////////////////////////

module cam_subsys_top (
    input  wire         clk_i,
    input  wire         rst_ni,
    // ----------------------------------------------------------------
    // DVP camera interface
    // ----------------------------------------------------------------
    input  wire         cam_pclk_i,
    input  wire         cam_vsync_i,
    input  wire         cam_href_i,
    input  wire [7:0]   cam_data_i,
    // ----------------------------------------------------------------
    // AXI4-Lite slave (CPU register access)
    // ----------------------------------------------------------------
    input  wire [31:0]  s_axi_lite_awaddr,
    input  wire         s_axi_lite_awvalid,
    output wire         s_axi_lite_awready,
    input  wire [31:0]  s_axi_lite_wdata,
    input  wire [3:0]   s_axi_lite_wstrb,
    input  wire         s_axi_lite_wvalid,
    output wire         s_axi_lite_wready,
    output wire [1:0]   s_axi_lite_bresp,
    output wire         s_axi_lite_bvalid,
    input  wire         s_axi_lite_bready,
    input  wire [31:0]  s_axi_lite_araddr,
    input  wire         s_axi_lite_arvalid,
    output wire         s_axi_lite_arready,
    output wire [31:0]  s_axi_lite_rdata,
    output wire [1:0]   s_axi_lite_rresp,
    output wire         s_axi_lite_rvalid,
    input  wire         s_axi_lite_rready,
    // ----------------------------------------------------------------
    // AXI4 master (128-bit DMA to DDR)
    // ----------------------------------------------------------------
    output wire [3:0]   m_axi_vdma_awid,
    output wire [31:0]  m_axi_vdma_awaddr,
    output wire [7:0]   m_axi_vdma_awlen,
    output wire [2:0]   m_axi_vdma_awsize,
    output wire [1:0]   m_axi_vdma_awburst,
    output wire         m_axi_vdma_awvalid,
    input  wire         m_axi_vdma_awready,
    output wire [127:0] m_axi_vdma_wdata,
    output wire [15:0]  m_axi_vdma_wstrb,
    output wire         m_axi_vdma_wlast,
    output wire         m_axi_vdma_wvalid,
    input  wire         m_axi_vdma_wready,
    input  wire [3:0]   m_axi_vdma_bid,
    input  wire [1:0]   m_axi_vdma_bresp,
    input  wire         m_axi_vdma_bvalid,
    output wire         m_axi_vdma_bready,
    output wire [3:0]   m_axi_vdma_arid,
    output wire [31:0]  m_axi_vdma_araddr,
    output wire [7:0]   m_axi_vdma_arlen,
    output wire [2:0]   m_axi_vdma_arsize,
    output wire [1:0]   m_axi_vdma_arburst,
    output wire         m_axi_vdma_arvalid,
    input  wire         m_axi_vdma_arready,
    input  wire [3:0]   m_axi_vdma_rid,
    input  wire [127:0] m_axi_vdma_rdata,
    input  wire [1:0]   m_axi_vdma_rresp,
    input  wire         m_axi_vdma_rlast,
    input  wire         m_axi_vdma_rvalid,
    output wire         m_axi_vdma_rready,
    // ----------------------------------------------------------------
    // Interrupt
    // ----------------------------------------------------------------
    output wire         irq_camera_ready_o
);

    // ================================================================
    // Register file raw outputs (32-bit each)
    // ================================================================
    wire [31:0] reg_cam_control;
    wire [31:0] reg_cam_status;
    wire [31:0] reg_sensor_config;
    wire [31:0] reg_isp_config;
    wire [31:0] reg_isp_scale_x;
    wire [31:0] reg_isp_scale_y;
    wire [31:0] reg_frame_buf_a_addr;
    wire [31:0] reg_frame_buf_b_addr;
    wire [31:0] reg_active_buf;
    wire [31:0] reg_capture_start;
    wire [31:0] reg_crop_x;
    wire [31:0] reg_crop_y;
    wire [31:0] reg_crop_width;
    wire [31:0] reg_crop_height;
    wire [31:0] reg_crop_out_width;
    wire [31:0] reg_crop_out_height;
    wire [31:0] reg_crop_buf_addr;
    wire [31:0] reg_crop_start;
    wire [31:0] reg_irq_clear;
    wire [31:0] reg_raw_frame_addr;
    wire [31:0] reg_frame_size_bytes;

    // Decoded register fields
    wire        cfg_enable         = reg_cam_control[0];
    wire        cfg_soft_reset     = reg_cam_control[1];
    wire        cfg_continuous     = reg_cam_control[2];
    wire        cfg_irq_enable     = reg_cam_control[3];
    wire        cfg_crop_enable    = reg_cam_control[4];
    wire        cfg_bypass         = reg_isp_config[20];
    wire [9:0]  cfg_src_width      = reg_sensor_config[11:2];
    wire [9:0]  cfg_src_height     = reg_sensor_config[21:12];
    wire [9:0]  cfg_dst_width      = reg_isp_config[9:0];
    wire [9:0]  cfg_dst_height     = reg_isp_config[19:10];
    wire [23:0] cfg_scale_x        = reg_isp_scale_x[23:0];
    wire [23:0] cfg_scale_y        = reg_isp_scale_y[23:0];
    wire        cfg_capture_start  = reg_capture_start[0];
    wire        cfg_crop_start     = reg_crop_start[0];
    wire [9:0]  cfg_crop_x         = reg_crop_x[9:0];
    wire [9:0]  cfg_crop_y         = reg_crop_y[9:0];
    wire [9:0]  cfg_crop_w         = reg_crop_width[9:0];
    wire [9:0]  cfg_crop_h         = reg_crop_height[9:0];
    wire [9:0]  cfg_crop_out_w     = reg_crop_out_width[9:0];
    wire [9:0]  cfg_crop_out_h     = reg_crop_out_height[9:0];
    wire        cfg_irq_clear_frame = reg_irq_clear[0];
    wire        cfg_irq_clear_crop  = reg_irq_clear[1];

    // Status from controller to regfile
    wire        sts_capture_busy;
    wire        sts_frame_ready;
    wire        sts_crop_busy;
    wire        sts_crop_done;
    wire        sts_fifo_overrun;
    wire        sts_dma_busy;
    wire [7:0]  sts_frame_count;
    wire [31:0] sts_perf_capture;
    wire [31:0] sts_perf_isp;
    wire [31:0] sts_perf_crop;

    // Compose CAM_STATUS register
    wire [31:0] cam_status_reg = {
        16'd0,
        sts_frame_count,        // [15:8]
        2'd0,
        sts_dma_busy,           // [5]
        sts_fifo_overrun,       // [4]
        sts_crop_done,          // [3]
        sts_crop_busy,          // [2]
        sts_frame_ready,        // [1]
        sts_capture_busy        // [0]
    };

    // Frame buffer ctrl
    wire [31:0] active_wr_addr;
    wire [31:0] active_rd_addr;
    wire        fbuf_swap;

    // Frame stride: src_width * 4 bytes per pixel (RGBX)
    wire [15:0] frame_stride = {4'd0, cfg_src_width, 2'b00};

    // DVP capture -> pixel FIFO
    wire [15:0] dvp_pixel_data;
    wire        dvp_pixel_valid;
    wire        dvp_frame_done;

    // Pixel FIFO -> ISP (async FIFO interface)
    wire [15:0] fifo_rd_data;
    wire        fifo_rd_empty;
    reg         fifo_rd_en;
    wire        fifo_overflow;

    // ISP -> Video DMA
    wire [127:0] isp_out_data;
    wire         isp_out_valid;
    wire         isp_out_ready;
    wire         isp_done;
    wire         isp_in_ready;

    // Video DMA signals
    wire         vdma_done;
    wire         vdma_in_ready;

    // Controller -> sub-modules
    wire         isp_start;
    wire         vdma_start;
    wire         crop_start_pulse;

    // Crop engine signals
    wire         crop_engine_done;
    wire [3:0]   crop_axi_arid;
    wire [31:0]  crop_axi_araddr;
    wire [7:0]   crop_axi_arlen;
    wire [2:0]   crop_axi_arsize;
    wire [1:0]   crop_axi_arburst;
    wire         crop_axi_arvalid;
    wire [3:0]   crop_axi_awid;
    wire [31:0]  crop_axi_awaddr;
    wire [7:0]   crop_axi_awlen;
    wire [2:0]   crop_axi_awsize;
    wire [1:0]   crop_axi_awburst;
    wire         crop_axi_awvalid;
    wire [127:0] crop_axi_wdata;
    wire [15:0]  crop_axi_wstrb;
    wire         crop_axi_wlast;
    wire         crop_axi_wvalid;
    wire         crop_axi_bready;
    wire         crop_axi_rready;

    // Video DMA AXI signals
    wire [3:0]   vdma_axi_awid;
    wire [31:0]  vdma_axi_awaddr;
    wire [7:0]   vdma_axi_awlen;
    wire [2:0]   vdma_axi_awsize;
    wire [1:0]   vdma_axi_awburst;
    wire         vdma_axi_awvalid;
    wire [127:0] vdma_axi_wdata;
    wire [15:0]  vdma_axi_wstrb;
    wire         vdma_axi_wlast;
    wire         vdma_axi_wvalid;
    wire         vdma_axi_bready;

    // ================================================================
    // FIFO read-side bridging: async FIFO (rd_en/rd_data/rd_empty)
    // -> ISP (in_pixel_i/in_valid_i/in_ready_o)
    // ================================================================
    wire fifo_data_valid = ~fifo_rd_empty;

    always @(posedge clk_i) begin
        if (!rst_ni)
            fifo_rd_en <= 1'b0;
        else
            fifo_rd_en <= ~fifo_rd_empty & isp_in_ready;
    end

    // ================================================================
    // AXI master mux: Video DMA writes + Crop engine reads/writes
    // (they never run simultaneously per architecture)
    // ================================================================

    // Read channel: only crop engine uses it
    assign m_axi_vdma_arid    = crop_axi_arid;
    assign m_axi_vdma_araddr  = crop_axi_araddr;
    assign m_axi_vdma_arlen   = crop_axi_arlen;
    assign m_axi_vdma_arsize  = crop_axi_arsize;
    assign m_axi_vdma_arburst = crop_axi_arburst;
    assign m_axi_vdma_arvalid = crop_axi_arvalid;
    assign m_axi_vdma_rready  = crop_axi_rready;

    // Write channel mux: crop_busy selects crop_dma_writer, else video_dma
    assign m_axi_vdma_awid    = sts_crop_busy ? crop_axi_awid    : vdma_axi_awid;
    assign m_axi_vdma_awaddr  = sts_crop_busy ? crop_axi_awaddr  : vdma_axi_awaddr;
    assign m_axi_vdma_awlen   = sts_crop_busy ? crop_axi_awlen   : vdma_axi_awlen;
    assign m_axi_vdma_awsize  = sts_crop_busy ? crop_axi_awsize  : vdma_axi_awsize;
    assign m_axi_vdma_awburst = sts_crop_busy ? crop_axi_awburst : vdma_axi_awburst;
    assign m_axi_vdma_awvalid = sts_crop_busy ? crop_axi_awvalid : vdma_axi_awvalid;
    assign m_axi_vdma_wdata   = sts_crop_busy ? crop_axi_wdata   : vdma_axi_wdata;
    assign m_axi_vdma_wstrb   = sts_crop_busy ? crop_axi_wstrb   : vdma_axi_wstrb;
    assign m_axi_vdma_wlast   = sts_crop_busy ? crop_axi_wlast   : vdma_axi_wlast;
    assign m_axi_vdma_wvalid  = sts_crop_busy ? crop_axi_wvalid  : vdma_axi_wvalid;
    assign m_axi_vdma_bready  = sts_crop_busy ? crop_axi_bready  : vdma_axi_bready;

    // ================================================================
    // Module instantiations
    // ================================================================

    // ----------------------------------------------------------------
    // 1. Register file (AXI4-Lite slave)
    //    cam_regfile uses s_axil_* with 8-bit address
    // ----------------------------------------------------------------
    cam_regfile u_regfile (
        .clk                  (clk_i),
        .rst_n                (rst_ni),
        .s_axil_awaddr        (s_axi_lite_awaddr[7:0]),
        .s_axil_awvalid       (s_axi_lite_awvalid),
        .s_axil_awready       (s_axi_lite_awready),
        .s_axil_wdata         (s_axi_lite_wdata),
        .s_axil_wstrb         (s_axi_lite_wstrb),
        .s_axil_wvalid        (s_axi_lite_wvalid),
        .s_axil_wready        (s_axi_lite_wready),
        .s_axil_bresp         (s_axi_lite_bresp),
        .s_axil_bvalid        (s_axi_lite_bvalid),
        .s_axil_bready        (s_axi_lite_bready),
        .s_axil_araddr        (s_axi_lite_araddr[7:0]),
        .s_axil_arvalid       (s_axi_lite_arvalid),
        .s_axil_arready       (s_axi_lite_arready),
        .s_axil_rdata         (s_axi_lite_rdata),
        .s_axil_rresp         (s_axi_lite_rresp),
        .s_axil_rvalid        (s_axi_lite_rvalid),
        .s_axil_rready        (s_axi_lite_rready),
        // Register outputs
        .cam_control_o        (reg_cam_control),
        .cam_status_i         (cam_status_reg),
        .sensor_config_o      (reg_sensor_config),
        .isp_config_o         (reg_isp_config),
        .isp_scale_x_o        (reg_isp_scale_x),
        .isp_scale_y_o        (reg_isp_scale_y),
        .frame_buf_a_addr_o   (reg_frame_buf_a_addr),
        .frame_buf_b_addr_o   (reg_frame_buf_b_addr),
        .active_buf_o         (reg_active_buf),
        .capture_start_o      (reg_capture_start),
        .crop_x_o             (reg_crop_x),
        .crop_y_o             (reg_crop_y),
        .crop_width_o         (reg_crop_width),
        .crop_height_o        (reg_crop_height),
        .crop_out_width_o     (reg_crop_out_width),
        .crop_out_height_o    (reg_crop_out_height),
        .crop_buf_addr_o      (reg_crop_buf_addr),
        .crop_start_o         (reg_crop_start),
        .irq_clear_o          (reg_irq_clear),
        .raw_frame_addr_o     (reg_raw_frame_addr),
        .frame_size_bytes_o   (reg_frame_size_bytes),
        .perf_capture_cyc_i   (sts_perf_capture),
        .perf_isp_cyc_i       (sts_perf_isp),
        .perf_crop_cyc_i      (sts_perf_crop)
    );

    // ----------------------------------------------------------------
    // 2. DVP capture
    // ----------------------------------------------------------------
    dvp_capture u_dvp_capture (
        .clk           (clk_i),
        .rst_n         (rst_ni),
        .cam_pclk_i    (cam_pclk_i),
        .cam_vsync_i   (cam_vsync_i),
        .cam_href_i    (cam_href_i),
        .cam_data_i    (cam_data_i),
        .pixel_data_o  (dvp_pixel_data),
        .pixel_valid_o (dvp_pixel_valid),
        .frame_done_o  (dvp_frame_done),
        .line_count_o  (),
        .pixel_count_o (),
        .src_width_i   (cfg_src_width),
        .src_height_i  (cfg_src_height)
    );

    // ----------------------------------------------------------------
    // 3. Pixel FIFO (PCLK -> sys_clk CDC)
    //    pixel_fifo: wr_clk, wr_rst_n, wr_en, wr_data, wr_full,
    //               rd_clk, rd_rst_n, rd_en, rd_data, rd_empty,
    //               overflow_o
    // ----------------------------------------------------------------
    pixel_fifo u_pixel_fifo (
        .wr_clk     (cam_pclk_i),
        .wr_rst_n   (rst_ni),
        .wr_en      (dvp_pixel_valid),
        .wr_data    (dvp_pixel_data),
        .wr_full    (),
        .rd_clk     (clk_i),
        .rd_rst_n   (rst_ni),
        .rd_en      (fifo_rd_en),
        .rd_data    (fifo_rd_data),
        .rd_empty   (fifo_rd_empty),
        .overflow_o (fifo_overflow)
    );

    // ----------------------------------------------------------------
    // 4. ISP-Lite pipeline
    // ----------------------------------------------------------------
    isp_lite u_isp_lite (
        .clk          (clk_i),
        .rst_n        (rst_ni),
        .start_i      (isp_start),
        .bypass_i     (cfg_bypass),
        .scale_x_i    (cfg_scale_x),
        .scale_y_i    (cfg_scale_y),
        .src_width_i  (cfg_src_width),
        .src_height_i (cfg_src_height),
        .dst_width_i  (cfg_dst_width),
        .dst_height_i (cfg_dst_height),
        .in_pixel_i   (fifo_rd_data),
        .in_valid_i   (fifo_rd_en),
        .in_ready_o   (isp_in_ready),
        .out_data_o   (isp_out_data),
        .out_valid_o  (isp_out_valid),
        .out_ready_i  (vdma_in_ready),
        .done_o       (isp_done)
    );

    // ----------------------------------------------------------------
    // 5. Video DMA (128-bit AXI4 master writes)
    // ----------------------------------------------------------------
    video_dma u_video_dma (
        .clk            (clk_i),
        .rst_n          (rst_ni),
        .start_i        (vdma_start),
        .base_addr_i    (active_wr_addr),
        .frame_size_i   (reg_frame_size_bytes),
        .in_data_i      (isp_out_data),
        .in_valid_i     (isp_out_valid),
        .in_ready_o     (vdma_in_ready),
        .done_o         (vdma_done),
        .m_axi_awid     (vdma_axi_awid),
        .m_axi_awaddr   (vdma_axi_awaddr),
        .m_axi_awlen    (vdma_axi_awlen),
        .m_axi_awsize   (vdma_axi_awsize),
        .m_axi_awburst  (vdma_axi_awburst),
        .m_axi_awvalid  (vdma_axi_awvalid),
        .m_axi_awready  (m_axi_vdma_awready & ~sts_crop_busy),
        .m_axi_wdata    (vdma_axi_wdata),
        .m_axi_wstrb    (vdma_axi_wstrb),
        .m_axi_wlast    (vdma_axi_wlast),
        .m_axi_wvalid   (vdma_axi_wvalid),
        .m_axi_wready   (m_axi_vdma_wready & ~sts_crop_busy),
        .m_axi_bid      (m_axi_vdma_bid),
        .m_axi_bresp    (m_axi_vdma_bresp),
        .m_axi_bvalid   (m_axi_vdma_bvalid & ~sts_crop_busy),
        .m_axi_bready   (vdma_axi_bready)
    );

    // ----------------------------------------------------------------
    // 6. Frame buffer controller
    //    frame_buf_ctrl: wr_addr_o, rd_addr_o (not write_addr_o)
    // ----------------------------------------------------------------
    frame_buf_ctrl u_fbuf_ctrl (
        .clk          (clk_i),
        .rst_n        (rst_ni),
        .buf_a_addr_i (reg_frame_buf_a_addr),
        .buf_b_addr_i (reg_frame_buf_b_addr),
        .active_buf_i (reg_active_buf[0]),
        .swap_i       (fbuf_swap),
        .wr_addr_o    (active_wr_addr),
        .rd_addr_o    (active_rd_addr)
    );

    // ----------------------------------------------------------------
    // 7. Crop engine
    // ----------------------------------------------------------------
    crop_engine u_crop_engine (
        .clk              (clk_i),
        .rst_n            (rst_ni),
        .crop_start_i     (crop_start_pulse),
        .crop_done_o      (crop_engine_done),
        .crop_x_i         (cfg_crop_x),
        .crop_y_i         (cfg_crop_y),
        .crop_w_i         (cfg_crop_w),
        .crop_h_i         (cfg_crop_h),
        .crop_out_w_i     (cfg_crop_out_w),
        .crop_out_h_i     (cfg_crop_out_h),
        .raw_frame_addr_i (reg_raw_frame_addr),
        .frame_stride_i   (frame_stride),
        .crop_buf_addr_i  (reg_crop_buf_addr),
        // AXI read
        .m_axi_arid       (crop_axi_arid),
        .m_axi_araddr     (crop_axi_araddr),
        .m_axi_arlen      (crop_axi_arlen),
        .m_axi_arsize     (crop_axi_arsize),
        .m_axi_arburst    (crop_axi_arburst),
        .m_axi_arvalid    (crop_axi_arvalid),
        .m_axi_arready    (m_axi_vdma_arready),
        .m_axi_rid        (m_axi_vdma_rid),
        .m_axi_rdata      (m_axi_vdma_rdata),
        .m_axi_rresp      (m_axi_vdma_rresp),
        .m_axi_rlast      (m_axi_vdma_rlast),
        .m_axi_rvalid     (m_axi_vdma_rvalid),
        .m_axi_rready     (crop_axi_rready),
        // AXI write
        .m_axi_awid       (crop_axi_awid),
        .m_axi_awaddr     (crop_axi_awaddr),
        .m_axi_awlen      (crop_axi_awlen),
        .m_axi_awsize     (crop_axi_awsize),
        .m_axi_awburst    (crop_axi_awburst),
        .m_axi_awvalid    (crop_axi_awvalid),
        .m_axi_awready    (m_axi_vdma_awready & sts_crop_busy),
        .m_axi_wdata      (crop_axi_wdata),
        .m_axi_wstrb      (crop_axi_wstrb),
        .m_axi_wlast      (crop_axi_wlast),
        .m_axi_wvalid     (crop_axi_wvalid),
        .m_axi_wready     (m_axi_vdma_wready & sts_crop_busy),
        .m_axi_bid        (m_axi_vdma_bid),
        .m_axi_bresp      (m_axi_vdma_bresp),
        .m_axi_bvalid     (m_axi_vdma_bvalid & sts_crop_busy),
        .m_axi_bready     (crop_axi_bready)
    );

    // ----------------------------------------------------------------
    // 8. Camera controller (orchestrator)
    // ----------------------------------------------------------------
    cam_controller u_controller (
        .clk                    (clk_i),
        .rst_n                  (rst_ni),
        // Register interface
        .reg_enable_i           (cfg_enable),
        .reg_soft_reset_i       (cfg_soft_reset),
        .reg_continuous_i       (cfg_continuous),
        .reg_irq_enable_i       (cfg_irq_enable),
        .reg_crop_enable_i      (cfg_crop_enable),
        .reg_capture_start_i    (cfg_capture_start),
        .reg_crop_start_i       (cfg_crop_start),
        .reg_bypass_i           (cfg_bypass),
        .reg_src_width_i        (cfg_src_width),
        .reg_src_height_i       (cfg_src_height),
        .reg_dst_width_i        (cfg_dst_width),
        .reg_dst_height_i       (cfg_dst_height),
        .reg_scale_x_i          (cfg_scale_x),
        .reg_scale_y_i          (cfg_scale_y),
        .reg_frame_buf_addr_i   (active_wr_addr),
        .reg_frame_size_i       (reg_frame_size_bytes),
        .reg_crop_x_i           (cfg_crop_x),
        .reg_crop_y_i           (cfg_crop_y),
        .reg_crop_w_i           (cfg_crop_w),
        .reg_crop_h_i           (cfg_crop_h),
        .reg_crop_out_w_i       (cfg_crop_out_w),
        .reg_crop_out_h_i       (cfg_crop_out_h),
        .reg_raw_frame_addr_i   (reg_raw_frame_addr),
        .reg_frame_stride_i     (frame_stride),
        .reg_crop_buf_addr_i    (reg_crop_buf_addr),
        .reg_irq_clear_frame_i  (cfg_irq_clear_frame),
        .reg_irq_clear_crop_i   (cfg_irq_clear_crop),
        // Status outputs
        .capture_busy_o         (sts_capture_busy),
        .frame_ready_o          (sts_frame_ready),
        .crop_busy_o            (sts_crop_busy),
        .crop_done_o            (sts_crop_done),
        .fifo_overrun_o         (sts_fifo_overrun),
        .dma_busy_o             (sts_dma_busy),
        .frame_count_o          (sts_frame_count),
        .perf_capture_cyc_o     (sts_perf_capture),
        .perf_isp_cyc_o         (sts_perf_isp),
        .perf_crop_cyc_o        (sts_perf_crop),
        // Sub-module interfaces
        .dvp_frame_done_i       (dvp_frame_done),
        .isp_start_o            (isp_start),
        .isp_done_i             (isp_done),
        .vdma_start_o           (vdma_start),
        .vdma_done_i            (vdma_done),
        .crop_start_o           (crop_start_pulse),
        .crop_engine_done_i     (crop_engine_done),
        .fbuf_swap_o            (fbuf_swap),
        // IRQ
        .irq_camera_ready_o     (irq_camera_ready_o)
    );

endmodule
