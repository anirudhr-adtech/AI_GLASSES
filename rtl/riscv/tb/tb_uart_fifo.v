`timescale 1ns/1ps
//============================================================================
// Testbench : tb_uart_fifo
// Description : Self-checking testbench for uart_fifo (synchronous FIFO)
//============================================================================
module tb_uart_fifo;

    parameter DATA_WIDTH = 8;
    parameter DEPTH      = 4;  // small depth for easier testing
    parameter ADDR_WIDTH = $clog2(DEPTH);

    reg                    clk;
    reg                    rst_n;
    reg                    wr_en;
    reg                    rd_en;
    reg  [DATA_WIDTH-1:0]  din;
    wire [DATA_WIDTH-1:0]  dout;
    wire                   full;
    wire                   empty;
    wire [ADDR_WIDTH:0]    count;

    integer pass_count;
    integer fail_count;
    integer i;

    // Clock generation: 100 MHz
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // DUT
    uart_fifo #(
        .DATA_WIDTH (DATA_WIDTH),
        .DEPTH      (DEPTH)
    ) u_fifo (
        .clk   (clk),
        .rst_n (rst_n),
        .wr_en (wr_en),
        .rd_en (rd_en),
        .din   (din),
        .dout  (dout),
        .full  (full),
        .empty (empty),
        .count (count)
    );

    task check_flags;
        input exp_full;
        input exp_empty;
        input [ADDR_WIDTH:0] exp_count;
        input [63:0] test_id;
        begin
            if (full === exp_full && empty === exp_empty && count === exp_count) begin
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL test %0d: full=%b(%b) empty=%b(%b) count=%0d(%0d) at %0t",
                         test_id, full, exp_full, empty, exp_empty, count, exp_count, $time);
            end
        end
    endtask

    task check_dout;
        input [DATA_WIDTH-1:0] expected;
        input [63:0] test_id;
        begin
            if (dout === expected) begin
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL test %0d: dout=%h, expected=%h at %0t",
                         test_id, dout, expected, $time);
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        rst_n = 1'b0;
        wr_en = 1'b0;
        rd_en = 1'b0;
        din   = 8'd0;

        // Reset
        @(posedge clk); #1;
        @(posedge clk); #1;
        rst_n = 1'b1;
        @(posedge clk); #1;

        // Test 1: After reset, FIFO should be empty
        check_flags(1'b0, 1'b1, 0, 1);

        // Test 2-5: Write 4 items (fill FIFO)
        for (i = 0; i < DEPTH; i = i + 1) begin
            din   = i[DATA_WIDTH-1:0] + 8'hA0;
            wr_en = 1'b1;
            @(posedge clk); #1;
        end
        wr_en = 1'b0;

        // Test 2: FIFO should be full
        check_flags(1'b1, 1'b0, DEPTH, 2);

        // Test 3: Write when full — should be ignored, count stays same
        din   = 8'hFF;
        wr_en = 1'b1;
        @(posedge clk); #1;
        wr_en = 1'b0;
        check_flags(1'b1, 1'b0, DEPTH, 3);

        // Test 4: Read first item
        rd_en = 1'b1;
        @(posedge clk); #1;
        rd_en = 1'b0;
        check_dout(8'hA0, 4);
        check_flags(1'b0, 1'b0, DEPTH - 1, 5);

        // Test 6: Read remaining items
        for (i = 1; i < DEPTH; i = i + 1) begin
            rd_en = 1'b1;
            @(posedge clk); #1;
            rd_en = 1'b0;
            check_dout(i[DATA_WIDTH-1:0] + 8'hA0, 6 + i - 1);
        end

        // FIFO should now be empty
        @(posedge clk); #1;
        check_flags(1'b0, 1'b1, 0, 10);

        // Test 11: Read when empty — should be ignored
        rd_en = 1'b1;
        @(posedge clk); #1;
        rd_en = 1'b0;
        check_flags(1'b0, 1'b1, 0, 11);

        // Test 12: Simultaneous read+write when not empty
        // Write one item first
        din   = 8'h55;
        wr_en = 1'b1;
        @(posedge clk); #1;
        wr_en = 1'b0;
        // Now simultaneous read+write
        din   = 8'hAA;
        wr_en = 1'b1;
        rd_en = 1'b1;
        @(posedge clk); #1;
        wr_en = 1'b0;
        rd_en = 1'b0;
        check_flags(1'b0, 1'b0, 1, 12);  // count unchanged
        check_dout(8'h55, 13);  // read the old item

        // Summary
        $display("---------------------------------------");
        $display("Tests: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        $display("---------------------------------------");
        $finish;
    end

endmodule
