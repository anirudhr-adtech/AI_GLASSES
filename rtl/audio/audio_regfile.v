`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem
// Module: audio_regfile
// Description: AXI4-Lite slave + register file. 16 registers per design doc.
//              Base offset 0x00..0x3C.
//////////////////////////////////////////////////////////////////////////////

module audio_regfile (
    input  wire        clk,
    input  wire        rst_n,
    // AXI4-Lite Slave Interface
    input  wire [31:0] s_axil_awaddr,
    input  wire        s_axil_awvalid,
    output reg         s_axil_awready,
    input  wire [31:0] s_axil_wdata,
    input  wire [3:0]  s_axil_wstrb,
    input  wire        s_axil_wvalid,
    output reg         s_axil_wready,
    output reg  [1:0]  s_axil_bresp,
    output reg         s_axil_bvalid,
    input  wire        s_axil_bready,
    input  wire [31:0] s_axil_araddr,
    input  wire        s_axil_arvalid,
    output reg         s_axil_arready,
    output reg  [31:0] s_axil_rdata,
    output reg  [1:0]  s_axil_rresp,
    output reg         s_axil_rvalid,
    input  wire        s_axil_rready,
    // Register outputs (directly to controller)
    output reg  [31:0] reg_audio_control,   // 0x00
    output wire [31:0] reg_audio_status,     // 0x04 (RO)
    output reg  [31:0] reg_sample_rate_div,  // 0x08
    output wire [31:0] reg_fifo_status,      // 0x0C (RO)
    output reg  [31:0] reg_mfcc_config,      // 0x10
    output reg  [31:0] reg_window_config,    // 0x14
    output reg  [31:0] reg_fft_config,       // 0x18
    output reg  [31:0] reg_dma_base_addr,    // 0x1C
    output reg  [31:0] reg_dma_length,       // 0x20
    output wire [31:0] reg_dma_wr_ptr,       // 0x24 (RO)
    output reg  [31:0] reg_gain_control,     // 0x28
    output reg  [31:0] reg_noise_floor,      // 0x2C
    output reg         reg_start_pulse,      // 0x30 (WO, self-clearing)
    output reg         reg_irq_clear_frame,  // 0x34 bit[0] (WO, self-clearing)
    output reg         reg_irq_clear_dma,    // 0x34 bit[1] (WO, self-clearing)
    output wire [31:0] reg_perf_cycles,      // 0x38 (RO)
    output wire [31:0] reg_frame_energy,     // 0x3C (RO)
    // Status inputs (from controller / pipeline)
    input  wire [31:0] status_i,
    input  wire [31:0] fifo_status_i,
    input  wire [31:0] dma_wr_ptr_i,
    input  wire [31:0] perf_cycles_i,
    input  wire [31:0] frame_energy_i
);

    // Read-only register assignments
    assign reg_audio_status = status_i;
    assign reg_fifo_status  = fifo_status_i;
    assign reg_dma_wr_ptr   = dma_wr_ptr_i;
    assign reg_perf_cycles  = perf_cycles_i;
    assign reg_frame_energy = frame_energy_i;

    // Internal
    reg        aw_ready_r;
    reg        w_ready_r;
    reg [5:0]  wr_addr;
    reg        wr_en;
    reg [5:0]  rd_addr;

    // Write channel FSM
    localparam WR_IDLE = 2'd0;
    localparam WR_DATA = 2'd1;
    localparam WR_RESP = 2'd2;
    reg [1:0] wr_state;

    // Read channel FSM
    localparam RD_IDLE = 1'd0;
    localparam RD_RESP = 1'd1;
    reg rd_state;

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_state          <= WR_IDLE;
            s_axil_awready    <= 1'b0;
            s_axil_wready     <= 1'b0;
            s_axil_bvalid     <= 1'b0;
            s_axil_bresp      <= 2'b00;
            wr_addr           <= 6'd0;
            wr_en             <= 1'b0;
            reg_audio_control <= 32'd0;
            reg_sample_rate_div <= 32'd0;
            reg_mfcc_config   <= 32'd0;
            reg_window_config <= 32'd0;
            reg_fft_config    <= 32'd0;
            reg_dma_base_addr <= 32'd0;
            reg_dma_length    <= 32'd0;
            reg_gain_control  <= 32'h0000_0100; // Unity gain
            reg_noise_floor   <= 32'd0;
            reg_start_pulse   <= 1'b0;
            reg_irq_clear_frame <= 1'b0;
            reg_irq_clear_dma   <= 1'b0;
        end else begin
            // Self-clearing pulses
            reg_start_pulse     <= 1'b0;
            reg_irq_clear_frame <= 1'b0;
            reg_irq_clear_dma   <= 1'b0;

            // Soft reset self-clear
            if (reg_audio_control[1])
                reg_audio_control[1] <= 1'b0;

            case (wr_state)
                WR_IDLE: begin
                    s_axil_awready <= 1'b1;
                    s_axil_wready  <= 1'b1;
                    if (s_axil_awvalid && s_axil_wvalid) begin
                        wr_addr        <= s_axil_awaddr[7:2];
                        s_axil_awready <= 1'b0;
                        s_axil_wready  <= 1'b0;
                        // Write register
                        case (s_axil_awaddr[7:2])
                            6'h00: reg_audio_control   <= s_axil_wdata;
                            6'h02: reg_sample_rate_div <= s_axil_wdata;
                            6'h04: reg_mfcc_config     <= s_axil_wdata;
                            6'h05: reg_window_config   <= s_axil_wdata;
                            6'h06: reg_fft_config      <= s_axil_wdata;
                            6'h07: reg_dma_base_addr   <= s_axil_wdata;
                            6'h08: reg_dma_length      <= s_axil_wdata;
                            6'h0A: reg_gain_control    <= s_axil_wdata;
                            6'h0B: reg_noise_floor     <= s_axil_wdata;
                            6'h0C: reg_start_pulse     <= s_axil_wdata[0];
                            6'h0D: begin
                                reg_irq_clear_frame <= s_axil_wdata[0];
                                reg_irq_clear_dma   <= s_axil_wdata[1];
                            end
                            default: ; // Read-only or reserved
                        endcase
                        wr_state <= WR_RESP;
                    end else if (s_axil_awvalid) begin
                        wr_addr        <= s_axil_awaddr[7:2];
                        s_axil_awready <= 1'b0;
                        wr_state       <= WR_DATA;
                    end
                end

                WR_DATA: begin
                    s_axil_wready <= 1'b1;
                    if (s_axil_wvalid) begin
                        s_axil_wready <= 1'b0;
                        case (wr_addr)
                            6'h00: reg_audio_control   <= s_axil_wdata;
                            6'h02: reg_sample_rate_div <= s_axil_wdata;
                            6'h04: reg_mfcc_config     <= s_axil_wdata;
                            6'h05: reg_window_config   <= s_axil_wdata;
                            6'h06: reg_fft_config      <= s_axil_wdata;
                            6'h07: reg_dma_base_addr   <= s_axil_wdata;
                            6'h08: reg_dma_length      <= s_axil_wdata;
                            6'h0A: reg_gain_control    <= s_axil_wdata;
                            6'h0B: reg_noise_floor     <= s_axil_wdata;
                            6'h0C: reg_start_pulse     <= s_axil_wdata[0];
                            6'h0D: begin
                                reg_irq_clear_frame <= s_axil_wdata[0];
                                reg_irq_clear_dma   <= s_axil_wdata[1];
                            end
                            default: ;
                        endcase
                        wr_state <= WR_RESP;
                    end
                end

                WR_RESP: begin
                    s_axil_bvalid <= 1'b1;
                    s_axil_bresp  <= 2'b00; // OKAY
                    if (s_axil_bvalid && s_axil_bready) begin
                        s_axil_bvalid <= 1'b0;
                        wr_state      <= WR_IDLE;
                    end
                end

                default: wr_state <= WR_IDLE;
            endcase
        end
    end

    // Read channel
    always @(posedge clk) begin
        if (!rst_n) begin
            rd_state       <= RD_IDLE;
            s_axil_arready <= 1'b0;
            s_axil_rvalid  <= 1'b0;
            s_axil_rdata   <= 32'd0;
            s_axil_rresp   <= 2'b00;
        end else begin
            case (rd_state)
                RD_IDLE: begin
                    s_axil_arready <= 1'b1;
                    if (s_axil_arvalid && s_axil_arready) begin
                        s_axil_arready <= 1'b0;
                        case (s_axil_araddr[7:2])
                            6'h00: s_axil_rdata <= reg_audio_control;
                            6'h01: s_axil_rdata <= status_i;
                            6'h02: s_axil_rdata <= reg_sample_rate_div;
                            6'h03: s_axil_rdata <= fifo_status_i;
                            6'h04: s_axil_rdata <= reg_mfcc_config;
                            6'h05: s_axil_rdata <= reg_window_config;
                            6'h06: s_axil_rdata <= reg_fft_config;
                            6'h07: s_axil_rdata <= reg_dma_base_addr;
                            6'h08: s_axil_rdata <= reg_dma_length;
                            6'h09: s_axil_rdata <= dma_wr_ptr_i;
                            6'h0A: s_axil_rdata <= reg_gain_control;
                            6'h0B: s_axil_rdata <= reg_noise_floor;
                            6'h0C: s_axil_rdata <= 32'd0; // START is WO
                            6'h0D: s_axil_rdata <= 32'd0; // IRQ_CLEAR is WO
                            6'h0E: s_axil_rdata <= perf_cycles_i;
                            6'h0F: s_axil_rdata <= frame_energy_i;
                            default: s_axil_rdata <= 32'd0;
                        endcase
                        rd_state <= RD_RESP;
                    end
                end

                RD_RESP: begin
                    s_axil_rvalid <= 1'b1;
                    s_axil_rresp  <= 2'b00;
                    if (s_axil_rvalid && s_axil_rready) begin
                        s_axil_rvalid <= 1'b0;
                        rd_state      <= RD_IDLE;
                    end
                end

                default: rd_state <= RD_IDLE;
            endcase
        end
    end

endmodule
