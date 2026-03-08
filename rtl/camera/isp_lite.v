`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Camera Subsystem
// Module: isp_lite
// Description: ISP pipeline wrapper — YUV2RGB + resize + pixel packer
//////////////////////////////////////////////////////////////////////////////

module isp_lite (
    input  wire         clk,
    input  wire         rst_n,
    // Control
    input  wire         start_i,
    input  wire         bypass_i,
    // Scale / size configuration
    input  wire [23:0]  scale_x_i,
    input  wire [23:0]  scale_y_i,
    input  wire [9:0]   src_width_i,
    input  wire [9:0]   src_height_i,
    input  wire [9:0]   dst_width_i,
    input  wire [9:0]   dst_height_i,
    // Pixel input (YUV422 from pixel FIFO)
    input  wire [15:0]  in_pixel_i,
    input  wire         in_valid_i,
    output wire         in_ready_o,
    // Packed output (128-bit for DMA)
    output wire [127:0] out_data_o,
    output wire         out_valid_o,
    input  wire         out_ready_i,
    // Status
    output wire         done_o
);

    // ----------------------------------------------------------------
    // Internal wires
    // ----------------------------------------------------------------

    // YUV2RGB outputs (separate R, G, B channels)
    wire [7:0]  rgb_r, rgb_g, rgb_b;
    wire        rgb_valid;
    wire [23:0] rgb_pixel;
    assign rgb_pixel = {rgb_r, rgb_g, rgb_b};

    // Resize outputs
    wire [23:0] resized_pixel;
    wire        resized_valid;
    wire        resize_ready;

    // Resize done
    wire        resize_done;

    // ----------------------------------------------------------------
    // FSM for pipeline sequencing
    // ----------------------------------------------------------------
    localparam [1:0] S_IDLE    = 2'd0,
                     S_RUNNING = 2'd1,
                     S_DONE    = 2'd2;

    reg [1:0] state, state_next;
    reg       done_r;

    always @(posedge clk) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= state_next;
    end

    always @(*) begin
        state_next = state;
        case (state)
            S_IDLE:    if (start_i)     state_next = S_RUNNING;
            S_RUNNING: if (resize_done) state_next = S_DONE;
            S_DONE:                     state_next = S_IDLE;
            default:                    state_next = S_IDLE;
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n)
            done_r <= 1'b0;
        else
            done_r <= (state == S_DONE);
    end

    assign done_o = done_r;

    // ----------------------------------------------------------------
    // Pipeline active gating
    // ----------------------------------------------------------------
    wire pipeline_active = (state == S_RUNNING);

    // ----------------------------------------------------------------
    // YUV422 unpacking: 16-bit -> Y, U, V
    // YUV422 interleaved: {Y, U/V} — alternate U and V
    // ----------------------------------------------------------------
    reg  uv_toggle;  // 0 = U byte, 1 = V byte
    reg  [7:0] saved_u;
    wire [7:0] y_val = in_pixel_i[15:8];
    wire [7:0] uv_val = in_pixel_i[7:0];

    always @(posedge clk) begin
        if (!rst_n) begin
            uv_toggle <= 1'b0;
            saved_u   <= 8'd128;
        end else if (in_valid_i && pipeline_active && !bypass_i) begin
            uv_toggle <= ~uv_toggle;
            if (!uv_toggle)
                saved_u <= uv_val;
        end
    end

    wire [7:0] u_to_conv = uv_toggle ? saved_u : uv_val;
    wire [7:0] v_to_conv = uv_toggle ? uv_val  : 8'd128;
    wire       yuv_valid = in_valid_i & pipeline_active & ~bypass_i;

    // ----------------------------------------------------------------
    // Bypass path
    // ----------------------------------------------------------------
    wire [23:0] bypass_pixel = {in_pixel_i[15:8], in_pixel_i[7:0], 8'h00};
    wire        bypass_valid = in_valid_i & pipeline_active & bypass_i;

    // ----------------------------------------------------------------
    // YUV2RGB — Stage 1
    // yuv2rgb has: y_i, u_i, v_i, in_valid -> r_o, g_o, b_o, out_valid
    // ----------------------------------------------------------------
    yuv2rgb u_yuv2rgb (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (yuv_valid),
        .y_i       (y_val),
        .u_i       (u_to_conv),
        .v_i       (v_to_conv),
        .out_valid (rgb_valid),
        .r_o       (rgb_r),
        .g_o       (rgb_g),
        .b_o       (rgb_b)
    );

    // ----------------------------------------------------------------
    // Resize Engine — Stage 2
    // resize_engine: in_pixel_i[23:0], in_valid_i, in_ready_o,
    //               out_pixel_o[23:0], out_valid_o, done_o
    // ----------------------------------------------------------------
    wire [23:0] resize_in_pixel = bypass_i ? bypass_pixel : rgb_pixel;
    wire        resize_in_valid = bypass_i ? bypass_valid : rgb_valid;

    resize_engine u_resize (
        .clk          (clk),
        .rst_n        (rst_n),
        .start_i      (start_i),
        .scale_x_i    (scale_x_i),
        .scale_y_i    (scale_y_i),
        .src_width_i  (src_width_i),
        .src_height_i (src_height_i),
        .dst_width_i  (dst_width_i),
        .dst_height_i (dst_height_i),
        .in_pixel_i   (resize_in_pixel),
        .in_valid_i   (resize_in_valid),
        .in_ready_o   (resize_ready),
        .out_pixel_o  (resized_pixel),
        .out_valid_o  (resized_valid),
        .done_o       (resize_done)
    );

    // Back-pressure: resize_engine provides in_ready_o
    assign in_ready_o = resize_ready;

    // ----------------------------------------------------------------
    // Pixel Packer — Stage 3 (24-bit RGB -> 128-bit AXI words)
    // pixel_packer: in_pixel_i[23:0], in_valid_i,
    //              out_data_o[127:0], out_valid_o, out_ready_i
    // (no in_ready_o)
    // ----------------------------------------------------------------
    pixel_packer u_packer (
        .clk        (clk),
        .rst_n      (rst_n),
        .in_pixel_i (resized_pixel),
        .in_valid_i (resized_valid),
        .out_data_o (out_data_o),
        .out_valid_o(out_valid_o),
        .out_ready_i(out_ready_i)
    );

endmodule
