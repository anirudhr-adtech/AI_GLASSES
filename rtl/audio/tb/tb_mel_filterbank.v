`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem — Testbench
// Module: tb_mel_filterbank
// Description: Self-checking testbench for mel_filterbank.
//////////////////////////////////////////////////////////////////////////////

module tb_mel_filterbank;

    reg        clk;
    reg        rst_n;
    reg        start;
    wire [9:0] pwr_addr;
    wire       pwr_rd_en;
    wire       done;
    wire [31:0] mel_data;
    wire [5:0]  mel_idx;
    wire       mel_valid;

    // Simulated power spectrum memory
    reg [31:0] pwr_mem [0:1023];
    reg [31:0] pwr_data_r;

    always @(posedge clk) begin
        if (pwr_rd_en)
            pwr_data_r <= pwr_mem[pwr_addr];
    end

    mel_filterbank uut (
        .clk         (clk),
        .rst_n       (rst_n),
        .start_i     (start),
        .pwr_data_i  (pwr_data_r),
        .pwr_addr_o  (pwr_addr),
        .pwr_rd_en_o (pwr_rd_en),
        .done_o      (done),
        .mel_data_o  (mel_data),
        .mel_idx_o   (mel_idx),
        .mel_valid_o (mel_valid)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer errors;
    integer i;
    reg [5:0] mel_count;
    reg [31:0] mel_results [0:39];

    initial begin
        $display("=== tb_mel_filterbank: START ===");
        errors = 0;
        rst_n = 0;
        start = 0;
        mel_count = 0;

        // Initialize power spectrum with known values
        // Flat spectrum: all bins = 1000
        for (i = 0; i < 1024; i = i + 1)
            pwr_mem[i] = 32'd1000;

        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (3) @(posedge clk);

        // Start filterbank
        start = 1;
        @(posedge clk);
        start = 0;

        // Wait for completion, collect outputs
        fork
            begin : collect_outputs
                while (!done) begin
                    @(posedge clk);
                    if (mel_valid) begin
                        mel_results[mel_idx] = mel_data;
                        mel_count = mel_count + 1;
                    end
                end
            end
            begin : timeout
                repeat (50000) @(posedge clk);
                $display("FAIL: Timeout waiting for done");
                errors = errors + 1;
                disable collect_outputs;
            end
        join

        // Check: should have 40 outputs
        if (mel_count != 6'd40) begin
            $display("FAIL: Expected 40 mel outputs, got %0d", mel_count);
            errors = errors + 1;
        end

        // Check: all mel energies should be non-zero for flat spectrum
        for (i = 0; i < 40; i = i + 1) begin
            if (mel_results[i] == 32'd0) begin
                $display("FAIL: mel_energy[%0d] = 0 for flat spectrum", i);
                errors = errors + 1;
            end
        end

        // Test 2: Zero spectrum - all outputs should be zero
        for (i = 0; i < 1024; i = i + 1)
            pwr_mem[i] = 32'd0;

        mel_count = 0;
        repeat (3) @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        fork
            begin : collect2
                while (!done) begin
                    @(posedge clk);
                    if (mel_valid) begin
                        mel_results[mel_idx] = mel_data;
                        mel_count = mel_count + 1;
                    end
                end
            end
            begin : timeout2
                repeat (50000) @(posedge clk);
                disable collect2;
            end
        join

        for (i = 0; i < 40; i = i + 1) begin
            if (mel_results[i] != 32'd0) begin
                $display("FAIL: mel_energy[%0d] = %0d for zero spectrum, expected 0",
                         i, mel_results[i]);
                errors = errors + 1;
            end
        end

        if (errors == 0)
            $display("=== tb_mel_filterbank: PASSED ===");
        else
            $display("=== tb_mel_filterbank: FAILED (%0d errors) ===", errors);

        $finish;
    end

endmodule
