`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Camera Subsystem
// Testbench: tb_frame_buf_ctrl
//////////////////////////////////////////////////////////////////////////////

module tb_frame_buf_ctrl;

    reg        clk;
    reg        rst_n;
    reg [31:0] buf_a_addr;
    reg [31:0] buf_b_addr;
    reg        active_buf;
    reg        swap;
    wire [31:0] wr_addr;
    wire [31:0] rd_addr;

    integer err_count;

    frame_buf_ctrl uut (
        .clk          (clk),
        .rst_n        (rst_n),
        .buf_a_addr_i (buf_a_addr),
        .buf_b_addr_i (buf_b_addr),
        .active_buf_i (active_buf),
        .swap_i       (swap),
        .wr_addr_o    (wr_addr),
        .rd_addr_o    (rd_addr)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        err_count  = 0;
        rst_n      = 0;
        buf_a_addr = 32'h1000_0000;
        buf_b_addr = 32'h2000_0000;
        active_buf = 0;
        swap       = 0;

        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (2) @(posedge clk);
        #1;

        // Initial state: active_buf=0 -> write to A, read from B
        if (wr_addr !== 32'h1000_0000) begin
            $display("FAIL: wr_addr = %h, expected 10000000", wr_addr);
            err_count = err_count + 1;
        end
        if (rd_addr !== 32'h2000_0000) begin
            $display("FAIL: rd_addr = %h, expected 20000000", rd_addr);
            err_count = err_count + 1;
        end

        // Swap
        swap = 1;
        @(posedge clk);
        swap = 0;
        @(posedge clk);
        #1;

        // After swap: write to B, read from A
        if (wr_addr !== 32'h2000_0000) begin
            $display("FAIL: after swap wr_addr = %h, expected 20000000", wr_addr);
            err_count = err_count + 1;
        end
        if (rd_addr !== 32'h1000_0000) begin
            $display("FAIL: after swap rd_addr = %h, expected 10000000", rd_addr);
            err_count = err_count + 1;
        end

        // Swap again
        swap = 1;
        @(posedge clk);
        swap = 0;
        @(posedge clk);
        #1;

        // Back to original
        if (wr_addr !== 32'h1000_0000) begin
            $display("FAIL: after double swap wr_addr = %h, expected 10000000", wr_addr);
            err_count = err_count + 1;
        end

        // Test address change
        buf_a_addr = 32'h3000_0000;
        @(posedge clk);
        #1;
        if (wr_addr !== 32'h3000_0000) begin
            $display("FAIL: wr_addr not updated after addr change: %h", wr_addr);
            err_count = err_count + 1;
        end

        // Summary
        if (err_count == 0)
            $display("PASS: tb_frame_buf_ctrl — all tests passed");
        else
            $display("FAIL: tb_frame_buf_ctrl — %0d errors", err_count);

        $finish;
    end

endmodule
