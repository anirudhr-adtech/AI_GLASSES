`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////////////
// uart_monitor.v
// Passive UART TX line monitor (simulation only)
// Detects start bit, samples 8 data bits at baud centre, checks stop bit.
// Accumulates received bytes in a buffer for string comparison.
//////////////////////////////////////////////////////////////////////////////
module uart_monitor #(
    parameter BAUD_RATE = 115200,
    parameter CLK_FREQ  = 100000000
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       uart_tx,       // TX line to monitor (active low start)
    output reg [7:0]  rx_byte,
    output reg        rx_valid,
    output reg        frame_error,
    output reg [7:0]  rx_count
);

    // -----------------------------------------------------------------------
    // Baud-rate timing
    // -----------------------------------------------------------------------
    localparam integer CLKS_PER_BIT  = CLK_FREQ / BAUD_RATE;
    localparam integer HALF_BIT      = CLKS_PER_BIT / 2;

    // -----------------------------------------------------------------------
    // Receive buffer (up to 256 chars)
    // -----------------------------------------------------------------------
    reg [7:0] rx_buffer [0:255];

    // -----------------------------------------------------------------------
    // State machine
    // -----------------------------------------------------------------------
    localparam S_IDLE    = 3'd0;
    localparam S_START   = 3'd1;
    localparam S_DATA    = 3'd2;
    localparam S_STOP    = 3'd3;
    localparam S_CLEANUP = 3'd4;

    reg [2:0]  state;
    reg [31:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  rx_shift;

    // Edge detection on uart_tx
    reg uart_tx_d;

    // -----------------------------------------------------------------------
    // Initialisation
    // -----------------------------------------------------------------------
    integer buf_i;
    initial begin
        for (buf_i = 0; buf_i < 256; buf_i = buf_i + 1)
            rx_buffer[buf_i] = 8'h00;
    end

    // -----------------------------------------------------------------------
    // Main receiver — synchronous to clk, active-low reset
    // -----------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            clk_cnt     <= 32'd0;
            bit_idx     <= 3'd0;
            rx_shift    <= 8'd0;
            rx_byte     <= 8'd0;
            rx_valid    <= 1'b0;
            frame_error <= 1'b0;
            rx_count    <= 8'd0;
            uart_tx_d   <= 1'b1;
        end else begin
            uart_tx_d <= uart_tx;
            rx_valid  <= 1'b0;   // default: pulse cleared each cycle

            case (state)
                // ----- IDLE: wait for falling edge (start bit) -----
                S_IDLE: begin
                    frame_error <= 1'b0;
                    if (uart_tx_d == 1'b1 && uart_tx == 1'b0) begin
                        // Falling edge detected — start bit
                        state   <= S_START;
                        clk_cnt <= 32'd0;
                    end
                end

                // ----- START: wait to reach centre of start bit -----
                S_START: begin
                    if (clk_cnt == HALF_BIT - 1) begin
                        if (uart_tx == 1'b0) begin
                            // Valid start bit at centre
                            clk_cnt <= 32'd0;
                            bit_idx <= 3'd0;
                            state   <= S_DATA;
                        end else begin
                            // False start
                            state <= S_IDLE;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 32'd1;
                    end
                end

                // ----- DATA: sample 8 data bits at bit centre -----
                S_DATA: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt  <= 32'd0;
                        rx_shift <= {uart_tx, rx_shift[7:1]}; // LSB first
                        if (bit_idx == 3'd7) begin
                            state <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 3'd1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 32'd1;
                    end
                end

                // ----- STOP: check stop bit -----
                S_STOP: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        if (uart_tx == 1'b1) begin
                            // Valid stop bit
                            rx_byte  <= rx_shift;
                            rx_valid <= 1'b1;
                            // Store in buffer
                            if (rx_count < 8'd255) begin
                                rx_buffer[rx_count] <= rx_shift;
                                rx_count <= rx_count + 8'd1;
                            end
                        end else begin
                            // Frame error — stop bit not detected
                            frame_error <= 1'b1;
                            $display("[%0t] uart_monitor: FRAME ERROR — stop bit not detected", $time);
                        end
                        state <= S_CLEANUP;
                    end else begin
                        clk_cnt <= clk_cnt + 32'd1;
                    end
                end

                // ----- CLEANUP: one-cycle gap before next byte -----
                S_CLEANUP: begin
                    state   <= S_IDLE;
                    clk_cnt <= 32'd0;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // -----------------------------------------------------------------------
    // check_string task — compare rx_buffer against expected string
    // -----------------------------------------------------------------------
    task check_string;
        input [8*32-1:0] expected;  // up to 32-char expected string
        input [7:0]      len;       // length of expected string
        integer ci;
        reg match;
        reg [7:0] exp_byte;
        begin
            match = 1'b1;
            if (rx_count < len) begin
                $display("[%0t] uart_monitor: FAIL — received %0d bytes, expected %0d",
                         $time, rx_count, len);
                match = 1'b0;
            end else begin
                for (ci = 0; ci < len; ci = ci + 1) begin
                    // Extract byte from expected (MSB-packed: first char in highest byte)
                    exp_byte = expected[((len - 1 - ci) * 8) +: 8];
                    if (rx_buffer[ci] !== exp_byte) begin
                        $display("[%0t] uart_monitor: FAIL — byte[%0d] got 0x%02X, expected 0x%02X",
                                 $time, ci, rx_buffer[ci], exp_byte);
                        match = 1'b0;
                    end
                end
            end
            if (match)
                $display("[%0t] uart_monitor: PASS — string match (%0d bytes)", $time, len);
        end
    endtask

endmodule
