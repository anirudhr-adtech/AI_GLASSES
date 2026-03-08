`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Camera Subsystem
// Module: video_dma
// Description: 128-bit AXI4 master DMA for frame writes to DDR
//////////////////////////////////////////////////////////////////////////////

module video_dma (
    input  wire         clk,
    input  wire         rst_n,
    // Control
    input  wire         start_i,
    input  wire [31:0]  base_addr_i,
    input  wire [31:0]  frame_size_i,   // total bytes to transfer
    // Pixel input from ISP / packer (128-bit words)
    input  wire [127:0] in_data_i,
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
    localparam AXI_ID       = 4'b1101;
    localparam MAX_BURST    = 8'd255;     // 256 beats (AWLEN=255)
    localparam BYTES_PER_BEAT = 16;       // 128-bit = 16 bytes

    // ----------------------------------------------------------------
    // FSM
    // ----------------------------------------------------------------
    localparam [2:0] S_IDLE     = 3'd0,
                     S_AW       = 3'd1,
                     S_WRITE    = 3'd2,
                     S_BRESP    = 3'd3,
                     S_DONE     = 3'd4;

    reg [2:0] state, state_next;

    // Counters
    reg [31:0] bytes_remaining;
    reg [31:0] current_addr;
    reg [8:0]  beat_count;       // within current burst (0..255)
    reg [7:0]  burst_len;        // AWLEN for current burst

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
    // Next state logic
    // ----------------------------------------------------------------
    always @(*) begin
        state_next = state;
        case (state)
            S_IDLE: begin
                if (start_i)
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
                    if (bytes_remaining == 32'd0)
                        state_next = S_DONE;
                    else
                        state_next = S_AW;
                end
            end
            S_DONE: begin
                state_next = S_IDLE;
            end
            default: state_next = S_IDLE;
        endcase
    end

    // ----------------------------------------------------------------
    // Compute burst length
    // ----------------------------------------------------------------
    wire [31:0] beats_left = bytes_remaining / BYTES_PER_BEAT;
    wire [7:0]  next_burst_len = (beats_left > 256) ? MAX_BURST : (beats_left[7:0] - 8'd1);

    // ----------------------------------------------------------------
    // Datapath
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            bytes_remaining <= 32'd0;
            current_addr    <= 32'd0;
            beat_count      <= 9'd0;
            burst_len       <= 8'd0;
            done_o          <= 1'b0;
            in_ready_o      <= 1'b0;
            // AW channel
            m_axi_awid      <= AXI_ID;
            m_axi_awaddr    <= 32'd0;
            m_axi_awlen     <= 8'd0;
            m_axi_awsize    <= 3'b100;   // 16 bytes
            m_axi_awburst   <= 2'b01;    // INCR
            m_axi_awvalid   <= 1'b0;
            // W channel
            m_axi_wdata     <= 128'd0;
            m_axi_wstrb     <= 16'hFFFF;
            m_axi_wlast     <= 1'b0;
            m_axi_wvalid    <= 1'b0;
            // B channel
            m_axi_bready    <= 1'b0;
        end else begin
            done_o     <= 1'b0;
            in_ready_o <= 1'b0;

            case (state)
                S_IDLE: begin
                    m_axi_awvalid <= 1'b0;
                    m_axi_wvalid  <= 1'b0;
                    m_axi_bready  <= 1'b0;
                    if (start_i) begin
                        bytes_remaining <= frame_size_i;
                        current_addr    <= base_addr_i;
                        beat_count      <= 9'd0;
                    end
                end

                S_AW: begin
                    m_axi_awid    <= AXI_ID;
                    m_axi_awaddr  <= current_addr;
                    burst_len     <= next_burst_len;
                    m_axi_awlen   <= next_burst_len;
                    m_axi_awsize  <= 3'b100;
                    m_axi_awburst <= 2'b01;
                    m_axi_awvalid <= 1'b1;
                    m_axi_wvalid  <= 1'b0;
                    m_axi_bready  <= 1'b0;
                    beat_count    <= 9'd0;
                    if (m_axi_awvalid && m_axi_awready)
                        m_axi_awvalid <= 1'b0;
                end

                S_WRITE: begin
                    m_axi_awvalid <= 1'b0;
                    in_ready_o    <= m_axi_wready;
                    if (in_valid_i && m_axi_wready) begin
                        m_axi_wdata  <= in_data_i;
                        m_axi_wstrb  <= 16'hFFFF;
                        m_axi_wvalid <= 1'b1;
                        m_axi_wlast  <= (beat_count == {1'b0, burst_len});
                        beat_count   <= beat_count + 9'd1;
                        bytes_remaining <= bytes_remaining - BYTES_PER_BEAT;
                        current_addr    <= current_addr + BYTES_PER_BEAT;
                    end else if (m_axi_wvalid && m_axi_wready) begin
                        // Previous beat accepted, wait for next input
                        m_axi_wvalid <= 1'b0;
                        m_axi_wlast  <= 1'b0;
                    end
                end

                S_BRESP: begin
                    m_axi_wvalid <= 1'b0;
                    m_axi_wlast  <= 1'b0;
                    m_axi_bready <= 1'b1;
                    if (m_axi_bvalid && m_axi_bready)
                        m_axi_bready <= 1'b0;
                end

                S_DONE: begin
                    done_o        <= 1'b1;
                    m_axi_bready  <= 1'b0;
                end
            endcase
        end
    end

endmodule
