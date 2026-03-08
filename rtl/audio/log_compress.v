`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem
// Module: log_compress
// Description: LUT-based natural logarithm of mel energies.
//              Normalizes input to [0.5, 1.0), uses LUT on upper 8 mantissa
//              bits, adds exponent * ln(2). Output: 40 x 16-bit Q8.8.
//              If input = 0, output = 0 (avoid log(0)).
//////////////////////////////////////////////////////////////////////////////

module log_compress (
    input  wire        clk,
    input  wire        rst_n,
    // Control
    input  wire        start_i,
    // Mel energy input (streaming from mel_filterbank)
    input  wire [31:0] mel_data_i,
    input  wire [5:0]  mel_idx_i,
    input  wire        mel_valid_i,
    // Status
    output reg         done_o,
    // Log-mel output
    output reg  [15:0] log_data_o,
    output reg  [5:0]  log_idx_o,
    output reg         log_valid_o
);

    // FSM states
    localparam S_IDLE    = 3'd0;
    localparam S_CAPTURE = 3'd1;
    localparam S_NORM    = 3'd2;
    localparam S_LUT     = 3'd3;
    localparam S_COMPUTE = 3'd4;
    localparam S_OUTPUT  = 3'd5;
    localparam S_DONE    = 3'd6;

    reg [2:0]  state;
    reg [5:0]  count;       // Number of mel values processed
    reg [31:0] mel_val;     // Current mel energy
    reg [5:0]  cur_idx;     // Current filter index
    reg [4:0]  msb_pos;     // Position of MSB (exponent)
    reg [7:0]  lut_addr;    // LUT address (8 bits of mantissa)

    // LUT interface
    reg  [7:0]  rom_addr;
    wire [15:0] rom_data;

    log_lut_rom u_log_rom (
        .clk    (clk),
        .addr_i (rom_addr),
        .data_o (rom_data)
    );

    // ln(2) in Q8.8 = 0.6931 * 256 = 177.4 ~ 177
    localparam [15:0] LN2_Q8_8 = 16'h00B1; // 177 = 0xB1

    // Find MSB position (priority encoder)
    reg [4:0] msb_found;
    integer k;
    always @(*) begin
        msb_found = 5'd0;
        for (k = 31; k >= 0; k = k - 1) begin
            if (mel_val[k] && (msb_found == 5'd0))
                msb_found = k[4:0];
        end
    end

    // Registered computation
    reg signed [15:0] lut_val;
    reg signed [15:0] exp_offset;
    reg signed [15:0] result;

    always @(posedge clk) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            count      <= 6'd0;
            done_o     <= 1'b0;
            log_data_o <= 16'd0;
            log_idx_o  <= 6'd0;
            log_valid_o <= 1'b0;
            mel_val    <= 32'd0;
            cur_idx    <= 6'd0;
            msb_pos    <= 5'd0;
            rom_addr   <= 8'd0;
            lut_val    <= 16'd0;
            exp_offset <= 16'd0;
            result     <= 16'd0;
        end else begin
            done_o      <= 1'b0;
            log_valid_o <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start_i) begin
                        count <= 6'd0;
                        state <= S_CAPTURE;
                    end
                end

                S_CAPTURE: begin
                    if (mel_valid_i) begin
                        mel_val <= mel_data_i;
                        cur_idx <= mel_idx_i;
                        state   <= S_NORM;
                    end
                    if (count == 6'd40) begin
                        state <= S_DONE;
                    end
                end

                S_NORM: begin
                    if (mel_val == 32'd0) begin
                        // log(0) -> output 0
                        log_data_o  <= 16'd0;
                        log_idx_o   <= cur_idx;
                        log_valid_o <= 1'b1;
                        count       <= count + 6'd1;
                        state       <= S_CAPTURE;
                    end else begin
                        // Find MSB and extract 8 mantissa bits below it
                        msb_pos <= msb_found;
                        if (msb_found >= 5'd8)
                            rom_addr <= mel_val[msb_found -: 8];
                        else
                            rom_addr <= mel_val[7:0];
                        state <= S_LUT;
                    end
                end

                S_LUT: begin
                    // Wait for LUT read (1-cycle latency)
                    // Compute exponent offset: (msb_pos) * ln(2)
                    // msb_pos is the bit position, so the value is 2^msb_pos * mantissa
                    // ln(val) = ln(mantissa) + msb_pos * ln(2)
                    // But our LUT gives ln(mantissa) for mantissa in [0.5, 1.0)
                    // The actual exponent contribution is (msb_pos + 1) since
                    // we normalized by shifting mantissa to [0.5, 1.0) which is 2^(-1)
                    exp_offset <= msb_pos * LN2_Q8_8;
                    state      <= S_COMPUTE;
                end

                S_COMPUTE: begin
                    // result = lut_value + exponent * ln(2)
                    result <= $signed(rom_data) + $signed(exp_offset);
                    state  <= S_OUTPUT;
                end

                S_OUTPUT: begin
                    log_data_o  <= result;
                    log_idx_o   <= cur_idx;
                    log_valid_o <= 1'b1;
                    count       <= count + 6'd1;
                    state       <= S_CAPTURE;
                end

                S_DONE: begin
                    done_o <= 1'b1;
                    state  <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
