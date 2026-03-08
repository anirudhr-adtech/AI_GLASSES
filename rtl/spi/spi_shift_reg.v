`timescale 1ns / 1ps
//============================================================================
// spi_shift_reg.v
// AI_GLASSES — SPI Master
// 8-bit bidirectional shift register. MSB-first on MOSI, shift in from MISO.
//============================================================================

module spi_shift_reg (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        load,
    input  wire        shift_en,
    input  wire [7:0]  tx_data_i,

    output reg  [7:0]  rx_data_o,
    output reg         mosi_o,
    input  wire        miso_i,

    output reg         bit_done_o   // Pulses after 8 bits shifted
);

    reg [7:0] tx_shift;
    reg [7:0] rx_shift;
    reg [2:0] bit_cnt;

    always @(posedge clk) begin
        if (!rst_n) begin
            tx_shift   <= 8'd0;
            rx_shift   <= 8'd0;
            bit_cnt    <= 3'd0;
            mosi_o     <= 1'b0;
            rx_data_o  <= 8'd0;
            bit_done_o <= 1'b0;
        end else begin
            bit_done_o <= 1'b0;

            if (load) begin
                tx_shift <= tx_data_i;
                bit_cnt  <= 3'd0;
                mosi_o   <= tx_data_i[7]; // MSB first
            end else if (shift_en) begin
                // Shift out TX (MSB first)
                tx_shift <= {tx_shift[6:0], 1'b0};
                mosi_o   <= tx_shift[6]; // next bit

                // Shift in RX
                rx_shift <= {rx_shift[6:0], miso_i};

                bit_cnt <= bit_cnt + 3'd1;
                if (bit_cnt == 3'd7) begin
                    bit_done_o <= 1'b1;
                    rx_data_o  <= {rx_shift[6:0], miso_i};
                end
            end
        end
    end

endmodule
