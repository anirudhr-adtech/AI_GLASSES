`timescale 1ns/1ps
//============================================================================
// AI_GLASSES — DDR Subsystem (Simulation Model)
// Module: axi_mem_w_channel
// Description: W channel handler. Accepts W beats, writes to mem_array
//              with wstrb masking. Tracks beat count and WLAST.
//============================================================================

module axi_mem_w_channel #(
    parameter DATA_WIDTH = 128,
    parameter ADDR_WIDTH = 32
)(
    input  wire                      clk,
    input  wire                      rst_n,

    // AXI W channel
    input  wire [DATA_WIDTH-1:0]     s_axi_wdata,
    input  wire [DATA_WIDTH/8-1:0]   s_axi_wstrb,
    input  wire                      s_axi_wlast,
    input  wire                      s_axi_wvalid,
    output reg                       s_axi_wready,

    // Burst info from AW channel
    input  wire                      aw_valid_i,
    input  wire [ADDR_WIDTH-1:0]     aw_addr_i,
    input  wire [7:0]                aw_len_i,
    input  wire [2:0]                aw_size_i,
    output reg                       aw_consumed_o,

    // Completion signal
    output reg                       wlast_done_o,

    // Memory write interface
    output reg                       wr_en,
    output reg  [ADDR_WIDTH-1:0]     wr_addr,
    output reg  [DATA_WIDTH-1:0]     wr_data,
    output reg  [DATA_WIDTH/8-1:0]   wr_strb
);

    localparam STRB_WIDTH = DATA_WIDTH / 8;

    reg [7:0]              beat_cnt;
    reg [ADDR_WIDTH-1:0]   burst_addr;
    reg [7:0]              burst_len;
    reg [2:0]              burst_size;
    reg                    burst_active;

    initial begin
        s_axi_wready  = 1'b0;
        aw_consumed_o = 1'b0;
        wlast_done_o  = 1'b0;
        wr_en         = 1'b0;
        wr_addr       = {ADDR_WIDTH{1'b0}};
        wr_data       = {DATA_WIDTH{1'b0}};
        wr_strb       = {STRB_WIDTH{1'b0}};
        beat_cnt      = 8'd0;
        burst_addr    = {ADDR_WIDTH{1'b0}};
        burst_len     = 8'd0;
        burst_size    = 3'd0;
        burst_active  = 1'b0;
    end

    // Compute next address for INCR burst
    wire [ADDR_WIDTH-1:0] beat_addr = burst_addr + (beat_cnt << burst_size);

    always @(posedge clk) begin
        if (!rst_n) begin
            s_axi_wready  <= 1'b0;
            aw_consumed_o <= 1'b0;
            wlast_done_o  <= 1'b0;
            wr_en         <= 1'b0;
            wr_addr       <= {ADDR_WIDTH{1'b0}};
            wr_data       <= {DATA_WIDTH{1'b0}};
            wr_strb       <= {STRB_WIDTH{1'b0}};
            beat_cnt      <= 8'd0;
            burst_addr    <= {ADDR_WIDTH{1'b0}};
            burst_len     <= 8'd0;
            burst_size    <= 3'd0;
            burst_active  <= 1'b0;
        end else begin
            // Defaults
            aw_consumed_o <= 1'b0;
            wlast_done_o  <= 1'b0;
            wr_en         <= 1'b0;

            // Accept burst from AW channel
            if (!burst_active && aw_valid_i) begin
                burst_active  <= 1'b1;
                burst_addr    <= aw_addr_i;
                burst_len     <= aw_len_i;
                burst_size    <= aw_size_i;
                beat_cnt      <= 8'd0;
                s_axi_wready  <= 1'b1;
                aw_consumed_o <= 1'b1;
            end

            // Process W beats
            if (burst_active && s_axi_wvalid && s_axi_wready) begin
                wr_en   <= 1'b1;
                wr_addr <= beat_addr;
                wr_data <= s_axi_wdata;
                wr_strb <= s_axi_wstrb;

                beat_cnt <= beat_cnt + 8'd1;

                if (s_axi_wlast) begin
                    burst_active <= 1'b0;
                    s_axi_wready <= 1'b0;
                    wlast_done_o <= 1'b1;
                end
            end
        end
    end

endmodule
