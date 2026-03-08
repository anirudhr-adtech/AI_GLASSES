`timescale 1ns/1ps
//============================================================================
// AI_GLASSES — DDR Subsystem (Simulation Model)
// Testbench: tb_mem_array
//============================================================================

module tb_mem_array;

    parameter MEM_SIZE_BYTES = 4096;  // Small for fast sim

    reg          clk;
    reg          wr_en;
    reg  [31:0]  wr_addr;
    reg  [127:0] wr_data;
    reg  [15:0]  wr_strb;
    reg          rd_en;
    reg  [31:0]  rd_addr;
    wire [127:0] rd_data;

    integer pass_count, fail_count;

    mem_array #(.MEM_SIZE_BYTES(MEM_SIZE_BYTES)) dut (
        .clk     (clk),
        .wr_en   (wr_en),
        .wr_addr (wr_addr),
        .wr_data (wr_data),
        .wr_strb (wr_strb),
        .rd_en   (rd_en),
        .rd_addr (rd_addr),
        .rd_data (rd_data)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task check;
        input [127:0] expected;
        input [255:0] msg;
        begin
            if (rd_data === expected) begin
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL: %0s expected=%h got=%h", msg, expected, rd_data);
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        wr_en = 0; rd_en = 0;
        wr_addr = 0; wr_data = 0; wr_strb = 0;
        rd_addr = 0;

        // Wait for reset
        @(posedge clk); @(posedge clk);

        // Test 1: Read unwritten address -> should be 0
        rd_en = 1; rd_addr = 32'h0000_0100;
        @(posedge clk); rd_en = 0;
        @(posedge clk);
        check(128'd0, "Read unwritten addr should be 0");

        // Test 2: Full 16-byte write and readback
        wr_en = 1; wr_addr = 32'h0000_0000;
        wr_data = 128'hDEADBEEF_CAFEBABE_12345678_AABBCCDD;
        wr_strb = 16'hFFFF;
        @(posedge clk); wr_en = 0;
        @(posedge clk);

        rd_en = 1; rd_addr = 32'h0000_0000;
        @(posedge clk); rd_en = 0;
        @(posedge clk);
        check(128'hDEADBEEF_CAFEBABE_12345678_AABBCCDD, "Full write readback");

        // Test 3: Partial write with byte strobes (write only bytes 0-3)
        wr_en = 1; wr_addr = 32'h0000_0010;
        wr_data = 128'hFFFFFFFF_FFFFFFFF_FFFFFFFF_11223344;
        wr_strb = 16'h000F;
        @(posedge clk); wr_en = 0;
        @(posedge clk);

        rd_en = 1; rd_addr = 32'h0000_0010;
        @(posedge clk); rd_en = 0;
        @(posedge clk);
        check(128'h00000000_00000000_00000000_11223344, "Partial strobe write");

        // Test 4: Overwrite partial bytes
        wr_en = 1; wr_addr = 32'h0000_0010;
        wr_data = 128'h00000000_00000000_00000000_AABB0000;
        wr_strb = 16'h000C;  // bytes 2-3 only
        @(posedge clk); wr_en = 0;
        @(posedge clk);

        rd_en = 1; rd_addr = 32'h0000_0010;
        @(posedge clk); rd_en = 0;
        @(posedge clk);
        check(128'h00000000_00000000_00000000_AABB3344, "Overwrite partial bytes");

        // Test 5: Write to high address
        wr_en = 1; wr_addr = 32'h0000_0F00;
        wr_data = 128'h01020304_05060708_090A0B0C_0D0E0F10;
        wr_strb = 16'hFFFF;
        @(posedge clk); wr_en = 0;
        @(posedge clk);

        rd_en = 1; rd_addr = 32'h0000_0F00;
        @(posedge clk); rd_en = 0;
        @(posedge clk);
        check(128'h01020304_05060708_090A0B0C_0D0E0F10, "High address write");

        @(posedge clk);
        $display("========================================");
        $display("tb_mem_array: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        if (fail_count == 0) $display("ALL TESTS PASSED");
        $finish;
    end

    initial begin
        $dumpfile("tb_mem_array.vcd");
        $dumpvars(0, tb_mem_array);
    end

endmodule
