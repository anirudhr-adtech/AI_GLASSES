`timescale 1ns/1ps
//============================================================================
// AI_GLASSES — DDR Subsystem (Simulation Model)
// Testbench: tb_mem_preloader
//============================================================================

module tb_mem_preloader;

    parameter MEM_SIZE = 256;

    reg         clk;
    reg         preload_en;
    wire        wr_en;
    wire [31:0] wr_addr;
    wire [7:0]  wr_data_byte;

    integer pass_count, fail_count;
    integer i;
    integer fd;

    mem_preloader #(
        .MEM_SIZE_BYTES (MEM_SIZE),
        .HEX_FILE       ("tb_preload_test.hex"),
        .BASE_ADDR      (0)
    ) dut (
        .clk          (clk),
        .preload_en   (preload_en),
        .wr_en        (wr_en),
        .wr_addr      (wr_addr),
        .wr_data_byte (wr_data_byte)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // Track write count
    integer wr_count;
    reg [7:0] first_byte;
    reg       captured_first;

    initial begin
        pass_count = 0;
        fail_count = 0;
        preload_en = 0;
        wr_count = 0;
        captured_first = 0;

        // Create a test hex file
        fd = $fopen("tb_preload_test.hex", "w");
        $fwrite(fd, "DE\n");
        $fwrite(fd, "AD\n");
        $fwrite(fd, "BE\n");
        $fwrite(fd, "EF\n");
        $fclose(fd);

        repeat (3) @(posedge clk);

        // Test 1: Assert preload_en
        preload_en = 1;
        @(posedge clk);
        preload_en = 0;

        // Wait for loading to complete
        repeat (MEM_SIZE + 10) begin
            @(posedge clk);
            if (wr_en) begin
                wr_count = wr_count + 1;
                if (!captured_first) begin
                    first_byte = wr_data_byte;
                    captured_first = 1;
                end
            end
        end

        // Check that writes happened
        if (wr_count > 0) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: No writes occurred during preload");
        end

        // Check first byte was 0xDE
        if (first_byte == 8'hDE) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: First byte expected 0xDE got 0x%h", first_byte);
        end

        // Test 2: Second preload_en should not re-trigger (already done)
        wr_count = 0;
        preload_en = 1;
        @(posedge clk);
        preload_en = 0;
        repeat (20) begin
            @(posedge clk);
            if (wr_en) wr_count = wr_count + 1;
        end
        if (wr_count == 0) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: Second preload should not re-trigger");
        end

        @(posedge clk);
        $display("========================================");
        $display("tb_mem_preloader: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        if (fail_count == 0) $display("ALL TESTS PASSED");
        $finish;
    end

    initial begin
        $dumpfile("tb_mem_preloader.vcd");
        $dumpvars(0, tb_mem_preloader);
    end

endmodule
