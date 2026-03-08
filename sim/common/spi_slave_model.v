`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////////////
// spi_slave_model.v
// SPI slave responder — models ESP32-C3 (simulation only)
// CPOL=0, CPHA=0: sample MOSI on rising SCLK, shift MISO on falling SCLK.
// Protocol: byte 0 = address (bit7: 0=write, 1=read), byte 1 = data.
//
// All signals driven from a single always block per clock edge to avoid
// multi-driven warnings in lint. CS_N reset handled via synchronous
// detection within each edge-triggered block.
//////////////////////////////////////////////////////////////////////////////
module spi_slave_model #(
    parameter DATA_WIDTH = 8
)(
    input  wire       rst_n,
    input  wire       sclk,
    input  wire       mosi,
    input  wire       cs_n,
    output reg        miso         = 1'b0,
    output reg [7:0]  last_rx_data = 8'd0,
    output reg        rx_valid     = 1'b0
);

    // -----------------------------------------------------------------------
    // Internal 256-byte register map
    // -----------------------------------------------------------------------
    reg [7:0] reg_map [0:255];

    // State (initial values match async reset for Verilator compatibility)
    reg [2:0] bit_cnt    = 3'd0;
    reg [7:0] shift_in   = 8'd0;
    reg [7:0] shift_out  = 8'd0;
    reg [7:0] addr_reg   = 8'd0;
    reg       addr_phase = 1'b1;
    reg       read_mode  = 1'b0;
    reg       prev_cs_n  = 1'b1;

    // -----------------------------------------------------------------------
    // Initialise register map with default values
    // -----------------------------------------------------------------------
    integer init_i;
    initial begin
        for (init_i = 0; init_i < 256; init_i = init_i + 1)
            reg_map[init_i] = 8'h00;
        reg_map[0] = 8'hA5;  // Device ID
        reg_map[1] = 8'h01;  // Status register
    end

    // -----------------------------------------------------------------------
    // Sample MOSI on rising edge of SCLK (CPHA=0)
    // Also handles CS_N deassertion reset and async reset.
    // All signals that were split across posedge cs_n / posedge sclk are
    // now consolidated here to avoid MULTIDRIVEN.
    // -----------------------------------------------------------------------
    always @(posedge sclk or negedge rst_n) begin
        if (!rst_n) begin
            bit_cnt      <= 3'd0;
            shift_in     <= 8'd0;
            addr_reg     <= 8'd0;
            addr_phase   <= 1'b1;
            read_mode    <= 1'b0;
            last_rx_data <= 8'd0;
            rx_valid     <= 1'b0;
            prev_cs_n    <= 1'b1;
        end else begin
            prev_cs_n <= cs_n;

            // CS_N rising edge detection (deassertion) — reset transaction
            if (cs_n && !prev_cs_n) begin
                bit_cnt    <= 3'd0;
                addr_phase <= 1'b1;
                read_mode  <= 1'b0;
                rx_valid   <= 1'b0;
            end else if (!cs_n) begin
                rx_valid <= 1'b0;  // default: clear pulse

                shift_in <= {shift_in[6:0], mosi};
                bit_cnt  <= bit_cnt + 3'd1;

                if (bit_cnt == 3'd7) begin
                    // Full byte received
                    last_rx_data <= {shift_in[6:0], mosi};
                    rx_valid     <= 1'b1;

                    if (addr_phase) begin
                        // Address byte
                        addr_reg   <= {shift_in[6:0], mosi};
                        read_mode  <= shift_in[6]; // bit 7 of received byte
                        addr_phase <= 1'b0;
                    end else begin
                        // Data byte
                        if (!read_mode) begin
                            // Write: store data into register map
                            reg_map[addr_reg[6:0]] <= {shift_in[6:0], mosi};
                        end
                        // Auto-increment address for multi-byte transfers
                        addr_reg <= addr_reg + 8'd1;
                    end

                    bit_cnt <= 3'd0;
                end
            end else begin
                // CS_N is high and was high — idle
                rx_valid <= 1'b0;
            end
        end
    end

    // -----------------------------------------------------------------------
    // Drive MISO on falling edge of SCLK (CPHA=0)
    // Also handles CS_N deassertion reset and async reset.
    // -----------------------------------------------------------------------
    reg prev_cs_n_neg = 1'b1; // CS_N edge detection on negedge sclk domain

    always @(negedge sclk or negedge rst_n) begin
        if (!rst_n) begin
            shift_out    <= 8'd0;
            miso         <= 1'b0;
            prev_cs_n_neg <= 1'b1;
        end else begin
            prev_cs_n_neg <= cs_n;

            // CS_N rising edge detection (deassertion) — reset outputs
            if (cs_n && !prev_cs_n_neg) begin
                miso <= 1'b0;
            end else if (!cs_n) begin
                if (addr_phase) begin
                    // During address phase, MISO is don't-care; drive 0
                    miso <= 1'b0;
                end else begin
                    if (bit_cnt == 3'd0) begin
                        // Load new byte to shift out at start of data phase
                        if (read_mode) begin
                            shift_out <= reg_map[addr_reg[6:0]];
                            miso      <= reg_map[addr_reg[6:0]][7];
                        end else begin
                            miso <= 1'b0;
                        end
                    end else begin
                        miso      <= shift_out[6];
                        shift_out <= {shift_out[5:0], 1'b0};
                    end
                end
            end else begin
                miso <= 1'b0;
            end
        end
    end

endmodule
