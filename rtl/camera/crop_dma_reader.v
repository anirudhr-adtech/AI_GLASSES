`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Camera Subsystem
// Module: crop_dma_reader
// Description: AXI4 read controller for fetching ROI rows from DDR
//////////////////////////////////////////////////////////////////////////////

module crop_dma_reader (
    input  wire         clk,
    input  wire         rst_n,
    // Control
    input  wire         start_i,
    input  wire [31:0]  raw_frame_addr_i,
    input  wire [15:0]  frame_stride_i,
    input  wire [9:0]   crop_x_i,
    input  wire [9:0]   crop_y_i,
    input  wire [9:0]   crop_w_i,
    input  wire [9:0]   crop_h_i,
    // Status
    output reg          done_o,
    // Data output (128-bit words to downstream)
    output reg  [127:0] out_data_o,
    output reg          out_valid_o,
    input  wire         out_ready_i,
    // AXI4 Read Address Channel
    output reg  [3:0]   m_axi_arid,
    output reg  [31:0]  m_axi_araddr,
    output reg  [7:0]   m_axi_arlen,
    output reg  [2:0]   m_axi_arsize,
    output reg  [1:0]   m_axi_arburst,
    output reg          m_axi_arvalid,
    input  wire         m_axi_arready,
    // AXI4 Read Data Channel
    input  wire [3:0]   m_axi_rid,
    input  wire [127:0] m_axi_rdata,
    input  wire [1:0]   m_axi_rresp,
    input  wire         m_axi_rlast,
    input  wire         m_axi_rvalid,
    output reg          m_axi_rready
);

    // ----------------------------------------------------------------
    // Parameters
    // ----------------------------------------------------------------
    localparam AXI_ID         = 4'b1101;
    localparam BYTES_PER_BEAT = 16;         // 128-bit
    localparam BYTES_PER_PIXEL = 4;         // RGBX
    localparam MAX_BURST      = 8'd255;

    // ----------------------------------------------------------------
    // FSM
    // ----------------------------------------------------------------
    localparam [2:0] S_IDLE     = 3'd0,
                     S_CALC     = 3'd1,
                     S_AR       = 3'd2,
                     S_READ     = 3'd3,
                     S_NEXT_ROW = 3'd4,
                     S_DONE     = 3'd5;

    reg [2:0] state, state_next;

    // Row tracking
    reg [9:0]  row_idx;
    reg [31:0] row_addr;
    reg [15:0] row_bytes;       // bytes per crop row = crop_w * 4
    reg [15:0] row_bytes_rem;   // remaining bytes in current row
    reg [7:0]  burst_len;

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
                    state_next = S_CALC;
            end
            S_CALC: begin
                state_next = S_AR;
            end
            S_AR: begin
                if (m_axi_arvalid && m_axi_arready)
                    state_next = S_READ;
            end
            S_READ: begin
                if (m_axi_rvalid && m_axi_rready && m_axi_rlast) begin
                    if (row_bytes_rem == 16'd0) begin
                        if (row_idx >= crop_h_i)
                            state_next = S_DONE;
                        else
                            state_next = S_NEXT_ROW;
                    end else begin
                        state_next = S_AR; // more bursts for this row
                    end
                end
            end
            S_NEXT_ROW: begin
                state_next = S_CALC;
            end
            S_DONE: begin
                state_next = S_IDLE;
            end
            default: state_next = S_IDLE;
        endcase
    end

    // ----------------------------------------------------------------
    // Compute burst length from remaining row bytes
    // ----------------------------------------------------------------
    wire [15:0] beats_in_row = row_bytes_rem / BYTES_PER_BEAT;
    wire [7:0]  calc_burst_len = (beats_in_row > 256) ? MAX_BURST :
                                 (beats_in_row[7:0] - 8'd1);

    // ----------------------------------------------------------------
    // Datapath
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            row_idx       <= 10'd0;
            row_addr      <= 32'd0;
            row_bytes     <= 16'd0;
            row_bytes_rem <= 16'd0;
            burst_len     <= 8'd0;
            done_o        <= 1'b0;
            out_data_o    <= 128'd0;
            out_valid_o   <= 1'b0;
            // AR channel
            m_axi_arid    <= AXI_ID;
            m_axi_araddr  <= 32'd0;
            m_axi_arlen   <= 8'd0;
            m_axi_arsize  <= 3'b100;
            m_axi_arburst <= 2'b01;
            m_axi_arvalid <= 1'b0;
            // R channel
            m_axi_rready  <= 1'b0;
        end else begin
            done_o      <= 1'b0;
            out_valid_o <= 1'b0;

            case (state)
                S_IDLE: begin
                    m_axi_arvalid <= 1'b0;
                    m_axi_rready  <= 1'b0;
                    if (start_i) begin
                        row_idx   <= 10'd0;
                        row_bytes <= {4'd0, crop_w_i, 2'b00}; // crop_w * 4
                    end
                end

                S_CALC: begin
                    // Calculate row address:
                    // row_addr = raw_frame_addr + (crop_y + row_idx) * stride + crop_x * 4
                    row_addr <= raw_frame_addr_i +
                                ({16'd0, frame_stride_i} * {22'd0, crop_y_i + row_idx}) +
                                {20'd0, crop_x_i, 2'b00};
                    row_bytes_rem <= {4'd0, crop_w_i, 2'b00};
                    row_idx       <= row_idx + 10'd1;
                end

                S_AR: begin
                    m_axi_arid    <= AXI_ID;
                    m_axi_araddr  <= row_addr;
                    burst_len     <= calc_burst_len;
                    m_axi_arlen   <= calc_burst_len;
                    m_axi_arsize  <= 3'b100;
                    m_axi_arburst <= 2'b01;
                    m_axi_arvalid <= 1'b1;
                    m_axi_rready  <= 1'b0;
                    if (m_axi_arvalid && m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        // Update row_addr and row_bytes_rem for multi-burst rows
                        row_addr      <= row_addr + ({24'd0, burst_len} + 32'd1) * BYTES_PER_BEAT;
                        row_bytes_rem <= row_bytes_rem - (({8'd0, burst_len} + 16'd1) * BYTES_PER_BEAT);
                    end
                end

                S_READ: begin
                    m_axi_arvalid <= 1'b0;
                    m_axi_rready  <= out_ready_i;
                    if (m_axi_rvalid && m_axi_rready) begin
                        out_data_o  <= m_axi_rdata;
                        out_valid_o <= 1'b1;
                    end
                end

                S_NEXT_ROW: begin
                    // Proceed to next row calculation
                    m_axi_rready <= 1'b0;
                end

                S_DONE: begin
                    done_o       <= 1'b1;
                    m_axi_rready <= 1'b0;
                end
            endcase
        end
    end

endmodule
