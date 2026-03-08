`timescale 1ns/1ps
//============================================================================
// Module : axi_arbiter
// Project : AI_GLASSES — RISC-V Subsystem
// Description : Round-robin arbiter for 3 AXI masters with DMA priority
//               override, per-burst grant hold, and starvation prevention.
//============================================================================

module riscv_axi_arbiter #(
    parameter NUM_MASTERS    = 3,
    parameter STARVE_LIMIT   = 16
)(
    input  wire                       clk,
    input  wire                       rst_n,

    input  wire [NUM_MASTERS-1:0]     req_i,
    input  wire                       done_i,

    output wire [NUM_MASTERS-1:0]     grant_o,
    output wire [$clog2(NUM_MASTERS)-1:0] last_o
);

    // States
    localparam IDLE   = 1'b0;
    localparam ACTIVE = 1'b1;

    reg        state_r;
    reg [NUM_MASTERS-1:0] grant_r;
    reg [$clog2(NUM_MASTERS)-1:0] last_r;

    // Round-robin pointer: next master to check
    reg [$clog2(NUM_MASTERS)-1:0] rr_ptr_r;

    // Starvation counters
    reg [4:0] starve_cnt_r [0:NUM_MASTERS-1];
    reg [NUM_MASTERS-1:0] starved;

    // Detect starvation
    integer si;
    always @(*) begin
        for (si = 0; si < NUM_MASTERS; si = si + 1)
            starved[si] = (starve_cnt_r[si] >= STARVE_LIMIT) && req_i[si];
    end

    // Arbitration winner selection (combinational)
    reg [$clog2(NUM_MASTERS)-1:0] winner;
    reg                            winner_valid;

    integer wi;
    always @(*) begin
        winner       = rr_ptr_r;
        winner_valid = 1'b0;

        // Priority 1: starvation prevention (lowest index starved master)
        for (wi = NUM_MASTERS-1; wi >= 0; wi = wi - 1) begin
            if (starved[wi]) begin
                winner       = wi[$clog2(NUM_MASTERS)-1:0];
                winner_valid = 1'b1;
            end
        end

        // Priority 2: DMA override — M2 wins over M0 if only M0 and M2 are requesting
        if (!winner_valid) begin
            if (req_i[2] && req_i[0] && !req_i[1]) begin
                winner       = 2'd2;
                winner_valid = 1'b1;
            end
        end

        // Priority 3: round-robin from rr_ptr
        if (!winner_valid) begin
            for (wi = 0; wi < NUM_MASTERS; wi = wi + 1) begin
                if (req_i[(rr_ptr_r + wi[1:0]) % NUM_MASTERS]) begin
                    winner       = ((rr_ptr_r + wi[$clog2(NUM_MASTERS)-1:0]) < NUM_MASTERS) ?
                                   (rr_ptr_r + wi[$clog2(NUM_MASTERS)-1:0]) :
                                   (rr_ptr_r + wi[$clog2(NUM_MASTERS)-1:0] - NUM_MASTERS);
                    winner_valid = 1'b1;
                end
            end
        end
    end

    // FSM
    integer ci;
    always @(posedge clk) begin
        if (!rst_n) begin
            state_r  <= IDLE;
            grant_r  <= {NUM_MASTERS{1'b0}};
            last_r   <= {$clog2(NUM_MASTERS){1'b0}};
            rr_ptr_r <= {$clog2(NUM_MASTERS){1'b0}};
            for (ci = 0; ci < NUM_MASTERS; ci = ci + 1)
                starve_cnt_r[ci] <= 5'd0;
        end else begin
            case (state_r)
                IDLE: begin
                    grant_r <= {NUM_MASTERS{1'b0}};
                    if (|req_i && winner_valid) begin
                        grant_r[winner] <= 1'b1;
                        last_r          <= winner;
                        state_r         <= ACTIVE;
                        // Advance round-robin pointer past winner
                        rr_ptr_r <= (winner + 1 < NUM_MASTERS) ? winner + 1 :
                                    winner + 1 - NUM_MASTERS;
                        // Reset winner starvation, increment others
                        for (ci = 0; ci < NUM_MASTERS; ci = ci + 1) begin
                            if (ci[$clog2(NUM_MASTERS)-1:0] == winner)
                                starve_cnt_r[ci] <= 5'd0;
                            else if (req_i[ci])
                                starve_cnt_r[ci] <= starve_cnt_r[ci] + 5'd1;
                        end
                    end
                end

                ACTIVE: begin
                    if (done_i) begin
                        grant_r <= {NUM_MASTERS{1'b0}};
                        state_r <= IDLE;
                    end
                end
            endcase
        end
    end

    assign grant_o = grant_r;
    assign last_o  = last_r;

endmodule
