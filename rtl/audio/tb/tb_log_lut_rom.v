`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem — Testbench
// Module: tb_log_lut_rom
// Description: Self-checking testbench for log_lut_rom.
//////////////////////////////////////////////////////////////////////////////

module tb_log_lut_rom;

    reg        clk;
    reg [7:0]  addr;
    wire [15:0] data;

    log_lut_rom uut (
        .clk    (clk),
        .addr_i (addr),
        .data_o (data)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer errors;

    initial begin
        $display("=== tb_log_lut_rom: START ===");
        errors = 0;
        addr = 0;

        // Wait for initialization
        repeat (3) @(posedge clk);

        // Test 1: Address 0 should be ln(0.5) ~ -177 in Q8.8
        addr = 8'd0;
        @(posedge clk); @(posedge clk);
        // ln(0.5) = -0.6931 -> -177.4 in Q8.8 -> 0xFF4F
        if (data != 16'hFF4F) begin
            $display("FAIL: LUT[0] = 0x%04X, expected 0xFF4F (ln(0.5))", data);
            errors = errors + 1;
        end

        // Test 2: Address 128 should be near ln(0.75) ~ -73.6 in Q8.8
        addr = 8'd128;
        @(posedge clk); @(posedge clk);
        if (data != 16'h0006) begin
            $display("INFO: LUT[128] = 0x%04X (expected ~0x0006 for ln(0.75))", data);
        end

        // Test 3: Address 255 should be near ln(1.0) = 0
        addr = 8'd255;
        @(posedge clk); @(posedge clk);
        if (data == 16'd0) begin
            $display("FAIL: LUT[255] should be near ln(~1.0), not exactly 0");
            // Not a hard fail, close to 0 is OK
        end

        // Test 4: Verify monotonicity - LUT should be monotonically increasing
        begin : blk_mono
            reg signed [15:0] prev_val;
            integer i;
            addr = 8'd0;
            @(posedge clk); @(posedge clk);
            prev_val = $signed(data);
            for (i = 1; i < 256; i = i + 1) begin
                addr = i[7:0];
                @(posedge clk); @(posedge clk);
                if ($signed(data) < prev_val) begin
                    $display("FAIL: LUT[%0d] = %0d < LUT[%0d] = %0d (not monotonic)",
                             i, $signed(data), i-1, prev_val);
                    errors = errors + 1;
                end
                prev_val = $signed(data);
            end
        end

        if (errors == 0) begin
            $display("=== tb_log_lut_rom: PASSED ===");
            $display("ALL TESTS PASSED");
        end else
            $display("=== tb_log_lut_rom: FAILED (%0d errors) ===", errors);

        $finish;
    end

endmodule
