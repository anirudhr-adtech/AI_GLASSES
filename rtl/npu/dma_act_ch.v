`timescale 1ns/1ps
//============================================================================
// dma_act_ch.v
// Activation DMA channel — bidirectional.
//   direction=0 : DDR -> act buffer  (AXI read  path)
//   direction=1 : act buffer -> DDR  (AXI write path)
// Verilog-2005, active-low synchronous reset.
//============================================================================

module dma_act_ch (
    // Clock / reset
    input  wire         clk,
    input  wire         rst_n,

    // Control
    input  wire         start,
    input  wire         direction,   // 0=read (DDR->buf), 1=write (buf->DDR)
    input  wire [31:0]  src_addr,    // DDR source  (read path)
    input  wire [31:0]  dst_addr,    // DDR destination (write path)
    input  wire [31:0]  xfer_len,    // transfer length in bytes
    output reg          done,

    // Buffer write interface (read path: DMA -> buffer)
    output reg          buf_we,
    output reg  [14:0]  buf_addr,
    output reg  [31:0]  buf_wdata,

    // Buffer read interface (write path: buffer -> DMA)
    output reg          buf_re,
    output reg  [14:0]  buf_raddr,
    input  wire [31:0]  buf_rdata,

    // AXI4 read address channel (master)
    output reg  [31:0]  m_axi_araddr,
    output reg  [ 7:0]  m_axi_arlen,
    output reg  [ 2:0]  m_axi_arsize,
    output reg  [ 1:0]  m_axi_arburst,
    output reg          m_axi_arvalid,
    input  wire         m_axi_arready,

    // AXI4 read data channel (master)
    input  wire [127:0] m_axi_rdata,
    input  wire [  1:0] m_axi_rresp,
    input  wire         m_axi_rlast,
    input  wire         m_axi_rvalid,
    output reg          m_axi_rready,

    // AXI4 write address channel (master)
    output reg  [31:0]  m_axi_awaddr,
    output reg  [ 7:0]  m_axi_awlen,
    output reg  [ 2:0]  m_axi_awsize,
    output reg  [ 1:0]  m_axi_awburst,
    output reg          m_axi_awvalid,
    input  wire         m_axi_awready,

    // AXI4 write data channel (master)
    output reg  [127:0] m_axi_wdata,
    output reg  [ 15:0] m_axi_wstrb,
    output reg          m_axi_wlast,
    output reg          m_axi_wvalid,
    input  wire         m_axi_wready,

    // AXI4 write response channel (master)
    input  wire [  1:0] m_axi_bresp,
    input  wire         m_axi_bvalid,
    output reg          m_axi_bready
);

    // ---------------------------------------------------------------
    // FSM states — shared encoding for read & write paths
    // ---------------------------------------------------------------
    localparam [3:0] S_IDLE        = 4'd0,
                     S_CALC_BURSTS = 4'd1,
                     // Read path
                     S_AR_ISSUE    = 4'd2,
                     S_R_DATA      = 4'd3,
                     // Write path
                     S_AW_ISSUE    = 4'd4,
                     S_W_PREFETCH  = 4'd5,
                     S_W_DATA      = 4'd6,
                     S_B_RESP      = 4'd7,
                     //
                     S_DONE        = 4'd8;

    reg [3:0] state_r, state_nxt;

    // Burst bookkeeping
    reg [31:0] full_bursts_r;
    reg [ 7:0] remainder_r;
    reg [31:0] burst_cnt_r;
    reg [31:0] cur_addr_r;
    reg [ 7:0] beat_cnt_r;
    reg [ 7:0] cur_len_r;      // arlen / awlen for current burst
    reg [ 1:0] sub_word_r;     // sub-word counter 0-3
    reg [14:0] buf_addr_cnt_r;
    reg [127:0] rdata_latch_r;
    reg        dir_r;          // latched direction

    // Write-path packing register
    reg [127:0] wpack_r;
    reg [  1:0] wpack_cnt_r;   // how many 32-bit words gathered (0-3)

    localparam BYTES_PER_BEAT  = 32'd16;
    localparam BEATS_PER_BURST = 32'd256;

    wire [31:0] total_beats;
    assign total_beats = (xfer_len + BYTES_PER_BEAT - 1) / BYTES_PER_BEAT;

    // Helper: is there another burst after the current one?
    wire more_bursts;
    assign more_bursts = (burst_cnt_r + 1 < full_bursts_r) ||
                         (burst_cnt_r + 1 == full_bursts_r && remainder_r != 8'd0);

    // ---------------------------------------------------------------
    // FSM next-state
    // ---------------------------------------------------------------
    always @(*) begin
        state_nxt = state_r;
        case (state_r)
            S_IDLE:        if (start) state_nxt = S_CALC_BURSTS;

            S_CALC_BURSTS: state_nxt = dir_r ? S_AW_ISSUE : S_AR_ISSUE;

            // ---- read path ----
            S_AR_ISSUE:    if (m_axi_arvalid && m_axi_arready) state_nxt = S_R_DATA;

            S_R_DATA: begin
                if (m_axi_rvalid && m_axi_rready && (sub_word_r == 2'd3)) begin
                    if (m_axi_rlast) begin
                        state_nxt = more_bursts ? S_AR_ISSUE : S_DONE;
                    end
                end
            end

            // ---- write path ----
            S_AW_ISSUE:    if (m_axi_awvalid && m_axi_awready) state_nxt = S_W_PREFETCH;

            S_W_PREFETCH:  state_nxt = S_W_DATA; // 1-cycle prefetch latency

            S_W_DATA: begin
                if (m_axi_wvalid && m_axi_wready && m_axi_wlast) begin
                    state_nxt = S_B_RESP;
                end
            end

            S_B_RESP: begin
                if (m_axi_bvalid && m_axi_bready) begin
                    state_nxt = more_bursts ? S_AW_ISSUE : S_DONE;
                end
            end

            S_DONE:        state_nxt = S_IDLE;

            default:       state_nxt = S_IDLE;
        endcase
    end

    // ---------------------------------------------------------------
    // FSM sequential
    // ---------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            state_r        <= S_IDLE;
            full_bursts_r  <= 32'd0;
            remainder_r    <= 8'd0;
            burst_cnt_r    <= 32'd0;
            cur_addr_r     <= 32'd0;
            beat_cnt_r     <= 8'd0;
            cur_len_r      <= 8'd0;
            sub_word_r     <= 2'd0;
            buf_addr_cnt_r <= 15'd0;
            rdata_latch_r  <= 128'd0;
            dir_r          <= 1'b0;
            wpack_r        <= 128'd0;
            wpack_cnt_r    <= 2'd0;

            done           <= 1'b0;
            buf_we         <= 1'b0;
            buf_addr       <= 15'd0;
            buf_wdata      <= 32'd0;
            buf_re         <= 1'b0;
            buf_raddr      <= 15'd0;

            m_axi_araddr   <= 32'd0;
            m_axi_arlen    <= 8'd0;
            m_axi_arsize   <= 3'd0;
            m_axi_arburst  <= 2'd0;
            m_axi_arvalid  <= 1'b0;
            m_axi_rready   <= 1'b0;

            m_axi_awaddr   <= 32'd0;
            m_axi_awlen    <= 8'd0;
            m_axi_awsize   <= 3'd0;
            m_axi_awburst  <= 2'd0;
            m_axi_awvalid  <= 1'b0;
            m_axi_wdata    <= 128'd0;
            m_axi_wstrb    <= 16'd0;
            m_axi_wlast    <= 1'b0;
            m_axi_wvalid   <= 1'b0;
            m_axi_bready   <= 1'b0;
        end else begin
            state_r <= state_nxt;

            // Default de-assertions
            done   <= 1'b0;
            buf_we <= 1'b0;
            buf_re <= 1'b0;

            case (state_r)
                // ===================================================
                S_IDLE: begin
                    if (start) begin
                        dir_r          <= direction;
                        cur_addr_r     <= direction ? dst_addr : src_addr;
                        burst_cnt_r    <= 32'd0;
                        buf_addr_cnt_r <= 15'd0;
                        sub_word_r     <= 2'd0;
                        wpack_cnt_r    <= 2'd0;
                    end
                    m_axi_arvalid <= 1'b0;
                    m_axi_rready  <= 1'b0;
                    m_axi_awvalid <= 1'b0;
                    m_axi_wvalid  <= 1'b0;
                    m_axi_bready  <= 1'b0;
                end

                // ===================================================
                S_CALC_BURSTS: begin
                    full_bursts_r <= total_beats / BEATS_PER_BURST;
                    remainder_r   <= total_beats[7:0];
                end

                // ===================================================
                // READ PATH
                // ===================================================
                S_AR_ISSUE: begin
                    m_axi_araddr  <= cur_addr_r;
                    m_axi_arsize  <= 3'b100;
                    m_axi_arburst <= 2'b01;

                    if (burst_cnt_r < full_bursts_r) begin
                        m_axi_arlen <= 8'd255;
                        cur_len_r   <= 8'd255;
                    end else begin
                        m_axi_arlen <= remainder_r - 8'd1;
                        cur_len_r   <= remainder_r - 8'd1;
                    end

                    m_axi_arvalid <= 1'b1;

                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        beat_cnt_r    <= 8'd0;
                        sub_word_r    <= 2'd0;
                        m_axi_rready  <= 1'b1;
                    end
                end

                S_R_DATA: begin
                    m_axi_arvalid <= 1'b0;

                    if (sub_word_r == 2'd0) begin
                        if (m_axi_rvalid && m_axi_rready) begin
                            rdata_latch_r  <= m_axi_rdata;
                            buf_we         <= 1'b1;
                            buf_addr       <= buf_addr_cnt_r;
                            buf_wdata      <= m_axi_rdata[31:0];
                            buf_addr_cnt_r <= buf_addr_cnt_r + 15'd1;
                            sub_word_r     <= 2'd1;
                            m_axi_rready   <= 1'b0;
                        end
                    end else begin
                        buf_we   <= 1'b1;
                        buf_addr <= buf_addr_cnt_r;
                        case (sub_word_r)
                            2'd1: buf_wdata <= rdata_latch_r[ 63: 32];
                            2'd2: buf_wdata <= rdata_latch_r[ 95: 64];
                            2'd3: buf_wdata <= rdata_latch_r[127: 96];
                            default: buf_wdata <= 32'd0;
                        endcase
                        buf_addr_cnt_r <= buf_addr_cnt_r + 15'd1;

                        if (sub_word_r == 2'd3) begin
                            sub_word_r <= 2'd0;
                            beat_cnt_r <= beat_cnt_r + 8'd1;
                            cur_addr_r <= cur_addr_r + BYTES_PER_BEAT;
                            if (beat_cnt_r == cur_len_r) begin
                                burst_cnt_r  <= burst_cnt_r + 32'd1;
                                m_axi_rready <= 1'b0;
                            end else begin
                                m_axi_rready <= 1'b1;
                            end
                        end else begin
                            sub_word_r <= sub_word_r + 2'd1;
                        end
                    end
                end

                // ===================================================
                // WRITE PATH
                // ===================================================
                S_AW_ISSUE: begin
                    m_axi_awaddr  <= cur_addr_r;
                    m_axi_awsize  <= 3'b100;
                    m_axi_awburst <= 2'b01;

                    if (burst_cnt_r < full_bursts_r) begin
                        m_axi_awlen <= 8'd255;
                        cur_len_r   <= 8'd255;
                    end else begin
                        m_axi_awlen <= remainder_r - 8'd1;
                        cur_len_r   <= remainder_r - 8'd1;
                    end

                    m_axi_awvalid <= 1'b1;

                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        beat_cnt_r    <= 8'd0;
                        wpack_cnt_r   <= 2'd0;
                        // Start prefetching first word from buffer
                        buf_re        <= 1'b1;
                        buf_raddr     <= buf_addr_cnt_r;
                    end
                end

                S_W_PREFETCH: begin
                    // First word read latency cycle — issue read for next word
                    wpack_r[31:0]  <= buf_rdata;
                    wpack_cnt_r    <= 2'd1;
                    buf_addr_cnt_r <= buf_addr_cnt_r + 15'd1;
                    buf_re         <= 1'b1;
                    buf_raddr      <= buf_addr_cnt_r + 15'd1;
                end

                S_W_DATA: begin
                    // Pack 32-bit words from buffer into 128-bit AXI words
                    if (!m_axi_wvalid || m_axi_wready) begin
                        // We can accept/produce data
                        case (wpack_cnt_r)
                            2'd1: begin
                                wpack_r[63:32] <= buf_rdata;
                                wpack_cnt_r    <= 2'd2;
                                buf_addr_cnt_r <= buf_addr_cnt_r + 15'd1;
                                buf_re         <= 1'b1;
                                buf_raddr      <= buf_addr_cnt_r + 15'd1;
                                m_axi_wvalid   <= 1'b0;
                            end
                            2'd2: begin
                                wpack_r[95:64] <= buf_rdata;
                                wpack_cnt_r    <= 2'd3;
                                buf_addr_cnt_r <= buf_addr_cnt_r + 15'd1;
                                buf_re         <= 1'b1;
                                buf_raddr      <= buf_addr_cnt_r + 15'd1;
                                m_axi_wvalid   <= 1'b0;
                            end
                            2'd3: begin
                                wpack_r[127:96] <= buf_rdata;
                                buf_addr_cnt_r  <= buf_addr_cnt_r + 15'd1;

                                // Full 128-bit word ready — drive W channel
                                m_axi_wdata  <= {buf_rdata, wpack_r[95:0]};
                                m_axi_wstrb  <= 16'hFFFF;
                                m_axi_wvalid <= 1'b1;
                                m_axi_wlast  <= (beat_cnt_r == cur_len_r) ? 1'b1 : 1'b0;

                                beat_cnt_r  <= beat_cnt_r + 8'd1;
                                cur_addr_r  <= cur_addr_r + BYTES_PER_BEAT;
                                wpack_cnt_r <= 2'd0;

                                // Prefetch next word if not last beat
                                if (beat_cnt_r != cur_len_r) begin
                                    buf_re    <= 1'b1;
                                    buf_raddr <= buf_addr_cnt_r + 15'd1;
                                end else begin
                                    buf_re <= 1'b0;
                                end
                            end
                            2'd0: begin
                                // Latch first word of next 128-bit group
                                wpack_r[31:0]  <= buf_rdata;
                                wpack_cnt_r    <= 2'd1;
                                buf_addr_cnt_r <= buf_addr_cnt_r + 15'd1;
                                buf_re         <= 1'b1;
                                buf_raddr      <= buf_addr_cnt_r + 15'd1;
                                m_axi_wvalid   <= 1'b0;
                            end
                        endcase
                    end

                    // When wlast accepted, deassert
                    if (m_axi_wvalid && m_axi_wready && m_axi_wlast) begin
                        m_axi_wvalid <= 1'b0;
                        m_axi_wlast  <= 1'b0;
                        m_axi_bready <= 1'b1;
                    end
                end

                S_B_RESP: begin
                    m_axi_wvalid <= 1'b0;
                    m_axi_bready <= 1'b1;
                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bready <= 1'b0;
                        burst_cnt_r  <= burst_cnt_r + 32'd1;
                    end
                end

                // ===================================================
                S_DONE: begin
                    done         <= 1'b1;
                    m_axi_rready <= 1'b0;
                    m_axi_wvalid <= 1'b0;
                    m_axi_bready <= 1'b0;
                end

                default: ;
            endcase
        end
    end

endmodule
