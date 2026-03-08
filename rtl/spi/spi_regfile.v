`timescale 1ns / 1ps
//============================================================================
// spi_regfile.v
// AI_GLASSES — SPI Master
// AXI4-Lite slave register file for SPI master peripheral.
// Registers:
//   0x00 SPI_TXDATA   - [7:0] write to TX FIFO
//   0x04 RXDATA       - [7:0] read from RX FIFO
//   0x08 STATUS       - [0] busy, [1] tx_full, [2] tx_empty, [3] rx_full, [4] rx_empty
//   0x0C CONFIG       - [7:0] div, [8] cpol, [9] cpha, [10] auto_cs
//   0x10 CS           - [0] manual cs_n control
//   0x14 IRQ_EN       - [0] enable done IRQ
//   0x18 TX_FIFO      - [4:0] tx_count (read-only)
//   0x1C RX_FIFO      - [4:0] rx_count (read-only)
//============================================================================

module spi_regfile (
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
    output reg  [7:0]  reg_div,
    output reg         reg_cpol,
    output reg         reg_cpha,
    output reg         reg_auto_cs,
    output reg         reg_cs_n,
    output reg         reg_irq_en,

    // TX FIFO write
    output reg  [7:0]  tx_fifo_wdata,
    output reg         tx_fifo_wr_en,

    // RX FIFO read
    input  wire [7:0]  rx_fifo_rdata,
    output reg         rx_fifo_rd_en,

    // Status inputs
    input  wire        status_busy,
    input  wire        tx_fifo_full,
    input  wire        tx_fifo_empty,
    input  wire        rx_fifo_full,
    input  wire        rx_fifo_empty,
    input  wire [4:0]  tx_fifo_count,
    input  wire [4:0]  rx_fifo_count
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
            reg_div        <= 8'd4;   // default 10MHz
            reg_cpol       <= 1'b0;
            reg_cpha       <= 1'b0;
            reg_auto_cs    <= 1'b1;
            reg_cs_n       <= 1'b1;
            reg_irq_en     <= 1'b0;
            tx_fifo_wdata  <= 8'd0;
            tx_fifo_wr_en  <= 1'b0;
        end else begin
            tx_fifo_wr_en <= 1'b0;

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
                    6'd0: begin   // 0x00 TXDATA
                        tx_fifo_wdata <= s_axil_wdata[7:0];
                        tx_fifo_wr_en <= 1'b1;
                    end
                    6'd3: begin   // 0x0C CONFIG
                        reg_div     <= s_axil_wdata[7:0];
                        reg_cpol    <= s_axil_wdata[8];
                        reg_cpha    <= s_axil_wdata[9];
                        reg_auto_cs <= s_axil_wdata[10];
                    end
                    6'd4: reg_cs_n    <= s_axil_wdata[0];   // 0x10 CS
                    6'd5: reg_irq_en  <= s_axil_wdata[0];   // 0x14 IRQ_EN
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
                    6'd1: begin   // 0x04 RXDATA
                        s_axil_rdata  <= {24'd0, rx_fifo_rdata};
                        rx_fifo_rd_en <= 1'b1;
                    end
                    6'd2: s_axil_rdata <= {27'd0, rx_fifo_empty, rx_fifo_full,
                                           tx_fifo_empty, tx_fifo_full, status_busy};
                    6'd3: s_axil_rdata <= {21'd0, reg_auto_cs, reg_cpha, reg_cpol, reg_div};
                    6'd4: s_axil_rdata <= {31'd0, reg_cs_n};
                    6'd5: s_axil_rdata <= {31'd0, reg_irq_en};
                    6'd6: s_axil_rdata <= {27'd0, tx_fifo_count};
                    6'd7: s_axil_rdata <= {27'd0, rx_fifo_count};
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
