`timescale 1ns / 1ps
//============================================================================
// spi_master.v
// AI_GLASSES — SPI Master
// Top-level SPI master peripheral.
// Instantiates: spi_regfile, spi_master_fsm, spi_tx_fifo, spi_rx_fifo
//============================================================================

module spi_master (
    input  wire        clk_i,
    input  wire        rst_ni,

    // AXI4-Lite slave interface
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

    // SPI bus
    output wire        spi_sclk_o,
    output wire        spi_mosi_o,
    input  wire        spi_miso_i,
    output wire        spi_cs_n_o,

    // Interrupt
    output reg         irq_spi_o
);

    // Internal wires
    wire [7:0]  reg_div;
    wire        reg_cpol, reg_cpha, reg_auto_cs;
    wire        reg_cs_n;
    wire        reg_irq_en;

    // TX FIFO signals
    wire [7:0]  tx_fifo_wdata;
    wire        tx_fifo_wr_en;
    wire [7:0]  tx_fifo_rdata;
    wire        tx_fifo_rd_en;
    wire        tx_fifo_full, tx_fifo_empty;
    wire [4:0]  tx_fifo_count;

    // RX FIFO signals
    wire [7:0]  rx_fifo_wdata;
    wire        rx_fifo_wr_en;
    wire [7:0]  rx_fifo_rdata;
    wire        rx_fifo_rd_en;
    wire        rx_fifo_full, rx_fifo_empty;
    wire [4:0]  rx_fifo_count;

    // FSM signals
    wire        fsm_busy;
    wire        fsm_tx_ready;
    wire [7:0]  fsm_rx_data;
    wire        fsm_rx_valid;
    wire        fsm_cs_n;

    // Register file
    spi_regfile u_regfile (
        .clk             (clk_i),
        .rst_n           (rst_ni),
        .s_axil_awaddr   (s_axi_lite_awaddr),
        .s_axil_awvalid  (s_axi_lite_awvalid),
        .s_axil_awready  (s_axi_lite_awready),
        .s_axil_wdata    (s_axi_lite_wdata),
        .s_axil_wstrb    (s_axi_lite_wstrb),
        .s_axil_wvalid   (s_axi_lite_wvalid),
        .s_axil_wready   (s_axi_lite_wready),
        .s_axil_bresp    (s_axi_lite_bresp),
        .s_axil_bvalid   (s_axi_lite_bvalid),
        .s_axil_bready   (s_axi_lite_bready),
        .s_axil_araddr   (s_axi_lite_araddr),
        .s_axil_arvalid  (s_axi_lite_arvalid),
        .s_axil_arready  (s_axi_lite_arready),
        .s_axil_rdata    (s_axi_lite_rdata),
        .s_axil_rresp    (s_axi_lite_rresp),
        .s_axil_rvalid   (s_axi_lite_rvalid),
        .s_axil_rready   (s_axi_lite_rready),
        .reg_div         (reg_div),
        .reg_cpol        (reg_cpol),
        .reg_cpha        (reg_cpha),
        .reg_auto_cs     (reg_auto_cs),
        .reg_cs_n        (reg_cs_n),
        .reg_irq_en      (reg_irq_en),
        .tx_fifo_wdata   (tx_fifo_wdata),
        .tx_fifo_wr_en   (tx_fifo_wr_en),
        .rx_fifo_rdata   (rx_fifo_rdata),
        .rx_fifo_rd_en   (rx_fifo_rd_en),
        .status_busy     (fsm_busy),
        .tx_fifo_full    (tx_fifo_full),
        .tx_fifo_empty   (tx_fifo_empty),
        .rx_fifo_full    (rx_fifo_full),
        .rx_fifo_empty   (rx_fifo_empty),
        .tx_fifo_count   (tx_fifo_count),
        .rx_fifo_count   (rx_fifo_count)
    );

    // TX FIFO
    spi_tx_fifo u_tx_fifo (
        .clk       (clk_i),
        .rst_n     (rst_ni),
        .wr_data_i (tx_fifo_wdata),
        .wr_en_i   (tx_fifo_wr_en),
        .rd_data_o (tx_fifo_rdata),
        .rd_en_i   (fsm_tx_ready),
        .full_o    (tx_fifo_full),
        .empty_o   (tx_fifo_empty),
        .count_o   (tx_fifo_count)
    );

    // RX FIFO
    spi_rx_fifo u_rx_fifo (
        .clk       (clk_i),
        .rst_n     (rst_ni),
        .wr_data_i (fsm_rx_data),
        .wr_en_i   (fsm_rx_valid),
        .rd_data_o (rx_fifo_rdata),
        .rd_en_i   (rx_fifo_rd_en),
        .full_o    (rx_fifo_full),
        .empty_o   (rx_fifo_empty),
        .count_o   (rx_fifo_count)
    );

    // FSM
    spi_master_fsm u_fsm (
        .clk         (clk_i),
        .rst_n       (rst_ni),
        .tx_data_i   (tx_fifo_rdata),
        .tx_valid_i  (~tx_fifo_empty),
        .tx_ready_o  (fsm_tx_ready),
        .rx_data_o   (fsm_rx_data),
        .rx_valid_o  (fsm_rx_valid),
        .div_i       (reg_div),
        .cpol_i      (reg_cpol),
        .cpha_i      (reg_cpha),
        .auto_cs_i   (reg_auto_cs),
        .busy_o      (fsm_busy),
        .spi_sclk_o  (spi_sclk_o),
        .spi_mosi_o  (spi_mosi_o),
        .spi_miso_i  (spi_miso_i),
        .spi_cs_n_o  (fsm_cs_n)
    );

    // CS mux: auto_cs from FSM or manual from register
    assign spi_cs_n_o = reg_auto_cs ? fsm_cs_n : reg_cs_n;

    // Interrupt: assert when FSM goes not-busy (transfer done) and IRQ enabled
    reg busy_prev;
    always @(posedge clk_i) begin
        if (!rst_ni) begin
            irq_spi_o <= 1'b0;
            busy_prev <= 1'b0;
        end else begin
            busy_prev <= fsm_busy;
            if (busy_prev && !fsm_busy && reg_irq_en)
                irq_spi_o <= 1'b1;
            else
                irq_spi_o <= 1'b0;
        end
    end

endmodule
