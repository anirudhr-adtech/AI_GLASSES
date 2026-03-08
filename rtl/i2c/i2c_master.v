`timescale 1ns / 1ps
//============================================================================
// i2c_master.v
// AI_GLASSES — I2C Master
// Top-level I2C master peripheral.
// Instantiates: i2c_regfile, i2c_master_fsm, i2c_tx_fifo, i2c_rx_fifo
//============================================================================

module i2c_master (
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

    // I2C bus (open-drain)
    output wire        i2c_scl_o,
    output wire        i2c_scl_oe_o,
    input  wire        i2c_scl_i,
    output wire        i2c_sda_o,
    output wire        i2c_sda_oe_o,
    input  wire        i2c_sda_i,

    // Interrupt
    output reg         irq_i2c_done_o
);

    // Internal wires — regfile to FSM
    wire [31:0] reg_control;
    wire [7:0]  reg_slave_addr;
    wire [7:0]  reg_xfer_len;
    wire [15:0] reg_prescaler;
    wire        reg_start_pulse;
    wire        irq_clear;

    // TX FIFO signals
    wire [7:0]  tx_fifo_wdata;
    wire        tx_fifo_wr_en;
    wire [7:0]  tx_fifo_rdata;
    wire        tx_fifo_rd_en;
    wire        tx_fifo_full;
    wire        tx_fifo_empty;
    wire [4:0]  tx_fifo_count;

    // RX FIFO signals
    wire [7:0]  rx_fifo_wdata;
    wire        rx_fifo_wr_en;
    wire [7:0]  rx_fifo_rdata;
    wire        rx_fifo_rd_en;
    wire        rx_fifo_full;
    wire        rx_fifo_empty;
    wire [4:0]  rx_fifo_count;

    // FSM status
    wire        fsm_busy;
    wire        fsm_done;   // 1-cycle pulse
    wire        fsm_nack;
    wire        fsm_tx_ready;

    // Sticky done/nack for STATUS register (cleared by irq_clear)
    reg         sticky_done;
    reg         sticky_nack;

    // Register file
    i2c_regfile u_regfile (
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
        .reg_control     (reg_control),
        .reg_slave_addr  (reg_slave_addr),
        .reg_xfer_len   (reg_xfer_len),
        .reg_prescaler   (reg_prescaler),
        .reg_start_pulse (reg_start_pulse),
        .tx_fifo_wdata   (tx_fifo_wdata),
        .tx_fifo_wr_en   (tx_fifo_wr_en),
        .rx_fifo_rdata   (rx_fifo_rdata),
        .rx_fifo_rd_en   (rx_fifo_rd_en),
        .irq_clear       (irq_clear),
        .status_busy     (fsm_busy),
        .status_done     (sticky_done),
        .status_nack     (sticky_nack),
        .tx_fifo_count   (tx_fifo_count),
        .tx_fifo_full    (tx_fifo_full),
        .tx_fifo_empty   (tx_fifo_empty),
        .rx_fifo_count   (rx_fifo_count),
        .rx_fifo_full    (rx_fifo_full),
        .rx_fifo_empty   (rx_fifo_empty)
    );

    // TX FIFO
    i2c_tx_fifo u_tx_fifo (
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
    i2c_rx_fifo u_rx_fifo (
        .clk       (clk_i),
        .rst_n     (rst_ni),
        .wr_data_i (rx_fifo_wdata),
        .wr_en_i   (rx_fifo_wr_en),
        .rd_data_o (rx_fifo_rdata),
        .rd_en_i   (rx_fifo_rd_en),
        .full_o    (rx_fifo_full),
        .empty_o   (rx_fifo_empty),
        .count_o   (rx_fifo_count)
    );

    // FSM
    wire [7:0] fsm_rx_data;
    wire       fsm_rx_valid;

    i2c_master_fsm u_fsm (
        .clk           (clk_i),
        .rst_n         (rst_ni),
        .start_i       (reg_start_pulse),
        .slave_addr_i  (reg_slave_addr),
        .xfer_len_i    (reg_xfer_len),
        .prescaler_i   (reg_prescaler),
        .tx_data_i     (tx_fifo_rdata),
        .tx_valid_i    (~tx_fifo_empty),
        .tx_ready_o    (fsm_tx_ready),
        .rx_data_o     (fsm_rx_data),
        .rx_valid_o    (fsm_rx_valid),
        .busy_o        (fsm_busy),
        .done_o        (fsm_done),
        .nack_o        (fsm_nack),
        .i2c_scl_o     (i2c_scl_o),
        .i2c_scl_oe_o  (i2c_scl_oe_o),
        .i2c_scl_i     (i2c_scl_i),
        .i2c_sda_o     (i2c_sda_o),
        .i2c_sda_oe_o  (i2c_sda_oe_o),
        .i2c_sda_i     (i2c_sda_i)
    );

    // RX FIFO write from FSM
    assign rx_fifo_wdata = fsm_rx_data;
    assign rx_fifo_wr_en = fsm_rx_valid;

    // Sticky done/nack + Interrupt — all cleared by irq_clear
    always @(posedge clk_i) begin
        if (!rst_ni) begin
            irq_i2c_done_o <= 1'b0;
            sticky_done    <= 1'b0;
            sticky_nack    <= 1'b0;
        end else begin
            if (irq_clear) begin
                irq_i2c_done_o <= 1'b0;
                sticky_done    <= 1'b0;
                sticky_nack    <= 1'b0;
            end else begin
                if (fsm_done) begin
                    irq_i2c_done_o <= 1'b1;
                    sticky_done    <= 1'b1;
                end
                if (fsm_nack)
                    sticky_nack <= 1'b1;
            end
        end
    end

endmodule
