`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem — Testbench
// Module: tb_mfcc_out_buf
// Description: Self-checking testbench for mfcc_out_buf.
//////////////////////////////////////////////////////////////////////////////

module tb_mfcc_out_buf;

    reg        clk;
    reg        rst_n;
    reg        wr_en;
    reg [15:0] wr_data;
    reg [3:0]  wr_idx;
    wire       frame_ready;
    reg        bank_swap;
    reg        rd_en;
    reg [8:0]  rd_addr;
    wire [15:0] rd_data;

    mfcc_out_buf uut (
        .clk           (clk),
        .rst_n         (rst_n),
        .wr_en         (wr_en),
        .wr_data       (wr_data),
        .wr_idx        (wr_idx),
        .frame_ready_o (frame_ready),
        .bank_swap_i   (bank_swap),
        .rd_en         (rd_en),
        .rd_addr       (rd_addr),
        .rd_data       (rd_data)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer errors;
    integer v, c;

    initial begin
        $display("=== tb_mfcc_out_buf: START ===");
        errors = 0;
        rst_n = 0;
        wr_en = 0;
        wr_data = 0;
        wr_idx = 0;
        bank_swap = 0;
        rd_en = 0;
        rd_addr = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (3) @(posedge clk);

        // Test 1: Write 49 vectors of 10 coefficients each
        for (v = 0; v < 49; v = v + 1) begin
            for (c = 0; c < 10; c = c + 1) begin
                @(posedge clk);
                wr_en   = 1;
                wr_data = (v * 10 + c) & 16'hFFFF;
                wr_idx  = c[3:0];
            end
        end
        @(posedge clk);
        wr_en = 0;

        // Check frame_ready assertion
        repeat (3) @(posedge clk);
        if (!frame_ready) begin
            $display("FAIL: frame_ready not asserted after 49 vectors");
            errors = errors + 1;
        end

        // Test 2: Bank swap - after swap, frame_ready should deassert
        bank_swap = 1;
        @(posedge clk);
        bank_swap = 0;
        @(posedge clk);

        if (frame_ready) begin
            $display("FAIL: frame_ready should be 0 after bank swap");
            errors = errors + 1;
        end

        // Test 3: Read back from swapped (now inactive) bank
        // The bank that was written should now be readable
        repeat (2) @(posedge clk);
        begin : blk_read
            reg [15:0] expected;
            for (v = 0; v < 5; v = v + 1) begin
                for (c = 0; c < 10; c = c + 1) begin
                    rd_addr = v * 10 + c;
                    rd_en = 1;
                    @(posedge clk);
                    rd_en = 0;
                    @(posedge clk); // Wait for read
                    expected = (v * 10 + c) & 16'hFFFF;
                    if (rd_data != expected) begin
                        $display("FAIL: Read[%0d] = 0x%04X, expected 0x%04X",
                                 v*10+c, rd_data, expected);
                        errors = errors + 1;
                    end
                end
            end
        end

        // Test 4: Write second frame to new active bank
        for (v = 0; v < 49; v = v + 1) begin
            for (c = 0; c < 10; c = c + 1) begin
                @(posedge clk);
                wr_en   = 1;
                wr_data = 16'hA000 + (v * 10 + c);
                wr_idx  = c[3:0];
            end
        end
        @(posedge clk);
        wr_en = 0;

        repeat (3) @(posedge clk);
        if (!frame_ready) begin
            $display("FAIL: frame_ready not asserted after second frame");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("=== tb_mfcc_out_buf: PASSED ===");
        else
            $display("=== tb_mfcc_out_buf: FAILED (%0d errors) ===", errors);

        $finish;
    end

endmodule
