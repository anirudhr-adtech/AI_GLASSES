`timescale 1ns/1ps
//============================================================================
// Module : irq_controller
// Project : AI_GLASSES — RISC-V Subsystem
// Description : Interrupt aggregator with 8 sources, per-source edge/level
//               type configuration, enable masking, and fixed priority
//               encoding (bit 0 = highest priority).
//============================================================================

module irq_controller (
    input  wire        clk,
    input  wire        rst_n,

    // AXI-Lite Slave — Write Address
    input  wire [7:0]  s_axil_awaddr,
    input  wire        s_axil_awvalid,
    output wire        s_axil_awready,

    // AXI-Lite Slave — Write Data
    input  wire [31:0] s_axil_wdata,
    input  wire [3:0]  s_axil_wstrb,
    input  wire        s_axil_wvalid,
    output wire        s_axil_wready,

    // AXI-Lite Slave — Write Response
    output wire [1:0]  s_axil_bresp,
    output wire        s_axil_bvalid,
    input  wire        s_axil_bready,

    // AXI-Lite Slave — Read Address
    input  wire [7:0]  s_axil_araddr,
    input  wire        s_axil_arvalid,
    output wire        s_axil_arready,

    // AXI-Lite Slave — Read Data
    output wire [31:0] s_axil_rdata,
    output wire [1:0]  s_axil_rresp,
    output wire        s_axil_rvalid,
    input  wire        s_axil_rready,

    // Interrupt sources
    input  wire [7:0]  irq_sources_i,

    // Aggregated interrupt output to CPU
    output wire        irq_external_o
);

    // ----------------------------------------------------------------
    // Register offsets
    // ----------------------------------------------------------------
    localparam ADDR_IRQ_PENDING = 8'h00;
    localparam ADDR_IRQ_ENABLE  = 8'h04;
    localparam ADDR_IRQ_CLEAR   = 8'h08;
    localparam ADDR_IRQ_TYPE    = 8'h0C;
    localparam ADDR_IRQ_STATUS  = 8'h10;
    localparam ADDR_IRQ_HIGHEST = 8'h14;

    // ----------------------------------------------------------------
    // Internal registers
    // ----------------------------------------------------------------
    reg [7:0] irq_enable;
    reg [7:0] irq_type;         // 0=level, 1=edge
    reg [7:0] irq_pending_edge; // edge-detected pending bits
    reg [7:0] irq_sources_prev; // previous cycle source value

    // Combinational
    reg [7:0] irq_pending;
    reg [7:0] irq_status;
    reg [7:0] irq_highest;

    // Registered outputs for read
    reg [7:0] irq_pending_reg;
    reg [7:0] irq_status_reg;
    reg [7:0] irq_highest_reg;
    reg       irq_external_reg;

    // Edge detection
    wire [7:0] rising_edge_det;
    assign rising_edge_det = irq_sources_i & ~irq_sources_prev;

    // Write-clear value latched during write
    reg [7:0] irq_clear_val;
    reg       irq_clear_pulse;

    // AXI-Lite write channel
    reg        aw_ready_reg;
    reg        w_ready_reg;
    reg        b_valid_reg;
    reg [7:0]  aw_addr_latched;
    reg        aw_done;
    reg        w_done;
    reg [31:0] w_data_latched;
    reg [3:0]  w_strb_latched;

    // AXI-Lite read channel
    reg        ar_ready_reg;
    reg        r_valid_reg;
    reg [31:0] r_data_reg;

    // ----------------------------------------------------------------
    // Output assignments
    // ----------------------------------------------------------------
    assign s_axil_awready = aw_ready_reg;
    assign s_axil_wready  = w_ready_reg;
    assign s_axil_bresp   = 2'b00;
    assign s_axil_bvalid  = b_valid_reg;
    assign s_axil_arready = ar_ready_reg;
    assign s_axil_rdata   = r_data_reg;
    assign s_axil_rresp   = 2'b00;
    assign s_axil_rvalid  = r_valid_reg;
    assign irq_external_o = irq_external_reg;

    // ----------------------------------------------------------------
    // Pending logic (combinational)
    // ----------------------------------------------------------------
    integer i;
    always @(*) begin
        for (i = 0; i < 8; i = i + 1) begin
            if (irq_type[i])
                irq_pending[i] = irq_pending_edge[i];
            else
                irq_pending[i] = irq_sources_i[i];
        end
        irq_status = irq_pending & irq_enable;

        // Priority encoder: find lowest set bit
        irq_highest = 8'hFF; // none
        for (i = 7; i >= 0; i = i - 1) begin
            if (irq_status[i])
                irq_highest = i[7:0];
        end
    end

    // ----------------------------------------------------------------
    // Register combinational outputs for module boundary
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            irq_pending_reg  <= 8'd0;
            irq_status_reg   <= 8'd0;
            irq_highest_reg  <= 8'hFF;
            irq_external_reg <= 1'b0;
        end else begin
            irq_pending_reg  <= irq_pending;
            irq_status_reg   <= irq_status;
            irq_highest_reg  <= irq_highest;
            irq_external_reg <= |irq_status;
        end
    end

    // ----------------------------------------------------------------
    // Edge detection and pending edge register
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            irq_sources_prev <= 8'd0;
            irq_pending_edge <= 8'd0;
            irq_clear_pulse  <= 1'b0;
        end else begin
            irq_sources_prev <= irq_sources_i;
            irq_clear_pulse  <= 1'b0;

            // Set on rising edge
            irq_pending_edge <= (irq_pending_edge | rising_edge_det);

            // Clear on write-1-to-clear
            if (irq_clear_pulse) begin
                irq_pending_edge <= (irq_pending_edge | rising_edge_det) & ~irq_clear_val;
            end
        end
    end

    // ----------------------------------------------------------------
    // AXI-Lite Write Channel
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            aw_ready_reg    <= 1'b0;
            w_ready_reg     <= 1'b0;
            b_valid_reg     <= 1'b0;
            aw_done         <= 1'b0;
            w_done          <= 1'b0;
            aw_addr_latched <= 8'd0;
            w_data_latched  <= 32'd0;
            w_strb_latched  <= 4'd0;
            irq_enable      <= 8'h00;
            irq_type        <= 8'hFC;
            irq_clear_val   <= 8'd0;
        end else begin
            aw_ready_reg    <= 1'b0;
            w_ready_reg     <= 1'b0;
            irq_clear_pulse <= 1'b0;

            // Accept write address
            if (s_axil_awvalid && !aw_done) begin
                aw_ready_reg    <= 1'b1;
                aw_addr_latched <= s_axil_awaddr;
                aw_done         <= 1'b1;
            end

            // Accept write data
            if (s_axil_wvalid && !w_done) begin
                w_ready_reg    <= 1'b1;
                w_data_latched <= s_axil_wdata;
                w_strb_latched <= s_axil_wstrb;
                w_done         <= 1'b1;
            end

            // When both captured, perform write
            if ((aw_done || (s_axil_awvalid && !aw_done)) &&
                (w_done  || (s_axil_wvalid  && !w_done))  &&
                !b_valid_reg) begin

                b_valid_reg <= 1'b1;

                case (aw_addr_latched)
                    ADDR_IRQ_ENABLE: begin
                        if (w_strb_latched[0]) irq_enable <= w_data_latched[7:0];
                    end
                    ADDR_IRQ_CLEAR: begin
                        irq_clear_val   <= w_data_latched[7:0];
                        irq_clear_pulse <= 1'b1;
                    end
                    ADDR_IRQ_TYPE: begin
                        if (w_strb_latched[0]) irq_type <= w_data_latched[7:0];
                    end
                    default: ; // ignore writes to read-only registers
                endcase
            end

            // Write response handshake
            if (b_valid_reg && s_axil_bready) begin
                b_valid_reg <= 1'b0;
                aw_done     <= 1'b0;
                w_done      <= 1'b0;
            end
        end
    end

    // ----------------------------------------------------------------
    // AXI-Lite Read Channel
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            ar_ready_reg <= 1'b0;
            r_valid_reg  <= 1'b0;
            r_data_reg   <= 32'd0;
        end else begin
            ar_ready_reg <= 1'b0;

            if (s_axil_arvalid && !r_valid_reg) begin
                ar_ready_reg <= 1'b1;
                r_valid_reg  <= 1'b1;

                case (s_axil_araddr)
                    ADDR_IRQ_PENDING: r_data_reg <= {24'd0, irq_pending_reg};
                    ADDR_IRQ_ENABLE:  r_data_reg <= {24'd0, irq_enable};
                    ADDR_IRQ_TYPE:    r_data_reg <= {24'd0, irq_type};
                    ADDR_IRQ_STATUS:  r_data_reg <= {24'd0, irq_status_reg};
                    ADDR_IRQ_HIGHEST: r_data_reg <= {24'd0, irq_highest_reg};
                    default:          r_data_reg <= 32'd0;
                endcase
            end

            if (r_valid_reg && s_axil_rready) begin
                r_valid_reg <= 1'b0;
            end
        end
    end

endmodule
