`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Camera Subsystem
// Module: crop_dma_writer
// Description: AXI4 write controller for writing cropped face to DDR
//              Packs 24-bit RGB -> 32-bit RGBX -> 128-bit AXI words
//////////////////////////////////////////////////////////////////////////////

module crop_dma_writer (
    input  wire         clk,
    input  wire         rst_n,
    // Control
    input  wire         start_i,
    input  wire [31:0]  crop_buf_addr_i,
    // Pixel input (24-bit RGB from crop_resize)
    input  wire [23:0]  in_data_i,
    input  wire         in_valid_i,
    output reg          in_ready_o,
    // Status
    output reg          done_o,
    // AXI4 Write Address Channel
    output reg  [3:0]   m_axi_awid,
    output reg  [31:0]  m_axi_awaddr,
    output reg  [7:0]   m_axi_awlen,
    output reg  [2:0]   m_axi_awsize,
    output reg  [1:0]   m_axi_awburst,
    output reg          m_axi_awvalid,
    input  wire         m_axi_awready,
    // AXI4 Write Data Channel
    output reg  [127:0] m_axi_wdata,
    output reg  [15:0]  m_axi_wstrb,
    output reg          m_axi_wlast,
    output reg          m_axi_wvalid,
    input  wire         m_axi_wready,
    // AXI4 Write Response Channel
    input  wire [3:0]   m_axi_bid,
    input  wire [1:0]   m_axi_bresp,
    input  wire         m_axi_bvalid,
    output reg          m_axi_bready
);

    // ----------------------------------------------------------------
    // Parameters
    // ----------------------------------------------------------------
    localparam AXI_ID         = 4'b1101;
    localparam MAX_BURST      = 8'd255;
    localparam BYTES_PER_BEAT = 16;
    // 112x112 RGBX = 50176 bytes = 3136 beats
    // 3136 / 256 = 12 full bursts + 1 partial (64 beats)
    localparam TOTAL_PIXELS   = 112 * 112;  // 12544

    // ----------------------------------------------------------------
    // FSM
    // ----------------------------------------------------------------
    localparam [2:0] S_IDLE     = 3'd0,
                     S_PACK     = 3'd1,
                     S_AW       = 3'd2,
                     S_WRITE    = 3'd3,
                     S_BRESP    = 3'd4,
                     S_DONE     = 3'd5;

    reg [2:0] state, state_next;

    // Pixel packing: 4 pixels (32-bit RGBX each) -> 128-bit word
    reg [127:0] pack_buf;
    reg [1:0]   pack_cnt;       // 0..3 pixel count within 128-bit word
    reg         pack_valid;

    // FIFO for packed 128-bit words (small: 4 entries for burst staging)
    reg [127:0] fifo_mem [0:3];
    reg [2:0]   fifo_wr_ptr;
    reg [2:0]   fifo_rd_ptr;
    wire [2:0]  fifo_count = fifo_wr_ptr - fifo_rd_ptr;
    wire        fifo_full  = (fifo_count == 3'd4);
    wire        fifo_empty = (fifo_wr_ptr == fifo_rd_ptr);

    // Burst management
    reg [31:0]  current_addr;
    reg [31:0]  total_beats_rem; // total beats remaining
    reg [8:0]   beat_count;
    reg [7:0]   burst_len;
    reg [13:0]  pixel_count;    // total pixels received

    // ----------------------------------------------------------------
    // State register
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= state_next;
    end

    // ----------------------------------------------------------------
    // Next state
    // ----------------------------------------------------------------
    always @(*) begin
        state_next = state;
        case (state)
            S_IDLE: begin
                if (start_i)
                    state_next = S_PACK;
            end
            S_PACK: begin
                // Accumulate 256 words (or fewer if end), then issue burst
                if (fifo_count >= 3'd4 || (total_beats_rem <= 32'd4 && !fifo_empty && pixel_count >= TOTAL_PIXELS))
                    state_next = S_AW;
                else if (pixel_count >= TOTAL_PIXELS && pack_cnt == 2'd0 && !fifo_empty)
                    state_next = S_AW;
            end
            S_AW: begin
                if (m_axi_awvalid && m_axi_awready)
                    state_next = S_WRITE;
            end
            S_WRITE: begin
                if (m_axi_wvalid && m_axi_wready && m_axi_wlast)
                    state_next = S_BRESP;
            end
            S_BRESP: begin
                if (m_axi_bvalid && m_axi_bready) begin
                    if (total_beats_rem == 32'd0)
                        state_next = S_DONE;
                    else
                        state_next = S_PACK;
                end
            end
            S_DONE: begin
                state_next = S_IDLE;
            end
            default: state_next = S_IDLE;
        endcase
    end

    // ----------------------------------------------------------------
    // Pixel packing: 24-bit RGB -> 32-bit RGBX -> accumulate 4 -> 128-bit
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            pack_buf   <= 128'd0;
            pack_cnt   <= 2'd0;
            pack_valid <= 1'b0;
            fifo_wr_ptr <= 3'd0;
            pixel_count <= 14'd0;
        end else begin
            pack_valid <= 1'b0;
            if (state == S_IDLE && start_i) begin
                pack_cnt    <= 2'd0;
                fifo_wr_ptr <= 3'd0;
                pixel_count <= 14'd0;
            end else if ((state == S_PACK || state == S_AW || state == S_WRITE || state == S_BRESP) &&
                         in_valid_i && in_ready_o) begin
                // Pack pixel into buffer: {R, G, B, 0x00} = 32-bit RGBX
                case (pack_cnt)
                    2'd0: pack_buf[127:96] <= {in_data_i, 8'h00};
                    2'd1: pack_buf[95:64]  <= {in_data_i, 8'h00};
                    2'd2: pack_buf[63:32]  <= {in_data_i, 8'h00};
                    2'd3: pack_buf[31:0]   <= {in_data_i, 8'h00};
                endcase
                pack_cnt    <= pack_cnt + 2'd1;
                pixel_count <= pixel_count + 14'd1;

                if (pack_cnt == 2'd3) begin
                    // Write to FIFO
                    if (!fifo_full) begin
                        fifo_mem[fifo_wr_ptr[1:0]] <= {pack_buf[127:32], in_data_i, 8'h00};
                        fifo_wr_ptr <= fifo_wr_ptr + 3'd1;
                    end
                end
            end
        end
    end

    // ----------------------------------------------------------------
    // Burst write datapath
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            current_addr    <= 32'd0;
            total_beats_rem <= 32'd0;
            beat_count      <= 9'd0;
            burst_len       <= 8'd0;
            done_o          <= 1'b0;
            in_ready_o      <= 1'b0;
            fifo_rd_ptr     <= 3'd0;
            // AW channel
            m_axi_awid      <= AXI_ID;
            m_axi_awaddr    <= 32'd0;
            m_axi_awlen     <= 8'd0;
            m_axi_awsize    <= 3'b100;
            m_axi_awburst   <= 2'b01;
            m_axi_awvalid   <= 1'b0;
            // W channel
            m_axi_wdata     <= 128'd0;
            m_axi_wstrb     <= 16'hFFFF;
            m_axi_wlast     <= 1'b0;
            m_axi_wvalid    <= 1'b0;
            // B channel
            m_axi_bready    <= 1'b0;
        end else begin
            done_o <= 1'b0;

            case (state)
                S_IDLE: begin
                    m_axi_awvalid <= 1'b0;
                    m_axi_wvalid  <= 1'b0;
                    m_axi_bready  <= 1'b0;
                    in_ready_o    <= 1'b0;
                    if (start_i) begin
                        current_addr    <= crop_buf_addr_i;
                        total_beats_rem <= 32'd3136; // 112*112*4/16
                        fifo_rd_ptr     <= 3'd0;
                    end
                end

                S_PACK: begin
                    in_ready_o    <= ~fifo_full;
                    m_axi_awvalid <= 1'b0;
                    m_axi_wvalid  <= 1'b0;
                    m_axi_bready  <= 1'b0;
                end

                S_AW: begin
                    in_ready_o <= ~fifo_full;
                    // Determine burst length based on remaining beats
                    burst_len <= (total_beats_rem > 256) ? MAX_BURST :
                                 (total_beats_rem[7:0] - 8'd1);
                    m_axi_awid    <= AXI_ID;
                    m_axi_awaddr  <= current_addr;
                    m_axi_awlen   <= (total_beats_rem > 256) ? MAX_BURST :
                                     (total_beats_rem[7:0] - 8'd1);
                    m_axi_awsize  <= 3'b100;
                    m_axi_awburst <= 2'b01;
                    m_axi_awvalid <= 1'b1;
                    beat_count    <= 9'd0;
                    if (m_axi_awvalid && m_axi_awready)
                        m_axi_awvalid <= 1'b0;
                end

                S_WRITE: begin
                    m_axi_awvalid <= 1'b0;
                    in_ready_o    <= ~fifo_full;
                    if (!fifo_empty && m_axi_wready) begin
                        m_axi_wdata  <= fifo_mem[fifo_rd_ptr[1:0]];
                        m_axi_wstrb  <= 16'hFFFF;
                        m_axi_wvalid <= 1'b1;
                        m_axi_wlast  <= (beat_count == {1'b0, burst_len});
                        fifo_rd_ptr  <= fifo_rd_ptr + 3'd1;
                        beat_count   <= beat_count + 9'd1;
                        total_beats_rem <= total_beats_rem - 32'd1;
                        current_addr    <= current_addr + BYTES_PER_BEAT;
                    end else if (m_axi_wvalid && m_axi_wready) begin
                        m_axi_wvalid <= 1'b0;
                        m_axi_wlast  <= 1'b0;
                    end
                end

                S_BRESP: begin
                    m_axi_wvalid <= 1'b0;
                    m_axi_wlast  <= 1'b0;
                    m_axi_bready <= 1'b1;
                    in_ready_o   <= ~fifo_full;
                    if (m_axi_bvalid && m_axi_bready)
                        m_axi_bready <= 1'b0;
                end

                S_DONE: begin
                    done_o       <= 1'b1;
                    in_ready_o   <= 1'b0;
                    m_axi_bready <= 1'b0;
                end
            endcase
        end
    end

endmodule
