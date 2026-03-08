`timescale 1ns / 1ps
//============================================================================
// i2c_shift_reg.v
// AI_GLASSES — I2C Master
// 8-bit bidirectional shift register for I2C data.
// MSB-first. Open-drain: sda_o=0, sda_oe=1 to pull low; sda_oe=0 to release.
//============================================================================

module i2c_shift_reg (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        load,
    input  wire        shift_en,
    input  wire [7:0]  tx_data_i,

    output reg  [7:0]  rx_data_o,

    // Open-drain SDA
    output reg         sda_o,
    output reg         sda_oe_o,
    input  wire        sda_i,

    output reg         bit_done_o   // Pulses after 8 bits shifted
);

    reg [7:0] shift_reg;
    reg [2:0] bit_cnt;

    always @(posedge clk) begin
        if (!rst_n) begin
            shift_reg <= 8'd0;
            bit_cnt   <= 3'd0;
            rx_data_o <= 8'd0;
            sda_o     <= 1'b0;
            sda_oe_o  <= 1'b0;
            bit_done_o <= 1'b0;
        end else begin
            bit_done_o <= 1'b0;

            if (load) begin
                shift_reg <= tx_data_i;
                bit_cnt   <= 3'd0;
                // Drive MSB immediately
                sda_o    <= 1'b0;
                sda_oe_o <= ~tx_data_i[7]; // pull low if bit=0, release if bit=1
            end else if (shift_en) begin
                // Shift in from SDA (RX)
                rx_data_o <= {rx_data_o[6:0], sda_i};

                // Shift out (TX) - next bit
                shift_reg <= {shift_reg[6:0], 1'b0};
                bit_cnt   <= bit_cnt + 3'd1;

                if (bit_cnt == 3'd7) begin
                    bit_done_o <= 1'b1;
                end else begin
                    // Drive next bit
                    sda_o    <= 1'b0;
                    sda_oe_o <= ~shift_reg[6]; // next bit after shift
                end
            end
        end
    end

endmodule
