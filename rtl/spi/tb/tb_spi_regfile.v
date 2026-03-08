`timescale 1ns / 1ps
//============================================================================
// tb_spi_regfile.v — Self-checking testbench for spi_regfile
//============================================================================

module tb_spi_regfile;

    reg         clk, rst_n;
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

    wire [7:0]  reg_div;
    wire        reg_cpol, reg_cpha, reg_auto_cs, reg_cs_n, reg_irq_en;
    wire [7:0]  tx_fifo_wdata;
    wire        tx_fifo_wr_en;
    wire        rx_fifo_rd_en;

    spi_regfile uut (
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
        .reg_div         (reg_div),
        .reg_cpol        (reg_cpol),
        .reg_cpha        (reg_cpha),
        .reg_auto_cs     (reg_auto_cs),
        .reg_cs_n        (reg_cs_n),
        .reg_irq_en      (reg_irq_en),
        .tx_fifo_wdata   (tx_fifo_wdata),
        .tx_fifo_wr_en   (tx_fifo_wr_en),
        .rx_fifo_rdata   (8'hDE),
        .rx_fifo_rd_en   (rx_fifo_rd_en),
        .status_busy     (1'b1),
        .tx_fifo_full    (1'b0),
        .tx_fifo_empty   (1'b0),
        .rx_fifo_full    (1'b0),
        .rx_fifo_empty   (1'b0),
        .tx_fifo_count   (5'd5),
        .rx_fifo_count   (5'd3)
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
        araddr = addr; arvalid = 1; rready = 1;
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

        // Check defaults
        check("default div=4", reg_div == 8'd4);
        check("default cpol=0", reg_cpol == 1'b0);
        check("default auto_cs=1", reg_auto_cs == 1'b1);

        // Write CONFIG (0x0C): div=9, cpol=1, cpha=1, auto_cs=0
        axil_write(8'h0C, 32'h00000309);
        @(posedge clk);
        check("div written", reg_div == 8'd9);
        check("cpol written", reg_cpol == 1'b1);
        check("cpha written", reg_cpha == 1'b1);
        check("auto_cs written", reg_auto_cs == 1'b0);

        // Read STATUS (0x08)
        axil_read(8'h08, rd_val);
        check("status busy bit", rd_val[0] == 1'b1);

        // Write TXDATA (0x00)
        axil_write(8'h00, 32'h000000AB);
        @(posedge clk);
        check("TX FIFO write data", tx_fifo_wdata == 8'hAB);

        // Read TX_FIFO count (0x18)
        axil_read(8'h18, rd_val);
        check("TX FIFO count", rd_val[4:0] == 5'd5);

        // Read RX_FIFO count (0x1C)
        axil_read(8'h1C, rd_val);
        check("RX FIFO count", rd_val[4:0] == 5'd3);

        $display("========================================");
        if (fail_count == 0)
            $display("SPI REGFILE TB: ALL %0d TESTS PASSED", pass_count);
        else
            $display("SPI REGFILE TB: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        $finish;
    end

endmodule
