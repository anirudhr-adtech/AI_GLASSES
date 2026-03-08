`timescale 1ns / 1ps
//============================================================================
// Module : clk_rst_mgr
// Project : AI_GLASSES — SoC Top-Level
// Description : Clock and reset management for the full SoC.
//               Synchronises the asynchronous Zynq FCLK_RESET0_N to
//               sys_clk (and optionally npu_clk), then produces a
//               sequenced reset tree:
//                 periph_rst_n deasserts first  (peripherals, crossbar, DDR)
//                 cpu_rst_n    deasserts 8 cycles later (CPU starts boot)
//                 npu_rst_n    deasserts after cpu  (NPU ready for cmds)
//============================================================================

module clk_rst_mgr (
    input  wire clk_i,          // 100 MHz sys_clk from Zynq FCLK_CLK0
    input  wire npu_clk_i,      // 200 MHz npu_clk (optional; tie to clk_i if single-domain)
    input  wire sys_rst_ni,     // Active-low async reset from Zynq FCLK_RESET0_N

    output wire periph_rst_no,  // Synchronised reset for peripherals / crossbar / DDR
    output wire cpu_rst_no,     // Reset for RISC-V CPU (deasserts 8 cycles after periph)
    output wire npu_rst_no      // Reset for NPU (synchronised to npu_clk domain)
);

    //------------------------------------------------------------------------
    // sys_clk domain: 2-FF synchroniser for async reset
    //------------------------------------------------------------------------
    reg [1:0] sync_sys;

    always @(posedge clk_i or negedge sys_rst_ni) begin
        if (!sys_rst_ni)
            sync_sys <= 2'b00;
        else
            sync_sys <= {sync_sys[0], 1'b1};
    end

    wire sys_rst_n_sync;
    assign sys_rst_n_sync = sync_sys[1];

    //------------------------------------------------------------------------
    // Reset sequencing counter (sys_clk domain)
    //   0–1 : all resets asserted
    //   2+  : periph_rst_n deasserts
    //   10+ : cpu_rst_n deasserts (8 cycles after periph)
    //   12+ : npu domain reset deasserts (2 extra cycles margin)
    //------------------------------------------------------------------------
    reg [3:0] seq_cnt;
    reg       periph_rst_r;
    reg       cpu_rst_r;
    reg       npu_release_r;   // flag in sys_clk domain before CDC

    always @(posedge clk_i) begin
        if (!sys_rst_n_sync) begin
            seq_cnt      <= 4'd0;
            periph_rst_r <= 1'b0;
            cpu_rst_r    <= 1'b0;
            npu_release_r <= 1'b0;
        end else begin
            if (seq_cnt < 4'd15)
                seq_cnt <= seq_cnt + 4'd1;

            if (seq_cnt >= 4'd2)
                periph_rst_r <= 1'b1;

            if (seq_cnt >= 4'd10)
                cpu_rst_r <= 1'b1;

            if (seq_cnt >= 4'd12)
                npu_release_r <= 1'b1;
        end
    end

    assign periph_rst_no = periph_rst_r;
    assign cpu_rst_no    = cpu_rst_r;

    //------------------------------------------------------------------------
    // npu_clk domain: 2-FF synchroniser for NPU reset
    //------------------------------------------------------------------------
    reg [1:0] sync_npu;

    always @(posedge npu_clk_i or negedge sys_rst_ni) begin
        if (!sys_rst_ni)
            sync_npu <= 2'b00;
        else
            sync_npu <= {sync_npu[0], npu_release_r};
    end

    assign npu_rst_no = sync_npu[1];

endmodule
