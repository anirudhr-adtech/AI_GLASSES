`timescale 1ns/1ps
//============================================================================
// AI_GLASSES — DDR Subsystem (Simulation Model)
// Module: backpressure_gen
// Description: Configurable READY signal throttling for stress testing.
//              Mode 0: always ready
//              Mode 1: deassert 1 cycle every PERIOD
//              Mode 2: random (LFSR-based)
//              Mode 3: worst-case (ready 1 of PERIOD cycles)
//============================================================================

module backpressure_gen #(
    parameter MODE   = 0,
    parameter PERIOD = 8,
    parameter SEED   = 42
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [1:0]  mode_i,
    output reg         ready_o
);

    reg [15:0] lfsr;
    reg [31:0] counter;

    initial begin
        lfsr    = SEED[15:0];
        counter = 32'd0;
        ready_o = 1'b1;
    end

    // LFSR for pseudo-random generation (taps at 16,14,13,11)
    wire lfsr_feedback = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10];

    always @(posedge clk) begin
        if (!rst_n) begin
            lfsr    <= SEED[15:0];
            counter <= 32'd0;
            ready_o <= 1'b1;
        end else begin
            // Update LFSR
            lfsr <= {lfsr[14:0], lfsr_feedback};

            // Update counter
            if (counter >= PERIOD - 1)
                counter <= 32'd0;
            else
                counter <= counter + 32'd1;

            // Generate ready based on mode
            case (mode_i)
                2'd0: ready_o <= 1'b1;                           // Always ready
                2'd1: ready_o <= (counter != PERIOD - 1);        // Deassert 1/PERIOD
                2'd2: ready_o <= lfsr[0];                        // Random
                2'd3: ready_o <= (counter == 0);                 // Ready 1 of PERIOD
            endcase
        end
    end

endmodule
