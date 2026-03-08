`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem
// Module: mfcc_out_buf
// Description: Double-buffered 49x10 MFCC accumulator. Two banks: while one
//              fills with MFCC vectors, the other is DMA'd to DDR.
//              Asserts frame_ready when 49 vectors accumulated.
//////////////////////////////////////////////////////////////////////////////

module mfcc_out_buf (
    input  wire        clk,
    input  wire        rst_n,
    // Write interface (from DCT unit)
    input  wire        wr_en,
    input  wire [15:0] wr_data,
    input  wire [3:0]  wr_idx,       // MFCC coefficient index (0-9)
    // Frame control
    output reg         frame_ready_o,
    input  wire        bank_swap_i,  // Swap banks (after DMA completes)
    // Read interface (for DMA)
    input  wire        rd_en,
    input  wire [8:0]  rd_addr,      // 0..489 (49*10-1)
    output reg  [15:0] rd_data
);

    // Double buffer: 2 banks x 490 entries (49 vectors x 10 coefficients)
    // Bank select: active_bank = which bank is currently being written
    (* ram_style = "block" *) reg [15:0] bank0 [0:511]; // 512 deep for power-of-2
    (* ram_style = "block" *) reg [15:0] bank1 [0:511];

    reg        active_bank;   // 0 = writing bank0, 1 = writing bank1
    reg [5:0]  vec_count;     // Number of complete MFCC vectors written (0-49)
    reg [3:0]  coeff_count;   // Coefficients received for current vector
    reg [8:0]  wr_addr;       // Write address = vec_count * 10 + wr_idx

    always @(posedge clk) begin
        if (!rst_n) begin
            active_bank   <= 1'b0;
            vec_count     <= 6'd0;
            coeff_count   <= 4'd0;
            frame_ready_o <= 1'b0;
            rd_data       <= 16'd0;
        end else begin
            // Bank swap
            if (bank_swap_i) begin
                active_bank   <= ~active_bank;
                vec_count     <= 6'd0;
                coeff_count   <= 4'd0;
                frame_ready_o <= 1'b0;
            end

            // Write path
            if (wr_en && !frame_ready_o) begin
                wr_addr = vec_count * 10 + {5'd0, wr_idx};
                if (active_bank == 1'b0)
                    bank0[wr_addr] <= wr_data;
                else
                    bank1[wr_addr] <= wr_data;

                // Track when a full vector (10 coefficients) is written
                if (wr_idx == 4'd9) begin
                    if (vec_count == 6'd48) begin
                        frame_ready_o <= 1'b1;
                    end
                    vec_count <= vec_count + 6'd1;
                end
            end

            // Read path (from inactive bank for DMA)
            if (rd_en) begin
                if (active_bank == 1'b0)
                    rd_data <= bank1[rd_addr]; // Read from inactive bank1
                else
                    rd_data <= bank0[rd_addr]; // Read from inactive bank0
            end
        end
    end

endmodule
