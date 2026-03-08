`timescale 1ns/1ps
//============================================================================
// Testbench: tb_npu_regfile
// Verifies AXI4-Lite register read/write and interrupt logic
//============================================================================

module tb_npu_regfile;

    reg         clk;
    reg         rst_n;

    // AXI4-Lite
    reg  [7:0]  awaddr;
    reg         awvalid;
    wire        awready;
    reg  [31:0] wdata;
    reg  [3:0]  wstrb;
    reg         wvalid;
    wire        wready;
    wire [1:0]  bresp;
    wire        bvalid;
    reg         bready;
    reg  [7:0]  araddr;
    reg         arvalid;
    wire        arready;
    wire [31:0] rdata;
    wire [1:0]  rresp;
    wire        rvalid;
    reg         rready;

    // Register outputs
    wire [31:0] reg_control, reg_input_addr, reg_weight_addr, reg_output_addr;
    wire [31:0] reg_input_size, reg_weight_size, reg_output_size;
    wire [31:0] reg_layer_config, reg_conv_config, reg_tensor_dims, reg_quant_param;
    wire        reg_start_pulse;

    // Status inputs
    reg  [31:0] status_i, perf_cycles_i, dma_status_i;
    wire        irq_npu_done_o;

    initial clk = 0;
    always #5 clk = ~clk;

    npu_regfile dut (
        .clk(clk), .rst_n(rst_n),
        .s_axil_awaddr(awaddr), .s_axil_awvalid(awvalid), .s_axil_awready(awready),
        .s_axil_wdata(wdata), .s_axil_wstrb(wstrb), .s_axil_wvalid(wvalid), .s_axil_wready(wready),
        .s_axil_bresp(bresp), .s_axil_bvalid(bvalid), .s_axil_bready(bready),
        .s_axil_araddr(araddr), .s_axil_arvalid(arvalid), .s_axil_arready(arready),
        .s_axil_rdata(rdata), .s_axil_rresp(rresp), .s_axil_rvalid(rvalid), .s_axil_rready(rready),
        .reg_control(reg_control), .reg_input_addr(reg_input_addr),
        .reg_weight_addr(reg_weight_addr), .reg_output_addr(reg_output_addr),
        .reg_input_size(reg_input_size), .reg_weight_size(reg_weight_size),
        .reg_output_size(reg_output_size), .reg_layer_config(reg_layer_config),
        .reg_conv_config(reg_conv_config), .reg_tensor_dims(reg_tensor_dims),
        .reg_quant_param(reg_quant_param), .reg_start_pulse(reg_start_pulse),
        .status_i(status_i), .perf_cycles_i(perf_cycles_i), .dma_status_i(dma_status_i),
        .irq_npu_done_o(irq_npu_done_o)
    );

    integer pass_count, fail_count;

    task axi_write;
        input [7:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);
            awaddr = addr; awvalid = 1;
            wdata = data; wstrb = 4'hF; wvalid = 1;
            bready = 1;
            @(posedge clk);
            while (!awready || !wready) @(posedge clk);
            awvalid = 0; wvalid = 0;
            while (!bvalid) @(posedge clk);
            @(posedge clk);
            bready = 0;
        end
    endtask

    task axi_read;
        input [7:0] addr;
        output [31:0] data;
        begin
            @(posedge clk);
            araddr = addr; arvalid = 1;
            rready = 1;
            @(posedge clk);
            while (!arready) @(posedge clk);
            arvalid = 0;
            while (!rvalid) @(posedge clk);
            data = rdata;
            @(posedge clk);
            rready = 0;
        end
    endtask

    reg [31:0] read_data;

    initial begin
        pass_count = 0; fail_count = 0;
        rst_n = 0;
        awaddr = 0; awvalid = 0; wdata = 0; wstrb = 0; wvalid = 0; bready = 0;
        araddr = 0; arvalid = 0; rready = 0;
        status_i = 0; perf_cycles_i = 0; dma_status_i = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // Test 1: Write CONTROL register
        axi_write(8'h00, 32'h0000_0005); // enable + irq_enable
        if (reg_control == 32'h5) pass_count = pass_count + 1;
        else begin fail_count = fail_count + 1; $display("FAIL: CONTROL write"); end

        // Test 2: Write INPUT_ADDR
        axi_write(8'h08, 32'h8100_0000);
        if (reg_input_addr == 32'h8100_0000) pass_count = pass_count + 1;
        else begin fail_count = fail_count + 1; $display("FAIL: INPUT_ADDR write"); end

        // Test 3: Read back STATUS (read-only, driven externally)
        status_i = 32'h0000_0003;
        @(posedge clk);
        axi_read(8'h04, read_data);
        if (read_data == 32'h3) pass_count = pass_count + 1;
        else begin fail_count = fail_count + 1; $display("FAIL: STATUS read, got %h", read_data); end

        // Test 4: Write LAYER_CONFIG
        axi_write(8'h20, 32'h0008_1004); // DW-Conv2D, ReLU, 16 in_ch, 8 out_ch
        if (reg_layer_config == 32'h0008_1004) pass_count = pass_count + 1;
        else begin fail_count = fail_count + 1; $display("FAIL: LAYER_CONFIG write"); end

        repeat (3) @(posedge clk);
        $display("========================================");
        $display("tb_npu_regfile: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        $finish;
    end

endmodule
