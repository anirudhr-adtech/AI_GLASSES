`timescale 1ns / 1ps
//============================================================================
// spi_master_fsm.v
// AI_GLASSES — SPI Master
// SPI protocol FSM. Instantiates spi_clk_gen and spi_shift_reg.
// States: IDLE -> SHIFT (8 bits) -> BYTE_DONE (check TX FIFO, auto-CS)
//============================================================================

module spi_master_fsm (
    input  wire        clk,
    input  wire        rst_n,

    // TX data from FIFO
    input  wire [7:0]  tx_data_i,
    input  wire        tx_valid_i,
    output reg         tx_ready_o,

    // RX data to FIFO
    output reg  [7:0]  rx_data_o,
    output reg         rx_valid_o,

    // Configuration
    input  wire [7:0]  div_i,
    input  wire        cpol_i,
    input  wire        cpha_i,
    input  wire        auto_cs_i,

    // Status
    output reg         busy_o,

    // SPI bus
    output wire        spi_sclk_o,
    output wire        spi_mosi_o,
    input  wire        spi_miso_i,
    output reg         spi_cs_n_o
);

    localparam [1:0] IDLE      = 2'd0,
                     SHIFT     = 2'd1,
                     BYTE_DONE = 2'd2;

    reg [1:0] state;

    // Clock generator
    reg sclk_en;
    wire sample_edge, shift_edge;

    spi_clk_gen u_clk_gen (
        .clk           (clk),
        .rst_n         (rst_n),
        .div_i         (div_i),
        .cpol_i        (cpol_i),
        .cpha_i        (cpha_i),
        .sclk_en       (sclk_en),
        .sclk_o        (spi_sclk_o),
        .sample_edge_o (sample_edge),
        .shift_edge_o  (shift_edge)
    );

    // Shift register
    reg        sr_load, sr_shift_en, sr_sample_en;
    reg  [7:0] sr_tx_data;
    wire [7:0] sr_rx_data;
    wire       sr_bit_done;

    spi_shift_reg u_shift_reg (
        .clk        (clk),
        .rst_n      (rst_n),
        .load       (sr_load),
        .shift_en   (sr_shift_en),
        .sample_en  (sr_sample_en),
        .tx_data_i  (sr_tx_data),
        .rx_data_o  (sr_rx_data),
        .mosi_o     (spi_mosi_o),
        .miso_i     (spi_miso_i),
        .bit_done_o (sr_bit_done)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            state      <= IDLE;
            busy_o     <= 1'b0;
            tx_ready_o <= 1'b0;
            rx_data_o  <= 8'd0;
            rx_valid_o <= 1'b0;
            spi_cs_n_o <= 1'b1;
            sclk_en    <= 1'b0;
            sr_load    <= 1'b0;
            sr_shift_en  <= 1'b0;
            sr_sample_en <= 1'b0;
            sr_tx_data   <= 8'd0;
        end else begin
            // Defaults
            sr_load      <= 1'b0;
            sr_shift_en  <= 1'b0;
            sr_sample_en <= 1'b0;
            tx_ready_o   <= 1'b0;
            rx_valid_o   <= 1'b0;

            case (state)
                IDLE: begin
                    busy_o <= 1'b0;
                    if (tx_valid_i) begin
                        busy_o     <= 1'b1;
                        sr_tx_data <= tx_data_i;
                        sr_load    <= 1'b1;
                        tx_ready_o <= 1'b1;
                        sclk_en    <= 1'b1;
                        if (auto_cs_i)
                            spi_cs_n_o <= 1'b0;
                        state <= SHIFT;
                    end
                end

                SHIFT: begin
                    if (sample_edge) begin
                        sr_sample_en <= 1'b1;
                    end
                    if (shift_edge) begin
                        sr_shift_en <= 1'b1;
                    end
                    if (sr_bit_done) begin
                        rx_data_o  <= sr_rx_data;
                        rx_valid_o <= 1'b1;
                        sclk_en    <= 1'b0;
                        state      <= BYTE_DONE;
                    end
                end

                BYTE_DONE: begin
                    if (tx_valid_i) begin
                        // More data to send
                        sr_tx_data <= tx_data_i;
                        sr_load    <= 1'b1;
                        tx_ready_o <= 1'b1;
                        sclk_en    <= 1'b1;
                        state      <= SHIFT;
                    end else begin
                        // Transfer complete
                        if (auto_cs_i)
                            spi_cs_n_o <= 1'b1;
                        busy_o <= 1'b0;
                        state  <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
