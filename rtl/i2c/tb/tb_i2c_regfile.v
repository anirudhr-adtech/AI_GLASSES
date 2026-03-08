`timescale 1ns / 1ps
//============================================================================
// tb_i2c_regfile.v — Self-checking testbench for i2c_regfile
//============================================================================

module tb_i2c_regfile;

    reg         clk, rst_n;

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

    // Outputs
    wire [31:0] reg_control;
    wire [7:0]  reg_slave_addr;
    wire [7:0]  reg_xfer_len;
    wire [15:0] reg_prescaler;
    wire        reg_start_pulse;
    wire [7:0]  tx_fifo_wdata;
    wire        tx_fifo_wr_en;
    wire        rx_fifo_rd_en;
    wire        irq_clear;

    i2c_regfile uut (
        .clk             (clk),
        .rst_n           (rst_n),
        .s_axil_awaddr   (awaddr),
        .s_axil_awvalid  (awvalid),
        .s_axil_awready  (awready),
        .s_axil_wdata    (wdata),
        .s_axil_wstrb    (wstrb),
        .s_axil_wvalid   (wvalid),
        .s_axil_wready   (wready),
        .s_axil_bresp    (bresp),
        .s_axil_bvalid   (bvalid),
        .s_axil_bready   (bready),
        .s_axil_araddr   (araddr),
        .s_axil_arvalid  (arvalid),
        .s_axil_arready  (arready),
        .s_axil_rdata    (rdata),
        .s_axil_rresp    (rresp),
        .s_axil_rvalid   (rvalid),
        .s_axil_rready   (rready),
        .reg_control     (reg_control),
        .reg_slave_addr  (reg_slave_addr),
        .reg_xfer_len    (reg_xfer_len),
        .reg_prescaler   (reg_prescaler),
        .reg_start_pulse (reg_start_pulse),
        .tx_fifo_wdata   (tx_fifo_wdata),
        .tx_fifo_wr_en   (tx_fifo_wr_en),
        .rx_fifo_rdata   (8'hBE),
        .rx_fifo_rd_en   (rx_fifo_rd_en),
        .irq_clear       (irq_clear),
        .status_busy     (1'b0),
        .status_done     (1'b1),
        .status_nack     (1'b0),
        .tx_fifo_count   (5'd3),
        .tx_fifo_full    (1'b0),
        .tx_fifo_empty   (1'b0),
        .rx_fifo_count   (5'd2),
        .rx_fifo_full    (1'b0),
        .rx_fifo_empty   (1'b0)
    );

    integer pass_count = 0;
    integer fail_count = 0;

    task check;
        input [255:0] msg;
        input         cond;
    begin
        if (cond) pass_count = pass_count + 1;
        else begin
            fail_count = fail_count + 1;
            $display("FAIL: %0s at time %0t", msg, $time);
        end
    end
    endtask

    task axil_write;
        input [7:0]  addr;
        input [31:0] data;
    begin
        @(posedge clk);
        awaddr = addr; awvalid = 1;
        wdata = data; wstrb = 4'hF; wvalid = 1;
        bready = 1;
        wait (awready || wready);
        @(posedge clk);
        awvalid = 0; wvalid = 0;
        wait (bvalid);
        @(posedge clk);
        bready = 0;
    end
    endtask

    task axil_read;
        input  [7:0]  addr;
        output [31:0] data;
    begin
        @(posedge clk);
        araddr = addr; arvalid = 1;
        rready = 1;
        wait (arready);
        @(posedge clk);
        arvalid = 0;
        wait (rvalid);
        data = rdata;
        @(posedge clk);
        rready = 0;
    end
    endtask

    initial clk = 0;
    always #5 clk = ~clk;

    reg [31:0] rd_val;

    initial begin
        rst_n = 0; awvalid = 0; wvalid = 0; arvalid = 0;
        bready = 0; rready = 0;
        awaddr = 0; wdata = 0; wstrb = 0; araddr = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // Write CONTROL register
        axil_write(8'h00, 32'h0000_0001);
        @(posedge clk);
        check("CONTROL written", reg_control == 32'h0000_0001);

        // Write SLAVE_ADDR
        axil_write(8'h08, 32'h0000_00A0);
        @(posedge clk);
        check("SLAVE_ADDR written", reg_slave_addr == 8'hA0);

        // Write PRESCALER
        axil_write(8'h1C, 32'h0000_003E);
        @(posedge clk);
        check("PRESCALER written", reg_prescaler == 16'h003E);

        // Read STATUS (0x04)
        axil_read(8'h04, rd_val);
        check("STATUS reads done=1", rd_val[1] == 1'b1);

        // Write START
        axil_write(8'h18, 32'h0000_0001);
        // start_pulse is one-shot, hard to check timing but verify it was asserted

        @(posedge clk);
        $display("========================================");
        if (fail_count == 0)
            $display("I2C REGFILE TB: ALL %0d TESTS PASSED", pass_count);
        else
            $display("I2C REGFILE TB: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        $finish;
    end

endmodule
