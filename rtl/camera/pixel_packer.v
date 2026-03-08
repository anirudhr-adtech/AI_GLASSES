`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Camera Subsystem
// Module: pixel_packer
// Description: Packs 24-bit RGB pixels into 128-bit AXI words (4 x RGBX)
//////////////////////////////////////////////////////////////////////////////

module pixel_packer (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [23:0]  in_pixel_i,
    input  wire         in_valid_i,
    output reg  [127:0] out_data_o,
    output reg          out_valid_o,
    input  wire         out_ready_i
);

    // Accumulator: 4 pixels x 32 bits = 128 bits
    reg [127:0] acc;
    reg [1:0]   cnt;  // 0..3 pixel counter

    always @(posedge clk) begin
        if (!rst_n) begin
            acc         <= 128'd0;
            cnt         <= 2'd0;
            out_data_o  <= 128'd0;
            out_valid_o <= 1'b0;
        end else begin
            // Clear valid once downstream accepts
            if (out_valid_o && out_ready_i)
                out_valid_o <= 1'b0;

            if (in_valid_i && !(out_valid_o && !out_ready_i)) begin
                // Pack 24-bit RGB into 32-bit RGBX (X = 0x00)
                case (cnt)
                    2'd0: acc[31:0]    <= {in_pixel_i, 8'h00};
                    2'd1: acc[63:32]   <= {in_pixel_i, 8'h00};
                    2'd2: acc[95:64]   <= {in_pixel_i, 8'h00};
                    2'd3: acc[127:96]  <= {in_pixel_i, 8'h00};
                endcase

                if (cnt == 2'd3) begin
                    out_data_o  <= {in_pixel_i, 8'h00, acc[95:0]};
                    out_valid_o <= 1'b1;
                    cnt         <= 2'd0;
                end else begin
                    cnt <= cnt + 2'd1;
                end
            end
        end
    end

endmodule
