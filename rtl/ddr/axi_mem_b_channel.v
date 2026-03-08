`timescale 1ns/1ps
//============================================================================
// AI_GLASSES — DDR Subsystem (Simulation Model)
// Module: axi_mem_b_channel
// Description: B channel handler. Generates write response after
//              WRITE_LATENCY cycles from WLAST.
//============================================================================

module axi_mem_b_channel #(
    parameter WRITE_LATENCY = 5,
    parameter ID_WIDTH      = 6
)(
    input  wire                 clk,
    input  wire                 rst_n,

    // Write completion from W channel
    input  wire                 wlast_done_i,
    input  wire [ID_WIDTH-1:0]  aw_id_i,

    // AXI B channel
    output reg  [ID_WIDTH-1:0]  s_axi_bid,
    output reg  [1:0]           s_axi_bresp,
    output reg                  s_axi_bvalid,
    input  wire                 s_axi_bready,

    // Error injection (for testing SLVERR)
    input  wire                 error_inject_i
);

    // Latency shift register for valid
    reg                 lat_valid [0:WRITE_LATENCY-1];
    reg [ID_WIDTH-1:0]  lat_id    [0:WRITE_LATENCY-1];
    reg                 lat_err   [0:WRITE_LATENCY-1];

    // Response holding register
    reg                 resp_pending;
    reg [ID_WIDTH-1:0]  resp_id;
    reg [1:0]           resp_code;

    integer i;

    initial begin
        for (i = 0; i < WRITE_LATENCY; i = i + 1) begin
            lat_valid[i] = 1'b0;
            lat_id[i]    = {ID_WIDTH{1'b0}};
            lat_err[i]   = 1'b0;
        end
        s_axi_bid    = {ID_WIDTH{1'b0}};
        s_axi_bresp  = 2'b00;
        s_axi_bvalid = 1'b0;
        resp_pending  = 1'b0;
        resp_id       = {ID_WIDTH{1'b0}};
        resp_code     = 2'b00;
    end

    // Latency pipeline
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < WRITE_LATENCY; i = i + 1) begin
                lat_valid[i] <= 1'b0;
                lat_id[i]    <= {ID_WIDTH{1'b0}};
                lat_err[i]   <= 1'b0;
            end
        end else begin
            lat_valid[0] <= wlast_done_i;
            lat_id[0]    <= aw_id_i;
            lat_err[0]   <= error_inject_i;
            for (i = 1; i < WRITE_LATENCY; i = i + 1) begin
                lat_valid[i] <= lat_valid[i-1];
                lat_id[i]    <= lat_id[i-1];
                lat_err[i]   <= lat_err[i-1];
            end
        end
    end

    // B response output
    always @(posedge clk) begin
        if (!rst_n) begin
            s_axi_bvalid <= 1'b0;
            s_axi_bid    <= {ID_WIDTH{1'b0}};
            s_axi_bresp  <= 2'b00;
            resp_pending  <= 1'b0;
        end else begin
            // New response from latency pipe has priority
            if (lat_valid[WRITE_LATENCY-1]) begin
                if (!s_axi_bvalid || s_axi_bready) begin
                    // Output channel free or being consumed — present new response
                    s_axi_bvalid <= 1'b1;
                    s_axi_bid    <= lat_id[WRITE_LATENCY-1];
                    s_axi_bresp  <= lat_err[WRITE_LATENCY-1] ? 2'b10 : 2'b00;
                end else begin
                    // Output busy — hold in pending register
                    resp_pending <= 1'b1;
                    resp_id      <= lat_id[WRITE_LATENCY-1];
                    resp_code    <= lat_err[WRITE_LATENCY-1] ? 2'b10 : 2'b00;
                end
            end else if (resp_pending && (!s_axi_bvalid || s_axi_bready)) begin
                // Drain pending response
                s_axi_bvalid <= 1'b1;
                s_axi_bid    <= resp_id;
                s_axi_bresp  <= resp_code;
                resp_pending  <= 1'b0;
            end else if (s_axi_bvalid && s_axi_bready) begin
                // Handshake complete — deassert valid
                s_axi_bvalid <= 1'b0;
            end
        end
    end

endmodule
