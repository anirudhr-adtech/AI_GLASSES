`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem
// Module: audio_dma
// Description: 32-bit AXI4 master DMA for DDR writes. Two modes:
//              MFCC mode (burst write 245 words) and Passthrough mode
//              (streaming PCM to ring buffer). AXI ID = 4'b1100.
//////////////////////////////////////////////////////////////////////////////

module audio_dma #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
)(
    input  wire                    clk,
    input  wire                    rst_n,
    // Control
    input  wire                    start_i,
    input  wire                    mode_i,        // 0=MFCC, 1=passthrough
    input  wire [ADDR_WIDTH-1:0]  base_addr_i,
    input  wire [ADDR_WIDTH-1:0]  length_i,      // Transfer length in bytes
    // Source data interface
    input  wire [DATA_WIDTH-1:0]  src_data_i,
    input  wire                    src_valid_i,
    output reg                     src_ready_o,
    // Status
    output reg                     done_o,
    output reg  [ADDR_WIDTH-1:0]  dma_wr_ptr_o,
    // AXI4 Write Address Channel
    output reg  [3:0]             m_axi_awid,
    output reg  [ADDR_WIDTH-1:0]  m_axi_awaddr,
    output reg  [7:0]             m_axi_awlen,
    output reg  [2:0]             m_axi_awsize,
    output reg  [1:0]             m_axi_awburst,
    output reg                     m_axi_awvalid,
    input  wire                    m_axi_awready,
    // AXI4 Write Data Channel
    output reg  [DATA_WIDTH-1:0]  m_axi_wdata,
    output reg  [3:0]             m_axi_wstrb,
    output reg                     m_axi_wlast,
    output reg                     m_axi_wvalid,
    input  wire                    m_axi_wready,
    // AXI4 Write Response Channel
    input  wire [3:0]             m_axi_bid,
    input  wire [1:0]             m_axi_bresp,
    input  wire                    m_axi_bvalid,
    output reg                     m_axi_bready
);

    // FSM states
    localparam S_IDLE     = 3'd0;
    localparam S_ADDR     = 3'd1;
    localparam S_DATA     = 3'd2;
    localparam S_RESP     = 3'd3;
    localparam S_NEXT     = 3'd4;
    localparam S_DONE     = 3'd5;

    localparam MAX_BURST  = 8'd63;  // Max burst = 64 beats (AWLEN=63)
    localparam AXI_ID     = 4'b1100;

    reg [2:0]              state;
    reg [ADDR_WIDTH-1:0]   cur_addr;
    reg [ADDR_WIDTH-1:0]   bytes_remaining;
    reg [7:0]              beat_cnt;
    reg [7:0]              cur_burst_len;  // AWLEN value for current burst
    reg                    mode_r;
    reg [ADDR_WIDTH-1:0]   ring_size;     // For passthrough ring buffer

    // Calculate burst length
    wire [ADDR_WIDTH-1:0] words_remaining = bytes_remaining >> 2;
    wire [7:0] burst_len = (words_remaining > {24'd0, MAX_BURST + 8'd1}) ?
                            MAX_BURST : words_remaining[7:0] - 8'd1;

    always @(posedge clk) begin
        if (!rst_n) begin
            state           <= S_IDLE;
            cur_addr        <= {ADDR_WIDTH{1'b0}};
            bytes_remaining <= {ADDR_WIDTH{1'b0}};
            beat_cnt        <= 8'd0;
            cur_burst_len   <= 8'd0;
            mode_r          <= 1'b0;
            ring_size       <= {ADDR_WIDTH{1'b0}};
            done_o          <= 1'b0;
            src_ready_o     <= 1'b0;
            dma_wr_ptr_o    <= {ADDR_WIDTH{1'b0}};
            m_axi_awid      <= AXI_ID;
            m_axi_awaddr    <= {ADDR_WIDTH{1'b0}};
            m_axi_awlen     <= 8'd0;
            m_axi_awsize    <= 3'b010; // 4 bytes
            m_axi_awburst   <= 2'b01;  // INCR
            m_axi_awvalid   <= 1'b0;
            m_axi_wdata     <= {DATA_WIDTH{1'b0}};
            m_axi_wstrb     <= 4'hF;
            m_axi_wlast     <= 1'b0;
            m_axi_wvalid    <= 1'b0;
            m_axi_bready    <= 1'b0;
        end else begin
            done_o <= 1'b0;

            case (state)
                S_IDLE: begin
                    src_ready_o <= 1'b0;
                    if (start_i) begin
                        cur_addr        <= base_addr_i;
                        bytes_remaining <= length_i;
                        mode_r          <= mode_i;
                        ring_size       <= length_i;
                        state           <= S_ADDR;
                    end
                end

                S_ADDR: begin
                    if (bytes_remaining == {ADDR_WIDTH{1'b0}}) begin
                        state <= S_DONE;
                    end else begin
                        m_axi_awaddr  <= cur_addr;
                        m_axi_awlen   <= burst_len;
                        m_axi_awvalid <= 1'b1;
                        m_axi_awid    <= AXI_ID;
                        cur_burst_len <= burst_len;
                        beat_cnt      <= 8'd0;

                        if (m_axi_awvalid && m_axi_awready) begin
                            m_axi_awvalid <= 1'b0;
                            m_axi_wlast   <= (burst_len == 8'd0); // Pre-set wlast for first beat
                            src_ready_o   <= 1'b1;
                            state         <= S_DATA;
                        end
                    end
                end

                S_DATA: begin
                    if (src_valid_i && src_ready_o) begin
                        m_axi_wdata  <= src_data_i;
                        m_axi_wstrb  <= 4'hF;
                        m_axi_wvalid <= 1'b1;
                        // wlast is pre-set by S_ADDR or previous handshake

                        if (m_axi_wvalid && m_axi_wready) begin
                            beat_cnt        <= beat_cnt + 8'd1;
                            cur_addr        <= cur_addr + 32'd4;
                            bytes_remaining <= bytes_remaining - 32'd4;
                            dma_wr_ptr_o    <= cur_addr + 32'd4;

                            if (beat_cnt == cur_burst_len) begin
                                m_axi_wvalid <= 1'b0;
                                m_axi_wlast  <= 1'b0;
                                src_ready_o  <= 1'b0;
                                m_axi_bready <= 1'b1;
                                state        <= S_RESP;
                            end else begin
                                // Pre-set wlast for the next beat
                                m_axi_wlast <= (beat_cnt + 8'd1 == cur_burst_len);
                            end
                        end
                    end else if (!src_valid_i) begin
                        m_axi_wvalid <= 1'b0;
                    end
                end

                S_RESP: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bready <= 1'b0;
                        // Passthrough ring: wrap address
                        if (mode_r && (cur_addr >= base_addr_i + ring_size)) begin
                            cur_addr <= base_addr_i;
                        end
                        state <= S_NEXT;
                    end
                end

                S_NEXT: begin
                    if (bytes_remaining == {ADDR_WIDTH{1'b0}}) begin
                        state <= S_DONE;
                    end else begin
                        state <= S_ADDR;
                    end
                end

                S_DONE: begin
                    done_o <= 1'b1;
                    state  <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
