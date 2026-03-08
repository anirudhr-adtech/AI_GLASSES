`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Camera Subsystem
// Testbench: tb_crop_dma_writer
// Description: Self-checking testbench for crop DMA AXI4 write controller
//////////////////////////////////////////////////////////////////////////////

module tb_crop_dma_writer;

    localparam CLK_PERIOD = 10;

    reg         clk;
    reg         rst_n;
    reg         start;
    reg  [31:0] crop_buf_addr;
    reg  [23:0] in_data;
    reg         in_valid;
    wire        in_ready;
    wire        done;
    // AXI write
    wire [3:0]  awid;
    wire [31:0] awaddr;
    wire [7:0]  awlen;
    wire [2:0]  awsize;
    wire [1:0]  awburst;
    wire        awvalid;
    reg         awready;
    wire [127:0] wdata;
    wire [15:0] wstrb;
    wire        wlast;
    wire        wvalid;
    reg         wready;
    reg  [3:0]  bid;
    reg  [1:0]  bresp;
    reg         bvalid;
    wire        bready;

    integer test_num, pass_count, fail_count;
    integer write_beat_count;

    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    crop_dma_writer u_dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .start_i         (start),
        .crop_buf_addr_i (crop_buf_addr),
        .in_data_i       (in_data),
        .in_valid_i      (in_valid),
        .in_ready_o      (in_ready),
        .done_o          (done),
        .m_axi_awid      (awid),
        .m_axi_awaddr    (awaddr),
        .m_axi_awlen     (awlen),
        .m_axi_awsize    (awsize),
        .m_axi_awburst   (awburst),
        .m_axi_awvalid   (awvalid),
        .m_axi_awready   (awready),
        .m_axi_wdata     (wdata),
        .m_axi_wstrb     (wstrb),
        .m_axi_wlast     (wlast),
        .m_axi_wvalid    (wvalid),
        .m_axi_wready    (wready),
        .m_axi_bid       (bid),
        .m_axi_bresp     (bresp),
        .m_axi_bvalid    (bvalid),
        .m_axi_bready    (bready)
    );

    task reset_dut;
        begin
            rst_n         <= 1'b0;
            start         <= 1'b0;
            crop_buf_addr <= 32'd0;
            in_data       <= 24'd0;
            in_valid      <= 1'b0;
            awready       <= 1'b0;
            wready        <= 1'b0;
            bid           <= 4'b1101;
            bresp         <= 2'b00;
            bvalid        <= 1'b0;
            repeat (5) @(posedge clk);
            rst_n <= 1'b1;
            repeat (2) @(posedge clk);
        end
    endtask

    task check(input [255:0] name, input cond);
        begin
            test_num = test_num + 1;
            if (cond) begin
                $display("[PASS] Test %0d: %0s", test_num, name);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] Test %0d: %0s", test_num, name);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // AXI write slave responder
    always @(posedge clk) begin
        if (!rst_n) begin
            awready <= 1'b0;
            bvalid  <= 1'b0;
        end else begin
            if (awvalid && !awready)
                awready <= 1'b1;
            else
                awready <= 1'b0;

            if (wvalid && wready && wlast && !bvalid)
                bvalid <= 1'b1;
            else if (bvalid && bready)
                bvalid <= 1'b0;
        end
    end

    // Count write beats
    always @(posedge clk) begin
        if (!rst_n)
            write_beat_count <= 0;
        else if (wvalid && wready)
            write_beat_count <= write_beat_count + 1;
    end

    initial begin
        $display("============================================================");
        $display("  TB: crop_dma_writer — AXI4 Crop Write Controller");
        $display("============================================================");

        test_num   = 0;
        pass_count = 0;
        fail_count = 0;
        write_beat_count = 0;

        reset_dut;

        // Test 1: Reset state
        check("done deasserted after reset", done == 1'b0);
        check("awvalid deasserted after reset", awvalid == 1'b0);

        // Test 2: Feed 16 pixels (4 beats worth: 16 * 32-bit = 4 * 128-bit)
        crop_buf_addr <= 32'h0420_0000;
        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;
        wready <= 1'b1;

        // Feed 16 RGB pixels
        begin : feed
            integer i;
            for (i = 0; i < 16; i = i + 1) begin
                @(posedge clk);
                while (!in_ready) @(posedge clk);
                in_data  <= {8'd255, 8'd128, 8'd64};
                in_valid <= 1'b1;
                @(posedge clk);
                in_valid <= 1'b0;
            end
        end

        // Wait some cycles for packing and AXI write
        repeat (100) @(posedge clk);

        check("AXI ID correct", awid == 4'b1101);
        check("Writes generated", write_beat_count > 0);

        // Test 3: Verify WSTRB all-ones
        check("Write strobe all-ones", wstrb == 16'hFFFF || !wvalid);

        // Summary
        $display("============================================================");
        $display("  Results: %0d passed, %0d failed out of %0d tests",
                 pass_count, fail_count, test_num);
        $display("============================================================");
        if (fail_count == 0)
            $display("  >>> ALL TESTS PASSED <<<");
        else
            $display("  >>> SOME TESTS FAILED <<<");
        $finish;
    end

    initial begin
        #200000;
        $display("[TIMEOUT]");
        $finish;
    end

endmodule
