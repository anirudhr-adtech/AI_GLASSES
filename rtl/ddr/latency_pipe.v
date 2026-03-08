`timescale 1ns/1ps
//============================================================================
// AI_GLASSES — DDR Subsystem (Simulation Model)
// Module: latency_pipe
// Description: Configurable delay pipeline for read responses.
//              Data enters and exits after LATENCY clock cycles.
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
    input  wire                    out_ready
);

    // Total entry width: data + id + last + valid
    localparam ENTRY_W = DATA_WIDTH + ID_WIDTH + 1;

    // Shift register pipeline
    reg [ENTRY_W-1:0] pipe_data [0:LATENCY-1];
    reg               pipe_valid [0:LATENCY-1];

    integer i;

    // Initialize
    initial begin
        for (i = 0; i < LATENCY; i = i + 1) begin
            pipe_data[i]  = {ENTRY_W{1'b0}};
            pipe_valid[i] = 1'b0;
        end
    end

    // Pipeline shift
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < LATENCY; i = i + 1) begin
                pipe_data[i]  <= {ENTRY_W{1'b0}};
                pipe_valid[i] <= 1'b0;
            end
        end else begin
            // Stage 0 input
            pipe_valid[0] <= in_valid;
            pipe_data[0]  <= {in_last, in_id, in_data};
            // Shift through pipeline
            for (i = 1; i < LATENCY; i = i + 1) begin
                pipe_valid[i] <= pipe_valid[i-1];
                pipe_data[i]  <= pipe_data[i-1];
            end
        end
    end

    // Output from last stage
    assign out_valid = pipe_valid[LATENCY-1];
    assign out_data  = pipe_data[LATENCY-1][DATA_WIDTH-1:0];
    assign out_id    = pipe_data[LATENCY-1][DATA_WIDTH +: ID_WIDTH];
    assign out_last  = pipe_data[LATENCY-1][DATA_WIDTH + ID_WIDTH];

endmodule
