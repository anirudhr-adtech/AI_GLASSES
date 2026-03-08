`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////////////
// dvp_camera_model.v
// OV7670-like DVP camera stimulus generator (simulation only)
// Generates VSYNC, HREF, and pixel data in YUV422 format.
//
// Rewritten as a synthesizable-style state machine driven by an external
// pclk input for lint compatibility. The testbench must drive pclk.
//////////////////////////////////////////////////////////////////////////////
module dvp_camera_model #(
    parameter H_ACTIVE   = 640,
    parameter V_ACTIVE   = 480,
    parameter PIXEL_BITS = 8,
    parameter FRAME_FILE = "frame_data.hex"
)(
    input  wire                    rst_n,
    input  wire                    enable,
    input  wire                    pclk,
    output reg                     vsync,
    output reg                     href,
    output reg  [PIXEL_BITS-1:0]   data_o,
    output reg                     frame_done
);

    // -----------------------------------------------------------------------
    // Internal frame memory -- YUV422: 2 bytes per pixel
    // -----------------------------------------------------------------------
    localparam FRAME_BYTES = H_ACTIVE * V_ACTIVE * 2;
    reg [7:0] frame_mem [0:FRAME_BYTES-1];

    // Timing constants (in pclk cycles)
    localparam H_BLANK      = 144;          // horizontal blanking per line
    localparam VSYNC_LINES  = 3;            // VSYNC pulse width in lines
    localparam V_FRONT      = 17;           // lines before VSYNC (not critical for model)
    localparam V_BACK       = 12;           // lines after VSYNC before active
    localparam LINE_TOTAL   = H_ACTIVE * 2 + H_BLANK;  // total pclk per line

    // -----------------------------------------------------------------------
    // Color-bar pattern generator (fallback if file load fails)
    // 8 vertical bars, each bar = H_ACTIVE/8 pixels wide
    // Y values cycle: 16, 128, 240 ; U/V fixed at 128
    // YUV422 byte order: U0, Y0, V0, Y1, U2, Y2, V2, Y3 ...
    // -----------------------------------------------------------------------
    task generate_color_bars;
        integer px, bar, byte_idx;
        reg [7:0] y_val;
        reg [7:0] bar_y [0:7];
        begin
            bar_y[0] = 8'd16;   bar_y[1] = 8'd128;  bar_y[2] = 8'd240;
            bar_y[3] = 8'd16;   bar_y[4] = 8'd128;  bar_y[5] = 8'd240;
            bar_y[6] = 8'd16;   bar_y[7] = 8'd128;
            for (px = 0; px < H_ACTIVE * V_ACTIVE; px = px + 1) begin
                bar = (px % H_ACTIVE) / (H_ACTIVE / 8);
                if (bar > 7) bar = 7;
                y_val = bar_y[bar];
                byte_idx = px * 2;
                // Even pixel: U then Y ; Odd pixel: V then Y
                if (px[0] == 1'b0) begin
                    frame_mem[byte_idx]     = 8'd128; // U
                    frame_mem[byte_idx + 1] = y_val;  // Y
                end else begin
                    frame_mem[byte_idx]     = 8'd128; // V
                    frame_mem[byte_idx + 1] = y_val;  // Y
                end
            end
        end
    endtask

    // -----------------------------------------------------------------------
    // Frame memory initialisation
    // -----------------------------------------------------------------------
    integer file_check;
    initial begin
        // Zero-fill first
        for (file_check = 0; file_check < FRAME_BYTES; file_check = file_check + 1)
            frame_mem[file_check] = 8'h00;
        // Try loading hex file
        $readmemh(FRAME_FILE, frame_mem);
        // If first few bytes still zero after load, assume file missing -> color bars
        if (frame_mem[0] === 8'h00 && frame_mem[1] === 8'h00 &&
            frame_mem[2] === 8'h00 && frame_mem[3] === 8'h00) begin
            $display("[%0t] dvp_camera_model: FRAME_FILE not found or empty, generating color bars", $time);
            generate_color_bars;
        end
    end

    // -----------------------------------------------------------------------
    // State machine definitions
    // -----------------------------------------------------------------------
    localparam ST_WAIT_ENABLE = 3'd0;
    localparam ST_VSYNC       = 3'd1;
    localparam ST_V_BACK      = 3'd2;
    localparam ST_ACTIVE      = 3'd3;
    localparam ST_H_BLANK     = 3'd4;
    localparam ST_FRAME_DONE  = 3'd5;
    localparam ST_V_FRONT     = 3'd6;

    reg [2:0]  fsm_state;
    reg [31:0] line_cnt;
    reg [31:0] pclk_cnt;
    reg [31:0] byte_idx;

    // -----------------------------------------------------------------------
    // Frame generation state machine -- single posedge pclk block
    // -----------------------------------------------------------------------
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            vsync      <= 1'b0;
            href       <= 1'b0;
            data_o     <= {PIXEL_BITS{1'b0}};
            frame_done <= 1'b0;
            fsm_state  <= ST_WAIT_ENABLE;
            line_cnt   <= 32'd0;
            pclk_cnt   <= 32'd0;
            byte_idx   <= 32'd0;
        end else begin
            case (fsm_state)
                ST_WAIT_ENABLE: begin
                    vsync      <= 1'b0;
                    href       <= 1'b0;
                    data_o     <= {PIXEL_BITS{1'b0}};
                    frame_done <= 1'b0;
                    if (enable) begin
                        byte_idx  <= 32'd0;
                        line_cnt  <= 32'd0;
                        pclk_cnt  <= 32'd0;
                        vsync     <= 1'b1;
                        fsm_state <= ST_VSYNC;
                    end
                end

                ST_VSYNC: begin
                    // VSYNC active HIGH for VSYNC_LINES full lines
                    vsync <= 1'b1;
                    if (pclk_cnt < LINE_TOTAL - 1) begin
                        pclk_cnt <= pclk_cnt + 32'd1;
                    end else begin
                        pclk_cnt <= 32'd0;
                        if (line_cnt < VSYNC_LINES - 1) begin
                            line_cnt <= line_cnt + 32'd1;
                        end else begin
                            line_cnt  <= 32'd0;
                            vsync     <= 1'b0;
                            fsm_state <= ST_V_BACK;
                        end
                    end
                end

                ST_V_BACK: begin
                    // Vertical back porch
                    vsync <= 1'b0;
                    if (pclk_cnt < LINE_TOTAL - 1) begin
                        pclk_cnt <= pclk_cnt + 32'd1;
                    end else begin
                        pclk_cnt <= 32'd0;
                        if (line_cnt < V_BACK - 1) begin
                            line_cnt <= line_cnt + 32'd1;
                        end else begin
                            line_cnt  <= 32'd0;
                            pclk_cnt  <= 32'd0;
                            href      <= 1'b1;
                            data_o    <= frame_mem[byte_idx][PIXEL_BITS-1:0];
                            fsm_state <= ST_ACTIVE;
                        end
                    end
                end

                ST_ACTIVE: begin
                    // Active pixel output -- HREF high, output pixel bytes
                    href   <= 1'b1;
                    data_o <= frame_mem[byte_idx][PIXEL_BITS-1:0];
                    if (pclk_cnt < H_ACTIVE * 2 - 1) begin
                        pclk_cnt <= pclk_cnt + 32'd1;
                        byte_idx <= byte_idx + 32'd1;
                    end else begin
                        pclk_cnt  <= 32'd0;
                        byte_idx  <= byte_idx + 32'd1;
                        href      <= 1'b0;
                        data_o    <= {PIXEL_BITS{1'b0}};
                        fsm_state <= ST_H_BLANK;
                    end
                end

                ST_H_BLANK: begin
                    // Horizontal blanking
                    href   <= 1'b0;
                    data_o <= {PIXEL_BITS{1'b0}};
                    if (pclk_cnt < H_BLANK - 1) begin
                        pclk_cnt <= pclk_cnt + 32'd1;
                    end else begin
                        pclk_cnt <= 32'd0;
                        if (line_cnt < V_ACTIVE - 1) begin
                            line_cnt  <= line_cnt + 32'd1;
                            href      <= 1'b1;
                            data_o    <= frame_mem[byte_idx][PIXEL_BITS-1:0];
                            fsm_state <= ST_ACTIVE;
                        end else begin
                            line_cnt  <= 32'd0;
                            fsm_state <= ST_FRAME_DONE;
                        end
                    end
                end

                ST_FRAME_DONE: begin
                    // Frame done pulse (1 pclk wide)
                    frame_done <= 1'b1;
                    pclk_cnt   <= 32'd0;
                    fsm_state  <= ST_V_FRONT;
                end

                ST_V_FRONT: begin
                    // Vertical front porch
                    frame_done <= 1'b0;
                    if (pclk_cnt < LINE_TOTAL - 1) begin
                        pclk_cnt <= pclk_cnt + 32'd1;
                    end else begin
                        pclk_cnt <= 32'd0;
                        if (line_cnt < V_FRONT - 1) begin
                            line_cnt <= line_cnt + 32'd1;
                        end else begin
                            line_cnt <= 32'd0;
                            if (enable) begin
                                // Start next frame
                                byte_idx  <= 32'd0;
                                vsync     <= 1'b1;
                                fsm_state <= ST_VSYNC;
                            end else begin
                                fsm_state <= ST_WAIT_ENABLE;
                            end
                        end
                    end
                end

                default: begin
                    fsm_state <= ST_WAIT_ENABLE;
                end
            endcase
        end
    end

endmodule
