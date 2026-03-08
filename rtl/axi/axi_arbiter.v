`timescale 1ns/1ps
//============================================================================
// Module:      axi_arbiter
// Project:     AI_GLASSES — AXI Interconnect
// Description: 3-tier priority arbiter for per-slave arbitration.
//              Tier 0 (highest): NPU DMA. Tier 1: Camera DMA.
//              Tier 2: CPU, Audio. Round-robin within tier.
//              Starvation prevention: promote after STALL_LIMIT cycles.
//              Burst-level lock prevents mid-burst preemption.
//============================================================================

module axi_arbiter #(
    parameter NUM_MASTERS = 5,
    parameter STALL_LIMIT = 32
)(
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire [NUM_MASTERS-1:0]    req_i,
    input  wire [2*NUM_MASTERS-1:0]  tier_i,
    input  wire                      lock_i,
    input  wire                      done_i,
    output reg  [NUM_MASTERS-1:0]    grant_o,
    output reg  [16*NUM_MASTERS-1:0] stall_count_o
);

    // FSM states
    localparam IDLE                = 2'd0;
    localparam GRANTED             = 2'd1;
    localparam STARVATION_OVERRIDE = 2'd2;

    reg [1:0] state;
    reg [NUM_MASTERS-1:0] rr_priority;  // Round-robin pointer per tier
    reg [15:0] stall_cnt [0:NUM_MASTERS-1];
    reg [NUM_MASTERS-1:0] starved_mask;

    integer i;

    // Extract tier for a master
    function [1:0] get_tier;
        input integer idx;
        begin
            get_tier = tier_i[idx*2 +: 2];
        end
    endfunction

    // Find highest priority request
    reg [NUM_MASTERS-1:0] grant_next;
    reg                   found;
    reg [1:0]             sel_tier;
    integer j, k;

    always @(*) begin
        grant_next = {NUM_MASTERS{1'b0}};
        found      = 1'b0;
        sel_tier   = 2'd2;

        // If starvation override active, use starved_mask
        if (state == STARVATION_OVERRIDE) begin
            for (j = 0; j < NUM_MASTERS; j = j + 1) begin
                if (starved_mask[j] && req_i[j] && !found) begin
                    grant_next[j] = 1'b1;
                    found = 1'b1;
                end
            end
        end

        if (!found) begin
            // Determine highest active tier
            sel_tier = 2'd3; // invalid
            for (j = 0; j < NUM_MASTERS; j = j + 1) begin
                if (req_i[j] && (get_tier(j) < sel_tier))
                    sel_tier = get_tier(j);
            end

            // Round-robin within selected tier
            // Scan from rr_priority position
            if (sel_tier != 2'd3) begin
                for (k = 0; k < NUM_MASTERS; k = k + 1) begin
                    j = (rr_priority + k) % NUM_MASTERS;
                    if (req_i[j] && (get_tier(j) == sel_tier) && !found) begin
                        grant_next[j] = 1'b1;
                        found = 1'b1;
                    end
                end
            end
        end
    end

    // Stall counter output packing
    always @(*) begin
        for (i = 0; i < NUM_MASTERS; i = i + 1) begin
            stall_count_o[i*16 +: 16] = stall_cnt[i];
        end
    end

    // Main FSM
    always @(posedge clk) begin
        if (!rst_n) begin
            state       <= IDLE;
            grant_o     <= {NUM_MASTERS{1'b0}};
            rr_priority <= {NUM_MASTERS{1'b0}};
            rr_priority[0] <= 1'b1;
            starved_mask <= {NUM_MASTERS{1'b0}};
            for (i = 0; i < NUM_MASTERS; i = i + 1) begin
                stall_cnt[i] <= 16'd0;
            end
        end else begin
            case (state)
                IDLE: begin
                    // Update stall counters for waiting masters
                    for (i = 0; i < NUM_MASTERS; i = i + 1) begin
                        if (req_i[i] && !grant_o[i])
                            stall_cnt[i] <= stall_cnt[i] + 16'd1;
                        else
                            stall_cnt[i] <= 16'd0;
                    end

                    // Check for starvation
                    starved_mask <= {NUM_MASTERS{1'b0}};
                    for (i = 0; i < NUM_MASTERS; i = i + 1) begin
                        if (stall_cnt[i] >= STALL_LIMIT)
                            starved_mask[i] <= 1'b1;
                    end

                    if (|req_i) begin
                        // Check if any master starved
                        if (|starved_mask) begin
                            grant_o <= grant_next;
                            state   <= STARVATION_OVERRIDE;
                        end else begin
                            grant_o <= grant_next;
                            state   <= GRANTED;
                        end
                        // Update round-robin pointer
                        for (i = 0; i < NUM_MASTERS; i = i + 1) begin
                            if (grant_next[i])
                                rr_priority <= (i + 1) % NUM_MASTERS;
                        end
                    end else begin
                        grant_o <= {NUM_MASTERS{1'b0}};
                    end
                end

                GRANTED: begin
                    // Reset stall counter for granted master
                    for (i = 0; i < NUM_MASTERS; i = i + 1) begin
                        if (grant_o[i])
                            stall_cnt[i] <= 16'd0;
                        else if (req_i[i])
                            stall_cnt[i] <= stall_cnt[i] + 16'd1;
                    end

                    if (done_i && !lock_i) begin
                        grant_o <= {NUM_MASTERS{1'b0}};
                        state   <= IDLE;
                    end
                end

                STARVATION_OVERRIDE: begin
                    // Same as GRANTED but after one grant, demote back
                    for (i = 0; i < NUM_MASTERS; i = i + 1) begin
                        if (grant_o[i])
                            stall_cnt[i] <= 16'd0;
                        else if (req_i[i])
                            stall_cnt[i] <= stall_cnt[i] + 16'd1;
                    end

                    if (done_i && !lock_i) begin
                        grant_o      <= {NUM_MASTERS{1'b0}};
                        starved_mask <= {NUM_MASTERS{1'b0}};
                        state        <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
