`timescale 1ns/1ps
//============================================================================
// Module : rst_sync
// Project : AI_GLASSES — RISC-V Subsystem
// Description : 2-FF reset synchronizer for active-low reset.
//               Asynchronous assertion, synchronous deassertion.
//============================================================================
module rst_sync (
    input  wire clk,
    input  wire rst_n_async,
    output wire rst_n_sync
);

    reg ff1;
    reg ff2;

    always @(posedge clk or negedge rst_n_async) begin
        if (!rst_n_async) begin
            ff1 <= 1'b0;
            ff2 <= 1'b0;
        end else begin
            ff1 <= 1'b1;
            ff2 <= ff1;
        end
    end

    assign rst_n_sync = ff2;

endmodule
