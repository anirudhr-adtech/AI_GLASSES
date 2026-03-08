`timescale 1ns/1ps
//============================================================================
// AI_GLASSES — DDR Subsystem (Simulation Model)
// Module: mem_array
// Description: Byte-addressable memory storage with fixed-size reg array.
//              Simulation-only behavioral model.
//============================================================================

module mem_array #(
    parameter MEM_SIZE_BYTES = 1048576  // 1MB for simulation
)(
    input  wire         clk,
    input  wire         wr_en,
    input  wire [31:0]  wr_addr,
    input  wire [127:0] wr_data,
    input  wire [15:0]  wr_strb,
    input  wire         rd_en,
    input  wire [31:0]  rd_addr,
    output reg  [127:0] rd_data
);

    // Byte-addressable memory
    reg [7:0] mem [0:MEM_SIZE_BYTES-1];

    integer i;

    // Initialize memory to zero
    initial begin
        for (i = 0; i < MEM_SIZE_BYTES; i = i + 1)
            mem[i] = 8'h00;
        rd_data = 128'd0;
    end

    // Write with byte strobes
    always @(posedge clk) begin
        if (wr_en) begin
            for (i = 0; i < 16; i = i + 1) begin
                if (wr_strb[i] && (wr_addr + i) < MEM_SIZE_BYTES)
                    mem[wr_addr + i] <= wr_data[i*8 +: 8];
            end
        end
    end

    // Registered read
    always @(posedge clk) begin
        if (rd_en) begin
            rd_data[ 7:  0] <= ((rd_addr +  0) < MEM_SIZE_BYTES) ? mem[rd_addr +  0] : 8'h00;
            rd_data[ 15:  8] <= ((rd_addr +  1) < MEM_SIZE_BYTES) ? mem[rd_addr +  1] : 8'h00;
            rd_data[ 23: 16] <= ((rd_addr +  2) < MEM_SIZE_BYTES) ? mem[rd_addr +  2] : 8'h00;
            rd_data[ 31: 24] <= ((rd_addr +  3) < MEM_SIZE_BYTES) ? mem[rd_addr +  3] : 8'h00;
            rd_data[ 39: 32] <= ((rd_addr +  4) < MEM_SIZE_BYTES) ? mem[rd_addr +  4] : 8'h00;
            rd_data[ 47: 40] <= ((rd_addr +  5) < MEM_SIZE_BYTES) ? mem[rd_addr +  5] : 8'h00;
            rd_data[ 55: 48] <= ((rd_addr +  6) < MEM_SIZE_BYTES) ? mem[rd_addr +  6] : 8'h00;
            rd_data[ 63: 56] <= ((rd_addr +  7) < MEM_SIZE_BYTES) ? mem[rd_addr +  7] : 8'h00;
            rd_data[ 71: 64] <= ((rd_addr +  8) < MEM_SIZE_BYTES) ? mem[rd_addr +  8] : 8'h00;
            rd_data[ 79: 72] <= ((rd_addr +  9) < MEM_SIZE_BYTES) ? mem[rd_addr +  9] : 8'h00;
            rd_data[ 87: 80] <= ((rd_addr + 10) < MEM_SIZE_BYTES) ? mem[rd_addr + 10] : 8'h00;
            rd_data[ 95: 88] <= ((rd_addr + 11) < MEM_SIZE_BYTES) ? mem[rd_addr + 11] : 8'h00;
            rd_data[103: 96] <= ((rd_addr + 12) < MEM_SIZE_BYTES) ? mem[rd_addr + 12] : 8'h00;
            rd_data[111:104] <= ((rd_addr + 13) < MEM_SIZE_BYTES) ? mem[rd_addr + 13] : 8'h00;
            rd_data[119:112] <= ((rd_addr + 14) < MEM_SIZE_BYTES) ? mem[rd_addr + 14] : 8'h00;
            rd_data[127:120] <= ((rd_addr + 15) < MEM_SIZE_BYTES) ? mem[rd_addr + 15] : 8'h00;
        end
    end

endmodule
