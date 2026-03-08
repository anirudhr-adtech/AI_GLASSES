`timescale 1ns/1ps
//============================================================================
// Module : timer_clint
// Project : AI_GLASSES — RISC-V Subsystem
// Description : CLINT-compatible timer with 64-bit mtime counter, mtimecmp
//               compare register, and configurable prescaler. Generates
//               timer interrupt when mtime >= mtimecmp.
//============================================================================

module timer_clint (
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

    // Timer interrupt output
    output wire        irq_timer_o
);

    // ----------------------------------------------------------------
    // Register offsets
    // ----------------------------------------------------------------
    localparam ADDR_MTIME_LO    = 8'h00;
    localparam ADDR_MTIME_HI    = 8'h04;
    localparam ADDR_MTIMECMP_LO = 8'h08;
    localparam ADDR_MTIMECMP_HI = 8'h0C;
    localparam ADDR_PRESCALER   = 8'h10;

    // ----------------------------------------------------------------
    // Internal registers
    // ----------------------------------------------------------------
    reg [63:0] mtime;
    reg [63:0] mtimecmp;
    reg [31:0] prescaler;
    reg [31:0] prescaler_cnt;

    // AXI-Lite write channel
    reg        aw_ready_reg;
    reg        w_ready_reg;
    reg        b_valid_reg;
    reg [7:0]  aw_addr_latched;
    reg        aw_done;
    reg        w_done;

    // AXI-Lite read channel
    reg        ar_ready_reg;
    reg        r_valid_reg;
    reg [31:0] r_data_reg;

    // IRQ output register
    reg        irq_timer_reg;

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
    assign irq_timer_o    = irq_timer_reg;

    // ----------------------------------------------------------------
    // Timer IRQ — registered comparison
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            irq_timer_reg <= 1'b0;
        end else begin
            irq_timer_reg <= (mtime >= mtimecmp);
        end
    end

    // ----------------------------------------------------------------
    // Prescaler counter and mtime increment
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            mtime         <= 64'd0;
            prescaler_cnt <= 32'd0;
        end else begin
            if (prescaler_cnt >= prescaler) begin
                prescaler_cnt <= 32'd0;
                mtime         <= mtime + 64'd1;
            end else begin
                prescaler_cnt <= prescaler_cnt + 32'd1;
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
            mtimecmp        <= 64'hFFFFFFFF_FFFFFFFF;
            prescaler       <= 32'd0;
        end else begin
            // Default: deassert ready pulses
            aw_ready_reg <= 1'b0;
            w_ready_reg  <= 1'b0;

            // Accept write address
            if (s_axil_awvalid && !aw_done) begin
                aw_ready_reg    <= 1'b1;
                aw_addr_latched <= s_axil_awaddr;
                aw_done         <= 1'b1;
            end

            // Accept write data
            if (s_axil_wvalid && !w_done) begin
                w_ready_reg <= 1'b1;
                w_done      <= 1'b1;
            end

            // When both address and data are captured, perform write
            if ((aw_done || (s_axil_awvalid && !aw_done)) &&
                (w_done  || (s_axil_wvalid  && !w_done))  &&
                !b_valid_reg) begin

                b_valid_reg <= 1'b1;

                case (aw_addr_latched)
                    ADDR_MTIMECMP_LO: begin
                        if (s_axil_wstrb[0]) mtimecmp[ 7: 0] <= s_axil_wdata[ 7: 0];
                        if (s_axil_wstrb[1]) mtimecmp[15: 8] <= s_axil_wdata[15: 8];
                        if (s_axil_wstrb[2]) mtimecmp[23:16] <= s_axil_wdata[23:16];
                        if (s_axil_wstrb[3]) mtimecmp[31:24] <= s_axil_wdata[31:24];
                    end
                    ADDR_MTIMECMP_HI: begin
                        if (s_axil_wstrb[0]) mtimecmp[39:32] <= s_axil_wdata[ 7: 0];
                        if (s_axil_wstrb[1]) mtimecmp[47:40] <= s_axil_wdata[15: 8];
                        if (s_axil_wstrb[2]) mtimecmp[55:48] <= s_axil_wdata[23:16];
                        if (s_axil_wstrb[3]) mtimecmp[63:56] <= s_axil_wdata[31:24];
                    end
                    ADDR_PRESCALER: begin
                        if (s_axil_wstrb[0]) prescaler[ 7: 0] <= s_axil_wdata[ 7: 0];
                        if (s_axil_wstrb[1]) prescaler[15: 8] <= s_axil_wdata[15: 8];
                        if (s_axil_wstrb[2]) prescaler[23:16] <= s_axil_wdata[23:16];
                        if (s_axil_wstrb[3]) prescaler[31:24] <= s_axil_wdata[31:24];
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
                    ADDR_MTIME_LO:    r_data_reg <= mtime[31:0];
                    ADDR_MTIME_HI:    r_data_reg <= mtime[63:32];
                    ADDR_MTIMECMP_LO: r_data_reg <= mtimecmp[31:0];
                    ADDR_MTIMECMP_HI: r_data_reg <= mtimecmp[63:32];
                    ADDR_PRESCALER:   r_data_reg <= prescaler;
                    default:          r_data_reg <= 32'd0;
                endcase
            end

            if (r_valid_reg && s_axil_rready) begin
                r_valid_reg <= 1'b0;
            end
        end
    end

endmodule
