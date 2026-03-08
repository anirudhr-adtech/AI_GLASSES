`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Camera Subsystem
// Module: crop_engine
// Description: Full crop + resize flow — reads ROI from DDR, resizes,
//              writes cropped face back to DDR
//////////////////////////////////////////////////////////////////////////////

module crop_engine (
    input  wire         clk,
    input  wire         rst_n,
    // Control
    input  wire         crop_start_i,
    output reg          crop_done_o,
    // Crop configuration
    input  wire [9:0]   crop_x_i,
    input  wire [9:0]   crop_y_i,
    input  wire [9:0]   crop_w_i,
    input  wire [9:0]   crop_h_i,
    input  wire [9:0]   crop_out_w_i,
    input  wire [9:0]   crop_out_h_i,
    // DDR addresses
    input  wire [31:0]  raw_frame_addr_i,
    input  wire [15:0]  frame_stride_i,
    input  wire [31:0]  crop_buf_addr_i,
    // AXI4 Read Address Channel (from crop_dma_reader)
    output wire [3:0]   m_axi_arid,
    output wire [31:0]  m_axi_araddr,
    output wire [7:0]   m_axi_arlen,
    output wire [2:0]   m_axi_arsize,
    output wire [1:0]   m_axi_arburst,
    output wire         m_axi_arvalid,
    input  wire         m_axi_arready,
    // AXI4 Read Data Channel
    input  wire [3:0]   m_axi_rid,
    input  wire [127:0] m_axi_rdata,
    input  wire [1:0]   m_axi_rresp,
    input  wire         m_axi_rlast,
    input  wire         m_axi_rvalid,
    output wire         m_axi_rready,
    // AXI4 Write Address Channel (from crop_dma_writer)
    output wire [3:0]   m_axi_awid,
    output wire [31:0]  m_axi_awaddr,
    output wire [7:0]   m_axi_awlen,
    output wire [2:0]   m_axi_awsize,
    output wire [1:0]   m_axi_awburst,
    output wire         m_axi_awvalid,
    input  wire         m_axi_awready,
    // AXI4 Write Data Channel
    output wire [127:0] m_axi_wdata,
    output wire [15:0]  m_axi_wstrb,
    output wire         m_axi_wlast,
    output wire         m_axi_wvalid,
    input  wire         m_axi_wready,
    // AXI4 Write Response Channel
    input  wire [3:0]   m_axi_bid,
    input  wire [1:0]   m_axi_bresp,
    input  wire         m_axi_bvalid,
    output wire         m_axi_bready
);

    // ----------------------------------------------------------------
    // FSM: sequence reader -> resize -> writer
    // ----------------------------------------------------------------
    localparam [1:0] S_IDLE    = 2'd0,
                     S_RUNNING = 2'd1,
                     S_DONE    = 2'd2;

    reg [1:0] state, state_next;

    // Sub-module control signals
    reg  reader_start;
    wire reader_done;
    reg  resize_start;
    wire resize_done;
    reg  writer_start;
    wire writer_done;

    // Interconnect: reader -> unpack -> resize -> writer
    wire [127:0] reader_data;
    wire         reader_valid;
    wire         reader_ready;

    // Unpack 128-bit words to 24-bit RGB pixels
    // 128-bit = 4 x 32-bit RGBX words
    reg [1:0]    unpack_cnt;
    reg [127:0]  unpack_buf;
    reg          unpack_buf_valid;
    wire [23:0]  unpack_pixel;
    wire         unpack_valid;
    wire         unpack_ready;

    // Resize output
    wire [23:0]  resized_pixel;
    wire         resized_valid;

    // Total output pixels for DMA writer
    wire [13:0] crop_total_pixels = crop_out_w_i[9:0] * crop_out_h_i[9:0];

    // Scale factors (computed: src / dst in Q8.16)
    // For simplicity, CPU provides these via registers; we forward them
    wire [23:0] scale_x = {14'd0, crop_w_i} * 24'd65536 / {14'd0, crop_out_w_i};
    wire [23:0] scale_y = {14'd0, crop_h_i} * 24'd65536 / {14'd0, crop_out_h_i};

    // ----------------------------------------------------------------
    // State register
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= state_next;
    end

    always @(*) begin
        state_next = state;
        case (state)
            S_IDLE:    if (crop_start_i) state_next = S_RUNNING;
            S_RUNNING: if (writer_done)  state_next = S_DONE;
            S_DONE:                      state_next = S_IDLE;
            default:                     state_next = S_IDLE;
        endcase
    end

    // ----------------------------------------------------------------
    // Sub-module start pulses
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            reader_start <= 1'b0;
            resize_start <= 1'b0;
            writer_start <= 1'b0;
            crop_done_o  <= 1'b0;
        end else begin
            reader_start <= 1'b0;
            resize_start <= 1'b0;
            writer_start <= 1'b0;
            crop_done_o  <= 1'b0;
            if (state == S_IDLE && crop_start_i) begin
                reader_start <= 1'b1;
                resize_start <= 1'b1;
                writer_start <= 1'b1;
            end
            if (state == S_DONE)
                crop_done_o <= 1'b1;
        end
    end

    // ----------------------------------------------------------------
    // 128-bit to 24-bit unpacker
    // ----------------------------------------------------------------
    assign reader_ready = !unpack_buf_valid || (unpack_cnt == 2'd3 && unpack_ready);
    assign unpack_pixel = (unpack_cnt == 2'd0) ? unpack_buf[127:104] :
                          (unpack_cnt == 2'd1) ? unpack_buf[95:72]   :
                          (unpack_cnt == 2'd2) ? unpack_buf[63:40]   :
                                                 unpack_buf[31:8];
    assign unpack_valid = unpack_buf_valid;

    always @(posedge clk) begin
        if (!rst_n) begin
            unpack_cnt       <= 2'd0;
            unpack_buf       <= 128'd0;
            unpack_buf_valid <= 1'b0;
        end else begin
            if (state == S_IDLE) begin
                unpack_cnt       <= 2'd0;
                unpack_buf_valid <= 1'b0;
            end else begin
                // Load new 128-bit word when current is consumed
                if (reader_valid && reader_ready) begin
                    unpack_buf       <= reader_data;
                    unpack_buf_valid <= 1'b1;
                    unpack_cnt       <= 2'd0;
                end else if (unpack_buf_valid && unpack_ready) begin
                    if (unpack_cnt == 2'd3) begin
                        unpack_buf_valid <= 1'b0;
                        unpack_cnt       <= 2'd0;
                    end else begin
                        unpack_cnt <= unpack_cnt + 2'd1;
                    end
                end
            end
        end
    end

    // ----------------------------------------------------------------
    // crop_dma_reader
    // ----------------------------------------------------------------
    crop_dma_reader u_reader (
        .clk              (clk),
        .rst_n            (rst_n),
        .start_i          (reader_start),
        .raw_frame_addr_i (raw_frame_addr_i),
        .frame_stride_i   (frame_stride_i),
        .crop_x_i         (crop_x_i),
        .crop_y_i         (crop_y_i),
        .crop_w_i         (crop_w_i),
        .crop_h_i         (crop_h_i),
        .done_o           (reader_done),
        .out_data_o       (reader_data),
        .out_valid_o      (reader_valid),
        .out_ready_i      (reader_ready),
        .m_axi_arid       (m_axi_arid),
        .m_axi_araddr     (m_axi_araddr),
        .m_axi_arlen      (m_axi_arlen),
        .m_axi_arsize     (m_axi_arsize),
        .m_axi_arburst    (m_axi_arburst),
        .m_axi_arvalid    (m_axi_arvalid),
        .m_axi_arready    (m_axi_arready),
        .m_axi_rid        (m_axi_rid),
        .m_axi_rdata      (m_axi_rdata),
        .m_axi_rresp      (m_axi_rresp),
        .m_axi_rlast      (m_axi_rlast),
        .m_axi_rvalid     (m_axi_rvalid),
        .m_axi_rready     (m_axi_rready)
    );

    // ----------------------------------------------------------------
    // crop_resize
    // ----------------------------------------------------------------
    crop_resize u_resize (
        .clk          (clk),
        .rst_n        (rst_n),
        .start_i      (resize_start),
        .scale_x_i    (scale_x),
        .scale_y_i    (scale_y),
        .src_width_i  (crop_w_i),
        .src_height_i (crop_h_i),
        .dst_width_i  (crop_out_w_i),
        .dst_height_i (crop_out_h_i),
        .in_pixel_i   (unpack_pixel),
        .in_valid_i   (unpack_valid),
        .in_ready_o   (unpack_ready),
        .out_pixel_o  (resized_pixel),
        .out_valid_o  (resized_valid),
        .done_o       (resize_done)
    );

    // ----------------------------------------------------------------
    // crop_dma_writer
    // ----------------------------------------------------------------
    crop_dma_writer u_writer (
        .clk             (clk),
        .rst_n           (rst_n),
        .start_i         (writer_start),
        .crop_buf_addr_i (crop_buf_addr_i),
        .total_pixels_i  (crop_total_pixels),
        .in_data_i       (resized_pixel),
        .in_valid_i      (resized_valid),
        .in_ready_o      (),   // resize has no backpressure output
        .done_o          (writer_done),
        .m_axi_awid      (m_axi_awid),
        .m_axi_awaddr    (m_axi_awaddr),
        .m_axi_awlen     (m_axi_awlen),
        .m_axi_awsize    (m_axi_awsize),
        .m_axi_awburst   (m_axi_awburst),
        .m_axi_awvalid   (m_axi_awvalid),
        .m_axi_awready   (m_axi_awready),
        .m_axi_wdata     (m_axi_wdata),
        .m_axi_wstrb     (m_axi_wstrb),
        .m_axi_wlast     (m_axi_wlast),
        .m_axi_wvalid    (m_axi_wvalid),
        .m_axi_wready    (m_axi_wready),
        .m_axi_bid       (m_axi_bid),
        .m_axi_bresp     (m_axi_bresp),
        .m_axi_bvalid    (m_axi_bvalid),
        .m_axi_bready    (m_axi_bready)
    );

endmodule
