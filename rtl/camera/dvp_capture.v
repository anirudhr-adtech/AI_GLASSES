`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Camera Subsystem
// Module: dvp_capture
// Description: Parallel DVP camera interface — captures YUV422 from OV7670
//////////////////////////////////////////////////////////////////////////////

module dvp_capture (
    input  wire        clk,
    input  wire        rst_n,
    // DVP camera interface
    input  wire        cam_pclk_i,
    input  wire        cam_vsync_i,
    input  wire        cam_href_i,
    input  wire [7:0]  cam_data_i,
    // Pixel output
    output reg  [15:0] pixel_data_o,
    output reg         pixel_valid_o,
    output reg         frame_done_o,
    output reg  [9:0]  line_count_o,
    output reg  [9:0]  pixel_count_o,
    // Configuration
    input  wire [9:0]  src_width_i,
    input  wire [9:0]  src_height_i
);

    // FSM states
    localparam [1:0] S_IDLE       = 2'd0,
                     S_WAIT_HREF  = 2'd1,
                     S_CAPTURE    = 2'd2,
                     S_FRAME_DONE = 2'd3;

    reg [1:0] state, state_next;

    // Synchronized DVP signals from dvp_sync
    wire       pclk_sync;
    wire       vsync_sync;
    wire       href_sync;
    wire [7:0] data_sync;
    wire       pclk_rise;
    wire       pclk_fall;
    wire       vsync_rise;

    // Byte toggle: 0 = first byte, 1 = second byte
    reg        byte_toggle;
    reg [7:0]  byte_first;

    // Internal counters
    reg [9:0]  line_cnt;
    reg [9:0]  pixel_cnt;

    // Instantiate synchronizer
    dvp_sync u_dvp_sync (
        .clk          (clk),
        .rst_n        (rst_n),
        .pclk_i       (cam_pclk_i),
        .vsync_i      (cam_vsync_i),
        .href_i       (cam_href_i),
        .data_i       (cam_data_i),
        .pclk_sync_o  (pclk_sync),
        .vsync_sync_o (vsync_sync),
        .href_sync_o  (href_sync),
        .data_sync_o  (data_sync),
        .pclk_rise_o  (pclk_rise),
        .pclk_fall_o  (pclk_fall),
        .vsync_rise_o (vsync_rise)
    );

    // FSM sequential
    always @(posedge clk) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= state_next;
    end

    // FSM combinational
    always @(*) begin
        state_next = state;
        case (state)
            S_IDLE: begin
                if (vsync_rise)
                    state_next = S_WAIT_HREF;
            end
            S_WAIT_HREF: begin
                if (href_sync)
                    state_next = S_CAPTURE;
                else if (line_cnt >= src_height_i)
                    state_next = S_FRAME_DONE;
            end
            S_CAPTURE: begin
                if (!href_sync)
                    state_next = S_WAIT_HREF;
            end
            S_FRAME_DONE: begin
                state_next = S_IDLE;
            end
            default: state_next = S_IDLE;
        endcase
    end

    // Datapath
    always @(posedge clk) begin
        if (!rst_n) begin
            byte_toggle   <= 1'b0;
            byte_first    <= 8'd0;
            pixel_data_o  <= 16'd0;
            pixel_valid_o <= 1'b0;
            frame_done_o  <= 1'b0;
            line_cnt      <= 10'd0;
            pixel_cnt     <= 10'd0;
            line_count_o  <= 10'd0;
            pixel_count_o <= 10'd0;
        end else begin
            pixel_valid_o <= 1'b0;
            frame_done_o  <= 1'b0;

            case (state)
                S_IDLE: begin
                    line_cnt    <= 10'd0;
                    pixel_cnt   <= 10'd0;
                    byte_toggle <= 1'b0;
                end

                S_WAIT_HREF: begin
                    byte_toggle <= 1'b0;
                    pixel_cnt   <= 10'd0;
                end

                S_CAPTURE: begin
                    if (pclk_rise) begin
                        if (!byte_toggle) begin
                            byte_first  <= data_sync;
                            byte_toggle <= 1'b1;
                        end else begin
                            pixel_data_o  <= {byte_first, data_sync};
                            pixel_valid_o <= 1'b1;
                            byte_toggle   <= 1'b0;
                            pixel_cnt     <= pixel_cnt + 10'd1;
                            pixel_count_o <= pixel_cnt + 10'd1;
                        end
                    end
                    // Transition to WAIT_HREF increments line count
                    if (!href_sync) begin
                        line_cnt     <= line_cnt + 10'd1;
                        line_count_o <= line_cnt + 10'd1;
                    end
                end

                S_FRAME_DONE: begin
                    frame_done_o <= 1'b1;
                end
            endcase
        end
    end

endmodule
