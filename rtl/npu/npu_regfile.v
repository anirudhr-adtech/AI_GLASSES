`timescale 1ns / 1ps
//============================================================================
// npu_regfile.v
// AXI4-Lite slave with 16 NPU configuration/status registers.
// Register map per NPU v2 doc Section 4.
//============================================================================

module npu_regfile (
    // Clock and reset
    input  wire        clk,
    input  wire        rst_n,

    // AXI4-Lite slave – write address channel
    input  wire [7:0]  s_axil_awaddr,
    input  wire        s_axil_awvalid,
    output reg         s_axil_awready,

    // AXI4-Lite slave – write data channel
    input  wire [31:0] s_axil_wdata,
    input  wire [3:0]  s_axil_wstrb,
    input  wire        s_axil_wvalid,
    output reg         s_axil_wready,

    // AXI4-Lite slave – write response channel
    output reg  [1:0]  s_axil_bresp,
    output reg         s_axil_bvalid,
    input  wire        s_axil_bready,

    // AXI4-Lite slave – read address channel
    input  wire [7:0]  s_axil_araddr,
    input  wire        s_axil_arvalid,
    output reg         s_axil_arready,

    // AXI4-Lite slave – read data channel
    output reg  [31:0] s_axil_rdata,
    output reg  [1:0]  s_axil_rresp,
    output reg         s_axil_rvalid,
    input  wire        s_axil_rready,

    // Register outputs to controller
    output reg  [31:0] reg_control,
    output reg  [31:0] reg_input_addr,
    output reg  [31:0] reg_weight_addr,
    output reg  [31:0] reg_output_addr,
    output reg  [31:0] reg_input_size,
    output reg  [31:0] reg_weight_size,
    output reg  [31:0] reg_output_size,
    output reg  [31:0] reg_layer_config,
    output reg  [31:0] reg_conv_config,
    output reg  [31:0] reg_tensor_dims,
    output reg  [31:0] reg_quant_param,
    output reg         reg_start_pulse,

    // Status / performance inputs from controller
    input  wire [31:0] status_i,
    input  wire [31:0] perf_cycles_i,
    input  wire [31:0] dma_status_i,

    // Interrupt output
    output reg         irq_npu_done_o
);

    //------------------------------------------------------------------------
    // Word-address indices (s_axil_awaddr[7:2] / s_axil_araddr[7:2])
    //------------------------------------------------------------------------
    localparam [5:0] ADDR_CONTROL      = 6'h00; // 0x00
    localparam [5:0] ADDR_STATUS       = 6'h01; // 0x04
    localparam [5:0] ADDR_INPUT_ADDR   = 6'h02; // 0x08
    localparam [5:0] ADDR_WEIGHT_ADDR  = 6'h03; // 0x0C
    localparam [5:0] ADDR_OUTPUT_ADDR  = 6'h04; // 0x10
    localparam [5:0] ADDR_INPUT_SIZE   = 6'h05; // 0x14
    localparam [5:0] ADDR_WEIGHT_SIZE  = 6'h06; // 0x18
    localparam [5:0] ADDR_OUTPUT_SIZE  = 6'h07; // 0x1C
    localparam [5:0] ADDR_LAYER_CONFIG = 6'h08; // 0x20
    localparam [5:0] ADDR_CONV_CONFIG  = 6'h09; // 0x24
    localparam [5:0] ADDR_TENSOR_DIMS  = 6'h0A; // 0x28
    localparam [5:0] ADDR_QUANT_PARAM  = 6'h0B; // 0x2C
    localparam [5:0] ADDR_START        = 6'h0C; // 0x30
    localparam [5:0] ADDR_IRQ_CLEAR    = 6'h0D; // 0x34
    localparam [5:0] ADDR_PERF_CYCLES  = 6'h0E; // 0x38
    localparam [5:0] ADDR_DMA_STATUS   = 6'h0F; // 0x3C

    //------------------------------------------------------------------------
    // Internal signals
    //------------------------------------------------------------------------
    reg [5:0]  aw_addr_r;
    reg        aw_en;       // address-phase captured flag
    reg        irq_pending;
    reg        layer_done_d; // delayed layer_done for edge detect

    wire [5:0] wr_addr;
    wire [5:0] rd_addr;

    assign wr_addr = aw_addr_r;
    assign rd_addr = s_axil_araddr[7:2];

    //------------------------------------------------------------------------
    // Byte-strobe helper: merge new data with old using wstrb
    //------------------------------------------------------------------------
    function [31:0] apply_wstrb;
        input [31:0] old_val;
        input [31:0] new_val;
        input [3:0]  strb;
        begin
            apply_wstrb[ 7: 0] = strb[0] ? new_val[ 7: 0] : old_val[ 7: 0];
            apply_wstrb[15: 8] = strb[1] ? new_val[15: 8] : old_val[15: 8];
            apply_wstrb[23:16] = strb[2] ? new_val[23:16] : old_val[23:16];
            apply_wstrb[31:24] = strb[3] ? new_val[31:24] : old_val[31:24];
        end
    endfunction

    //------------------------------------------------------------------------
    // AXI4-Lite write address channel
    //------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            s_axil_awready <= 1'b0;
            aw_en          <= 1'b1;
            aw_addr_r      <= 6'b0;
        end else begin
            if (~s_axil_awready && s_axil_awvalid && s_axil_wvalid && aw_en) begin
                s_axil_awready <= 1'b1;
                aw_en          <= 1'b0;
                aw_addr_r      <= s_axil_awaddr[7:2];
            end else begin
                s_axil_awready <= 1'b0;
                if (s_axil_bvalid && s_axil_bready) begin
                    aw_en <= 1'b1;
                end
            end
        end
    end

    //------------------------------------------------------------------------
    // AXI4-Lite write data channel
    //------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            s_axil_wready <= 1'b0;
        end else begin
            if (~s_axil_wready && s_axil_wvalid && s_axil_awvalid && aw_en) begin
                s_axil_wready <= 1'b1;
            end else begin
                s_axil_wready <= 1'b0;
            end
        end
    end

    //------------------------------------------------------------------------
    // AXI4-Lite write response channel
    //------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            s_axil_bvalid <= 1'b0;
            s_axil_bresp  <= 2'b00;
        end else begin
            if (s_axil_awready && s_axil_awvalid && s_axil_wready && s_axil_wvalid && ~s_axil_bvalid) begin
                s_axil_bvalid <= 1'b1;
                s_axil_bresp  <= 2'b00; // OKAY
            end else if (s_axil_bvalid && s_axil_bready) begin
                s_axil_bvalid <= 1'b0;
            end
        end
    end

    //------------------------------------------------------------------------
    // Register write logic
    //------------------------------------------------------------------------
    wire wr_en;
    assign wr_en = s_axil_awready && s_axil_awvalid && s_axil_wready && s_axil_wvalid;

    always @(posedge clk) begin
        if (!rst_n) begin
            reg_control      <= 32'h0;
            reg_input_addr   <= 32'h0;
            reg_weight_addr  <= 32'h0;
            reg_output_addr  <= 32'h0;
            reg_input_size   <= 32'h0;
            reg_weight_size  <= 32'h0;
            reg_output_size  <= 32'h0;
            reg_layer_config <= 32'h0;
            reg_conv_config  <= 32'h0;
            reg_tensor_dims  <= 32'h0;
            reg_quant_param  <= 32'h0;
            reg_start_pulse  <= 1'b0;
        end else begin
            // Self-clearing soft_reset bit
            if (reg_control[1]) begin
                reg_control[1] <= 1'b0;
            end

            // Default: clear start pulse after one cycle
            reg_start_pulse <= 1'b0;

            if (wr_en) begin
                case (wr_addr)
                    ADDR_CONTROL:      reg_control      <= apply_wstrb(reg_control,      s_axil_wdata, s_axil_wstrb);
                    // STATUS (0x04) is read-only — writes ignored
                    ADDR_INPUT_ADDR:   reg_input_addr   <= apply_wstrb(reg_input_addr,   s_axil_wdata, s_axil_wstrb);
                    ADDR_WEIGHT_ADDR:  reg_weight_addr  <= apply_wstrb(reg_weight_addr,  s_axil_wdata, s_axil_wstrb);
                    ADDR_OUTPUT_ADDR:  reg_output_addr  <= apply_wstrb(reg_output_addr,  s_axil_wdata, s_axil_wstrb);
                    ADDR_INPUT_SIZE:   reg_input_size   <= apply_wstrb(reg_input_size,   s_axil_wdata, s_axil_wstrb);
                    ADDR_WEIGHT_SIZE:  reg_weight_size  <= apply_wstrb(reg_weight_size,  s_axil_wdata, s_axil_wstrb);
                    ADDR_OUTPUT_SIZE:  reg_output_size  <= apply_wstrb(reg_output_size,  s_axil_wdata, s_axil_wstrb);
                    ADDR_LAYER_CONFIG: reg_layer_config <= apply_wstrb(reg_layer_config, s_axil_wdata, s_axil_wstrb);
                    ADDR_CONV_CONFIG:  reg_conv_config  <= apply_wstrb(reg_conv_config,  s_axil_wdata, s_axil_wstrb);
                    ADDR_TENSOR_DIMS:  reg_tensor_dims  <= apply_wstrb(reg_tensor_dims,  s_axil_wdata, s_axil_wstrb);
                    ADDR_QUANT_PARAM:  reg_quant_param  <= apply_wstrb(reg_quant_param,  s_axil_wdata, s_axil_wstrb);
                    ADDR_START: begin
                        if (s_axil_wdata[0]) begin
                            reg_start_pulse <= 1'b1;
                        end
                    end
                    // IRQ_CLEAR handled in irq_pending block
                    // PERF_CYCLES, DMA_STATUS are read-only
                    default: ;
                endcase
            end
        end
    end

    //------------------------------------------------------------------------
    // AXI4-Lite read address channel
    //------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            s_axil_arready <= 1'b0;
        end else begin
            if (~s_axil_arready && s_axil_arvalid) begin
                s_axil_arready <= 1'b1;
            end else begin
                s_axil_arready <= 1'b0;
            end
        end
    end

    //------------------------------------------------------------------------
    // AXI4-Lite read data channel
    //------------------------------------------------------------------------
    reg [31:0] rdata_mux;

    always @(*) begin
        case (rd_addr)
            ADDR_CONTROL:      rdata_mux = reg_control;
            ADDR_STATUS:       rdata_mux = status_i;
            ADDR_INPUT_ADDR:   rdata_mux = reg_input_addr;
            ADDR_WEIGHT_ADDR:  rdata_mux = reg_weight_addr;
            ADDR_OUTPUT_ADDR:  rdata_mux = reg_output_addr;
            ADDR_INPUT_SIZE:   rdata_mux = reg_input_size;
            ADDR_WEIGHT_SIZE:  rdata_mux = reg_weight_size;
            ADDR_OUTPUT_SIZE:  rdata_mux = reg_output_size;
            ADDR_LAYER_CONFIG: rdata_mux = reg_layer_config;
            ADDR_CONV_CONFIG:  rdata_mux = reg_conv_config;
            ADDR_TENSOR_DIMS:  rdata_mux = reg_tensor_dims;
            ADDR_QUANT_PARAM:  rdata_mux = reg_quant_param;
            ADDR_START:        rdata_mux = 32'h0; // write-only
            ADDR_IRQ_CLEAR:    rdata_mux = 32'h0; // write-only
            ADDR_PERF_CYCLES:  rdata_mux = perf_cycles_i;
            ADDR_DMA_STATUS:   rdata_mux = dma_status_i;
            default:           rdata_mux = 32'h0;
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            s_axil_rdata  <= 32'h0;
            s_axil_rresp  <= 2'b00;
            s_axil_rvalid <= 1'b0;
        end else begin
            if (s_axil_arready && s_axil_arvalid && ~s_axil_rvalid) begin
                s_axil_rdata  <= rdata_mux;
                s_axil_rresp  <= 2'b00; // OKAY
                s_axil_rvalid <= 1'b1;
            end else if (s_axil_rvalid && s_axil_rready) begin
                s_axil_rvalid <= 1'b0;
            end
        end
    end

    //------------------------------------------------------------------------
    // IRQ logic
    // Set irq_pending on rising edge of status_i[1] (layer_done).
    // Clear when IRQ_CLEAR register is written with bit[0] = 1.
    //------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            irq_pending  <= 1'b0;
            layer_done_d <= 1'b0;
        end else begin
            layer_done_d <= status_i[1];

            // Clear on IRQ_CLEAR write
            if (wr_en && (wr_addr == ADDR_IRQ_CLEAR) && s_axil_wdata[0]) begin
                irq_pending <= 1'b0;
            end
            // Set on rising edge of layer_done
            else if (status_i[1] && ~layer_done_d) begin
                irq_pending <= 1'b1;
            end
        end
    end

    // Registered IRQ output: pending AND irq_enable
    always @(posedge clk) begin
        if (!rst_n) begin
            irq_npu_done_o <= 1'b0;
        end else begin
            irq_npu_done_o <= irq_pending & reg_control[2];
        end
    end

endmodule
