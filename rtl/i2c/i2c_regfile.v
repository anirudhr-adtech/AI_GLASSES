`timescale 1ns / 1ps
//============================================================================
// i2c_regfile.v
// AI_GLASSES — I2C Master
// AXI4-Lite slave register file for I2C master peripheral.
// Registers:
//   0x00 I2C_CONTROL    - [0] enable
//   0x04 STATUS         - [0] busy, [1] done, [2] nack
//   0x08 SLAVE_ADDR     - [7:0] {7-bit addr, R/W}
//   0x0C TXDATA         - [7:0] write to TX FIFO
//   0x10 RXDATA         - [7:0] read from RX FIFO
//   0x14 XFER_LEN       - [7:0] transfer byte count
//   0x18 START          - [0] write 1 to start transfer
//   0x1C PRESCALER      - [15:0] SCL prescaler
//   0x20 IRQ_CLEAR      - [0] write 1 to clear IRQ
//   0x24 FIFO_STATUS    - [4:0] tx_count, [12:8] rx_count, [16] tx_full,
//                          [17] tx_empty, [18] rx_full, [19] rx_empty
//============================================================================

module i2c_regfile (
    input  wire        clk,
    input  wire        rst_n,

    // AXI4-Lite slave — write address
    input  wire [7:0]  s_axil_awaddr,
    input  wire        s_axil_awvalid,
    output reg         s_axil_awready,

    // AXI4-Lite slave — write data
    input  wire [31:0] s_axil_wdata,
    input  wire [3:0]  s_axil_wstrb,
    input  wire        s_axil_wvalid,
    output reg         s_axil_wready,

    // AXI4-Lite slave — write response
    output reg  [1:0]  s_axil_bresp,
    output reg         s_axil_bvalid,
    input  wire        s_axil_bready,

    // AXI4-Lite slave — read address
    input  wire [7:0]  s_axil_araddr,
    input  wire        s_axil_arvalid,
    output reg         s_axil_arready,

    // AXI4-Lite slave — read data
    output reg  [31:0] s_axil_rdata,
    output reg  [1:0]  s_axil_rresp,
    output reg         s_axil_rvalid,
    input  wire        s_axil_rready,

    // Register outputs
    output reg  [31:0] reg_control,
    output reg  [7:0]  reg_slave_addr,
    output reg  [7:0]  reg_xfer_len,
    output reg  [15:0] reg_prescaler,
    output reg         reg_start_pulse,

    // TX FIFO write
    output reg  [7:0]  tx_fifo_wdata,
    output reg         tx_fifo_wr_en,

    // RX FIFO read
    input  wire [7:0]  rx_fifo_rdata,
    output reg         rx_fifo_rd_en,

    // IRQ
    output reg         irq_clear,

    // Status inputs
    input  wire        status_busy,
    input  wire        status_done,
    input  wire        status_nack,

    // FIFO status inputs
    input  wire [4:0]  tx_fifo_count,
    input  wire        tx_fifo_full,
    input  wire        tx_fifo_empty,
    input  wire [4:0]  rx_fifo_count,
    input  wire        rx_fifo_full,
    input  wire        rx_fifo_empty
);

    // Write state machine
    reg aw_done, w_done;
    reg [7:0] aw_addr_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            s_axil_awready <= 1'b0;
            s_axil_wready  <= 1'b0;
            s_axil_bvalid  <= 1'b0;
            s_axil_bresp   <= 2'b00;
            aw_done        <= 1'b0;
            w_done         <= 1'b0;
            aw_addr_r      <= 8'd0;
            reg_control    <= 32'd0;
            reg_slave_addr <= 8'd0;
            reg_xfer_len   <= 8'd0;
            reg_prescaler  <= 16'd249; // default 100kHz
            reg_start_pulse <= 1'b0;
            tx_fifo_wdata  <= 8'd0;
            tx_fifo_wr_en  <= 1'b0;
            irq_clear      <= 1'b0;
        end else begin
            // Defaults
            reg_start_pulse <= 1'b0;
            tx_fifo_wr_en  <= 1'b0;
            irq_clear      <= 1'b0;

            // AW handshake
            if (s_axil_awvalid && !aw_done) begin
                s_axil_awready <= 1'b1;
                aw_addr_r      <= s_axil_awaddr;
                aw_done        <= 1'b1;
            end else begin
                s_axil_awready <= 1'b0;
            end

            // W handshake
            if (s_axil_wvalid && !w_done) begin
                s_axil_wready <= 1'b1;
                w_done        <= 1'b1;
            end else begin
                s_axil_wready <= 1'b0;
            end

            // Both received — perform write
            if (aw_done && w_done) begin
                aw_done <= 1'b0;
                w_done  <= 1'b0;
                s_axil_bvalid <= 1'b1;
                s_axil_bresp  <= 2'b00;

                case (aw_addr_r[7:2])
                    6'd0: reg_control    <= s_axil_wdata;                // 0x00
                    6'd2: reg_slave_addr <= s_axil_wdata[7:0];           // 0x08
                    6'd3: begin                                           // 0x0C TXDATA
                        tx_fifo_wdata <= s_axil_wdata[7:0];
                        tx_fifo_wr_en <= 1'b1;
                    end
                    6'd5: reg_xfer_len   <= s_axil_wdata[7:0];           // 0x14
                    6'd6: reg_start_pulse <= s_axil_wdata[0];            // 0x18
                    6'd7: reg_prescaler  <= s_axil_wdata[15:0];          // 0x1C
                    6'd8: irq_clear      <= s_axil_wdata[0];            // 0x20
                    default: ;
                endcase
            end

            // B handshake
            if (s_axil_bvalid && s_axil_bready) begin
                s_axil_bvalid <= 1'b0;
            end
        end
    end

    // Read state machine
    reg ar_done;
    reg [7:0] ar_addr_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            s_axil_arready <= 1'b0;
            s_axil_rvalid  <= 1'b0;
            s_axil_rdata   <= 32'd0;
            s_axil_rresp   <= 2'b00;
            ar_done        <= 1'b0;
            ar_addr_r      <= 8'd0;
            rx_fifo_rd_en  <= 1'b0;
        end else begin
            rx_fifo_rd_en <= 1'b0;

            // AR handshake
            if (s_axil_arvalid && !ar_done) begin
                s_axil_arready <= 1'b1;
                ar_addr_r      <= s_axil_araddr;
                ar_done        <= 1'b1;
            end else begin
                s_axil_arready <= 1'b0;
            end

            // Perform read
            if (ar_done && !s_axil_rvalid) begin
                ar_done       <= 1'b0;
                s_axil_rvalid <= 1'b1;
                s_axil_rresp  <= 2'b00;

                case (ar_addr_r[7:2])
                    6'd0: s_axil_rdata <= reg_control;
                    6'd1: s_axil_rdata <= {29'd0, status_nack, status_done, status_busy};
                    6'd2: s_axil_rdata <= {24'd0, reg_slave_addr};
                    6'd4: begin
                        s_axil_rdata  <= {24'd0, rx_fifo_rdata};
                        rx_fifo_rd_en <= 1'b1;
                    end
                    6'd5: s_axil_rdata <= {24'd0, reg_xfer_len};
                    6'd7: s_axil_rdata <= {16'd0, reg_prescaler};
                    6'd9: s_axil_rdata <= {12'd0, rx_fifo_empty, rx_fifo_full,
                                           tx_fifo_empty, tx_fifo_full,
                                           3'd0, rx_fifo_count,
                                           3'd0, tx_fifo_count};
                    default: s_axil_rdata <= 32'd0;
                endcase
            end

            // R handshake
            if (s_axil_rvalid && s_axil_rready) begin
                s_axil_rvalid <= 1'b0;
            end
        end
    end

endmodule
