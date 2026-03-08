`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem
// Module: fft_engine
// Description: 1024-point radix-2 DIT FFT. In-place computation using
//              dual-port BRAM. 10 stages x 512 butterflies = 5120 ops.
//              FSM: IDLE -> LOAD (bit-reversed write) -> COMPUTE -> DONE
//////////////////////////////////////////////////////////////////////////////

module fft_engine (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start_i,
    // Input data write port
    input  wire [15:0] in_data_i,
    input  wire [9:0]  in_addr_i,
    input  wire        in_wr_en_i,
    // Status
    output reg         done_o,
    // Output read port
    output wire [15:0] out_re_o,
    output wire [15:0] out_im_o,
    input  wire [9:0]  out_addr_i,
    input  wire        out_rd_en_i
);

    // FSM states
    localparam S_IDLE    = 3'd0;
    localparam S_LOAD    = 3'd1;
    localparam S_COMPUTE = 3'd2;
    localparam S_BF_WAIT = 3'd3;
    localparam S_BF_WB   = 3'd4;
    localparam S_DONE    = 3'd5;

    reg [2:0] state;
    reg [3:0] stage_cnt;    // 0..9
    reg [8:0] bf_cnt;       // 0..511
    reg       bf_wait_cnt;  // wait for butterfly pipeline

    // Dual-port BRAM: 1024 x 32 (16-bit Re + 16-bit Im)
    (* ram_style = "block" *)
    reg [31:0] bram [0:1023];

    // Port A (read/write for computation)
    reg  [9:0]  porta_addr;
    reg  [31:0] porta_wdata;
    reg         porta_wen;
    reg  [31:0] porta_rdata;

    // Port B (read/write for computation)
    reg  [9:0]  portb_addr;
    reg  [31:0] portb_wdata;
    reg         portb_wen;
    reg  [31:0] portb_rdata;

    // BRAM Port A
    always @(posedge clk) begin
        if (porta_wen)
            bram[porta_addr] <= porta_wdata;
        porta_rdata <= bram[porta_addr];
    end

    // BRAM Port B
    always @(posedge clk) begin
        if (portb_wen)
            bram[portb_addr] <= portb_wdata;
        portb_rdata <= bram[portb_addr];
    end

    // Address generator
    wire [9:0] p_addr, q_addr;
    wire [8:0] tw_addr;
    wire [9:0] bitrev_out;

    reg [9:0] bitrev_in;

    fft_addr_gen u_addr_gen (
        .clk           (clk),
        .rst_n         (rst_n),
        .stage_i       (stage_cnt),
        .butterfly_i   (bf_cnt),
        .p_addr_o      (p_addr),
        .q_addr_o      (q_addr),
        .tw_addr_o     (tw_addr),
        .bitrev_addr_i (bitrev_in),
        .bitrev_addr_o (bitrev_out)
    );

    // Twiddle ROM
    wire [15:0] tw_re, tw_im;
    reg  [8:0]  tw_addr_reg;

    fft_twiddle_rom u_twiddle (
        .clk    (clk),
        .addr_i (tw_addr_reg),
        .re_o   (tw_re),
        .im_o   (tw_im)
    );

    // Butterfly unit
    reg         bf_en;
    reg  signed [15:0] bf_a_re, bf_a_im, bf_b_re, bf_b_im;
    wire signed [15:0] bf_p_re, bf_p_im, bf_q_re, bf_q_im;
    wire        bf_valid;

    fft_butterfly u_butterfly (
        .clk     (clk),
        .rst_n   (rst_n),
        .en      (bf_en),
        .a_re    (bf_a_re),
        .a_im    (bf_a_im),
        .b_re    (bf_b_re),
        .b_im    (bf_b_im),
        .w_re    (tw_re),
        .w_im    (tw_im),
        .p_re    (bf_p_re),
        .p_im    (bf_p_im),
        .q_re    (bf_q_re),
        .q_im    (bf_q_im),
        .valid_o (bf_valid)
    );

    // Delayed addresses for writeback (2-cycle butterfly pipeline + 1 cycle addr_gen)
    reg [9:0] p_addr_d1, p_addr_d2, p_addr_d3;
    reg [9:0] q_addr_d1, q_addr_d2, q_addr_d3;

    always @(posedge clk) begin
        p_addr_d1 <= p_addr;
        p_addr_d2 <= p_addr_d1;
        p_addr_d3 <= p_addr_d2;
        q_addr_d1 <= q_addr;
        q_addr_d2 <= q_addr_d1;
        q_addr_d3 <= q_addr_d2;
    end

    // Output read mux
    reg [31:0] out_rdata;
    always @(posedge clk) begin
        if (out_rd_en_i)
            out_rdata <= bram[out_addr_i];
    end
    assign out_re_o = out_rdata[31:16];
    assign out_im_o = out_rdata[15:0];

    // Main FSM
    always @(posedge clk) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            stage_cnt    <= 4'd0;
            bf_cnt       <= 9'd0;
            bf_wait_cnt  <= 1'b0;
            done_o       <= 1'b0;
            porta_wen    <= 1'b0;
            portb_wen    <= 1'b0;
            porta_addr   <= 10'd0;
            portb_addr   <= 10'd0;
            porta_wdata  <= 32'd0;
            portb_wdata  <= 32'd0;
            bf_en        <= 1'b0;
            bf_a_re      <= 16'd0;
            bf_a_im      <= 16'd0;
            bf_b_re      <= 16'd0;
            bf_b_im      <= 16'd0;
            tw_addr_reg  <= 9'd0;
            bitrev_in    <= 10'd0;
        end else begin
            porta_wen <= 1'b0;
            portb_wen <= 1'b0;
            bf_en     <= 1'b0;
            done_o    <= 1'b0;

            case (state)
                S_IDLE: begin
                    // External loading: allow writes via in_wr_en_i
                    if (in_wr_en_i) begin
                        bitrev_in <= in_addr_i;
                    end
                    // Use bit-reversed address for loading
                    // Need 1-cycle delay for addr_gen output
                    if (start_i) begin
                        state     <= S_COMPUTE;
                        stage_cnt <= 4'd0;
                        bf_cnt    <= 9'd0;
                    end
                end

                S_LOAD: begin
                    // Not used - loading done externally in IDLE via in_wr_en_i
                    state <= S_IDLE;
                end

                S_COMPUTE: begin
                    // Read p and q addresses from BRAM
                    porta_addr  <= p_addr;
                    portb_addr  <= q_addr;
                    tw_addr_reg <= tw_addr;
                    state       <= S_BF_WAIT;
                end

                S_BF_WAIT: begin
                    // BRAM read data available, feed to butterfly
                    bf_a_re <= porta_rdata[31:16];
                    bf_a_im <= porta_rdata[15:0];
                    bf_b_re <= portb_rdata[31:16];
                    bf_b_im <= portb_rdata[15:0];
                    bf_en   <= 1'b1;
                    state   <= S_BF_WB;
                end

                S_BF_WB: begin
                    if (bf_valid) begin
                        // Write back results
                        porta_addr  <= p_addr_d3;
                        porta_wdata <= {bf_p_re, bf_p_im};
                        porta_wen   <= 1'b1;
                        portb_addr  <= q_addr_d3;
                        portb_wdata <= {bf_q_re, bf_q_im};
                        portb_wen   <= 1'b1;

                        // Advance butterfly counter
                        if (bf_cnt == 9'd511) begin
                            bf_cnt <= 9'd0;
                            if (stage_cnt == 4'd9) begin
                                state <= S_DONE;
                            end else begin
                                stage_cnt <= stage_cnt + 4'd1;
                                state     <= S_COMPUTE;
                            end
                        end else begin
                            bf_cnt <= bf_cnt + 9'd1;
                            state  <= S_COMPUTE;
                        end
                    end
                end

                S_DONE: begin
                    done_o <= 1'b1;
                    state  <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase

            // External data loading in IDLE state (bit-reversed addressing)
            if (state == S_IDLE && in_wr_en_i) begin
                porta_addr  <= bitrev_out;
                porta_wdata <= {in_data_i, 16'd0};  // Real part only, imag = 0
                porta_wen   <= 1'b1;
            end
        end
    end

endmodule
