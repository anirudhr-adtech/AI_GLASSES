`timescale 1ns/1ps
//============================================================================
// AI_GLASSES — DDR Subsystem (Simulation Model)
// Module: latency_pipe
// Description: Configurable delay pipeline for read responses.
//              Data enters and exits after LATENCY clock cycles.
//              Pipeline stalls when output cannot be consumed (out_ready=0).
//              Uses a FIFO-style approach to prevent data loss under
//              backpressure.
//============================================================================

module latency_pipe #(
    parameter LATENCY    = 10,
    parameter DATA_WIDTH = 128,
    parameter ID_WIDTH   = 6
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    in_valid,
    input  wire [DATA_WIDTH-1:0]  in_data,
    input  wire [ID_WIDTH-1:0]    in_id,
    input  wire                    in_last,
    output wire                    out_valid,
    output wire [DATA_WIDTH-1:0]  out_data,
    output wire [ID_WIDTH-1:0]    out_id,
    output wire                    out_last,
    input  wire                    out_ready,
    output wire                    pipe_empty_o
);

    // Total entry width: data + id + last
    localparam ENTRY_W = DATA_WIDTH + ID_WIDTH + 1;

    // FIFO depth: LATENCY + small margin for backpressure absorption
    localparam FIFO_DEPTH = LATENCY + 4;
    localparam PTR_W = $clog2(FIFO_DEPTH + 1);  // extra bit for full/empty

    reg [ENTRY_W-1:0] fifo_mem [0:FIFO_DEPTH-1];
    reg [PTR_W-1:0]   wr_ptr;
    reg [PTR_W-1:0]   rd_ptr;
    reg [PTR_W-1:0]   count;

    // Delay counter: tracks how many cycles the oldest entry has been in the FIFO
    // We use a shift register of valid bits to model the latency
    reg [0:LATENCY-1] delay_sr;  // shift register: delay_sr[LATENCY-1]=1 means oldest entry is ready

    integer i;

    // Initialize
    initial begin
        wr_ptr = {PTR_W{1'b0}};
        rd_ptr = {PTR_W{1'b0}};
        count  = {PTR_W{1'b0}};
        for (i = 0; i < LATENCY; i = i + 1)
            delay_sr[i] = 1'b0;
    end

    wire fifo_full  = (count == FIFO_DEPTH[PTR_W-1:0]);
    wire fifo_empty = (count == {PTR_W{1'b0}});

    // An entry is "mature" (past latency) when it has been in the FIFO >= LATENCY cycles
    // We track this with a count of mature entries
    reg [PTR_W-1:0] mature_count;

    initial begin
        mature_count = {PTR_W{1'b0}};
    end

    wire out_available = (mature_count != {PTR_W{1'b0}});
    wire do_write = in_valid && !fifo_full;
    wire do_read  = out_available && out_ready;

    // Wrap-around pointer helpers
    function [PTR_W-1:0] next_ptr;
        input [PTR_W-1:0] ptr;
    begin
        if (ptr == FIFO_DEPTH[PTR_W-1:0] - 1)
            next_ptr = {PTR_W{1'b0}};
        else
            next_ptr = ptr + {{(PTR_W-1){1'b0}}, 1'b1};
    end
    endfunction

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_ptr       <= {PTR_W{1'b0}};
            rd_ptr       <= {PTR_W{1'b0}};
            count        <= {PTR_W{1'b0}};
            mature_count <= {PTR_W{1'b0}};
            for (i = 0; i < LATENCY; i = i + 1)
                delay_sr[i] <= 1'b0;
        end else begin
            // Shift register for latency tracking:
            // When a new entry is written, a '1' enters delay_sr[0].
            // Each cycle it shifts right. When it reaches delay_sr[LATENCY-1],
            // the corresponding entry becomes mature.

            // Shift the delay pipeline
            for (i = LATENCY-1; i > 0; i = i - 1)
                delay_sr[i] <= delay_sr[i-1];
            delay_sr[0] <= do_write;

            // Update mature count:
            // +1 when delay_sr[LATENCY-1] fires (entry becomes mature)
            // -1 when do_read fires (mature entry consumed)
            if (delay_sr[LATENCY-1] && !do_read)
                mature_count <= mature_count + {{(PTR_W-1){1'b0}}, 1'b1};
            else if (!delay_sr[LATENCY-1] && do_read)
                mature_count <= mature_count - {{(PTR_W-1){1'b0}}, 1'b1};
            // else both or neither: no change

            // FIFO write
            if (do_write) begin
                fifo_mem[wr_ptr] <= {in_last, in_id, in_data};
                wr_ptr <= next_ptr(wr_ptr);
            end

            // FIFO read
            if (do_read) begin
                rd_ptr <= next_ptr(rd_ptr);
            end

            // Update count
            if (do_write && !do_read)
                count <= count + {{(PTR_W-1){1'b0}}, 1'b1};
            else if (!do_write && do_read)
                count <= count - {{(PTR_W-1){1'b0}}, 1'b1};
        end
    end

    // Output mux — directly from FIFO head (combinational read)
    wire [ENTRY_W-1:0] head_data = fifo_mem[rd_ptr];

    assign out_valid = out_available;
    assign out_data  = head_data[DATA_WIDTH-1:0];
    assign out_id    = head_data[DATA_WIDTH +: ID_WIDTH];
    assign out_last  = head_data[DATA_WIDTH + ID_WIDTH];

    // Empty flag: FIFO has no entries AND no entries in the delay pipeline
    wire delay_sr_empty;
    reg delay_sr_has_entry;
    integer j;
    always @(*) begin
        delay_sr_has_entry = 1'b0;
        for (j = 0; j < LATENCY; j = j + 1)
            delay_sr_has_entry = delay_sr_has_entry | delay_sr[j];
    end
    assign pipe_empty_o = fifo_empty && !delay_sr_has_entry;

endmodule
