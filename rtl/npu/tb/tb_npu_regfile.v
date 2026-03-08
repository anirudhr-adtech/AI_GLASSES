`timescale 1ns/1ps
//============================================================================
// Testbench: tb_npu_regfile
// Verifies AXI4-Lite register read/write and interrupt logic
// Fixed for Verilator --timing: #1 sampling, hold valids through write cycle
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
    reg [31:0] read_data;

    // ---------------------------------------------------------------
    // AXI-Lite write sequence (inline, no task with disable)
    //
    // DUT behavior (npu_regfile):
    //   Cycle A: TB presents awvalid+wvalid
    //   Cycle B: DUT NBA sets awready<=1, wready<=1
    //   Cycle C: DUT has awready=1 from NBA; wr_en=awready&awvalid&wready&wvalid
    //            fires if TB STILL holds awvalid+wvalid. Write happens. bvalid<=1.
    //   Cycle D: TB sees bvalid, deasserts bready.
    //
    // KEY: TB must hold awvalid/wvalid for one full cycle PAST seeing awready.
    // ---------------------------------------------------------------

    initial begin
        pass_count = 0; fail_count = 0;
        rst_n = 0;
        awaddr = 0; awvalid = 0; wdata = 0; wstrb = 0; wvalid = 0; bready = 0;
        araddr = 0; arvalid = 0; rready = 0;
        status_i = 0; perf_cycles_i = 0; dma_status_i = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // ============================================================
        // Test 1: Write CONTROL register (0x00) = 0x00000005
        // ============================================================
        begin : wr1
            integer countdown;
            // Assert AW + W
            @(posedge clk); #1;
            awaddr = 8'h00; awvalid = 1;
            wdata = 32'h0000_0005; wstrb = 4'hF; wvalid = 1;
            bready = 1;
            // Wait for awready (DUT asserts it one cycle after seeing awvalid+wvalid)
            countdown = 100;
            while (countdown > 0) begin
                @(posedge clk); #1;
                if (awready) countdown = 0;
                else countdown = countdown - 1;
            end
            // HOLD valids for one more posedge so wr_en fires
            @(posedge clk); #1;
            awvalid = 0; wvalid = 0;
            // Wait for bvalid
            countdown = 100;
            while (countdown > 0) begin
                @(posedge clk); #1;
                if (bvalid) countdown = 0;
                else countdown = countdown - 1;
            end
            @(posedge clk); #1;
            bready = 0;
            // Check register value (allow one more cycle for propagation)
            @(posedge clk); #1;
            if (reg_control == 32'h5) pass_count = pass_count + 1;
            else begin fail_count = fail_count + 1; $display("FAIL: CONTROL write, got %h", reg_control); end
        end

        // ============================================================
        // Test 2: Write INPUT_ADDR (0x08) = 0x81000000
        // ============================================================
        begin : wr2
            integer countdown;
            @(posedge clk); #1;
            awaddr = 8'h08; awvalid = 1;
            wdata = 32'h8100_0000; wstrb = 4'hF; wvalid = 1;
            bready = 1;
            countdown = 100;
            while (countdown > 0) begin
                @(posedge clk); #1;
                if (awready) countdown = 0;
                else countdown = countdown - 1;
            end
            @(posedge clk); #1;
            awvalid = 0; wvalid = 0;
            countdown = 100;
            while (countdown > 0) begin
                @(posedge clk); #1;
                if (bvalid) countdown = 0;
                else countdown = countdown - 1;
            end
            @(posedge clk); #1;
            bready = 0;
            @(posedge clk); #1;
            if (reg_input_addr == 32'h8100_0000) pass_count = pass_count + 1;
            else begin fail_count = fail_count + 1; $display("FAIL: INPUT_ADDR write, got %h", reg_input_addr); end
        end

        // ============================================================
        // Test 3: Read STATUS (0x04) - read-only, driven by status_i
        // ============================================================
        begin : rd3
            integer countdown;
            status_i = 32'h0000_0003;
            repeat (2) @(posedge clk);
            // status_i should be stable at 0x3
            // Assert AR
            @(posedge clk); #1;
            araddr = 8'h04; arvalid = 1; rready = 1;
            // Wait for arready, then hold arvalid one more cycle for rdata sampling
            countdown = 100;
            while (countdown > 0) begin
                @(posedge clk); #1;
                if (arready) countdown = 0;
                else countdown = countdown - 1;
            end
            // Hold arvalid one more cycle: at next posedge, DUT registers rdata
            @(posedge clk); #1;
            arvalid = 0;
            // rvalid should now be 1 (DUT set it this cycle via NBA)
            // Capture rdata immediately -- rvalid is only high for 1 cycle
            // because rready is already asserted, causing rvalid to clear next cycle
            if (rvalid) begin
                read_data = rdata;
            end else begin
                // Wait one more cycle in case of extra pipeline delay
                countdown = 100;
                while (countdown > 0) begin
                    @(posedge clk); #1;
                    if (rvalid) begin
                        read_data = rdata;
                        countdown = 0;
                    end else
                        countdown = countdown - 1;
                end
            end
            @(posedge clk); #1;
            rready = 0;
            if (read_data == 32'h3) pass_count = pass_count + 1;
            else begin fail_count = fail_count + 1; $display("FAIL: STATUS read, got %h", read_data); end
        end

        // ============================================================
        // Test 4: Write LAYER_CONFIG (0x20) = 0x00081004
        // ============================================================
        begin : wr4
            integer countdown;
            @(posedge clk); #1;
            awaddr = 8'h20; awvalid = 1;
            wdata = 32'h0008_1004; wstrb = 4'hF; wvalid = 1;
            bready = 1;
            countdown = 100;
            while (countdown > 0) begin
                @(posedge clk); #1;
                if (awready) countdown = 0;
                else countdown = countdown - 1;
            end
            @(posedge clk); #1;
            awvalid = 0; wvalid = 0;
            countdown = 100;
            while (countdown > 0) begin
                @(posedge clk); #1;
                if (bvalid) countdown = 0;
                else countdown = countdown - 1;
            end
            @(posedge clk); #1;
            bready = 0;
            @(posedge clk); #1;
            if (reg_layer_config == 32'h0008_1004) pass_count = pass_count + 1;
            else begin fail_count = fail_count + 1; $display("FAIL: LAYER_CONFIG write, got %h", reg_layer_config); end
        end

        repeat (3) @(posedge clk);
        $display("========================================");
        $display("tb_npu_regfile: %0d PASSED, %0d FAILED", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        $display("========================================");
        $finish;
    end

    // Global watchdog
    initial begin
        #200000;
        $display("FAIL: Global watchdog timeout");
        $finish;
    end

endmodule
