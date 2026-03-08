`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Camera Subsystem
// Module: cam_controller
// Description: Camera subsystem orchestrator FSM — sequences capture,
//              ISP, DMA, and crop operations
//////////////////////////////////////////////////////////////////////////////

module cam_controller (
    input  wire        clk,
    input  wire        rst_n,

    // ----------------------------------------------------------------
    // Register interface (from cam_regfile)
    // ----------------------------------------------------------------
    input  wire        reg_enable_i,           // CAM_CONTROL[0]
    input  wire        reg_soft_reset_i,       // CAM_CONTROL[1]
    input  wire        reg_continuous_i,        // CAM_CONTROL[2]
    input  wire        reg_irq_enable_i,       // CAM_CONTROL[3]
    input  wire        reg_crop_enable_i,      // CAM_CONTROL[4]
    input  wire        reg_capture_start_i,    // CAPTURE_START write
    input  wire        reg_crop_start_i,       // CROP_START write
    input  wire        reg_bypass_i,           // ISP_CONFIG[20]
    input  wire [9:0]  reg_src_width_i,
    input  wire [9:0]  reg_src_height_i,
    input  wire [9:0]  reg_dst_width_i,
    input  wire [9:0]  reg_dst_height_i,
    input  wire [23:0] reg_scale_x_i,
    input  wire [23:0] reg_scale_y_i,
    input  wire [31:0] reg_frame_buf_addr_i,   // active buffer address
    input  wire [31:0] reg_frame_size_i,       // frame size in bytes
    // Crop config
    input  wire [9:0]  reg_crop_x_i,
    input  wire [9:0]  reg_crop_y_i,
    input  wire [9:0]  reg_crop_w_i,
    input  wire [9:0]  reg_crop_h_i,
    input  wire [9:0]  reg_crop_out_w_i,
    input  wire [9:0]  reg_crop_out_h_i,
    input  wire [31:0] reg_raw_frame_addr_i,
    input  wire [15:0] reg_frame_stride_i,
    input  wire [31:0] reg_crop_buf_addr_i,
    // IRQ clear
    input  wire        reg_irq_clear_frame_i,
    input  wire        reg_irq_clear_crop_i,

    // ----------------------------------------------------------------
    // Status outputs (to cam_regfile)
    // ----------------------------------------------------------------
    output reg         capture_busy_o,
    output reg         frame_ready_o,
    output reg         crop_busy_o,
    output reg         crop_done_o,
    output reg         fifo_overrun_o,
    output reg         dma_busy_o,
    output reg  [7:0]  frame_count_o,

    // ----------------------------------------------------------------
    // Performance counters
    // ----------------------------------------------------------------
    output reg  [31:0] perf_capture_cyc_o,
    output reg  [31:0] perf_isp_cyc_o,
    output reg  [31:0] perf_crop_cyc_o,

    // ----------------------------------------------------------------
    // Sub-module interfaces
    // ----------------------------------------------------------------
    // DVP capture
    input  wire        dvp_frame_done_i,

    // ISP-lite
    output reg         isp_start_o,
    input  wire        isp_done_i,

    // Video DMA
    output reg         vdma_start_o,
    input  wire        vdma_done_i,

    // Crop engine
    output reg         crop_start_o,
    input  wire        crop_engine_done_i,

    // Frame buffer control
    output reg         fbuf_swap_o,

    // ----------------------------------------------------------------
    // IRQ output
    // ----------------------------------------------------------------
    output reg         irq_camera_ready_o
);

    // ----------------------------------------------------------------
    // Capture FSM
    // ----------------------------------------------------------------
    localparam [2:0] CS_IDLE      = 3'd0,
                     CS_WAIT_VSYNC = 3'd1,
                     CS_CAPTURE    = 3'd2,
                     CS_ISP        = 3'd3,
                     CS_DMA        = 3'd4,
                     CS_FRAME_DONE = 3'd5;

    reg [2:0] cap_state, cap_state_next;

    // ----------------------------------------------------------------
    // Crop FSM
    // ----------------------------------------------------------------
    localparam [1:0] CRS_IDLE    = 2'd0,
                     CRS_RUNNING = 2'd1,
                     CRS_DONE    = 2'd2;

    reg [1:0] crop_state, crop_state_next;

    // ----------------------------------------------------------------
    // Perf counter regs
    // ----------------------------------------------------------------
    reg [31:0] capture_cyc_cnt;
    reg [31:0] isp_cyc_cnt;
    reg [31:0] crop_cyc_cnt;

    // ----------------------------------------------------------------
    // Capture FSM sequential
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n || reg_soft_reset_i)
            cap_state <= CS_IDLE;
        else
            cap_state <= cap_state_next;
    end

    // ----------------------------------------------------------------
    // Capture FSM combinational
    // ----------------------------------------------------------------
    always @(*) begin
        cap_state_next = cap_state;
        case (cap_state)
            CS_IDLE: begin
                if (reg_enable_i && reg_capture_start_i)
                    cap_state_next = CS_WAIT_VSYNC;
            end
            CS_WAIT_VSYNC: begin
                // DVP capture waits for VSYNC internally;
                // transition when frame_done signals capture complete
                cap_state_next = CS_CAPTURE;
            end
            CS_CAPTURE: begin
                if (dvp_frame_done_i)
                    cap_state_next = CS_ISP;
            end
            CS_ISP: begin
                if (isp_done_i)
                    cap_state_next = CS_DMA;
            end
            CS_DMA: begin
                if (vdma_done_i)
                    cap_state_next = CS_FRAME_DONE;
            end
            CS_FRAME_DONE: begin
                if (reg_continuous_i)
                    cap_state_next = CS_WAIT_VSYNC;
                else
                    cap_state_next = CS_IDLE;
            end
            default: cap_state_next = CS_IDLE;
        endcase
    end

    // ----------------------------------------------------------------
    // Crop FSM sequential
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n || reg_soft_reset_i)
            crop_state <= CRS_IDLE;
        else
            crop_state <= crop_state_next;
    end

    always @(*) begin
        crop_state_next = crop_state;
        case (crop_state)
            CRS_IDLE:    if (reg_crop_enable_i && reg_crop_start_i) crop_state_next = CRS_RUNNING;
            CRS_RUNNING: if (crop_engine_done_i)                    crop_state_next = CRS_DONE;
            CRS_DONE:                                               crop_state_next = CRS_IDLE;
            default:                                                crop_state_next = CRS_IDLE;
        endcase
    end

    // ----------------------------------------------------------------
    // Control outputs & status
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n || reg_soft_reset_i) begin
            capture_busy_o     <= 1'b0;
            frame_ready_o      <= 1'b0;
            crop_busy_o        <= 1'b0;
            crop_done_o        <= 1'b0;
            fifo_overrun_o     <= 1'b0;
            dma_busy_o         <= 1'b0;
            frame_count_o      <= 8'd0;
            isp_start_o        <= 1'b0;
            vdma_start_o       <= 1'b0;
            crop_start_o       <= 1'b0;
            fbuf_swap_o        <= 1'b0;
            irq_camera_ready_o <= 1'b0;
            capture_cyc_cnt    <= 32'd0;
            isp_cyc_cnt        <= 32'd0;
            crop_cyc_cnt       <= 32'd0;
            perf_capture_cyc_o <= 32'd0;
            perf_isp_cyc_o     <= 32'd0;
            perf_crop_cyc_o    <= 32'd0;
        end else begin
            // Default pulse signals
            isp_start_o  <= 1'b0;
            vdma_start_o <= 1'b0;
            crop_start_o <= 1'b0;
            fbuf_swap_o  <= 1'b0;

            // --------------------------------------------------------
            // Capture path control
            // --------------------------------------------------------
            capture_busy_o <= (cap_state != CS_IDLE);
            dma_busy_o     <= (cap_state == CS_DMA);

            // Performance counter: capture
            if (cap_state == CS_CAPTURE)
                capture_cyc_cnt <= capture_cyc_cnt + 32'd1;
            else if (cap_state == CS_IDLE && reg_capture_start_i)
                capture_cyc_cnt <= 32'd0;

            // Performance counter: ISP
            if (cap_state == CS_ISP)
                isp_cyc_cnt <= isp_cyc_cnt + 32'd1;

            // Start ISP when capture finishes
            if (cap_state == CS_CAPTURE && cap_state_next == CS_ISP) begin
                isp_start_o         <= 1'b1;
                perf_capture_cyc_o  <= capture_cyc_cnt;
                isp_cyc_cnt         <= 32'd0;
            end

            // Start DMA when ISP finishes
            if (cap_state == CS_ISP && cap_state_next == CS_DMA) begin
                vdma_start_o    <= 1'b1;
                perf_isp_cyc_o  <= isp_cyc_cnt;
            end

            // Frame done
            if (cap_state == CS_DMA && cap_state_next == CS_FRAME_DONE) begin
                frame_ready_o <= 1'b1;
                frame_count_o <= frame_count_o + 8'd1;
                fbuf_swap_o   <= 1'b1;
                if (reg_irq_enable_i)
                    irq_camera_ready_o <= 1'b1;
            end

            // --------------------------------------------------------
            // Crop path control
            // --------------------------------------------------------
            crop_busy_o <= (crop_state != CRS_IDLE);

            if (crop_state == CRS_RUNNING)
                crop_cyc_cnt <= crop_cyc_cnt + 32'd1;
            else if (crop_state == CRS_IDLE && reg_crop_start_i)
                crop_cyc_cnt <= 32'd0;

            if (crop_state == CRS_IDLE && crop_state_next == CRS_RUNNING)
                crop_start_o <= 1'b1;

            if (crop_state == CRS_RUNNING && crop_state_next == CRS_DONE) begin
                crop_done_o        <= 1'b1;
                perf_crop_cyc_o    <= crop_cyc_cnt;
                if (reg_irq_enable_i)
                    irq_camera_ready_o <= 1'b1;
            end

            // --------------------------------------------------------
            // IRQ clear
            // --------------------------------------------------------
            if (reg_irq_clear_frame_i)
                frame_ready_o <= 1'b0;
            if (reg_irq_clear_crop_i)
                crop_done_o <= 1'b0;
            if (reg_irq_clear_frame_i || reg_irq_clear_crop_i)
                irq_camera_ready_o <= 1'b0;
        end
    end

endmodule
