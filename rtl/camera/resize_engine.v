`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Camera Subsystem
// Module: resize_engine
// Description: Bilinear resize with parameterizable Q8.16 scale factors
//////////////////////////////////////////////////////////////////////////////

module resize_engine (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start_i,
    // Scale factors (Q8.16 fixed-point)
    input  wire [23:0] scale_x_i,
    input  wire [23:0] scale_y_i,
    // Dimensions
    input  wire [9:0]  src_width_i,
    input  wire [9:0]  src_height_i,
    input  wire [9:0]  dst_width_i,
    input  wire [9:0]  dst_height_i,
    // Input pixel stream
    input  wire [23:0] in_pixel_i,
    input  wire        in_valid_i,
    output reg         in_ready_o,
    // Output pixel stream
    output reg  [23:0] out_pixel_o,
    output reg         out_valid_o,
    output reg         done_o
);

    // FSM states
    localparam [2:0] S_IDLE           = 3'd0,
                     S_FILL_LINE_BUF  = 3'd1,
                     S_GENERATE_ROW   = 3'd2,
                     S_ADVANCE_LINE   = 3'd3,
                     S_DONE           = 3'd4;

    reg [2:0] state, state_next;

    // Line buffer instance
    reg         lb_wr_en;
    reg         lb_wr_line_sel;
    reg [9:0]   lb_wr_addr;
    reg [23:0]  lb_wr_data;
    reg         lb_rd_line_sel;
    reg [9:0]   lb_rd_addr;
    wire [23:0] lb_rd_data;

    line_buffer u_line_buffer (
        .clk         (clk),
        .rst_n       (rst_n),
        .wr_en       (lb_wr_en),
        .wr_line_sel (lb_wr_line_sel),
        .wr_addr     (lb_wr_addr),
        .wr_data     (lb_wr_data),
        .rd_line_sel (lb_rd_line_sel),
        .rd_addr     (lb_rd_addr),
        .rd_data     (lb_rd_data)
    );

    // Counters
    reg [9:0]  dst_x;        // Current output column
    reg [9:0]  dst_y;        // Current output row
    reg [9:0]  fill_col;     // Fill column counter
    reg [9:0]  src_y_cur;    // Current source line loaded in buffer
    reg        line_sel;     // Which line buffer to write into (ping-pong)

    // Fixed-point accumulators
    reg [31:0] acc_x;        // Q16.16 horizontal position
    reg [31:0] acc_y;        // Q16.16 vertical position

    // Interpolation pipeline
    reg [23:0] pixel_top;
    reg [23:0] pixel_bot;
    reg [7:0]  frac_x;
    reg [7:0]  frac_y;
    reg        interp_phase; // 0=read top, 1=read bot
    reg        interp_valid;

    // Horizontal interpolation result
    reg [23:0] h_interp_top;
    reg [23:0] h_interp_bot;

    // Combinational interpolation helpers
    wire [7:0] top_r = pixel_top[23:16];
    wire [7:0] top_g = pixel_top[15:8];
    wire [7:0] top_b = pixel_top[7:0];
    wire [7:0] bot_r = pixel_bot[23:16];
    wire [7:0] bot_g = pixel_bot[15:8];
    wire [7:0] bot_b = pixel_bot[7:0];

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
            S_IDLE:
                if (start_i) state_next = S_FILL_LINE_BUF;
            S_FILL_LINE_BUF:
                if (fill_col >= src_width_i) state_next = S_GENERATE_ROW;
            S_GENERATE_ROW:
                if (dst_x >= dst_width_i) state_next = S_ADVANCE_LINE;
            S_ADVANCE_LINE:
                if (dst_y >= dst_height_i)
                    state_next = S_DONE;
                else
                    state_next = S_FILL_LINE_BUF;
            S_DONE:
                state_next = S_IDLE;
            default: state_next = S_IDLE;
        endcase
    end

    // Datapath
    always @(posedge clk) begin
        if (!rst_n) begin
            lb_wr_en       <= 1'b0;
            lb_wr_line_sel <= 1'b0;
            lb_wr_addr     <= 10'd0;
            lb_wr_data     <= 24'd0;
            lb_rd_line_sel <= 1'b0;
            lb_rd_addr     <= 10'd0;
            in_ready_o     <= 1'b0;
            out_pixel_o    <= 24'd0;
            out_valid_o    <= 1'b0;
            done_o         <= 1'b0;
            dst_x          <= 10'd0;
            dst_y          <= 10'd0;
            fill_col       <= 10'd0;
            src_y_cur      <= 10'd0;
            line_sel       <= 1'b0;
            acc_x          <= 32'd0;
            acc_y          <= 32'd0;
            pixel_top      <= 24'd0;
            pixel_bot      <= 24'd0;
            frac_x         <= 8'd0;
            frac_y         <= 8'd0;
            interp_phase   <= 1'b0;
            interp_valid   <= 1'b0;
            h_interp_top   <= 24'd0;
            h_interp_bot   <= 24'd0;
        end else begin
            lb_wr_en    <= 1'b0;
            out_valid_o <= 1'b0;
            done_o      <= 1'b0;
            in_ready_o  <= 1'b0;
            interp_valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    dst_x     <= 10'd0;
                    dst_y     <= 10'd0;
                    fill_col  <= 10'd0;
                    src_y_cur <= 10'd0;
                    line_sel  <= 1'b0;
                    acc_x     <= 32'd0;
                    acc_y     <= 32'd0;
                end

                S_FILL_LINE_BUF: begin
                    in_ready_o <= 1'b1;
                    if (in_valid_i && in_ready_o) begin
                        lb_wr_en       <= 1'b1;
                        lb_wr_line_sel <= line_sel;
                        lb_wr_addr     <= fill_col;
                        lb_wr_data     <= in_pixel_i;
                        fill_col       <= fill_col + 10'd1;
                    end
                    if (fill_col >= src_width_i) begin
                        in_ready_o  <= 1'b0;
                        src_y_cur   <= src_y_cur + 10'd1;
                    end
                end

                S_GENERATE_ROW: begin
                    if (!interp_phase) begin
                        // Phase 0: read from top line, compute source X
                        acc_x <= {6'd0, dst_x, 16'd0};  // dst_x * 65536
                        // src_x = (dst_x * scale_x) >> 16
                        lb_rd_line_sel <= ~line_sel;  // top line = previous
                        lb_rd_addr     <= (dst_x * scale_x_i[23:0]) >> 16;
                        frac_x         <= ((dst_x * scale_x_i[23:0]) >> 8);
                        frac_y         <= acc_y[15:8];
                        interp_phase   <= 1'b1;
                    end else begin
                        // Phase 1: read top value, request bot
                        pixel_top <= lb_rd_data;
                        lb_rd_line_sel <= line_sel;   // bot line = current
                        lb_rd_addr     <= (dst_x * scale_x_i[23:0]) >> 16;
                        interp_phase   <= 1'b0;
                        interp_valid   <= 1'b1;
                    end

                    // Output interpolated pixel when valid
                    if (interp_valid) begin
                        pixel_bot <= lb_rd_data;
                        // Vertical interpolation: top*(256-frac_y) + bot*frac_y >> 8
                        out_pixel_o[23:16] <= ((top_r * (8'd255 - frac_y)) + (lb_rd_data[23:16] * frac_y)) >> 8;
                        out_pixel_o[15:8]  <= ((top_g * (8'd255 - frac_y)) + (lb_rd_data[15:8]  * frac_y)) >> 8;
                        out_pixel_o[7:0]   <= ((top_b * (8'd255 - frac_y)) + (lb_rd_data[7:0]   * frac_y)) >> 8;
                        out_valid_o <= 1'b1;
                        dst_x <= dst_x + 10'd1;
                    end
                end

                S_ADVANCE_LINE: begin
                    dst_x    <= 10'd0;
                    dst_y    <= dst_y + 10'd1;
                    fill_col <= 10'd0;
                    line_sel <= ~line_sel;
                    acc_y    <= acc_y + {8'd0, scale_y_i};
                    interp_phase <= 1'b0;
                end

                S_DONE: begin
                    done_o <= 1'b1;
                end
            endcase
        end
    end

endmodule
