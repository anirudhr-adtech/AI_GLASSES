`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Camera Subsystem
// Module: crop_resize
// Description: Bilinear resize for crop path (variable ROI -> 112x112)
//              Wrapper around resize_engine logic for crop DMA data
//////////////////////////////////////////////////////////////////////////////

module crop_resize (
    input  wire        clk,
    input  wire        rst_n,
    // Control
    input  wire        start_i,
    input  wire [23:0] scale_x_i,
    input  wire [23:0] scale_y_i,
    input  wire [9:0]  src_width_i,
    input  wire [9:0]  src_height_i,
    input  wire [9:0]  dst_width_i,
    input  wire [9:0]  dst_height_i,
    // Pixel input (24-bit RGB from crop DMA reader unpacker)
    input  wire [23:0] in_pixel_i,
    input  wire        in_valid_i,
    output wire        in_ready_o,
    // Pixel output (24-bit RGB to crop DMA writer)
    output wire [23:0] out_pixel_o,
    output wire        out_valid_o,
    // Status
    output wire        done_o
);

    // ----------------------------------------------------------------
    // Instantiate resize_engine with crop-specific connections
    // ----------------------------------------------------------------
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
        .in_pixel_i   (in_pixel_i),
        .in_valid_i   (in_valid_i),
        .in_ready_o   (in_ready_o),
        .out_pixel_o  (out_pixel_o),
        .out_valid_o  (out_valid_o),
        .done_o       (done_o)
    );

endmodule
