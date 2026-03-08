`timescale 1ns/1ps
//============================================================================
// AI_GLASSES — DDR Subsystem (Simulation Model)
// Module: axi_mem_r_channel
// Description: R channel handler. Reads from mem_array, sends through
//              latency_pipe, outputs R data with RLAST.
//============================================================================

module axi_mem_r_channel #(
    parameter DATA_WIDTH   = 128,
    parameter ADDR_WIDTH   = 32,
    parameter ID_WIDTH     = 6,
    parameter READ_LATENCY = 10
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // Burst info from AR channel
    input  wire                    ar_valid_i,
    input  wire [ADDR_WIDTH-1:0]  ar_addr_i,
    input  wire [7:0]             ar_len_i,
    input  wire [2:0]             ar_size_i,
    input  wire [ID_WIDTH-1:0]    ar_id_i,
    output reg                    ar_ready_o,

    // AXI R channel
    output wire [ID_WIDTH-1:0]    s_axi_rid,
    output wire [DATA_WIDTH-1:0]  s_axi_rdata,
    output wire [1:0]             s_axi_rresp,
    output wire                   s_axi_rlast,
    output wire                   s_axi_rvalid,
    input  wire                   s_axi_rready,

    // Memory read interface
    output reg                    rd_en,
    output reg  [ADDR_WIDTH-1:0]  rd_addr,
    input  wire [DATA_WIDTH-1:0]  rd_data
);

    // State machine
    localparam S_IDLE = 1'b0;
    localparam S_BURST = 1'b1;

    reg                    state;
    reg [ADDR_WIDTH-1:0]   burst_addr;
    reg [7:0]              burst_len;
    reg [2:0]              burst_size;
    reg [ID_WIDTH-1:0]     burst_id;
    reg [7:0]              beat_cnt;

    // Pipe input signals
    reg                    pipe_in_valid;
    reg [DATA_WIDTH-1:0]   pipe_in_data;
    reg [ID_WIDTH-1:0]     pipe_in_id;
    reg                    pipe_in_last;

    // Pipe output signals
    wire                   pipe_out_valid;
    wire [DATA_WIDTH-1:0]  pipe_out_data;
    wire [ID_WIDTH-1:0]    pipe_out_id;
    wire                   pipe_out_last;
    wire                   pipe_empty;

    initial begin
        state        = S_IDLE;
        ar_ready_o   = 1'b0;
        rd_en        = 1'b0;
        rd_addr      = {ADDR_WIDTH{1'b0}};
        burst_addr   = {ADDR_WIDTH{1'b0}};
        burst_len    = 8'd0;
        burst_size   = 3'd0;
        burst_id     = {ID_WIDTH{1'b0}};
        beat_cnt     = 8'd0;
        pipe_in_valid = 1'b0;
        pipe_in_data  = {DATA_WIDTH{1'b0}};
        pipe_in_id    = {ID_WIDTH{1'b0}};
        pipe_in_last  = 1'b0;
    end

    // Address generation: INCR burst
    wire [ADDR_WIDTH-1:0] beat_addr = burst_addr + (beat_cnt << burst_size);

    // Read state machine
    // mem_array has 1-cycle registered read: rd_en at cycle N, rd_data valid at cycle N+2
    // (rd_en captured at posedge N, rd_data NBA at posedge N+1, visible at posedge N+2)
    // So we use a 2-stage pending: rd_pending_p1 -> rd_pending_p2 -> capture
    reg rd_pending_p1;  // 1 cycle after rd_en
    reg rd_pending_p2;  // 2 cycles after rd_en (rd_data now valid)
    reg rd_is_last;
    reg rd_is_last_p2;

    initial begin
        rd_pending_p1 = 1'b0;
        rd_pending_p2 = 1'b0;
        rd_is_last    = 1'b0;
        rd_is_last_p2 = 1'b0;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            ar_ready_o    <= 1'b0;
            rd_en         <= 1'b0;
            rd_addr       <= {ADDR_WIDTH{1'b0}};
            beat_cnt      <= 8'd0;
            pipe_in_valid <= 1'b0;
            rd_pending_p1 <= 1'b0;
            rd_pending_p2 <= 1'b0;
            rd_is_last    <= 1'b0;
            rd_is_last_p2 <= 1'b0;
        end else begin
            pipe_in_valid <= 1'b0;
            rd_en         <= 1'b0;
            ar_ready_o    <= 1'b0;

            // Pipeline the pending flag to account for mem_array registered read
            rd_pending_p2 <= rd_pending_p1;
            rd_is_last_p2 <= rd_is_last;
            rd_pending_p1 <= 1'b0;  // default clear (set below when rd_en issued)

            // Capture read data from mem_array (2 cycles after rd_en)
            if (rd_pending_p2) begin
                pipe_in_valid <= 1'b1;
                pipe_in_data  <= rd_data;
                pipe_in_id    <= burst_id;
                pipe_in_last  <= rd_is_last_p2;
            end

            case (state)
                S_IDLE: begin
                    ar_ready_o <= pipe_empty;  // only accept new burst when pipe is drained
                    if (ar_valid_i && ar_ready_o) begin
                        state      <= S_BURST;
                        burst_addr <= ar_addr_i;
                        burst_len  <= ar_len_i;
                        burst_size <= ar_size_i;
                        burst_id   <= ar_id_i;
                        beat_cnt   <= 8'd0;
                        // Issue first read
                        rd_en         <= 1'b1;
                        rd_addr       <= ar_addr_i;
                        rd_pending_p1 <= 1'b1;
                        rd_is_last    <= (ar_len_i == 8'd0);
                        ar_ready_o    <= 1'b0;
                    end
                end
                S_BURST: begin
                    // After capturing previous beat, issue next read
                    if (pipe_in_valid && !pipe_in_last) begin
                        beat_cnt      <= beat_cnt + 8'd1;
                        rd_en         <= 1'b1;
                        rd_addr       <= burst_addr + ((beat_cnt + 8'd1) << burst_size);
                        rd_pending_p1 <= 1'b1;
                        rd_is_last    <= ((beat_cnt + 8'd1) == burst_len);
                    end

                    // Burst complete
                    if (pipe_in_valid && pipe_in_last) begin
                        state <= S_IDLE;
                    end
                end
            endcase
        end
    end

    // Latency pipe instance
    latency_pipe #(
        .LATENCY    (READ_LATENCY),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) u_lat_pipe (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (pipe_in_valid),
        .in_data   (pipe_in_data),
        .in_id     (pipe_in_id),
        .in_last   (pipe_in_last),
        .out_valid    (pipe_out_valid),
        .out_data     (pipe_out_data),
        .out_id       (pipe_out_id),
        .out_last     (pipe_out_last),
        .out_ready    (s_axi_rready),
        .pipe_empty_o (pipe_empty)
    );

    // AXI R outputs
    assign s_axi_rvalid = pipe_out_valid;
    assign s_axi_rdata  = pipe_out_data;
    assign s_axi_rid    = pipe_out_id;
    assign s_axi_rlast  = pipe_out_last;
    assign s_axi_rresp  = 2'b00;  // OKAY

endmodule
