// ============================================================================
// Module:      npu_controller
// Description: Top-level NPU orchestrator FSM. Controls DMA transfers, MAC
//              array computation, quantization, and activation pipeline stages
//              for neural network inference acceleration.
// Standard:    Verilog-2005
// ============================================================================

`timescale 1ns/1ps

module npu_controller (
    input  wire        clk,
    input  wire        rst_n,

    // From regfile
    input  wire [31:0] reg_control,
    input  wire [31:0] reg_input_addr,
    input  wire [31:0] reg_weight_addr,
    input  wire [31:0] reg_output_addr,
    input  wire [31:0] reg_input_size,
    input  wire [31:0] reg_weight_size,
    input  wire [31:0] reg_output_size,
    input  wire [31:0] reg_layer_config,
    input  wire [31:0] reg_conv_config,
    input  wire [31:0] reg_tensor_dims,
    input  wire [31:0] reg_quant_param,
    input  wire        reg_start_pulse,

    // To regfile (status)
    output reg  [31:0] status_o,
    output reg  [31:0] perf_cycles_o,
    output reg  [31:0] dma_status_o,

    // DMA control (to npu_dma)
    output reg         weight_dma_start,
    output reg  [31:0] weight_dma_src_addr,
    output reg  [31:0] weight_dma_xfer_len,
    input  wire        weight_dma_done,

    output reg         act_dma_start,
    output reg  [31:0] act_dma_src_addr,
    output reg  [31:0] act_dma_dst_addr,
    output reg  [31:0] act_dma_xfer_len,
    output reg         act_dma_direction,  // 0=DDR->buf, 1=buf->DDR
    input  wire        act_dma_done,

    // MAC array control (to npu_mac_array)
    output reg         mac_en,
    output reg         mac_clear_acc,
    output reg  [1:0]  mac_mode,  // 0=Conv2D, 1=DW-Conv2D, 2=FC
    input  wire        mac_acc_valid,

    // Buffer address control (to weight/act buffer port B)
    output reg         wbuf_rd_en,
    output reg  [14:0] wbuf_rd_addr,
    output reg         abuf_rd_en,
    output reg  [14:0] abuf_rd_addr,

    // Quantize control (to npu_quantize)
    output reg         quant_en,
    output reg  [7:0]  quant_shift,
    output reg  [15:0] quant_scale,

    // Activation control (to npu_activation)
    output reg         act_en,
    output reg  [1:0]  act_type
);

    // ========================================================================
    // FSM State Encoding (4-bit binary)
    // ========================================================================
    localparam [3:0] S_IDLE        = 4'd0;
    localparam [3:0] S_LOAD_CONFIG = 4'd1;
    localparam [3:0] S_DMA_PREFETCH = 4'd2;
    localparam [3:0] S_WAIT_DMA    = 4'd3;
    localparam [3:0] S_MAC_COMPUTE = 4'd4;
    localparam [3:0] S_WAIT_MAC    = 4'd5;
    localparam [3:0] S_QUANTIZE    = 4'd6;
    localparam [3:0] S_ACTIVATE    = 4'd7;
    localparam [3:0] S_OUTPUT_DMA  = 4'd8;
    localparam [3:0] S_WAIT_OUTPUT = 4'd9;
    localparam [3:0] S_DONE        = 4'd10;

    // ========================================================================
    // Internal registers
    // ========================================================================
    reg [3:0]  state, state_next;

    // Latched configuration
    reg [3:0]  layer_type;
    reg [3:0]  act_type_cfg;
    reg [7:0]  input_channels_div8;  // reg_layer_config[15:8]
    reg [3:0]  kernel_size;
    reg [3:0]  stride;
    reg [3:0]  padding;
    reg [15:0] input_dims;
    reg [15:0] output_dims;

    // Counters
    reg [15:0] compute_count;
    reg [15:0] compute_target;
    reg [3:0]  pipe_count;          // counter for quant/act pipeline stages
    reg        mac_first_cycle;     // flag for mac_clear_acc on first cycle

    // DMA completion tracking
    reg        weight_dma_done_r;
    reg        act_dma_done_r;

    // ========================================================================
    // Performance counter
    // ========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            perf_cycles_o <= 32'd0;
        end else begin
            if (state == S_IDLE && state_next == S_LOAD_CONFIG) begin
                perf_cycles_o <= 32'd0;
            end else if (state >= S_LOAD_CONFIG && state <= S_WAIT_OUTPUT) begin
                perf_cycles_o <= perf_cycles_o + 32'd1;
            end
        end
    end

    // ========================================================================
    // FSM: State register
    // ========================================================================
    always @(posedge clk) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= state_next;
    end

    // ========================================================================
    // FSM: Next-state logic
    // ========================================================================
    always @(*) begin
        state_next = state;
        case (state)
            S_IDLE: begin
                if (reg_start_pulse && reg_control[0])
                    state_next = S_LOAD_CONFIG;
            end

            S_LOAD_CONFIG: begin
                state_next = S_DMA_PREFETCH;
            end

            S_DMA_PREFETCH: begin
                state_next = S_WAIT_DMA;
            end

            S_WAIT_DMA: begin
                if (weight_dma_done_r && act_dma_done_r)
                    state_next = S_MAC_COMPUTE;
            end

            S_MAC_COMPUTE: begin
                if (compute_count >= compute_target && !mac_first_cycle)
                    state_next = S_WAIT_MAC;
            end

            S_WAIT_MAC: begin
                if (mac_acc_valid)
                    state_next = S_QUANTIZE;
            end

            S_QUANTIZE: begin
                if (pipe_count >= 4'd7)
                    state_next = S_ACTIVATE;
            end

            S_ACTIVATE: begin
                if (pipe_count >= 4'd7)
                    state_next = S_OUTPUT_DMA;
            end

            S_OUTPUT_DMA: begin
                state_next = S_WAIT_OUTPUT;
            end

            S_WAIT_OUTPUT: begin
                if (act_dma_done)
                    state_next = S_DONE;
            end

            S_DONE: begin
                state_next = S_IDLE;
            end

            default: begin
                state_next = S_IDLE;
            end
        endcase
    end

    // ========================================================================
    // FSM: Output and datapath logic
    // ========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            // Status
            status_o          <= 32'd0;
            dma_status_o      <= 32'd0;

            // Weight DMA
            weight_dma_start    <= 1'b0;
            weight_dma_src_addr <= 32'd0;
            weight_dma_xfer_len <= 32'd0;

            // Activation DMA
            act_dma_start     <= 1'b0;
            act_dma_src_addr  <= 32'd0;
            act_dma_dst_addr  <= 32'd0;
            act_dma_xfer_len  <= 32'd0;
            act_dma_direction <= 1'b0;

            // MAC
            mac_en            <= 1'b0;
            mac_clear_acc     <= 1'b0;
            mac_mode          <= 2'd0;

            // Buffer read
            wbuf_rd_en        <= 1'b0;
            wbuf_rd_addr      <= 15'd0;
            abuf_rd_en        <= 1'b0;
            abuf_rd_addr      <= 15'd0;

            // Quantize
            quant_en          <= 1'b0;
            quant_shift       <= 8'd0;
            quant_scale       <= 16'd0;

            // Activation
            act_en            <= 1'b0;
            act_type          <= 2'd0;

            // Internal
            layer_type        <= 4'd0;
            act_type_cfg      <= 4'd0;
            input_channels_div8 <= 8'd0;
            kernel_size       <= 4'd0;
            stride            <= 4'd0;
            padding           <= 4'd0;
            input_dims        <= 16'd0;
            output_dims       <= 16'd0;
            compute_count     <= 16'd0;
            compute_target    <= 16'd0;
            pipe_count        <= 4'd0;
            mac_first_cycle   <= 1'b0;
            weight_dma_done_r <= 1'b0;
            act_dma_done_r    <= 1'b0;
        end else begin
            // ----------------------------------------------------------------
            // Default: deassert single-cycle pulses
            // ----------------------------------------------------------------
            weight_dma_start <= 1'b0;
            act_dma_start    <= 1'b0;

            // Track DMA completions in WAIT_DMA
            if (state == S_WAIT_DMA) begin
                if (weight_dma_done)
                    weight_dma_done_r <= 1'b1;
                if (act_dma_done)
                    act_dma_done_r <= 1'b1;
            end

            case (state)
                // ============================================================
                // IDLE
                // ============================================================
                S_IDLE: begin
                    status_o      <= 32'd0;
                    dma_status_o  <= 32'd0;
                    mac_en        <= 1'b0;
                    mac_clear_acc <= 1'b0;
                    quant_en      <= 1'b0;
                    act_en        <= 1'b0;
                    wbuf_rd_en    <= 1'b0;
                    abuf_rd_en    <= 1'b0;
                    weight_dma_done_r <= 1'b0;
                    act_dma_done_r    <= 1'b0;
                end

                // ============================================================
                // LOAD_CONFIG
                // ============================================================
                S_LOAD_CONFIG: begin
                    // Mark busy
                    status_o[0] <= 1'b1;
                    status_o[31:1] <= 31'd0;

                    // Decode layer config
                    layer_type        <= reg_layer_config[3:0];
                    act_type_cfg      <= reg_layer_config[7:4];
                    input_channels_div8 <= reg_layer_config[15:8];

                    // MAC mode based on layer type
                    case (reg_layer_config[3:0])
                        4'd0:    mac_mode <= 2'd0;  // Conv2D
                        4'd1:    mac_mode <= 2'd2;  // FC
                        4'd4:    mac_mode <= 2'd1;  // DW-Conv2D
                        default: mac_mode <= 2'd0;
                    endcase

                    // Latch quantization parameters
                    quant_shift <= reg_quant_param[23:16];
                    quant_scale <= reg_quant_param[15:0];

                    // Latch activation type
                    act_type <= reg_layer_config[5:4];

                    // Latch conv config: kernel_size[3:0], stride[7:4], padding[11:8]
                    kernel_size <= reg_conv_config[3:0];
                    stride      <= reg_conv_config[7:4];
                    padding     <= reg_conv_config[11:8];

                    // Latch tensor dims
                    input_dims  <= reg_tensor_dims[15:0];
                    output_dims <= reg_tensor_dims[31:16];

                    // Compute target: input_channels / 8 for Conv2D/FC, 1 for DW-Conv2D
                    // Minimum of 1 to ensure MAC pipeline produces a valid output
                    if (reg_layer_config[3:0] == 4'd4) begin
                        compute_target <= 16'd1;
                    end else if (reg_layer_config[15:8] == 8'd0) begin
                        compute_target <= 16'd1;
                    end else begin
                        compute_target <= {8'd0, reg_layer_config[15:8]};
                    end
                end

                // ============================================================
                // DMA_PREFETCH
                // ============================================================
                S_DMA_PREFETCH: begin
                    // Program weight DMA
                    weight_dma_src_addr <= reg_weight_addr;
                    weight_dma_xfer_len <= reg_weight_size;
                    weight_dma_start    <= 1'b1;

                    // Program activation DMA (DDR -> buffer)
                    act_dma_src_addr  <= reg_input_addr;
                    act_dma_xfer_len  <= reg_input_size;
                    act_dma_direction <= 1'b0;
                    act_dma_start     <= 1'b1;

                    // Clear DMA tracking
                    weight_dma_done_r <= 1'b0;
                    act_dma_done_r    <= 1'b0;
                    dma_status_o      <= 32'd0;
                end

                // ============================================================
                // WAIT_DMA
                // ============================================================
                S_WAIT_DMA: begin
                    dma_status_o[0] <= weight_dma_done_r;
                    dma_status_o[1] <= act_dma_done_r;

                    if (weight_dma_done_r && act_dma_done_r) begin
                        // Prepare for MAC compute
                        mac_first_cycle <= 1'b1;
                        compute_count   <= 16'd0;
                        wbuf_rd_addr    <= 15'd0;
                        abuf_rd_addr    <= 15'd0;
                    end
                end

                // ============================================================
                // MAC_COMPUTE
                // ============================================================
                S_MAC_COMPUTE: begin
                    if (mac_first_cycle) begin
                        // First cycle: clear accumulators
                        mac_clear_acc   <= 1'b1;
                        mac_en          <= 1'b1;
                        wbuf_rd_en      <= 1'b1;
                        abuf_rd_en      <= 1'b1;
                        mac_first_cycle <= 1'b0;
                        compute_count   <= 16'd1;
                        wbuf_rd_addr    <= 15'd1;
                        abuf_rd_addr    <= 15'd1;
                    end else if (compute_count < compute_target) begin
                        mac_clear_acc <= 1'b0;
                        mac_en        <= 1'b1;
                        wbuf_rd_en    <= 1'b1;
                        abuf_rd_en    <= 1'b1;
                        compute_count <= compute_count + 16'd1;
                        wbuf_rd_addr  <= wbuf_rd_addr + 15'd1;
                        abuf_rd_addr  <= abuf_rd_addr + 15'd1;
                    end else begin
                        // Done computing — keep mac_en high for pipeline drain
                        mac_en        <= 1'b1;
                        mac_clear_acc <= 1'b0;
                        wbuf_rd_en    <= 1'b0;
                        abuf_rd_en    <= 1'b0;
                    end
                end

                // ============================================================
                // WAIT_MAC
                // Keep mac_en asserted so the MAC pipeline valid counter
                // can reach LATENCY and produce acc_valid.
                // ============================================================
                S_WAIT_MAC: begin
                    mac_en        <= 1'b1;
                    mac_clear_acc <= 1'b0;
                    wbuf_rd_en    <= 1'b0;
                    abuf_rd_en    <= 1'b0;

                    if (mac_acc_valid) begin
                        pipe_count <= 4'd0;
                        mac_en     <= 1'b0;
                    end
                end

                // ============================================================
                // QUANTIZE
                // ============================================================
                S_QUANTIZE: begin
                    quant_en <= 1'b1;
                    if (pipe_count < 4'd7) begin
                        pipe_count <= pipe_count + 4'd1;
                    end else begin
                        quant_en   <= 1'b0;
                        pipe_count <= 4'd0;
                    end
                end

                // ============================================================
                // ACTIVATE
                // ============================================================
                S_ACTIVATE: begin
                    act_en <= 1'b1;
                    if (pipe_count < 4'd7) begin
                        pipe_count <= pipe_count + 4'd1;
                    end else begin
                        act_en     <= 1'b0;
                        pipe_count <= 4'd0;
                    end
                end

                // ============================================================
                // OUTPUT_DMA
                // ============================================================
                S_OUTPUT_DMA: begin
                    act_dma_dst_addr  <= reg_output_addr;
                    act_dma_xfer_len  <= reg_output_size;
                    act_dma_direction <= 1'b1;
                    act_dma_start     <= 1'b1;
                end

                // ============================================================
                // WAIT_OUTPUT
                // ============================================================
                S_WAIT_OUTPUT: begin
                    if (act_dma_done) begin
                        dma_status_o[2] <= 1'b1;
                    end
                end

                // ============================================================
                // DONE
                // ============================================================
                S_DONE: begin
                    status_o[0] <= 1'b0;  // not busy
                    status_o[1] <= 1'b1;  // layer_done
                end

                default: begin
                    // Safe default
                    status_o <= 32'd0;
                end
            endcase
        end
    end

endmodule
