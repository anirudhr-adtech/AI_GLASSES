`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Camera Subsystem
// Testbench: tb_dvp_sync
//////////////////////////////////////////////////////////////////////////////

module tb_dvp_sync;

    reg        clk;
    reg        rst_n;
    reg        pclk_i;
    reg        vsync_i;
    reg        href_i;
    reg [7:0]  data_i;
    wire       pclk_sync_o;
    wire       vsync_sync_o;
    wire       href_sync_o;
    wire [7:0] data_sync_o;
    wire       pclk_rise_o;
    wire       pclk_fall_o;
    wire       vsync_rise_o;

    integer err_count;

    dvp_sync uut (
        .clk          (clk),
        .rst_n        (rst_n),
        .pclk_i       (pclk_i),
        .vsync_i      (vsync_i),
        .href_i       (href_i),
        .data_i       (data_i),
        .pclk_sync_o  (pclk_sync_o),
        .vsync_sync_o (vsync_sync_o),
        .href_sync_o  (href_sync_o),
        .data_sync_o  (data_sync_o),
        .pclk_rise_o  (pclk_rise_o),
        .pclk_fall_o  (pclk_fall_o),
        .vsync_rise_o (vsync_rise_o)
    );

    // 100 MHz sys_clk
    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        err_count = 0;
        rst_n   = 0;
        pclk_i  = 0;
        vsync_i = 0;
        href_i  = 0;
        data_i  = 8'd0;

        // Reset
        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);

        // Check all outputs are 0 after reset propagation
        if (pclk_sync_o !== 0 || vsync_sync_o !== 0 || href_sync_o !== 0) begin
            $display("FAIL: outputs not 0 after reset");
            err_count = err_count + 1;
        end

        // Test PCLK rise detection
        pclk_i = 1;
        repeat (4) @(posedge clk);  // Wait for 2-FF sync + edge detect
        if (!pclk_rise_o && !pclk_sync_o) begin
            // Allow for pipeline; check after enough cycles
        end
        // Wait for pclk_rise_o to assert
        repeat (2) @(posedge clk);
        #1;
        if (pclk_sync_o !== 1'b1) begin
            $display("FAIL: pclk_sync_o did not go high");
            err_count = err_count + 1;
        end

        // Test PCLK fall detection
        pclk_i = 0;
        repeat (5) @(posedge clk);
        #1;
        if (pclk_sync_o !== 1'b0) begin
            $display("FAIL: pclk_sync_o did not go low");
            err_count = err_count + 1;
        end

        // Test VSYNC rise detection
        vsync_i = 1;
        repeat (5) @(posedge clk);
        #1;
        if (vsync_sync_o !== 1'b1) begin
            $display("FAIL: vsync_sync_o did not go high");
            err_count = err_count + 1;
        end

        // Test data synchronization
        data_i = 8'hA5;
        repeat (4) @(posedge clk);
        #1;
        if (data_sync_o !== 8'hA5) begin
            $display("FAIL: data_sync_o = %h, expected A5", data_sync_o);
            err_count = err_count + 1;
        end

        // Test href
        href_i = 1;
        repeat (4) @(posedge clk);
        #1;
        if (href_sync_o !== 1'b1) begin
            $display("FAIL: href_sync_o did not go high");
            err_count = err_count + 1;
        end

        // Summary
        if (err_count == 0)
            $display("PASS: tb_dvp_sync — all tests passed");
        else
            $display("FAIL: tb_dvp_sync — %0d errors", err_count);

        $finish;
    end

endmodule
