`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Camera Subsystem
// Module: cam_regfile
// Description: AXI4-Lite slave register file (24 registers)
//////////////////////////////////////////////////////////////////////////////

module cam_regfile (
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

    // Register outputs
    output reg  [31:0] cam_control_o,       // 0x00
    input  wire [31:0] cam_status_i,        // 0x04
    output reg  [31:0] sensor_config_o,     // 0x08
    output reg  [31:0] isp_config_o,        // 0x0C
    output reg  [31:0] isp_scale_x_o,       // 0x10
    output reg  [31:0] isp_scale_y_o,       // 0x14
    output reg  [31:0] frame_buf_a_addr_o,  // 0x18
    output reg  [31:0] frame_buf_b_addr_o,  // 0x1C
    output reg  [31:0] active_buf_o,        // 0x20
    output reg  [31:0] capture_start_o,     // 0x24
    output reg  [31:0] crop_x_o,            // 0x28
    output reg  [31:0] crop_y_o,            // 0x2C
    output reg  [31:0] crop_width_o,        // 0x30
    output reg  [31:0] crop_height_o,       // 0x34
    output reg  [31:0] crop_out_width_o,    // 0x38
    output reg  [31:0] crop_out_height_o,   // 0x3C
    output reg  [31:0] crop_buf_addr_o,     // 0x40
    output reg  [31:0] crop_start_o,        // 0x44
    output reg  [31:0] irq_clear_o,         // 0x48
    output reg  [31:0] raw_frame_addr_o,    // 0x4C
    output reg  [31:0] frame_size_bytes_o,  // 0x50
    input  wire [31:0] perf_capture_cyc_i,  // 0x54
    input  wire [31:0] perf_isp_cyc_i,      // 0x58
    input  wire [31:0] perf_crop_cyc_i      // 0x5C
);

    // Internal write address/data latches
    reg [7:0]  wr_addr;
    reg        aw_done;
    reg        w_done;

    // Write channel: accept AW and W independently, respond with B
    always @(posedge clk) begin
        if (!rst_n) begin
            s_axil_awready <= 1'b0;
            s_axil_wready  <= 1'b0;
            s_axil_bvalid  <= 1'b0;
            s_axil_bresp   <= 2'b00;
            aw_done        <= 1'b0;
            w_done         <= 1'b0;
            wr_addr        <= 8'd0;
        end else begin
            // Default deassert
            s_axil_awready <= 1'b0;
            s_axil_wready  <= 1'b0;

            // Accept write response
            if (s_axil_bvalid && s_axil_bready)
                s_axil_bvalid <= 1'b0;

            // Accept AW
            if (s_axil_awvalid && !aw_done && !s_axil_bvalid) begin
                s_axil_awready <= 1'b1;
                wr_addr        <= s_axil_awaddr;
                aw_done        <= 1'b1;
            end

            // Accept W
            if (s_axil_wvalid && !w_done && !s_axil_bvalid) begin
                s_axil_wready <= 1'b1;
                w_done        <= 1'b1;
            end

            // Perform write when both AW and W received
            if (aw_done && w_done) begin
                s_axil_bvalid <= 1'b1;
                s_axil_bresp  <= 2'b00;  // OKAY
                aw_done       <= 1'b0;
                w_done        <= 1'b0;
            end
        end
    end

    // Register write logic (byte strobes applied)
    wire [31:0] wdata_masked;
    assign wdata_masked = {
        s_axil_wstrb[3] ? s_axil_wdata[31:24] : 8'd0,
        s_axil_wstrb[2] ? s_axil_wdata[23:16] : 8'd0,
        s_axil_wstrb[1] ? s_axil_wdata[15:8]  : 8'd0,
        s_axil_wstrb[0] ? s_axil_wdata[7:0]   : 8'd0
    };

    always @(posedge clk) begin
        if (!rst_n) begin
            cam_control_o      <= 32'd0;
            sensor_config_o    <= 32'd0;
            isp_config_o       <= 32'd0;
            isp_scale_x_o     <= 32'h0001_0000;  // 1.0 in Q8.16
            isp_scale_y_o     <= 32'h0001_0000;
            frame_buf_a_addr_o <= 32'd0;
            frame_buf_b_addr_o <= 32'd0;
            active_buf_o       <= 32'd0;
            capture_start_o    <= 32'd0;
            crop_x_o           <= 32'd0;
            crop_y_o           <= 32'd0;
            crop_width_o       <= 32'd0;
            crop_height_o      <= 32'd0;
            crop_out_width_o   <= 32'd0;
            crop_out_height_o  <= 32'd0;
            crop_buf_addr_o    <= 32'd0;
            crop_start_o       <= 32'd0;
            irq_clear_o        <= 32'd0;
            raw_frame_addr_o   <= 32'd0;
            frame_size_bytes_o <= 32'd0;
        end else if (aw_done && w_done) begin
            case (wr_addr)
                8'h00: cam_control_o      <= s_axil_wdata;
                8'h08: sensor_config_o    <= s_axil_wdata;
                8'h0C: isp_config_o       <= s_axil_wdata;
                8'h10: isp_scale_x_o     <= s_axil_wdata;
                8'h14: isp_scale_y_o     <= s_axil_wdata;
                8'h18: frame_buf_a_addr_o <= s_axil_wdata;
                8'h1C: frame_buf_b_addr_o <= s_axil_wdata;
                8'h20: active_buf_o       <= s_axil_wdata;
                8'h24: capture_start_o    <= s_axil_wdata;
                8'h28: crop_x_o           <= s_axil_wdata;
                8'h2C: crop_y_o           <= s_axil_wdata;
                8'h30: crop_width_o       <= s_axil_wdata;
                8'h34: crop_height_o      <= s_axil_wdata;
                8'h38: crop_out_width_o   <= s_axil_wdata;
                8'h3C: crop_out_height_o  <= s_axil_wdata;
                8'h40: crop_buf_addr_o    <= s_axil_wdata;
                8'h44: crop_start_o       <= s_axil_wdata;
                8'h48: irq_clear_o        <= s_axil_wdata;
                8'h4C: raw_frame_addr_o   <= s_axil_wdata;
                8'h50: frame_size_bytes_o <= s_axil_wdata;
                default: ;  // read-only or reserved
            endcase
        end else begin
            // Auto-clear pulse registers
            capture_start_o <= 32'd0;
            crop_start_o    <= 32'd0;
            irq_clear_o     <= 32'd0;
        end
    end

    // Read channel
    reg [7:0] rd_addr;

    always @(posedge clk) begin
        if (!rst_n) begin
            s_axil_arready <= 1'b0;
            s_axil_rvalid  <= 1'b0;
            s_axil_rdata   <= 32'd0;
            s_axil_rresp   <= 2'b00;
            rd_addr        <= 8'd0;
        end else begin
            s_axil_arready <= 1'b0;

            // Accept read response
            if (s_axil_rvalid && s_axil_rready)
                s_axil_rvalid <= 1'b0;

            // Accept AR
            if (s_axil_arvalid && !s_axil_rvalid) begin
                s_axil_arready <= 1'b1;
                rd_addr        <= s_axil_araddr;
                s_axil_rvalid  <= 1'b1;
                s_axil_rresp   <= 2'b00;

                case (s_axil_araddr)
                    8'h00: s_axil_rdata <= cam_control_o;
                    8'h04: s_axil_rdata <= cam_status_i;
                    8'h08: s_axil_rdata <= sensor_config_o;
                    8'h0C: s_axil_rdata <= isp_config_o;
                    8'h10: s_axil_rdata <= isp_scale_x_o;
                    8'h14: s_axil_rdata <= isp_scale_y_o;
                    8'h18: s_axil_rdata <= frame_buf_a_addr_o;
                    8'h1C: s_axil_rdata <= frame_buf_b_addr_o;
                    8'h20: s_axil_rdata <= active_buf_o;
                    8'h24: s_axil_rdata <= capture_start_o;
                    8'h28: s_axil_rdata <= crop_x_o;
                    8'h2C: s_axil_rdata <= crop_y_o;
                    8'h30: s_axil_rdata <= crop_width_o;
                    8'h34: s_axil_rdata <= crop_height_o;
                    8'h38: s_axil_rdata <= crop_out_width_o;
                    8'h3C: s_axil_rdata <= crop_out_height_o;
                    8'h40: s_axil_rdata <= crop_buf_addr_o;
                    8'h44: s_axil_rdata <= crop_start_o;
                    8'h48: s_axil_rdata <= irq_clear_o;
                    8'h4C: s_axil_rdata <= raw_frame_addr_o;
                    8'h50: s_axil_rdata <= frame_size_bytes_o;
                    8'h54: s_axil_rdata <= perf_capture_cyc_i;
                    8'h58: s_axil_rdata <= perf_isp_cyc_i;
                    8'h5C: s_axil_rdata <= perf_crop_cyc_i;
                    default: s_axil_rdata <= 32'd0;
                endcase
            end
        end
    end

endmodule
