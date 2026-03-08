`timescale 1ns/1ps
//============================================================================
// Testbench: tb_npu_weight_buf
// Verifies dual-port BRAM write/read operations
//============================================================================

module tb_npu_weight_buf;

    reg         clk;
    reg         port_a_en, port_a_we;
    reg  [14:0] port_a_addr;
    reg  [31:0] port_a_wdata;
    wire [31:0] port_a_rdata;
    reg         port_b_en;
    reg  [14:0] port_b_addr;
    wire [31:0] port_b_rdata;

    initial clk = 0;
    always #5 clk = ~clk;

    npu_weight_buf #(
        .DEPTH(32768), .DATA_WIDTH(32), .ADDR_WIDTH(15)
    ) dut (
        .clk         (clk),
        .port_a_en   (port_a_en),
        .port_a_we   (port_a_we),
        .port_a_addr (port_a_addr),
        .port_a_wdata(port_a_wdata),
        .port_a_rdata(port_a_rdata),
        .port_b_en   (port_b_en),
        .port_b_addr (port_b_addr),
        .port_b_rdata(port_b_rdata)
    );

    integer i, pass_count, fail_count;

    initial begin
        pass_count = 0; fail_count = 0;
        port_a_en = 0; port_a_we = 0;
        port_a_addr = 0; port_a_wdata = 0;
        port_b_en = 0; port_b_addr = 0;

        repeat (3) @(posedge clk);

        // Write 16 words via Port A
        for (i = 0; i < 16; i = i + 1) begin
            port_a_en = 1; port_a_we = 1;
            port_a_addr = i;
            port_a_wdata = 32'hDEAD0000 + i;
            @(posedge clk);
        end
        port_a_we = 0; port_a_en = 0;
        @(posedge clk);

        // Read back via Port B
        for (i = 0; i < 16; i = i + 1) begin
            port_b_en = 1;
            port_b_addr = i;
            @(posedge clk); // 1-cycle read latency
            @(posedge clk); // data available now
            if (port_b_rdata === (32'hDEAD0000 + i))
                pass_count = pass_count + 1;
            else begin
                fail_count = fail_count + 1;
                $display("FAIL: addr=%0d, got=%h, exp=%h", i, port_b_rdata, 32'hDEAD0000 + i);
            end
        end

        port_b_en = 0;
        repeat (3) @(posedge clk);
        $display("========================================");
        $display("tb_npu_weight_buf: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        if (fail_count == 0) $display("ALL TESTS PASSED");
        $finish;
    end

endmodule
