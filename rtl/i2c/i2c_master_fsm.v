`timescale 1ns / 1ps
//============================================================================
// i2c_master_fsm.v
// AI_GLASSES — I2C Master
// I2C protocol FSM with 10 states. Instantiates i2c_scl_gen and i2c_shift_reg.
//============================================================================

module i2c_master_fsm (
    input  wire        clk,
    input  wire        rst_n,

    // Control
    input  wire        start_i,
    input  wire [7:0]  slave_addr_i,  // [7:1]=addr, [0]=R/W
    input  wire [7:0]  xfer_len_i,
    input  wire [15:0] prescaler_i,

    // TX data from FIFO
    input  wire [7:0]  tx_data_i,
    input  wire        tx_valid_i,
    output reg         tx_ready_o,

    // RX data to FIFO
    output reg  [7:0]  rx_data_o,
    output reg         rx_valid_o,

    // Status
    output reg         busy_o,
    output reg         done_o,
    output reg         nack_o,

    // I2C bus (open-drain)
    output wire        i2c_scl_o,
    output wire        i2c_scl_oe_o,
    input  wire        i2c_scl_i,
    output wire        i2c_sda_o,
    output wire        i2c_sda_oe_o,
    input  wire        i2c_sda_i
);

    // State encoding
    localparam [3:0] IDLE          = 4'd0,
                     GEN_START     = 4'd1,
                     SEND_ADDR     = 4'd2,
                     CHECK_ACK_ADDR= 4'd3,
                     SEND_DATA     = 4'd4,
                     CHECK_ACK_DATA= 4'd5,
                     RECV_DATA     = 4'd6,
                     SEND_ACK      = 4'd7,
                     GEN_STOP      = 4'd8,
                     CLOCK_STRETCH = 4'd9;

    reg [3:0]  state, next_return_state;
    reg [7:0]  byte_cnt;
    reg        rw_bit;
    reg        scl_en;
    reg [15:0] start_stop_cnt;

    // SCL generator
    wire scl_out, scl_oe_out, scl_rise, scl_fall, stretch_det;

    i2c_scl_gen u_scl_gen (
        .clk                (clk),
        .rst_n              (rst_n),
        .prescaler_i        (prescaler_i),
        .scl_en             (scl_en),
        .scl_o              (scl_out),
        .scl_oe_o           (scl_oe_out),
        .scl_i              (i2c_scl_i),
        .scl_rise_o         (scl_rise),
        .scl_fall_o         (scl_fall),
        .stretch_detected_o (stretch_det)
    );

    // Shift register
    reg        sr_load, sr_shift_en;
    reg  [7:0] sr_tx_data;
    wire [7:0] sr_rx_data;
    wire       sr_sda_o, sr_sda_oe, sr_bit_done;

    i2c_shift_reg u_shift_reg (
        .clk        (clk),
        .rst_n      (rst_n),
        .load       (sr_load),
        .shift_en   (sr_shift_en),
        .tx_data_i  (sr_tx_data),
        .rx_data_o  (sr_rx_data),
        .sda_o      (sr_sda_o),
        .sda_oe_o   (sr_sda_oe),
        .sda_i      (i2c_sda_i),
        .bit_done_o (sr_bit_done)
    );

    // SDA mux: FSM can override SDA for START/STOP/ACK conditions
    reg        fsm_sda_oe;
    reg        fsm_sda_override;

    assign i2c_scl_o    = scl_out;
    assign i2c_scl_oe_o = (state == IDLE || state == GEN_START || state == GEN_STOP || scl_fsm_hold) ? fsm_scl_oe_r : scl_oe_out;
    assign i2c_sda_o    = 1'b0; // open-drain: always drive 0 when enabled
    assign i2c_sda_oe_o = fsm_sda_override ? fsm_sda_oe : sr_sda_oe;

    reg fsm_scl_oe_r;
    reg scl_fsm_hold;         // keep FSM SCL override until SCL gen starts driving
    reg first_scl_rise_seen;  // gate shift until slave has sampled bit 7

    // Quarter-period timer for START/STOP generation
    wire start_stop_tick = (start_stop_cnt == prescaler_i);
    reg [2:0] ss_phase;

    always @(posedge clk) begin
        if (!rst_n) begin
            state           <= IDLE;
            next_return_state <= IDLE;
            byte_cnt        <= 8'd0;
            rw_bit          <= 1'b0;
            scl_en          <= 1'b0;
            busy_o          <= 1'b0;
            done_o          <= 1'b0;
            nack_o          <= 1'b0;
            tx_ready_o      <= 1'b0;
            rx_data_o       <= 8'd0;
            rx_valid_o      <= 1'b0;
            sr_load         <= 1'b0;
            sr_shift_en     <= 1'b0;
            sr_tx_data      <= 8'd0;
            fsm_sda_oe      <= 1'b0;
            fsm_sda_override <= 1'b1;
            fsm_scl_oe_r    <= 1'b0;
            scl_fsm_hold    <= 1'b0;
            first_scl_rise_seen <= 1'b0;
            start_stop_cnt  <= 16'd0;
            ss_phase        <= 3'd0;
        end else begin
            // Defaults
            sr_load     <= 1'b0;
            sr_shift_en <= 1'b0;
            done_o      <= 1'b0;
            rx_valid_o  <= 1'b0;
            tx_ready_o  <= 1'b0;

            case (state)
                IDLE: begin
                    busy_o           <= 1'b0;
                    nack_o           <= 1'b0;
                    scl_en           <= 1'b0;
                    fsm_sda_override <= 1'b1;
                    fsm_sda_oe       <= 1'b0; // SDA released (high)
                    fsm_scl_oe_r     <= 1'b0; // SCL released (high)
                    if (start_i) begin
                        busy_o     <= 1'b1;
                        rw_bit     <= slave_addr_i[0];
                        byte_cnt   <= xfer_len_i;
                        state      <= GEN_START;
                        start_stop_cnt <= 16'd0;
                        ss_phase   <= 3'd0;
                    end
                end

                GEN_START: begin
                    // START: SDA goes low while SCL is high
                    // Phase 0: ensure SCL high, SDA high
                    // Phase 1: pull SDA low (START condition)
                    // Phase 2: pull SCL low
                    if (start_stop_tick) begin
                        start_stop_cnt <= 16'd0;
                        ss_phase <= ss_phase + 3'd1;
                        case (ss_phase)
                            3'd0: begin
                                fsm_scl_oe_r <= 1'b0; // SCL high
                                fsm_sda_oe   <= 1'b0; // SDA high
                            end
                            3'd1: begin
                                fsm_sda_oe <= 1'b1; // SDA low (START)
                            end
                            3'd2: begin
                                fsm_scl_oe_r <= 1'b1; // SCL low
                                scl_fsm_hold <= 1'b1; // keep FSM SCL until gen starts
                                // Load address byte into shift register
                                sr_tx_data <= slave_addr_i;
                                sr_load    <= 1'b1;
                                fsm_sda_override <= 1'b0; // hand SDA to shift reg
                                scl_en     <= 1'b1;
                                state      <= SEND_ADDR;
                            end
                            default: ;
                        endcase
                    end else begin
                        start_stop_cnt <= start_stop_cnt + 16'd1;
                    end
                end

                SEND_ADDR: begin
                    fsm_sda_override <= 1'b0;
                    // Release FSM SCL hold once SCL gen is actively driving
                    if (scl_fsm_hold && scl_oe_out)
                        scl_fsm_hold <= 1'b0;
                    // Gate: only shift after first SCL rise (slave samples bit 7)
                    if (scl_rise)
                        first_scl_rise_seen <= 1'b1;
                    if (scl_fall && first_scl_rise_seen) begin
                        sr_shift_en <= 1'b1;
                    end
                    if (sr_bit_done) begin
                        state <= CHECK_ACK_ADDR;
                        fsm_sda_override <= 1'b1;
                        fsm_sda_oe <= 1'b0; // release SDA for ACK
                        first_scl_rise_seen <= 1'b0;
                    end
                end

                CHECK_ACK_ADDR: begin
                    fsm_sda_override <= 1'b1;
                    fsm_sda_oe <= 1'b0; // SDA released for slave ACK
                    if (scl_rise) begin
                        if (!i2c_sda_i) begin
                            // ACK received
                            if (rw_bit) begin
                                // Read mode
                                state <= RECV_DATA;
                                fsm_sda_override <= 1'b0;
                                // Load 0xFF so SDA is released during read
                                sr_tx_data <= 8'hFF;
                                sr_load    <= 1'b1;
                            end else begin
                                // Write mode
                                if (byte_cnt > 8'd0 && tx_valid_i) begin
                                    sr_tx_data <= tx_data_i;
                                    sr_load    <= 1'b1;
                                    tx_ready_o <= 1'b1;
                                    byte_cnt   <= byte_cnt - 8'd1;
                                    state      <= SEND_DATA;
                                    fsm_sda_override <= 1'b0;
                                end else begin
                                    state <= GEN_STOP;
                                    start_stop_cnt <= 16'd0;
                                    ss_phase <= 3'd0;
                                    scl_en <= 1'b0;
                                    fsm_sda_override <= 1'b1;
                                end
                            end
                        end else begin
                            // NACK
                            nack_o <= 1'b1;
                            state  <= GEN_STOP;
                            start_stop_cnt <= 16'd0;
                            ss_phase <= 3'd0;
                            scl_en <= 1'b0;
                        end
                    end
                end

                SEND_DATA: begin
                    fsm_sda_override <= 1'b0;
                    // Gate: only shift after first SCL rise (slave samples bit 7)
                    if (scl_rise)
                        first_scl_rise_seen <= 1'b1;
                    if (scl_fall && first_scl_rise_seen) begin
                        sr_shift_en <= 1'b1;
                    end
                    if (sr_bit_done) begin
                        state <= CHECK_ACK_DATA;
                        fsm_sda_override <= 1'b1;
                        fsm_sda_oe <= 1'b0;
                        first_scl_rise_seen <= 1'b0;
                    end
                end

                CHECK_ACK_DATA: begin
                    fsm_sda_override <= 1'b1;
                    fsm_sda_oe <= 1'b0;
                    if (scl_rise) begin
                        if (!i2c_sda_i) begin
                            // ACK
                            if (byte_cnt > 8'd0 && tx_valid_i) begin
                                sr_tx_data <= tx_data_i;
                                sr_load    <= 1'b1;
                                tx_ready_o <= 1'b1;
                                byte_cnt   <= byte_cnt - 8'd1;
                                state      <= SEND_DATA;
                                fsm_sda_override <= 1'b0;
                            end else begin
                                state <= GEN_STOP;
                                start_stop_cnt <= 16'd0;
                                ss_phase <= 3'd0;
                                scl_en <= 1'b0;
                            end
                        end else begin
                            nack_o <= 1'b1;
                            state  <= GEN_STOP;
                            start_stop_cnt <= 16'd0;
                            ss_phase <= 3'd0;
                            scl_en <= 1'b0;
                        end
                    end
                end

                RECV_DATA: begin
                    fsm_sda_override <= 1'b0;
                    // Gate: only shift after first SCL rise (sample bit 7 first)
                    if (scl_rise)
                        first_scl_rise_seen <= 1'b1;
                    if (scl_fall && first_scl_rise_seen) begin
                        sr_shift_en <= 1'b1;
                    end
                    if (sr_bit_done) begin
                        rx_data_o  <= sr_rx_data;
                        rx_valid_o <= 1'b1;
                        byte_cnt   <= byte_cnt - 8'd1;
                        state      <= SEND_ACK;
                        fsm_sda_override <= 1'b1;
                        first_scl_rise_seen <= 1'b0;
                    end
                end

                SEND_ACK: begin
                    fsm_sda_override <= 1'b1;
                    if (byte_cnt > 8'd0) begin
                        fsm_sda_oe <= 1'b1; // ACK (pull SDA low)
                    end else begin
                        fsm_sda_oe <= 1'b0; // NACK (release SDA) on last byte
                    end
                    if (scl_fall) begin
                        if (byte_cnt > 8'd0) begin
                            // More bytes to read
                            sr_tx_data <= 8'hFF;
                            sr_load    <= 1'b1;
                            state      <= RECV_DATA;
                            fsm_sda_override <= 1'b0;
                        end else begin
                            state <= GEN_STOP;
                            start_stop_cnt <= 16'd0;
                            ss_phase <= 3'd0;
                            scl_en <= 1'b0;
                        end
                    end
                end

                GEN_STOP: begin
                    // STOP: SDA goes high while SCL is high
                    // Phase 0: SCL low, SDA low
                    // Phase 1: SCL high, SDA low
                    // Phase 2: SDA high (STOP condition)
                    fsm_sda_override <= 1'b1;
                    if (start_stop_tick) begin
                        start_stop_cnt <= 16'd0;
                        ss_phase <= ss_phase + 3'd1;
                        case (ss_phase)
                            3'd0: begin
                                fsm_scl_oe_r <= 1'b1; // SCL low
                                fsm_sda_oe   <= 1'b1; // SDA low
                            end
                            3'd1: begin
                                fsm_scl_oe_r <= 1'b0; // SCL high
                            end
                            3'd2: begin
                                fsm_sda_oe <= 1'b0; // SDA high (STOP)
                                done_o     <= 1'b1;
                                state      <= IDLE;
                            end
                            default: ;
                        endcase
                    end else begin
                        start_stop_cnt <= start_stop_cnt + 16'd1;
                    end
                end

                CLOCK_STRETCH: begin
                    if (!stretch_det) begin
                        state <= next_return_state;
                    end
                end

                default: state <= IDLE;
            endcase

            // Clock stretch detection (can interrupt any state)
            if (stretch_det && state != IDLE && state != GEN_START &&
                state != GEN_STOP && state != CLOCK_STRETCH) begin
                next_return_state <= state;
                state <= CLOCK_STRETCH;
            end
        end
    end

endmodule
