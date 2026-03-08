`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////////////
// i2c_slave_model.v
// I2C slave responder -- models IMU sensor (BMI160) (simulation only)
// Open-drain SDA/SCL with pullups. 256-byte internal register map.
// Supports sequential read/write with auto-incrementing address.
//
// Uses a system clock (sys_clk) for oversampling SDA/SCL to avoid
// multi-driven signals across clock domains. All state driven from
// a single always @(posedge sys_clk) block.
//////////////////////////////////////////////////////////////////////////////
module i2c_slave_model #(
    parameter [6:0] SLAVE_ADDR     = 7'h68,
    parameter       STRETCH_CYCLES = 0       // SCL clock-stretch cycles after ACK
)(
    input  wire sys_clk,   // system clock for oversampling (must be >> SCL freq)
    input  wire rst_n,
    inout  wire sda,
    inout  wire scl
);

    // -----------------------------------------------------------------------
    // Open-drain modelling with pullups
    // -----------------------------------------------------------------------
    pullup (sda);
    pullup (scl);

    reg sda_drive_low;
    reg scl_drive_low;

    assign sda = sda_drive_low ? 1'b0 : 1'bz;
    assign scl = scl_drive_low ? 1'b0 : 1'bz;

    // -----------------------------------------------------------------------
    // Internal register map (256 bytes)
    // -----------------------------------------------------------------------
    reg [7:0] reg_map [0:255];

    integer init_i;
    initial begin
        for (init_i = 0; init_i < 256; init_i = init_i + 1)
            reg_map[init_i] = 8'h00;

        // BMI160 chip ID
        reg_map[8'h00] = 8'hD1;
        // Dummy accelerometer data (X/Y/Z, little-endian pairs)
        reg_map[8'h02] = 8'h10;  // accel_x low
        reg_map[8'h03] = 8'h27;  // accel_x high
        reg_map[8'h04] = 8'hF0;  // accel_y low
        reg_map[8'h05] = 8'hD8;  // accel_y high
        reg_map[8'h06] = 8'h00;  // accel_z low
        reg_map[8'h07] = 8'h40;  // accel_z high
    end

    // -----------------------------------------------------------------------
    // State definitions
    // -----------------------------------------------------------------------
    localparam S_IDLE        = 4'd0;
    localparam S_GET_ADDR    = 4'd1;
    localparam S_SEND_ACK    = 4'd2;
    localparam S_WRITE_REG   = 4'd3;  // receive register address byte
    localparam S_WRITE_DATA  = 4'd4;  // receive data bytes
    localparam S_READ_DATA   = 4'd5;  // transmit data bytes
    localparam S_WAIT_ACK    = 4'd6;  // wait for master ACK/NACK after read byte
    localparam S_SEND_ACK2   = 4'd7;  // ACK after reg addr / write data

    reg [3:0]  state;
    reg [3:0]  next_state_after_ack; // where to go after ACK
    reg [7:0]  shift_reg;
    reg [3:0]  bit_cnt;
    reg [7:0]  reg_addr;
    reg        rw_bit;               // 0=write, 1=read
    reg        addr_set;             // register address has been set

    // Stretch counter
    integer    stretch_cnt;

    // -----------------------------------------------------------------------
    // Edge detection registers (synchronous oversampling)
    // -----------------------------------------------------------------------
    reg sda_r, sda_rr;
    reg scl_r, scl_rr;

    wire sda_posedge = sda_r && !sda_rr;
    wire sda_negedge = !sda_r && sda_rr;
    wire scl_posedge = scl_r && !scl_rr;
    wire scl_negedge = !scl_r && scl_rr;

    wire start_cond = sda_negedge && scl_r;  // SDA falls while SCL high
    wire stop_cond  = sda_posedge && scl_r;  // SDA rises while SCL high

    // -----------------------------------------------------------------------
    // Initialisation
    // -----------------------------------------------------------------------
    initial begin
        sda_drive_low = 1'b0;
        scl_drive_low = 1'b0;
        state         = S_IDLE;
        shift_reg     = 8'd0;
        bit_cnt       = 4'd0;
        reg_addr      = 8'd0;
        rw_bit        = 1'b0;
        addr_set      = 1'b0;
        stretch_cnt   = 0;
        next_state_after_ack = S_IDLE;
        sda_r  = 1'b1;
        sda_rr = 1'b1;
        scl_r  = 1'b1;
        scl_rr = 1'b1;
    end

    // -----------------------------------------------------------------------
    // Single always block: oversample, detect edges, run state machine
    // -----------------------------------------------------------------------
    always @(posedge sys_clk) begin
        if (!rst_n) begin
            sda_r  <= 1'b1;
            sda_rr <= 1'b1;
            scl_r  <= 1'b1;
            scl_rr <= 1'b1;
            sda_drive_low <= 1'b0;
            scl_drive_low <= 1'b0;
            state         <= S_IDLE;
            shift_reg     <= 8'd0;
            bit_cnt       <= 4'd0;
            reg_addr      <= 8'd0;
            rw_bit        <= 1'b0;
            addr_set      <= 1'b0;
            stretch_cnt   <= 0;
            next_state_after_ack <= S_IDLE;
        end else begin
            // Synchronise SDA and SCL
            sda_r  <= sda;
            sda_rr <= sda_r;
            scl_r  <= scl;
            scl_rr <= scl_r;

            // ----------------------------------------------------------
            // START condition — reset to address phase
            // ----------------------------------------------------------
            if (start_cond) begin
                state         <= S_GET_ADDR;
                bit_cnt       <= 4'd0;
                sda_drive_low <= 1'b0;
                scl_drive_low <= 1'b0;
            end

            // ----------------------------------------------------------
            // STOP condition — return to idle
            // ----------------------------------------------------------
            else if (stop_cond) begin
                state         <= S_IDLE;
                sda_drive_low <= 1'b0;
                scl_drive_low <= 1'b0;
                addr_set      <= 1'b0;
            end

            // ----------------------------------------------------------
            // SCL rising edge — sample SDA (receive bits from master)
            // ----------------------------------------------------------
            else if (scl_posedge) begin
                case (state)
                    S_GET_ADDR: begin
                        shift_reg <= {shift_reg[6:0], sda_r};
                        bit_cnt   <= bit_cnt + 4'd1;
                        if (bit_cnt == 4'd7) begin
                            // Full address+RW received
                            if (shift_reg[6:0] == SLAVE_ADDR) begin
                                rw_bit <= sda_r; // bit 0 = R/W
                                next_state_after_ack <= sda_r ? S_READ_DATA : S_WRITE_REG;
                                state  <= S_SEND_ACK;
                            end else begin
                                // Not for us
                                state <= S_IDLE;
                            end
                        end
                    end

                    S_WRITE_REG: begin
                        // Receiving register address byte
                        shift_reg <= {shift_reg[6:0], sda_r};
                        bit_cnt   <= bit_cnt + 4'd1;
                        if (bit_cnt == 4'd7) begin
                            reg_addr <= {shift_reg[6:0], sda_r};
                            addr_set <= 1'b1;
                            next_state_after_ack <= S_WRITE_DATA;
                            state <= S_SEND_ACK;
                        end
                    end

                    S_WRITE_DATA: begin
                        // Receiving data bytes
                        shift_reg <= {shift_reg[6:0], sda_r};
                        bit_cnt   <= bit_cnt + 4'd1;
                        if (bit_cnt == 4'd7) begin
                            reg_map[reg_addr] <= {shift_reg[6:0], sda_r};
                            reg_addr <= reg_addr + 8'd1;
                            next_state_after_ack <= S_WRITE_DATA;
                            state <= S_SEND_ACK;
                        end
                    end

                    S_WAIT_ACK: begin
                        // Master drives ACK (0) or NACK (1) on SDA
                        if (sda_r == 1'b0) begin
                            // ACK -- master wants more data
                            reg_addr <= reg_addr + 8'd1;
                            state    <= S_READ_DATA;
                            bit_cnt  <= 4'd0;
                        end else begin
                            // NACK -- master is done reading
                            sda_drive_low <= 1'b0;
                            state <= S_IDLE;
                        end
                    end

                    default: ;
                endcase
            end

            // ----------------------------------------------------------
            // SCL falling edge — drive SDA (for ACK and read data)
            // ----------------------------------------------------------
            else if (scl_negedge) begin
                case (state)
                    S_SEND_ACK: begin
                        // Drive ACK (pull SDA low)
                        sda_drive_low <= 1'b1;
                        bit_cnt       <= 4'd0;

                        // Optional clock stretching (counter-based, no #delay)
                        if (STRETCH_CYCLES > 0) begin
                            scl_drive_low <= 1'b1;
                            stretch_cnt   <= STRETCH_CYCLES;
                        end

                        state <= S_SEND_ACK2;
                    end

                    S_SEND_ACK2: begin
                        // Handle clock stretch countdown
                        if (scl_drive_low && stretch_cnt > 0) begin
                            stretch_cnt <= stretch_cnt - 1;
                        end else begin
                            scl_drive_low <= 1'b0;

                            // Release SDA after ACK bit
                            sda_drive_low <= 1'b0;
                            bit_cnt       <= 4'd0;

                            if (next_state_after_ack == S_READ_DATA) begin
                                // Pre-load first bit of read data
                                shift_reg     <= reg_map[reg_addr];
                                sda_drive_low <= ~reg_map[reg_addr][7]; // drive low if bit is 0
                                state         <= S_READ_DATA;
                            end else begin
                                state <= next_state_after_ack;
                            end
                        end
                    end

                    S_READ_DATA: begin
                        if (bit_cnt < 4'd8) begin
                            if (bit_cnt == 4'd0) begin
                                // First bit already loaded; load shift reg
                                shift_reg     <= reg_map[reg_addr];
                                sda_drive_low <= ~reg_map[reg_addr][7];
                            end else begin
                                sda_drive_low <= ~shift_reg[6];
                                shift_reg     <= {shift_reg[5:0], 1'b0};
                            end
                            bit_cnt <= bit_cnt + 4'd1;

                            if (bit_cnt == 4'd7) begin
                                // After 8th bit, release SDA for master ACK/NACK
                                state <= S_WAIT_ACK;
                            end
                        end
                    end

                    S_WAIT_ACK: begin
                        // Release SDA so master can drive ACK/NACK
                        sda_drive_low <= 1'b0;
                    end

                    default: ;
                endcase
            end
        end
    end

endmodule
