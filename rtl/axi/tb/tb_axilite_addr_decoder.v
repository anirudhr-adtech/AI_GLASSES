`timescale 1ns/1ps
//============================================================================
// Testbench: tb_axilite_addr_decoder
// Project:   AI_GLASSES — AXI Interconnect
// Description: Self-checking testbench for axilite_addr_decoder
//============================================================================

module tb_axilite_addr_decoder;

    reg         clk, rst_n;
    reg  [31:0] addr_i;
    wire [3:0]  periph_sel_o;
    wire        decode_error_o;

    integer pass_count, fail_count, test_num;

    axilite_addr_decoder #(
        .ADDR_WIDTH(32), .NUM_PERIPHS(11)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .addr_i(addr_i),
        .periph_sel_o(periph_sel_o),
        .decode_error_o(decode_error_o)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task check_periph;
        input [31:0] addr;
        input [3:0]  exp_sel;
        input        exp_error;
        begin
            addr_i = addr;
            @(posedge clk); @(posedge clk); // registered output
            test_num = test_num + 1;
            if (periph_sel_o === exp_sel && decode_error_o === exp_error) begin
                pass_count = pass_count + 1;
                $display("PASS %0d: addr=0x%08h sel=%0d err=%b", test_num, addr, periph_sel_o, decode_error_o);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL %0d: addr=0x%08h exp_sel=%0d got=%0d exp_err=%b got=%b",
                         test_num, addr, exp_sel, periph_sel_o, exp_error, decode_error_o);
            end
        end
    endtask

    initial begin
        $display("=== tb_axilite_addr_decoder START ===");
        pass_count = 0; fail_count = 0; test_num = 0;
        rst_n = 0; addr_i = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // P0: UART  0x2000_0000
        check_periph(32'h2000_0000, 4'd0, 1'b0);
        check_periph(32'h2000_00FF, 4'd0, 1'b0);

        // P1: Timer 0x2000_0100
        check_periph(32'h2000_0100, 4'd1, 1'b0);

        // P2: IRQ   0x2000_0200
        check_periph(32'h2000_0200, 4'd2, 1'b0);

        // P3: GPIO  0x2000_0300
        check_periph(32'h2000_0300, 4'd3, 1'b0);

        // P4: Camera 0x2000_0400
        check_periph(32'h2000_0400, 4'd4, 1'b0);

        // P5: Audio 0x2000_0500
        check_periph(32'h2000_0500, 4'd5, 1'b0);

        // P6: I2C   0x2000_0600
        check_periph(32'h2000_0600, 4'd6, 1'b0);

        // P7: SPI   0x2000_0700
        check_periph(32'h2000_0700, 4'd7, 1'b0);
        check_periph(32'h2000_07FF, 4'd7, 1'b0);

        // P8: NPU   0x3000_0000
        check_periph(32'h3000_0000, 4'd8, 1'b0);
        check_periph(32'h3000_00FF, 4'd8, 1'b0);

        // P9: DMA   0x4000_0000
        check_periph(32'h4000_0000, 4'd9, 1'b0);

        // Error: unmapped
        check_periph(32'h2000_0800, 4'd10, 1'b1);
        check_periph(32'h5000_0000, 4'd10, 1'b1);
        check_periph(32'h2000_1000, 4'd10, 1'b1);

        $display("=== tb_axilite_addr_decoder DONE ===");
        $display("PASSED: %0d  FAILED: %0d  TOTAL: %0d", pass_count, fail_count, pass_count + fail_count);
        if (fail_count == 0) $display("*** ALL TESTS PASSED ***");
        else $display("*** SOME TESTS FAILED ***");
        $finish;
    end

endmodule
