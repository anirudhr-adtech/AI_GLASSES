`timescale 1ns/1ps
//============================================================================
// Module:      axi_addr_decoder
// Project:     AI_GLASSES — AXI Interconnect
// Description: Combinational address decoder with registered output.
//              Maps AXI address to one-hot slave select for 5 slave regions.
//              S0=Boot ROM, S1=SRAM, S2=Periph, S3=DDR, S4=Error.
//              Fine-grained boundary checks for Boot ROM (4KB) and SRAM (512KB).
//============================================================================

module axi_addr_decoder #(
    parameter NUM_SLAVES  = 5,
    parameter ADDR_WIDTH  = 32
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire [ADDR_WIDTH-1:0]  addr_i,
    output reg  [NUM_SLAVES-1:0]  slave_sel_o,
    output reg                    addr_error_o
);

    // Combinational decode
    reg [NUM_SLAVES-1:0] slave_sel_comb;
    reg                  addr_error_comb;

    always @(*) begin
        slave_sel_comb  = {NUM_SLAVES{1'b0}};
        addr_error_comb = 1'b0;

        casez (addr_i[31:28])
            4'b0000: slave_sel_comb[0] = 1'b1;  // S0: Boot ROM  (0x0000_xxxx)
            4'b0001: slave_sel_comb[1] = 1'b1;  // S1: SRAM      (0x1xxx_xxxx)
            4'b0010: slave_sel_comb[2] = 1'b1;  // S2: Periph    (0x2000_xxxx)
            4'b0011: slave_sel_comb[2] = 1'b1;  // S2: Periph    (0x3000_xxxx)
            4'b0100: slave_sel_comb[2] = 1'b1;  // S2: Periph    (0x4000_xxxx)
            4'b1000: slave_sel_comb[3] = 1'b1;  // S3: DDR       (0x8000_xxxx)
            4'b1001: slave_sel_comb[3] = 1'b1;  // S3: DDR
            4'b1010: slave_sel_comb[3] = 1'b1;  // S3: DDR
            4'b1011: slave_sel_comb[3] = 1'b1;  // S3: DDR
            4'b1100: slave_sel_comb[3] = 1'b1;  // S3: DDR
            4'b1101: slave_sel_comb[3] = 1'b1;  // S3: DDR
            4'b1110: slave_sel_comb[3] = 1'b1;  // S3: DDR
            4'b1111: slave_sel_comb[3] = 1'b1;  // S3: DDR
            default: slave_sel_comb[4] = 1'b1;  // S4: Error slave
        endcase

        // Fine-grained boundary enforcement
        // Boot ROM: only 4 KB at 0x0000_0000 - 0x0000_0FFF
        if (slave_sel_comb[0] && (addr_i[31:12] != 20'h00000)) begin
            addr_error_comb    = 1'b1;
            slave_sel_comb     = {NUM_SLAVES{1'b0}};
            slave_sel_comb[4]  = 1'b1;
        end

        // SRAM: only 512 KB at 0x1000_0000 - 0x1007_FFFF
        if (slave_sel_comb[1] && (addr_i[31:19] != 13'b0001_0000_0000_0)) begin
            addr_error_comb    = 1'b1;
            slave_sel_comb     = {NUM_SLAVES{1'b0}};
            slave_sel_comb[4]  = 1'b1;
        end
    end

    // Registered output
    always @(posedge clk) begin
        if (!rst_n) begin
            slave_sel_o  <= {NUM_SLAVES{1'b0}};
            addr_error_o <= 1'b0;
        end else begin
            slave_sel_o  <= slave_sel_comb;
            addr_error_o <= addr_error_comb;
        end
    end

endmodule
