`timescale 1ns / 1ps
//============================================================================
// Module : npu_top
// Project : AI_GLASSES -- NPU Subsystem
// Description : Integration wrapper that instantiates all NPU sub-modules:
//               regfile, controller, DMA, weight buffer, activation buffer,
//               MAC array, quantization, and activation function units.
//               Includes data-packing logic (32-bit buffer -> 64-bit MAC)
//               and quantize serialization (256-bit accumulator -> 8x 32-bit).
// Standard : Verilog-2005
//============================================================================

module npu_top (
    input  wire        clk,
    input  wire        rst_n,

    // AXI4-Lite slave (CPU register access)
    input  wire [7:0]  s_axi_lite_awaddr,
    input  wire        s_axi_lite_awvalid,
    output wire        s_axi_lite_awready,
    input  wire [31:0] s_axi_lite_wdata,
    input  wire [3:0]  s_axi_lite_wstrb,
    input  wire        s_axi_lite_wvalid,
    output wire        s_axi_lite_wready,
    output wire [1:0]  s_axi_lite_bresp,
    output wire        s_axi_lite_bvalid,
    input  wire        s_axi_lite_bready,
    input  wire [7:0]  s_axi_lite_araddr,
    input  wire        s_axi_lite_arvalid,
    output wire        s_axi_lite_arready,
    output wire [31:0] s_axi_lite_rdata,
    output wire [1:0]  s_axi_lite_rresp,
    output wire        s_axi_lite_rvalid,
    input  wire        s_axi_lite_rready,

    // AXI4 master (DDR data transfers) -- 128-bit
    output wire [3:0]  m_axi_dma_awid,
    output wire [31:0] m_axi_dma_awaddr,
    output wire [7:0]  m_axi_dma_awlen,
    output wire [2:0]  m_axi_dma_awsize,
    output wire [1:0]  m_axi_dma_awburst,
    output wire [3:0]  m_axi_dma_awqos,
    output wire        m_axi_dma_awvalid,
    input  wire        m_axi_dma_awready,
    output wire [127:0] m_axi_dma_wdata,
    output wire [15:0] m_axi_dma_wstrb,
    output wire        m_axi_dma_wlast,
    output wire        m_axi_dma_wvalid,
    input  wire        m_axi_dma_wready,
    input  wire [3:0]  m_axi_dma_bid,
    input  wire [1:0]  m_axi_dma_bresp,
    input  wire        m_axi_dma_bvalid,
    output wire        m_axi_dma_bready,
    output wire [3:0]  m_axi_dma_arid,
    output wire [31:0] m_axi_dma_araddr,
    output wire [7:0]  m_axi_dma_arlen,
    output wire [2:0]  m_axi_dma_arsize,
    output wire [1:0]  m_axi_dma_arburst,
    output wire [3:0]  m_axi_dma_arqos,
    output wire        m_axi_dma_arvalid,
    input  wire        m_axi_dma_arready,
    input  wire [3:0]  m_axi_dma_rid,
    input  wire [127:0] m_axi_dma_rdata,
    input  wire [1:0]  m_axi_dma_rresp,
    input  wire        m_axi_dma_rlast,
    input  wire        m_axi_dma_rvalid,
    output wire        m_axi_dma_rready,

    // Interrupt
    output wire        irq_npu_done
);

    //========================================================================
    // Internal wires -- Regfile <-> Controller
    //========================================================================
    wire [31:0] reg_control;
    wire [31:0] reg_input_addr;
    wire [31:0] reg_weight_addr;
    wire [31:0] reg_output_addr;
    wire [31:0] reg_input_size;
    wire [31:0] reg_weight_size;
    wire [31:0] reg_output_size;
    wire [31:0] reg_layer_config;
    wire [31:0] reg_conv_config;
    wire [31:0] reg_tensor_dims;
    wire [31:0] reg_quant_param;
    wire        reg_start_pulse;

    wire [31:0] status;
    wire [31:0] perf_cycles;
    wire [31:0] dma_status;

    //========================================================================
    // Internal wires -- Controller <-> DMA
    //========================================================================
    wire        weight_dma_start;
    wire [31:0] weight_dma_src_addr;
    wire [31:0] weight_dma_xfer_len;
    wire        weight_dma_done;

    wire        act_dma_start;
    wire [31:0] act_dma_src_addr;
    wire [31:0] act_dma_dst_addr;
    wire [31:0] act_dma_xfer_len;
    wire        act_dma_direction;
    wire        act_dma_done;

    //========================================================================
    // Internal wires -- Controller <-> MAC array
    //========================================================================
    wire        mac_en;
    wire        mac_clear_acc;
    wire [1:0]  mac_mode;
    wire        mac_acc_valid;

    //========================================================================
    // Internal wires -- Controller <-> Buffers (port B read side)
    //========================================================================
    wire        wbuf_rd_en;
    wire [14:0] wbuf_rd_addr;
    wire [31:0] wbuf_rd_data;

    wire        abuf_rd_en;
    wire [14:0] abuf_rd_addr;
    wire [31:0] abuf_rd_data;

    //========================================================================
    // Internal wires -- Controller <-> Quantize
    //========================================================================
    wire        quant_en;
    wire [7:0]  quant_shift;
    wire [15:0] quant_scale;

    //========================================================================
    // Internal wires -- Controller <-> Activation
    //========================================================================
    wire        act_en;
    wire [1:0]  act_type;

    //========================================================================
    // Internal wires -- DMA <-> Weight buffer (port A)
    //========================================================================
    wire        wbuf_dma_we;
    wire [14:0] wbuf_dma_addr;
    wire [31:0] wbuf_dma_wdata;

    //========================================================================
    // Internal wires -- DMA <-> Activation buffer (port A)
    //========================================================================
    wire        abuf_dma_we;
    wire [14:0] abuf_dma_waddr;
    wire [31:0] abuf_dma_wdata;
    wire        abuf_dma_re;
    wire [14:0] abuf_dma_raddr;
    wire [31:0] abuf_dma_rdata;

    //========================================================================
    // Internal wires -- MAC array outputs
    //========================================================================
    wire [255:0] mac_acc_out;   // 8 x 32-bit accumulators

    //========================================================================
    // Internal wires -- Quantize <-> Activation
    //========================================================================
    wire [7:0]  quant_data_out;
    wire        quant_valid_out;

    wire [7:0]  act_data_out;
    wire        act_valid_out;

    //========================================================================
    // Data packing: 32-bit buffer reads -> 64-bit MAC inputs
    //
    // The weight and activation buffers output 32 bits per read (4x INT8).
    // The MAC array requires 64 bits (8x INT8). A holding register captures
    // the first 32-bit word; on the second read the two halves are
    // concatenated into a 64-bit vector for the MAC.
    //========================================================================
    reg [31:0] wbuf_rd_data_hold;
    reg [31:0] abuf_rd_data_hold;
    reg        pack_phase;

    always @(posedge clk) begin
        if (!rst_n) begin
            wbuf_rd_data_hold <= 32'd0;
            abuf_rd_data_hold <= 32'd0;
            pack_phase        <= 1'b0;
        end else if (wbuf_rd_en || abuf_rd_en) begin
            if (pack_phase == 1'b0) begin
                wbuf_rd_data_hold <= wbuf_rd_data;
                abuf_rd_data_hold <= abuf_rd_data;
                pack_phase        <= 1'b1;
            end else begin
                pack_phase <= 1'b0;
            end
        end
    end

    wire [63:0] weight_pack_data;
    wire [63:0] act_pack_data;

    assign weight_pack_data = {wbuf_rd_data, wbuf_rd_data_hold};
    assign act_pack_data    = {abuf_rd_data, abuf_rd_data_hold};

    //========================================================================
    // Quantize serialization: 256-bit accumulator -> 8 sequential 32-bit
    //
    // mac_acc_out is 256 bits (8 x 32-bit). The quantize unit processes one
    // 32-bit value per cycle. A 3-bit counter (quant_idx) selects which of
    // the 8 accumulator results to feed in. The counter runs while quant_en
    // is asserted and mac_acc_valid is high.
    //========================================================================
    reg [2:0]  quant_idx;
    reg        quant_active;
    reg        quant_valid_in;

    always @(posedge clk) begin
        if (!rst_n) begin
            quant_idx    <= 3'd0;
            quant_active <= 1'b0;
            quant_valid_in <= 1'b0;
        end else if (quant_en && mac_acc_valid && !quant_active) begin
            quant_idx    <= 3'd0;
            quant_active <= 1'b1;
            quant_valid_in <= 1'b1;
        end else if (quant_active) begin
            if (quant_idx == 3'd7) begin
                quant_active   <= 1'b0;
                quant_valid_in <= 1'b0;
                quant_idx      <= 3'd0;
            end else begin
                quant_idx      <= quant_idx + 3'd1;
                quant_valid_in <= 1'b1;
            end
        end else begin
            quant_valid_in <= 1'b0;
        end
    end

    reg [31:0] quant_data_mux;
    always @(*) begin
        case (quant_idx)
            3'd0: quant_data_mux = mac_acc_out[ 31:  0];
            3'd1: quant_data_mux = mac_acc_out[ 63: 32];
            3'd2: quant_data_mux = mac_acc_out[ 95: 64];
            3'd3: quant_data_mux = mac_acc_out[127: 96];
            3'd4: quant_data_mux = mac_acc_out[159:128];
            3'd5: quant_data_mux = mac_acc_out[191:160];
            3'd6: quant_data_mux = mac_acc_out[223:192];
            3'd7: quant_data_mux = mac_acc_out[255:224];
            default: quant_data_mux = 32'd0;
        endcase
    end

    //========================================================================
    // Output staging: collect 8-bit activation outputs for write-back
    //
    // The activation unit produces one INT8 result per cycle. Results are
    // packed into a 32-bit word (4 values at a time). When 4 values are
    // collected a write-enable is asserted toward the activation buffer
    // (port A via DMA is separate; this path uses controller-managed
    // write-back through the act DMA channel).
    //========================================================================
    // Output staging is managed by the controller which issues DMA write-back
    // commands. The act_data_out and act_valid_out signals are available for
    // the controller to observe and sequence the output DMA accordingly.

    //========================================================================
    // Sub-module instantiations
    //========================================================================

    //--------------------------------------------------------------------
    // 1. Register file (AXI4-Lite slave)
    //--------------------------------------------------------------------
    npu_regfile u_regfile (
        .clk              (clk),
        .rst_n            (rst_n),

        // AXI4-Lite slave (prefix mapping: s_axi_lite_* -> s_axil_*)
        .s_axil_awaddr    (s_axi_lite_awaddr),
        .s_axil_awvalid   (s_axi_lite_awvalid),
        .s_axil_awready   (s_axi_lite_awready),
        .s_axil_wdata     (s_axi_lite_wdata),
        .s_axil_wstrb     (s_axi_lite_wstrb),
        .s_axil_wvalid    (s_axi_lite_wvalid),
        .s_axil_wready    (s_axi_lite_wready),
        .s_axil_bresp     (s_axi_lite_bresp),
        .s_axil_bvalid    (s_axi_lite_bvalid),
        .s_axil_bready    (s_axi_lite_bready),
        .s_axil_araddr    (s_axi_lite_araddr),
        .s_axil_arvalid   (s_axi_lite_arvalid),
        .s_axil_arready   (s_axi_lite_arready),
        .s_axil_rdata     (s_axi_lite_rdata),
        .s_axil_rresp     (s_axi_lite_rresp),
        .s_axil_rvalid    (s_axi_lite_rvalid),
        .s_axil_rready    (s_axi_lite_rready),

        // Register outputs
        .reg_control      (reg_control),
        .reg_input_addr   (reg_input_addr),
        .reg_weight_addr  (reg_weight_addr),
        .reg_output_addr  (reg_output_addr),
        .reg_input_size   (reg_input_size),
        .reg_weight_size  (reg_weight_size),
        .reg_output_size  (reg_output_size),
        .reg_layer_config (reg_layer_config),
        .reg_conv_config  (reg_conv_config),
        .reg_tensor_dims  (reg_tensor_dims),
        .reg_quant_param  (reg_quant_param),
        .reg_start_pulse  (reg_start_pulse),

        // Status inputs
        .status_i         (status),
        .perf_cycles_i    (perf_cycles),
        .dma_status_i     (dma_status),

        // Interrupt
        .irq_npu_done_o   (irq_npu_done)
    );

    //--------------------------------------------------------------------
    // 2. Controller FSM
    //--------------------------------------------------------------------
    npu_controller u_controller (
        .clk              (clk),
        .rst_n            (rst_n),

        // Regfile -> Controller
        .reg_control      (reg_control),
        .reg_input_addr   (reg_input_addr),
        .reg_weight_addr  (reg_weight_addr),
        .reg_output_addr  (reg_output_addr),
        .reg_input_size   (reg_input_size),
        .reg_weight_size  (reg_weight_size),
        .reg_output_size  (reg_output_size),
        .reg_layer_config (reg_layer_config),
        .reg_conv_config  (reg_conv_config),
        .reg_tensor_dims  (reg_tensor_dims),
        .reg_quant_param  (reg_quant_param),
        .reg_start_pulse  (reg_start_pulse),

        // Controller -> Regfile (status)
        .status_o         (status),
        .perf_cycles_o    (perf_cycles),
        .dma_status_o     (dma_status),

        // DMA weight channel control
        .weight_dma_start    (weight_dma_start),
        .weight_dma_src_addr (weight_dma_src_addr),
        .weight_dma_xfer_len (weight_dma_xfer_len),
        .weight_dma_done     (weight_dma_done),

        // DMA activation channel control
        .act_dma_start       (act_dma_start),
        .act_dma_src_addr    (act_dma_src_addr),
        .act_dma_dst_addr    (act_dma_dst_addr),
        .act_dma_xfer_len    (act_dma_xfer_len),
        .act_dma_direction   (act_dma_direction),
        .act_dma_done        (act_dma_done),

        // MAC array control
        .mac_en           (mac_en),
        .mac_clear_acc    (mac_clear_acc),
        .mac_mode         (mac_mode),
        .mac_acc_valid    (mac_acc_valid),

        // Buffer read control
        .wbuf_rd_en       (wbuf_rd_en),
        .wbuf_rd_addr     (wbuf_rd_addr),
        .abuf_rd_en       (abuf_rd_en),
        .abuf_rd_addr     (abuf_rd_addr),

        // Quantize control
        .quant_en         (quant_en),
        .quant_shift      (quant_shift),
        .quant_scale      (quant_scale),

        // Activation control
        .act_en           (act_en),
        .act_type         (act_type)
    );

    //--------------------------------------------------------------------
    // 3. DMA engine (weight + activation channels, AXI4 master)
    //--------------------------------------------------------------------
    npu_dma u_dma (
        .clk              (clk),
        .rst_n            (rst_n),

        // Weight channel control
        .weight_start     (weight_dma_start),
        .weight_src_addr  (weight_dma_src_addr),
        .weight_xfer_len  (weight_dma_xfer_len),
        .weight_done      (weight_dma_done),

        // Activation channel control
        .act_start        (act_dma_start),
        .act_src_addr     (act_dma_src_addr),
        .act_dst_addr     (act_dma_dst_addr),
        .act_xfer_len     (act_dma_xfer_len),
        .act_direction    (act_dma_direction),
        .act_done         (act_dma_done),

        // Weight buffer write port
        .wbuf_we          (wbuf_dma_we),
        .wbuf_addr        (wbuf_dma_addr),
        .wbuf_wdata       (wbuf_dma_wdata),

        // Activation buffer write port
        .abuf_we          (abuf_dma_we),
        .abuf_waddr       (abuf_dma_waddr),
        .abuf_wdata       (abuf_dma_wdata),

        // Activation buffer read port
        .abuf_re          (abuf_dma_re),
        .abuf_raddr       (abuf_dma_raddr),
        .abuf_rdata       (abuf_dma_rdata),

        // AXI4 master (mapped to external m_axi_dma_* ports)
        .m_axi_awid       (m_axi_dma_awid),
        .m_axi_awaddr     (m_axi_dma_awaddr),
        .m_axi_awlen      (m_axi_dma_awlen),
        .m_axi_awsize     (m_axi_dma_awsize),
        .m_axi_awburst    (m_axi_dma_awburst),
        .m_axi_awqos      (m_axi_dma_awqos),
        .m_axi_awvalid    (m_axi_dma_awvalid),
        .m_axi_awready    (m_axi_dma_awready),
        .m_axi_wdata      (m_axi_dma_wdata),
        .m_axi_wstrb      (m_axi_dma_wstrb),
        .m_axi_wlast      (m_axi_dma_wlast),
        .m_axi_wvalid     (m_axi_dma_wvalid),
        .m_axi_wready     (m_axi_dma_wready),
        .m_axi_bid        (m_axi_dma_bid),
        .m_axi_bresp      (m_axi_dma_bresp),
        .m_axi_bvalid     (m_axi_dma_bvalid),
        .m_axi_bready     (m_axi_dma_bready),
        .m_axi_arid       (m_axi_dma_arid),
        .m_axi_araddr     (m_axi_dma_araddr),
        .m_axi_arlen      (m_axi_dma_arlen),
        .m_axi_arsize     (m_axi_dma_arsize),
        .m_axi_arburst    (m_axi_dma_arburst),
        .m_axi_arqos      (m_axi_dma_arqos),
        .m_axi_arvalid    (m_axi_dma_arvalid),
        .m_axi_arready    (m_axi_dma_arready),
        .m_axi_rid        (m_axi_dma_rid),
        .m_axi_rdata      (m_axi_dma_rdata),
        .m_axi_rresp      (m_axi_dma_rresp),
        .m_axi_rlast      (m_axi_dma_rlast),
        .m_axi_rvalid     (m_axi_dma_rvalid),
        .m_axi_rready     (m_axi_dma_rready)
    );

    //--------------------------------------------------------------------
    // 4. Weight buffer (dual-port BRAM, 32K x 32-bit = 128 KB)
    //--------------------------------------------------------------------
    npu_weight_buf u_weight_buf (
        .clk              (clk),

        // Port A -- DMA side
        .port_a_en        (wbuf_dma_we | 1'b1),
        .port_a_we        (wbuf_dma_we),
        .port_a_addr      (wbuf_dma_addr),
        .port_a_wdata     (wbuf_dma_wdata),
        .port_a_rdata     (),                     // DMA read-back not used

        // Port B -- MAC read side
        .port_b_en        (wbuf_rd_en),
        .port_b_addr      (wbuf_rd_addr),
        .port_b_rdata     (wbuf_rd_data)
    );

    //--------------------------------------------------------------------
    // 5. Activation buffer (dual-port BRAM, 32K x 32-bit = 128 KB)
    //--------------------------------------------------------------------
    npu_act_buf u_act_buf (
        .clk              (clk),

        // Port A -- DMA side (read + write)
        .port_a_en        (abuf_dma_we | abuf_dma_re),
        .port_a_we        (abuf_dma_we),
        .port_a_addr      (abuf_dma_we ? abuf_dma_waddr : abuf_dma_raddr),
        .port_a_wdata     (abuf_dma_wdata),
        .port_a_rdata     (abuf_dma_rdata),

        // Port B -- MAC read side
        .port_b_en        (abuf_rd_en),
        .port_b_addr      (abuf_rd_addr),
        .port_b_rdata     (abuf_rd_data)
    );

    //--------------------------------------------------------------------
    // 6. MAC array (8x8 systolic, 64 parallel INT8 MACs)
    //    weight_data / act_data are 64 bits; buffers provide 32 bits.
    //    The packing registers above concatenate two consecutive reads.
    //    The controller manages address sequencing for the two-phase read.
    //--------------------------------------------------------------------
    npu_mac_array u_mac_array (
        .clk              (clk),
        .rst_n            (rst_n),
        .en               (mac_en),
        .clear_acc        (mac_clear_acc),
        .mode             (mac_mode),
        .weight_data      (weight_pack_data),
        .act_data         (act_pack_data),
        .acc_out          (mac_acc_out),
        .acc_valid        (mac_acc_valid)
    );

    //--------------------------------------------------------------------
    // 7. Quantization unit (INT32 -> INT8, 3-cycle pipeline)
    //    Input is serialized from 8 accumulator lanes via quant_data_mux.
    //--------------------------------------------------------------------
    npu_quantize u_quantize (
        .clk              (clk),
        .rst_n            (rst_n),
        .en               (quant_en),
        .data_i           (quant_data_mux),
        .valid_i          (quant_valid_in),
        .shift_i          (quant_shift),
        .scale_i          (quant_scale),
        .data_o           (quant_data_out),
        .valid_o          (quant_valid_out)
    );

    //--------------------------------------------------------------------
    // 8. Activation function unit (ReLU / ReLU6 / bypass, 1-cycle)
    //--------------------------------------------------------------------
    npu_activation u_activation (
        .clk              (clk),
        .rst_n            (rst_n),
        .en               (act_en),
        .act_type         (act_type),
        .data_i           (quant_data_out),
        .valid_i          (quant_valid_out),
        .data_o           (act_data_out),
        .valid_o          (act_valid_out)
    );

endmodule
