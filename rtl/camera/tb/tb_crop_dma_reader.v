`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Camera Subsystem
// Testbench: tb_crop_dma_reader
// Description: Self-checking testbench for crop DMA AXI4 read controller
//////////////////////////////////////////////////////////////////////////////

module tb_crop_dma_reader;

    localparam CLK_PERIOD = 10;

    // DUT signals
    reg         clk;
    reg         rst_n;
    reg         start;
    reg  [31:0] raw_frame_addr;
    reg  [15:0] frame_stride;
    reg  [9:0]  crop_x, crop_y, crop_w, crop_h;
    wire        done;
    wire [127:0] out_data;
    wire        out_valid;
    reg         out_ready;
    // AXI read
    wire [3:0]  arid;
    wire [31:0] araddr;
    wire [7:0]  arlen;
    wire [2:0]  arsize;
    wire [1:0]  arburst;
    wire        arvalid;
    reg         arready;
    reg  [3:0]  rid;
    reg  [127:0] rdata;
    reg  [1:0]  rresp;
    reg         rlast;
    reg         rvalid;
    wire        rready;

    // Test tracking
    integer test_num, pass_count, fail_count;
    integer row_count;
    reg [31:0] captured_araddr;

    // Clock
    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // DUT
    crop_dma_reader u_dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .start_i          (start),
        .raw_frame_addr_i (raw_frame_addr),
        .frame_stride_i   (frame_stride),
        .crop_x_i         (crop_x),
        .crop_y_i         (crop_y),
        .crop_w_i         (crop_w),
        .crop_h_i         (crop_h),
        .done_o           (done),
        .out_data_o       (out_data),
        .out_valid_o      (out_valid),
        .out_ready_i      (out_ready),
        .m_axi_arid       (arid),
        .m_axi_araddr     (araddr),
        .m_axi_arlen      (arlen),
        .m_axi_arsize     (arsize),
        .m_axi_arburst    (arburst),
        .m_axi_arvalid    (arvalid),
        .m_axi_arready    (arready),
        .m_axi_rid        (rid),
        .m_axi_rdata      (rdata),
        .m_axi_rresp      (rresp),
        .m_axi_rlast      (rlast),
        .m_axi_rvalid     (rvalid),
        .m_axi_rready     (rready)
    );

    // Tasks
    task reset_dut;
        begin
            rst_n          <= 1'b0;
            start          <= 1'b0;
            raw_frame_addr <= 32'd0;
            frame_stride   <= 16'd0;
            crop_x         <= 10'd0;
            crop_y         <= 10'd0;
            crop_w         <= 10'd0;
            crop_h         <= 10'd0;
            out_ready      <= 1'b1;
            arready        <= 1'b0;
            rid            <= 4'b1101;
            rdata          <= 128'd0;
            rresp          <= 2'b00;
            rlast          <= 1'b0;
            rvalid         <= 1'b0;
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

    // AXI read slave model: accept AR, return rdata
    reg [7:0] ar_beats_remaining;
    reg       ar_active;

    always @(posedge clk) begin
        if (!rst_n) begin
            arready           <= 1'b0;
            rvalid            <= 1'b0;
            rlast             <= 1'b0;
            ar_beats_remaining <= 8'd0;
            ar_active         <= 1'b0;
        end else begin
            // Accept AR
            if (arvalid && !ar_active) begin
                arready           <= 1'b1;
                ar_beats_remaining <= arlen;
                ar_active         <= 1'b1;
            end else begin
                arready <= 1'b0;
            end

            // Serve read data
            if (ar_active && (!rvalid || rready)) begin
                rdata  <= {4{row_count[31:0]}};
                rvalid <= 1'b1;
                rlast  <= (ar_beats_remaining == 8'd0);
                if (ar_beats_remaining == 8'd0 && rready) begin
                    ar_active <= 1'b0;
                    rvalid    <= 1'b0;
                    rlast     <= 1'b0;
                end else if (rready) begin
                    ar_beats_remaining <= ar_beats_remaining - 8'd1;
                end
            end
        end
    end

    // Main test
    initial begin
        $display("============================================================");
        $display("  TB: crop_dma_reader — AXI4 ROI Read Controller");
        $display("============================================================");

        test_num   = 0;
        pass_count = 0;
        fail_count = 0;
        row_count  = 0;

        reset_dut;

        // Test 1: Reset state
        check("done deasserted after reset", done == 1'b0);
        check("arvalid deasserted after reset", arvalid == 1'b0);

        // Test 2: Read a small 4x4 ROI (4 pixels wide = 16 bytes = 1 beat/row)
        raw_frame_addr <= 32'h0402_0000;
        frame_stride   <= 16'd2560; // 640 * 4 bytes
        crop_x         <= 10'd10;
        crop_y         <= 10'd20;
        crop_w         <= 10'd4;    // 4 pixels = 16 bytes = 1 beat
        crop_h         <= 10'd4;    // 4 rows
        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        // Wait for first AR
        repeat (20) begin
            @(posedge clk);
            if (arvalid) begin
                captured_araddr = araddr;
            end
        end

        check("AXI ID correct", arid == 4'b1101);
        check("Burst type INCR", arburst == 2'b01);

        // Wait for completion
        repeat (200) begin
            @(posedge clk);
            if (done) row_count = row_count + 1;
        end

        // Test 3: Verify done asserts
        // Give extra time
        repeat (100) @(posedge clk);
        check("Read completed (done asserted at least once)", row_count > 0 || done);

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
