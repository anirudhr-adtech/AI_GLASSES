`timescale 1ns/1ps
//============================================================================
// Testbench: tb_npu_controller
// Basic FSM state progression test
//============================================================================

module tb_npu_controller;

    reg         clk;
    reg         rst_n;

    // From regfile
    reg  [31:0] reg_control;
    reg  [31:0] reg_input_addr;
    reg  [31:0] reg_weight_addr;
    reg  [31:0] reg_output_addr;
    reg  [31:0] reg_input_size;
    reg  [31:0] reg_weight_size;
    reg  [31:0] reg_output_size;
    reg  [31:0] reg_layer_config;
    reg  [31:0] reg_conv_config;
    reg  [31:0] reg_tensor_dims;
    reg  [31:0] reg_quant_param;
    reg         reg_start_pulse;

    // Status outputs
    wire [31:0] status_o;
    wire [31:0] perf_cycles_o;
    wire [31:0] dma_status_o;

    // DMA control
    wire        weight_dma_start;
    wire [31:0] weight_dma_src_addr;
    wire [31:0] weight_dma_xfer_len;
    reg         weight_dma_done;

    wire        act_dma_start;
    wire [31:0] act_dma_src_addr;
    wire [31:0] act_dma_dst_addr;
    wire [31:0] act_dma_xfer_len;
    wire        act_dma_direction;
    reg         act_dma_done;

    // MAC control
    wire        mac_en;
    wire        mac_clear_acc;
    wire [1:0]  mac_mode;
    reg         mac_acc_valid;

    // Buffer control
    wire        wbuf_rd_en;
    wire [14:0] wbuf_rd_addr;
    wire        abuf_rd_en;
    wire [14:0] abuf_rd_addr;

    // Quantize/activation
    wire        quant_en;
    wire [7:0]  quant_shift;
    wire [15:0] quant_scale;
    wire        act_en;
    wire [1:0]  act_type;

    initial clk = 0;
    always #5 clk = ~clk;

    npu_controller dut (
        .clk(clk), .rst_n(rst_n),
        .reg_control(reg_control), .reg_input_addr(reg_input_addr),
        .reg_weight_addr(reg_weight_addr), .reg_output_addr(reg_output_addr),
        .reg_input_size(reg_input_size), .reg_weight_size(reg_weight_size),
        .reg_output_size(reg_output_size), .reg_layer_config(reg_layer_config),
        .reg_conv_config(reg_conv_config), .reg_tensor_dims(reg_tensor_dims),
        .reg_quant_param(reg_quant_param), .reg_start_pulse(reg_start_pulse),
        .status_o(status_o), .perf_cycles_o(perf_cycles_o), .dma_status_o(dma_status_o),
        .weight_dma_start(weight_dma_start), .weight_dma_src_addr(weight_dma_src_addr),
        .weight_dma_xfer_len(weight_dma_xfer_len), .weight_dma_done(weight_dma_done),
        .act_dma_start(act_dma_start), .act_dma_src_addr(act_dma_src_addr),
        .act_dma_dst_addr(act_dma_dst_addr), .act_dma_xfer_len(act_dma_xfer_len),
        .act_dma_direction(act_dma_direction), .act_dma_done(act_dma_done),
        .mac_en(mac_en), .mac_clear_acc(mac_clear_acc), .mac_mode(mac_mode),
        .mac_acc_valid(mac_acc_valid),
        .wbuf_rd_en(wbuf_rd_en), .wbuf_rd_addr(wbuf_rd_addr),
        .abuf_rd_en(abuf_rd_en), .abuf_rd_addr(abuf_rd_addr),
        .quant_en(quant_en), .quant_shift(quant_shift), .quant_scale(quant_scale),
        .act_en(act_en), .act_type(act_type)
    );

    initial begin
        rst_n = 0;
        reg_control = 0; reg_input_addr = 0; reg_weight_addr = 0;
        reg_output_addr = 0; reg_input_size = 0; reg_weight_size = 0;
        reg_output_size = 0; reg_layer_config = 0; reg_conv_config = 0;
        reg_tensor_dims = 0; reg_quant_param = 0; reg_start_pulse = 0;
        weight_dma_done = 0; act_dma_done = 0; mac_acc_valid = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // Configure for a simple FC layer
        reg_control     = 32'h0000_0005; // enable + irq_enable
        reg_input_addr  = 32'h8100_0000;
        reg_weight_addr = 32'h8000_0000;
        reg_output_addr = 32'h8300_0000;
        reg_input_size  = 32'd64;
        reg_weight_size = 32'd512;
        reg_output_size = 32'd8;
        reg_layer_config= 32'h0008_0801; // FC, no act, 8 in_ch, 8 out_ch
        reg_conv_config = 32'h0000_0101; // kernel=1, stride=1
        reg_tensor_dims = 32'h0001_0001; // 1x1 in, 1x1 out
        reg_quant_param = 32'h0004_0001; // shift=4, scale=1
        @(posedge clk);

        // Start
        reg_start_pulse = 1;
        @(posedge clk);
        reg_start_pulse = 0;

        // Wait for DMA prefetch
        repeat (10) @(posedge clk);
        $display("Status after start: busy=%b", status_o[0]);

        // Simulate DMA done
        weight_dma_done = 1; act_dma_done = 1;
        @(posedge clk);
        weight_dma_done = 0; act_dma_done = 0;

        // Wait for MAC compute
        repeat (20) @(posedge clk);

        // Simulate MAC done
        mac_acc_valid = 1;
        @(posedge clk);
        mac_acc_valid = 0;

        // Wait for quantize + activate
        repeat (20) @(posedge clk);

        // Simulate output DMA done
        act_dma_done = 1;
        @(posedge clk);
        act_dma_done = 0;

        // Wait for done state
        repeat (10) @(posedge clk);
        $display("Status after completion: busy=%b, done=%b", status_o[0], status_o[1]);
        $display("Perf cycles: %0d", perf_cycles_o);

        repeat (3) @(posedge clk);
        $display("========================================");
        $display("tb_npu_controller: FSM test complete");
        $display("========================================");
        $finish;
    end

endmodule
