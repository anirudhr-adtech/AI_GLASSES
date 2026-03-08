`timescale 1ns/1ps
//============================================================================
// Module : gpio_peripheral
// Project : AI_GLASSES — RISC-V Subsystem
// Description : AXI4-Lite GPIO peripheral with 8-bit I/O, direction
//               control, edge-triggered interrupts, and W1C pending.
//============================================================================

module gpio_peripheral #(
    parameter GPIO_WIDTH = 8
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // AXI4-Lite Slave Interface
    input  wire [7:0]            s_axil_awaddr,
    input  wire                  s_axil_awvalid,
    output reg                   s_axil_awready,
    input  wire [31:0]           s_axil_wdata,
    input  wire [3:0]            s_axil_wstrb,
    input  wire                  s_axil_wvalid,
    output reg                   s_axil_wready,
    output reg  [1:0]            s_axil_bresp,
    output reg                   s_axil_bvalid,
    input  wire                  s_axil_bready,
    input  wire [7:0]            s_axil_araddr,
    input  wire                  s_axil_arvalid,
    output reg                   s_axil_arready,
    output reg  [31:0]           s_axil_rdata,
    output reg  [1:0]            s_axil_rresp,
    output reg                   s_axil_rvalid,
    input  wire                  s_axil_rready,

    // GPIO pins
    input  wire [GPIO_WIDTH-1:0] gpio_i,
    output reg  [GPIO_WIDTH-1:0] gpio_o,
    output reg  [GPIO_WIDTH-1:0] gpio_oe,

    // Interrupt output
    output reg                   irq_gpio
);

    // ----------------------------------------------------------------
    // Register offsets
    // ----------------------------------------------------------------
    localparam ADDR_GPIO_DIR      = 8'h00;
    localparam ADDR_GPIO_OUT      = 8'h04;
    localparam ADDR_GPIO_IN       = 8'h08;
    localparam ADDR_GPIO_IRQ_EN   = 8'h0C;
    localparam ADDR_GPIO_IRQ_PEND = 8'h10;

    // ----------------------------------------------------------------
    // Internal registers
    // ----------------------------------------------------------------
    reg [GPIO_WIDTH-1:0] reg_dir;
    reg [GPIO_WIDTH-1:0] reg_out;
    reg [GPIO_WIDTH-1:0] reg_irq_en;
    reg [GPIO_WIDTH-1:0] reg_irq_pend;

    // ----------------------------------------------------------------
    // 2-FF synchronizer for gpio_i
    // ----------------------------------------------------------------
    reg [GPIO_WIDTH-1:0] gpio_sync_0;
    reg [GPIO_WIDTH-1:0] gpio_sync_1;

    always @(posedge clk) begin
        if (!rst_n) begin
            gpio_sync_0 <= {GPIO_WIDTH{1'b0}};
            gpio_sync_1 <= {GPIO_WIDTH{1'b0}};
        end else begin
            gpio_sync_0 <= gpio_i;
            gpio_sync_1 <= gpio_sync_0;
        end
    end

    // ----------------------------------------------------------------
    // Rising edge detection
    // ----------------------------------------------------------------
    reg [GPIO_WIDTH-1:0] gpio_prev;

    always @(posedge clk) begin
        if (!rst_n)
            gpio_prev <= {GPIO_WIDTH{1'b0}};
        else
            gpio_prev <= gpio_sync_1;
    end

    wire [GPIO_WIDTH-1:0] rising_edge;
    assign rising_edge = gpio_sync_1 & ~gpio_prev;

    // ----------------------------------------------------------------
    // IRQ pending with W1C support
    // ----------------------------------------------------------------
    // W1C clear signal from AXI write (set in state machine)
    reg [GPIO_WIDTH-1:0] irq_pend_w1c;

    always @(posedge clk) begin
        if (!rst_n)
            reg_irq_pend <= {GPIO_WIDTH{1'b0}};
        else
            reg_irq_pend <= (reg_irq_pend & ~irq_pend_w1c) | rising_edge;
    end

    // ----------------------------------------------------------------
    // Output drive
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            gpio_o  <= {GPIO_WIDTH{1'b0}};
            gpio_oe <= {GPIO_WIDTH{1'b0}};
        end else begin
            gpio_o  <= reg_out;
            gpio_oe <= reg_dir;
        end
    end

    // ----------------------------------------------------------------
    // Interrupt output (registered)
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n)
            irq_gpio <= 1'b0;
        else
            irq_gpio <= |(reg_irq_pend & reg_irq_en);
    end

    // ----------------------------------------------------------------
    // AXI-Lite state machine
    // ----------------------------------------------------------------
    localparam AXL_IDLE  = 2'd0;
    localparam AXL_WRITE = 2'd1;
    localparam AXL_READ  = 2'd2;
    localparam AXL_RESP  = 2'd3;

    reg [1:0]  axl_state;
    reg [7:0]  axl_addr;
    reg [31:0] axl_wdata;
    reg        axl_is_write;

    always @(posedge clk) begin
        if (!rst_n) begin
            axl_state      <= AXL_IDLE;
            axl_addr       <= 8'd0;
            axl_wdata      <= 32'd0;
            axl_is_write   <= 1'b0;
            s_axil_awready <= 1'b0;
            s_axil_wready  <= 1'b0;
            s_axil_bvalid  <= 1'b0;
            s_axil_bresp   <= 2'b00;
            s_axil_arready <= 1'b0;
            s_axil_rvalid  <= 1'b0;
            s_axil_rdata   <= 32'd0;
            s_axil_rresp   <= 2'b00;
            reg_dir        <= {GPIO_WIDTH{1'b0}};
            reg_out        <= {GPIO_WIDTH{1'b0}};
            reg_irq_en     <= {GPIO_WIDTH{1'b0}};
            irq_pend_w1c   <= {GPIO_WIDTH{1'b0}};
        end else begin
            // Default de-assert
            s_axil_awready <= 1'b0;
            s_axil_wready  <= 1'b0;
            s_axil_arready <= 1'b0;
            irq_pend_w1c   <= {GPIO_WIDTH{1'b0}};

            case (axl_state)
                AXL_IDLE: begin
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
                    case (axl_addr)
                        ADDR_GPIO_DIR: begin
                            reg_dir <= axl_wdata[GPIO_WIDTH-1:0];
                        end
                        ADDR_GPIO_OUT: begin
                            reg_out <= axl_wdata[GPIO_WIDTH-1:0];
                        end
                        ADDR_GPIO_IRQ_EN: begin
                            reg_irq_en <= axl_wdata[GPIO_WIDTH-1:0];
                        end
                        ADDR_GPIO_IRQ_PEND: begin
                            irq_pend_w1c <= axl_wdata[GPIO_WIDTH-1:0];
                        end
                        default: ;
                    endcase
                    s_axil_bresp  <= 2'b00;
                    s_axil_bvalid <= 1'b1;
                    axl_state     <= AXL_RESP;
                end

                AXL_READ: begin
                    case (axl_addr)
                        ADDR_GPIO_DIR: begin
                            s_axil_rdata <= {{(32-GPIO_WIDTH){1'b0}}, reg_dir};
                        end
                        ADDR_GPIO_OUT: begin
                            s_axil_rdata <= {{(32-GPIO_WIDTH){1'b0}}, reg_out};
                        end
                        ADDR_GPIO_IN: begin
                            s_axil_rdata <= {{(32-GPIO_WIDTH){1'b0}}, gpio_sync_1};
                        end
                        ADDR_GPIO_IRQ_EN: begin
                            s_axil_rdata <= {{(32-GPIO_WIDTH){1'b0}}, reg_irq_en};
                        end
                        ADDR_GPIO_IRQ_PEND: begin
                            s_axil_rdata <= {{(32-GPIO_WIDTH){1'b0}}, reg_irq_pend};
                        end
                        default: begin
                            s_axil_rdata <= 32'd0;
                        end
                    endcase
                    s_axil_rresp  <= 2'b00;
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

endmodule
