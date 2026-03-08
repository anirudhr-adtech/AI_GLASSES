`timescale 1ns/1ps
//============================================================================
// Module : uart_peripheral
// Project : AI_GLASSES — RISC-V Subsystem
// Description : AXI4-Lite UART peripheral wrapping uart_tx, uart_rx,
//               and two uart_fifo instances (TX/RX). Includes baud
//               rate generator and interrupt outputs.
//============================================================================

module uart_peripheral #(
    parameter FIFO_DEPTH = 16
)(
    input  wire        clk,
    input  wire        rst_n,

    // AXI4-Lite Slave Interface
    input  wire [7:0]  s_axil_awaddr,
    input  wire        s_axil_awvalid,
    output reg         s_axil_awready,
    input  wire [31:0] s_axil_wdata,
    input  wire [3:0]  s_axil_wstrb,
    input  wire        s_axil_wvalid,
    output reg         s_axil_wready,
    output reg  [1:0]  s_axil_bresp,
    output reg         s_axil_bvalid,
    input  wire        s_axil_bready,
    input  wire [7:0]  s_axil_araddr,
    input  wire        s_axil_arvalid,
    output reg         s_axil_arready,
    output reg  [31:0] s_axil_rdata,
    output reg  [1:0]  s_axil_rresp,
    output reg         s_axil_rvalid,
    input  wire        s_axil_rready,

    // UART signals
    output wire        uart_tx_o,
    input  wire        uart_rx_i,

    // Interrupt outputs
    output reg         irq_tx_empty,
    output reg         irq_rx_ready
);

    // ----------------------------------------------------------------
    // Register offsets
    // ----------------------------------------------------------------
    localparam ADDR_TXDATA     = 8'h00;
    localparam ADDR_RXDATA     = 8'h04;
    localparam ADDR_STATUS     = 8'h08;
    localparam ADDR_BAUDDIV    = 8'h0C;
    localparam ADDR_IRQ_ENABLE = 8'h10;

    // ----------------------------------------------------------------
    // Internal registers
    // ----------------------------------------------------------------
    reg [31:0] reg_bauddiv;
    reg [1:0]  reg_irq_en;  // [0] tx_empty, [1] rx_ready

    // ----------------------------------------------------------------
    // Baud rate generator
    // ----------------------------------------------------------------
    reg [31:0] baud_cnt;
    reg [31:0] baud_cnt_16x;
    reg        baud_tick;
    reg        baud_tick_16x;

    // 16x baud tick
    always @(posedge clk) begin
        if (!rst_n) begin
            baud_cnt_16x <= 32'd0;
            baud_tick_16x <= 1'b0;
        end else begin
            if (reg_bauddiv == 32'd0) begin
                baud_tick_16x <= 1'b1;
                baud_cnt_16x  <= 32'd0;
            end else if (baud_cnt_16x == ((reg_bauddiv + 1) / 16) - 1) begin
                baud_tick_16x <= 1'b1;
                baud_cnt_16x  <= 32'd0;
            end else begin
                baud_tick_16x <= 1'b0;
                baud_cnt_16x  <= baud_cnt_16x + 32'd1;
            end
        end
    end

    // 1x baud tick
    always @(posedge clk) begin
        if (!rst_n) begin
            baud_cnt  <= 32'd0;
            baud_tick <= 1'b0;
        end else begin
            if (baud_cnt == reg_bauddiv) begin
                baud_tick <= 1'b1;
                baud_cnt  <= 32'd0;
            end else begin
                baud_tick <= 1'b0;
                baud_cnt  <= baud_cnt + 32'd1;
            end
        end
    end

    // ----------------------------------------------------------------
    // TX FIFO signals
    // ----------------------------------------------------------------
    wire       tx_fifo_wr_en;
    wire [7:0] tx_fifo_wr_data;
    wire       tx_fifo_rd_en;
    wire [7:0] tx_fifo_rd_data;
    wire       tx_fifo_full;
    wire       tx_fifo_empty;

    // ----------------------------------------------------------------
    // RX FIFO signals
    // ----------------------------------------------------------------
    wire       rx_fifo_wr_en;
    wire [7:0] rx_fifo_wr_data;
    wire       rx_fifo_rd_en;
    wire [7:0] rx_fifo_rd_data;
    wire       rx_fifo_full;
    wire       rx_fifo_empty;

    // ----------------------------------------------------------------
    // UART TX / RX signals
    // ----------------------------------------------------------------
    wire       tx_busy;
    wire       tx_done;
    wire [7:0] rx_data_out;
    wire       rx_data_valid;
    wire       rx_frame_error;

    // ----------------------------------------------------------------
    // Status register bits
    // ----------------------------------------------------------------
    reg        rx_overrun;
    reg        framing_error;

    wire [31:0] status_reg;
    assign status_reg = {26'd0, framing_error, rx_overrun, rx_fifo_empty,
                         rx_fifo_full, tx_fifo_empty, tx_fifo_full};

    // Overrun: RX data valid but FIFO full
    always @(posedge clk) begin
        if (!rst_n)
            rx_overrun <= 1'b0;
        else if (rx_data_valid && rx_fifo_full)
            rx_overrun <= 1'b1;
    end

    // Framing error latch
    always @(posedge clk) begin
        if (!rst_n)
            framing_error <= 1'b0;
        else if (rx_frame_error)
            framing_error <= 1'b1;
    end

    // ----------------------------------------------------------------
    // TX FIFO write: driven by AXI write to TXDATA
    // ----------------------------------------------------------------
    reg        tx_fifo_wr_pulse;
    reg [7:0]  tx_fifo_wr_byte;

    assign tx_fifo_wr_en   = tx_fifo_wr_pulse;
    assign tx_fifo_wr_data = tx_fifo_wr_byte;

    // ----------------------------------------------------------------
    // TX FIFO -> UART TX path
    // ----------------------------------------------------------------
    reg        tx_start;
    reg [7:0]  tx_data_in;
    reg        tx_feeding;

    always @(posedge clk) begin
        if (!rst_n) begin
            tx_start   <= 1'b0;
            tx_data_in <= 8'd0;
            tx_feeding <= 1'b0;
        end else begin
            tx_start <= 1'b0;
            if (!tx_busy && !tx_fifo_empty && !tx_feeding) begin
                tx_feeding <= 1'b1;
            end else if (tx_feeding) begin
                tx_start   <= 1'b1;
                tx_data_in <= tx_fifo_rd_data;
                tx_feeding <= 1'b0;
            end
        end
    end

    assign tx_fifo_rd_en = (!tx_busy && !tx_fifo_empty && !tx_feeding);

    // ----------------------------------------------------------------
    // RX -> RX FIFO path
    // ----------------------------------------------------------------
    assign rx_fifo_wr_en   = rx_data_valid && !rx_fifo_full;
    assign rx_fifo_wr_data = rx_data_out;

    // ----------------------------------------------------------------
    // RX FIFO read: driven by AXI read from RXDATA
    // ----------------------------------------------------------------
    reg rx_fifo_rd_pulse;
    assign rx_fifo_rd_en = rx_fifo_rd_pulse;

    // ----------------------------------------------------------------
    // Submodule instantiations
    // ----------------------------------------------------------------
    uart_tx u_uart_tx (
        .clk       (clk),
        .rst_n     (rst_n),
        .baud_tick (baud_tick),
        .tx_start  (tx_start),
        .tx_data   (tx_data_in),
        .tx_out    (uart_tx_o),
        .tx_busy   (tx_busy),
        .tx_done   (tx_done)
    );

    uart_rx u_uart_rx (
        .clk           (clk),
        .rst_n         (rst_n),
        .baud_tick_16x (baud_tick_16x),
        .rx_in         (uart_rx_i),
        .rx_data       (rx_data_out),
        .rx_valid      (rx_data_valid),
        .rx_error      (rx_frame_error)
    );

    uart_fifo #(
        .DEPTH (FIFO_DEPTH),
        .DATA_WIDTH (8)
    ) u_tx_fifo (
        .clk    (clk),
        .rst_n  (rst_n),
        .wr_en  (tx_fifo_wr_en),
        .din    (tx_fifo_wr_data),
        .rd_en  (tx_fifo_rd_en),
        .dout   (tx_fifo_rd_data),
        .full   (tx_fifo_full),
        .empty  (tx_fifo_empty)
    );

    uart_fifo #(
        .DEPTH (FIFO_DEPTH),
        .DATA_WIDTH (8)
    ) u_rx_fifo (
        .clk    (clk),
        .rst_n  (rst_n),
        .wr_en  (rx_fifo_wr_en),
        .din    (rx_fifo_wr_data),
        .rd_en  (rx_fifo_rd_en),
        .dout   (rx_fifo_rd_data),
        .full   (rx_fifo_full),
        .empty  (rx_fifo_empty)
    );

    // ----------------------------------------------------------------
    // AXI-Lite state machine
    // ----------------------------------------------------------------
    localparam AXL_IDLE   = 2'd0;
    localparam AXL_WRITE  = 2'd1;
    localparam AXL_READ   = 2'd2;
    localparam AXL_RESP   = 2'd3;

    reg [1:0]  axl_state;
    reg [7:0]  axl_addr;
    reg [31:0] axl_wdata;
    reg        axl_is_write;

    always @(posedge clk) begin
        if (!rst_n) begin
            axl_state       <= AXL_IDLE;
            axl_addr        <= 8'd0;
            axl_wdata       <= 32'd0;
            axl_is_write    <= 1'b0;
            s_axil_awready  <= 1'b0;
            s_axil_wready   <= 1'b0;
            s_axil_bvalid   <= 1'b0;
            s_axil_bresp    <= 2'b00;
            s_axil_arready  <= 1'b0;
            s_axil_rvalid   <= 1'b0;
            s_axil_rdata    <= 32'd0;
            s_axil_rresp    <= 2'b00;
            tx_fifo_wr_pulse <= 1'b0;
            tx_fifo_wr_byte  <= 8'd0;
            rx_fifo_rd_pulse <= 1'b0;
            reg_bauddiv      <= 32'd0;
            reg_irq_en       <= 2'b00;
        end else begin
            // Default de-assert
            s_axil_awready  <= 1'b0;
            s_axil_wready   <= 1'b0;
            s_axil_arready  <= 1'b0;
            tx_fifo_wr_pulse <= 1'b0;
            rx_fifo_rd_pulse <= 1'b0;

            case (axl_state)
                AXL_IDLE: begin
                    // Write has priority
                    if (s_axil_awvalid && s_axil_wvalid) begin
                        s_axil_awready <= 1'b1;
                        s_axil_wready  <= 1'b1;
                        axl_addr       <= s_axil_awaddr;
                        axl_wdata      <= s_axil_wdata;
                        axl_is_write   <= 1'b1;
                        axl_state      <= AXL_WRITE;
                    end else if (s_axil_arvalid) begin
                        s_axil_arready <= 1'b1;
                        axl_addr       <= s_axil_araddr;
                        axl_is_write   <= 1'b0;
                        axl_state      <= AXL_READ;
                    end
                end

                AXL_WRITE: begin
                    // Process write
                    case (axl_addr)
                        ADDR_TXDATA: begin
                            if (!tx_fifo_full) begin
                                tx_fifo_wr_pulse <= 1'b1;
                                tx_fifo_wr_byte  <= axl_wdata[7:0];
                            end
                        end
                        ADDR_BAUDDIV: begin
                            reg_bauddiv <= axl_wdata;
                        end
                        ADDR_IRQ_ENABLE: begin
                            reg_irq_en <= axl_wdata[1:0];
                        end
                        default: ; // Ignore writes to RO regs
                    endcase
                    s_axil_bresp  <= 2'b00; // OKAY
                    s_axil_bvalid <= 1'b1;
                    axl_state     <= AXL_RESP;
                end

                AXL_READ: begin
                    case (axl_addr)
                        ADDR_TXDATA: begin
                            s_axil_rdata <= 32'd0;
                        end
                        ADDR_RXDATA: begin
                            s_axil_rdata     <= {rx_fifo_empty, 23'd0, rx_fifo_rd_data};
                            rx_fifo_rd_pulse <= !rx_fifo_empty;
                        end
                        ADDR_STATUS: begin
                            s_axil_rdata <= status_reg;
                        end
                        ADDR_BAUDDIV: begin
                            s_axil_rdata <= reg_bauddiv;
                        end
                        ADDR_IRQ_ENABLE: begin
                            s_axil_rdata <= {30'd0, reg_irq_en};
                        end
                        default: begin
                            s_axil_rdata <= 32'd0;
                        end
                    endcase
                    s_axil_rresp  <= 2'b00; // OKAY
                    s_axil_rvalid <= 1'b1;
                    axl_state     <= AXL_RESP;
                end

                AXL_RESP: begin
                    if (axl_is_write) begin
                        if (s_axil_bready) begin
                            s_axil_bvalid <= 1'b0;
                            axl_state     <= AXL_IDLE;
                        end
                    end else begin
                        if (s_axil_rready) begin
                            s_axil_rvalid <= 1'b0;
                            axl_state     <= AXL_IDLE;
                        end
                    end
                end
            endcase
        end
    end

    // ----------------------------------------------------------------
    // Interrupt generation (registered outputs)
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            irq_tx_empty <= 1'b0;
            irq_rx_ready <= 1'b0;
        end else begin
            irq_tx_empty <= reg_irq_en[0] & tx_fifo_empty;
            irq_rx_ready <= reg_irq_en[1] & ~rx_fifo_empty;
        end
    end

endmodule
