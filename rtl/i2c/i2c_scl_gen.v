`timescale 1ns / 1ps
//============================================================================
// i2c_scl_gen.v
// AI_GLASSES — I2C Master
// SCL clock generator with prescaler and clock stretching detection.
// SCL_freq = sys_clk / (4 * (prescaler + 1))
// Default 100kHz at 100MHz sys_clk: prescaler = 249
//============================================================================

module i2c_scl_gen (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [15:0] prescaler_i,
    input  wire        scl_en,

    // Open-drain SCL
    output reg         scl_o,
    output reg         scl_oe_o,
    input  wire        scl_i,

    // Edge detection
    output reg         scl_rise_o,
    output reg         scl_fall_o,

    // Clock stretching
    output reg         stretch_detected_o
);

    // Quarter-period counter: each SCL quarter = prescaler+1 clocks
    reg [15:0] cnt;
    reg [1:0]  phase;      // 0=low1, 1=rise, 2=high, 3=fall
    reg        scl_prev;
    reg        stretching;

    always @(posedge clk) begin
        if (!rst_n) begin
            cnt                <= 16'd0;
            phase              <= 2'd0;
            scl_o              <= 1'b1;
            scl_oe_o           <= 1'b0;
            scl_rise_o         <= 1'b0;
            scl_fall_o         <= 1'b0;
            stretch_detected_o <= 1'b0;
            scl_prev           <= 1'b1;
            stretching         <= 1'b0;
        end else begin
            scl_prev   <= scl_i;
            scl_rise_o <= 1'b0;
            scl_fall_o <= 1'b0;

            // Edge detection on actual SCL line
            if (scl_i && !scl_prev)
                scl_rise_o <= 1'b1;
            if (!scl_i && scl_prev)
                scl_fall_o <= 1'b1;

            if (!scl_en) begin
                cnt      <= 16'd0;
                phase    <= 2'd0;
                scl_o    <= 1'b1;
                scl_oe_o <= 1'b0;
                stretching <= 1'b0;
                stretch_detected_o <= 1'b0;
            end else if (stretching) begin
                // Clock stretching: slave holds SCL low
                stretch_detected_o <= 1'b1;
                if (scl_i) begin
                    stretching         <= 1'b0;
                    stretch_detected_o <= 1'b0;
                end
            end else begin
                stretch_detected_o <= 1'b0;
                if (cnt == prescaler_i) begin
                    cnt <= 16'd0;
                    phase <= phase + 2'd1;
                    case (phase)
                        2'd0: begin // End of low first half -> still low
                            scl_o    <= 1'b0;
                            scl_oe_o <= 1'b1;
                        end
                        2'd1: begin // Release SCL (go high)
                            scl_o    <= 1'b0;
                            scl_oe_o <= 1'b0; // release line
                            // Check for clock stretching
                            if (!scl_i) begin
                                stretching <= 1'b1;
                            end
                        end
                        2'd2: begin // End of high first half -> still released
                            scl_o    <= 1'b0;
                            scl_oe_o <= 1'b0;
                        end
                        2'd3: begin // Pull low
                            scl_o    <= 1'b0;
                            scl_oe_o <= 1'b1;
                        end
                    endcase
                end else begin
                    cnt <= cnt + 16'd1;
                end
            end
        end
    end

endmodule
