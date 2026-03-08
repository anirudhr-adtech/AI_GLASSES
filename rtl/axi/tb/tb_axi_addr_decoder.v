`timescale 1ns/1ps
//============================================================================
// Testbench: tb_axi_addr_decoder
// Project:   AI_GLASSES — AXI Interconnect
// Description: Self-checking testbench for axi_addr_decoder
//============================================================================

module tb_axi_addr_decoder;

    reg         clk;
    reg         rst_n;
    reg  [31:0] addr_i;
    wire [4:0]  slave_sel_o;
    wire        addr_error_o;

    integer pass_count;
    integer fail_count;
    integer test_num;

    axi_addr_decoder #(
        .NUM_SLAVES(5),
        .ADDR_WIDTH(32)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .addr_i     (addr_i),
        .slave_sel_o(slave_sel_o),
        .addr_error_o(addr_error_o)
    );

    // 100 MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    task check_decode;
        input [31:0] addr;
        input [4:0]  exp_sel;
        input        exp_error;
        begin
            addr_i = addr;
            @(posedge clk);
            @(posedge clk); // wait for registered output
            test_num = test_num + 1;
            if (slave_sel_o === exp_sel && addr_error_o === exp_error) begin
                pass_count = pass_count + 1;
                $display("PASS test %0d: addr=0x%08h sel=0x%02h err=%0b", test_num, addr, slave_sel_o, addr_error_o);
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL test %0d: addr=0x%08h exp_sel=0x%02h got=0x%02h exp_err=%0b got=%0b",
                         test_num, addr, exp_sel, slave_sel_o, exp_error, addr_error_o);
            end
        end
    endtask

    initial begin
        $display("=== tb_axi_addr_decoder START ===");
        pass_count = 0;
        fail_count = 0;
        test_num   = 0;
        rst_n      = 0;
        addr_i     = 32'h0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        // S0: Boot ROM (0x0000_0000 - 0x0000_0FFF)
        check_decode(32'h0000_0000, 5'b00001, 1'b0);
        check_decode(32'h0000_0FFF, 5'b00001, 1'b0);

        // S0 overflow -> S4 error
        check_decode(32'h0000_1000, 5'b10000, 1'b1);
        check_decode(32'h0FFF_FFFF, 5'b10000, 1'b1);

        // S1: SRAM (0x1000_0000 - 0x1007_FFFF)
        check_decode(32'h1000_0000, 5'b00010, 1'b0);
        check_decode(32'h1007_FFFF, 5'b00010, 1'b0);

        // S1 overflow -> S4 error
        check_decode(32'h1008_0000, 5'b10000, 1'b1);
        check_decode(32'h1FFF_FFFF, 5'b10000, 1'b1);

        // S2: Peripherals
        check_decode(32'h2000_0000, 5'b00100, 1'b0);
        check_decode(32'h3000_0000, 5'b00100, 1'b0);
        check_decode(32'h4000_0000, 5'b00100, 1'b0);

        // S3: DDR (0x8000_0000+)
        check_decode(32'h8000_0000, 5'b01000, 1'b0);
        check_decode(32'hFFFF_FFFF, 5'b01000, 1'b0);
        check_decode(32'hA000_0000, 5'b01000, 1'b0);

        // S4: Unmapped ranges -> Error
        check_decode(32'h5000_0000, 5'b10000, 1'b0);
        check_decode(32'h6000_0000, 5'b10000, 1'b0);
        check_decode(32'h7000_0000, 5'b10000, 1'b0);

        // Summary
        $display("=== tb_axi_addr_decoder DONE ===");
        $display("PASSED: %0d  FAILED: %0d  TOTAL: %0d", pass_count, fail_count, pass_count + fail_count);
        if (fail_count == 0)
            $display("*** ALL TESTS PASSED ***");
        else
            $display("*** SOME TESTS FAILED ***");
        $finish;
    end

endmodule
