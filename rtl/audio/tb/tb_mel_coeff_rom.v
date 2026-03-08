`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem — Testbench
// Module: tb_mel_coeff_rom
// Description: Self-checking testbench for mel_coeff_rom.
//////////////////////////////////////////////////////////////////////////////

module tb_mel_coeff_rom;

    reg        clk;
    reg [5:0]  filter_id;
    reg [5:0]  coeff_idx;
    wire [8:0] start_bin;
    wire [5:0] num_bins;
    wire [15:0] weight;

    mel_coeff_rom uut (
        .clk          (clk),
        .filter_id_i  (filter_id),
        .coeff_idx_i  (coeff_idx),
        .start_bin_o  (start_bin),
        .num_bins_o   (num_bins),
        .weight_o     (weight)
    );

    // Clock generation
    initial clk = 0;
    always #5 clk = ~clk;

    integer errors;
    integer f, b;

    initial begin
        $display("=== tb_mel_coeff_rom: START ===");
        errors = 0;
        filter_id = 0;
        coeff_idx = 0;

        @(posedge clk);
        @(posedge clk);

        // Test 1: Verify filter 0 metadata
        filter_id = 6'd0;
        coeff_idx = 6'd0;
        @(posedge clk); @(posedge clk);
        if (start_bin != 9'd1) begin
            $display("FAIL: filter 0 start_bin = %0d, expected 1", start_bin);
            errors = errors + 1;
        end
        if (num_bins != 6'd4) begin
            $display("FAIL: filter 0 num_bins = %0d, expected 4", num_bins);
            errors = errors + 1;
        end

        // Test 2: Verify filter 39 metadata
        filter_id = 6'd39;
        coeff_idx = 6'd0;
        @(posedge clk); @(posedge clk);
        if (start_bin != 9'd480) begin
            $display("FAIL: filter 39 start_bin = %0d, expected 480", start_bin);
            errors = errors + 1;
        end

        // Test 3: Verify weights are non-zero for valid bins, zero for invalid
        filter_id = 6'd0;
        coeff_idx = 6'd0;
        @(posedge clk); @(posedge clk);
        if (weight == 16'd0) begin
            $display("FAIL: filter 0, bin 0 weight should be non-zero");
            errors = errors + 1;
        end

        // Test 4: Check triangular shape - weight at edges should be < center
        filter_id = 6'd10;
        coeff_idx = 6'd0;
        @(posedge clk); @(posedge clk);
        begin : blk_edge
            reg [15:0] edge_weight;
            edge_weight = weight;
            coeff_idx = 6'd4; // Near center
            @(posedge clk); @(posedge clk);
            if (weight <= edge_weight) begin
                $display("FAIL: filter 10 center weight (%0d) should be > edge weight (%0d)", weight, edge_weight);
                errors = errors + 1;
            end
        end

        // Test 5: Sweep all 40 filters, verify start_bin is monotonically increasing
        begin : blk_mono
            reg [8:0] prev_start;
            prev_start = 9'd0;
            for (f = 0; f < 40; f = f + 1) begin
                filter_id = f[5:0];
                coeff_idx = 6'd0;
                @(posedge clk); @(posedge clk);
                if (start_bin < prev_start && f > 0) begin
                    $display("FAIL: filter %0d start_bin (%0d) < filter %0d start_bin (%0d)",
                             f, start_bin, f-1, prev_start);
                    errors = errors + 1;
                end
                prev_start = start_bin;
                if (num_bins == 6'd0) begin
                    $display("FAIL: filter %0d has num_bins = 0", f);
                    errors = errors + 1;
                end
            end
        end

        // Summary
        if (errors == 0) begin
            $display("=== tb_mel_coeff_rom: PASSED ===");
            $display("ALL TESTS PASSED");
        end else
            $display("=== tb_mel_coeff_rom: FAILED (%0d errors) ===", errors);

        $finish;
    end

endmodule
