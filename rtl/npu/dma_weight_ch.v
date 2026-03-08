`timescale 1ns/1ps
//============================================================================
// dma_weight_ch.v
// Weight DMA channel — reads from DDR via AXI4, writes to weight buffer.
// Verilog-2005, active-low synchronous reset.
//============================================================================

module dma_weight_ch (
    // Clock / reset
    input  wire         clk,
    input  wire         rst_n,

    // Control
    input  wire         start,
    input  wire [31:0]  src_addr,
    input  wire [31:0]  xfer_len,
    output reg          done,

    // Weight buffer write interface
    output reg          buf_we,
    output reg  [14:0]  buf_addr,
    output reg  [31:0]  buf_wdata,

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
    output reg          m_axi_rready
);

    // ---------------------------------------------------------------
    // FSM states
    // ---------------------------------------------------------------
    localparam [2:0] S_IDLE        = 3'd0,
                     S_CALC_BURSTS = 3'd1,
                     S_AR_ISSUE    = 3'd2,
                     S_R_DATA      = 3'd3,
                     S_DONE        = 3'd4;

    reg [2:0] state_r, state_nxt;

    // Burst bookkeeping
    reg [31:0] full_bursts_r;    // number of 256-beat bursts
    reg [ 7:0] remainder_r;     // remaining beats (0-255)
    reg [31:0] burst_cnt_r;     // bursts already issued
    reg [31:0] cur_addr_r;      // current AXI address
    reg [ 7:0] beat_cnt_r;      // beats received in current burst
    reg [ 7:0] cur_arlen_r;     // arlen for current burst
    reg [ 1:0] sub_word_r;      // 2-bit sub-word counter (0-3)
    reg [14:0] buf_addr_cnt_r;  // running buffer address
    reg [127:0] rdata_latch_r;  // latched 128-bit read data
    reg         rlast_latch_r;  // latched rlast from accepted beat

    // Bytes per beat = 16
    localparam BYTES_PER_BEAT = 32'd16;
    localparam BEATS_PER_BURST = 32'd256;

    // ---------------------------------------------------------------
    // Total beats calculation helpers
    // ---------------------------------------------------------------
    wire [31:0] total_beats;
    assign total_beats = (xfer_len + BYTES_PER_BEAT - 1) / BYTES_PER_BEAT; // ceiling

    // ---------------------------------------------------------------
    // FSM next-state (combinational)
    // ---------------------------------------------------------------
    always @(*) begin
        state_nxt = state_r;
        case (state_r)
            S_IDLE:        if (start)                            state_nxt = S_CALC_BURSTS;
            S_CALC_BURSTS:                                       state_nxt = S_AR_ISSUE;
            S_AR_ISSUE:    if (m_axi_arvalid && m_axi_arready)   state_nxt = S_R_DATA;
            S_R_DATA: begin
                // Transition when all 4 sub-words of the last beat have been written.
                // rlast_latch_r is set when the AXI beat is accepted (sub_word_r==0);
                // beat_cnt_r == cur_arlen_r confirms it was the final beat.
                if (sub_word_r == 2'd3 && beat_cnt_r == cur_arlen_r && rlast_latch_r) begin
                    if (burst_cnt_r + 1 < full_bursts_r ||
                        (burst_cnt_r + 1 == full_bursts_r && remainder_r != 8'd0))
                        state_nxt = S_AR_ISSUE;
                    else
                        state_nxt = S_DONE;
                end
            end
            S_DONE:                                              state_nxt = S_IDLE;
            default:                                             state_nxt = S_IDLE;
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
            cur_arlen_r    <= 8'd0;
            sub_word_r     <= 2'd0;
            buf_addr_cnt_r <= 15'd0;
            rdata_latch_r  <= 128'd0;
            rlast_latch_r  <= 1'b0;

            done           <= 1'b0;
            buf_we         <= 1'b0;
            buf_addr       <= 15'd0;
            buf_wdata      <= 32'd0;

            m_axi_araddr   <= 32'd0;
            m_axi_arlen    <= 8'd0;
            m_axi_arsize   <= 3'd0;
            m_axi_arburst  <= 2'd0;
            m_axi_arvalid  <= 1'b0;
            m_axi_rready   <= 1'b0;
        end else begin
            state_r <= state_nxt;

            // Default de-assertions
            done   <= 1'b0;
            buf_we <= 1'b0;

            case (state_r)
                // ---------------------------------------------------
                S_IDLE: begin
                    if (start) begin
                        cur_addr_r     <= src_addr;
                        burst_cnt_r    <= 32'd0;
                        buf_addr_cnt_r <= 15'd0;
                        sub_word_r     <= 2'd0;
                    end
                    m_axi_arvalid <= 1'b0;
                    m_axi_rready  <= 1'b0;
                end

                // ---------------------------------------------------
                S_CALC_BURSTS: begin
                    full_bursts_r <= total_beats / BEATS_PER_BURST;
                    remainder_r   <= total_beats[7:0]; // total_beats mod 256
                    // If total_beats is an exact multiple remainder will be 0
                end

                // ---------------------------------------------------
                S_AR_ISSUE: begin
                    m_axi_araddr  <= cur_addr_r;
                    m_axi_arsize  <= 3'b100;   // 16 bytes
                    m_axi_arburst <= 2'b01;    // INCR

                    if (burst_cnt_r < full_bursts_r) begin
                        m_axi_arlen <= 8'd255;
                        cur_arlen_r <= 8'd255;
                    end else begin
                        m_axi_arlen <= remainder_r - 8'd1;
                        cur_arlen_r <= remainder_r - 8'd1;
                    end

                    m_axi_arvalid <= 1'b1;

                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        beat_cnt_r    <= 8'd0;
                        sub_word_r    <= 2'd0;
                        m_axi_rready  <= 1'b1;
                    end
                end

                // ---------------------------------------------------
                S_R_DATA: begin
                    m_axi_arvalid <= 1'b0;

                    if (sub_word_r == 2'd0) begin
                        // Waiting for or consuming a new AXI beat
                        if (m_axi_rvalid && m_axi_rready) begin
                            rdata_latch_r  <= m_axi_rdata;
                            rlast_latch_r  <= m_axi_rlast;  // latch rlast for FSM transition
                            // Write first word immediately
                            buf_we    <= 1'b1;
                            buf_addr  <= buf_addr_cnt_r;
                            buf_wdata <= m_axi_rdata[31:0];
                            buf_addr_cnt_r <= buf_addr_cnt_r + 15'd1;
                            sub_word_r     <= 2'd1;
                            m_axi_rready   <= 1'b0; // pause accepting until all 4 words written
                        end
                    end else begin
                        // Write remaining sub-words from latched data
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
                            // Advance address for next burst
                            cur_addr_r <= cur_addr_r + BYTES_PER_BEAT;
                            // Check if this was the last beat
                            if (beat_cnt_r == cur_arlen_r) begin
                                burst_cnt_r  <= burst_cnt_r + 32'd1;
                                m_axi_rready <= 1'b0;
                            end else begin
                                m_axi_rready <= 1'b1; // ready for next beat
                            end
                        end else begin
                            sub_word_r <= sub_word_r + 2'd1;
                        end
                    end
                end

                // ---------------------------------------------------
                S_DONE: begin
                    done         <= 1'b1;
                    m_axi_rready <= 1'b0;
                end

                default: ;
            endcase
        end
    end

endmodule
