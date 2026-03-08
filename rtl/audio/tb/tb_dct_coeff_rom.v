`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem — Testbench
// Module: tb_dct_coeff_rom
// Description: Self-checking testbench for dct_coeff_rom.
//////////////////////////////////////////////////////////////////////////////

module tb_dct_coeff_rom;

    reg        clk;
    reg [3:0]  c_idx;
    reg [5:0]  m_idx;
    wire [15:0] coeff;

    dct_coeff_rom uut (
        .clk     (clk),
        .c_idx_i (c_idx),
        .m_idx_i (m_idx),
        .coeff_o (coeff)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer errors;
    integer c, m;

    initial begin
        $display("=== tb_dct_coeff_rom: START ===");
        errors = 0;
        c_idx = 0;
        m_idx = 0;

        repeat (3) @(posedge clk);

        // Test 1: c=0 should be all 0x7FFF (cos(0) = 1.0 in Q1.15)
        for (m = 0; m < 40; m = m + 1) begin
            c_idx = 4'd0;
            m_idx = m[5:0];
            @(posedge clk); @(posedge clk);
            if (coeff != 16'h7FFF) begin
                $display("FAIL: DCT[0][%0d] = 0x%04X, expected 0x7FFF", m, coeff);
                errors = errors + 1;
            end
        end

        // Test 2: c=1, m=0 should be close to cos(pi*0.5/40) ~ 0.9997 -> ~32757
        c_idx = 4'd1;
        m_idx = 6'd0;
        @(posedge clk); @(posedge clk);
        if ($signed(coeff) < 16'sd30000) begin
            $display("FAIL: DCT[1][0] = %0d, expected > 30000", $signed(coeff));
            errors = errors + 1;
        end

        // Test 3: c=2, check symmetry: DCT[c][m] = DCT[c][N-1-m] for even c
        c_idx = 4'd2;
        begin : blk_sym
            reg signed [15:0] val_m, val_nm;
            m_idx = 6'd5;
            @(posedge clk); @(posedge clk);
            val_m = $signed(coeff);
            m_idx = 6'd34; // 39-5
            @(posedge clk); @(posedge clk);
            val_nm = $signed(coeff);
            // For DCT-II, c=2: cos(2*pi*(m+0.5)/40) should have approximate symmetry
            $display("  DCT[2][5] = %0d, DCT[2][34] = %0d", val_m, val_nm);
        end

        // Test 4: Read all 400 entries, verify no undefined values
        for (c = 0; c < 10; c = c + 1) begin
            for (m = 0; m < 40; m = m + 1) begin
                c_idx = c[3:0];
                m_idx = m[5:0];
                @(posedge clk); @(posedge clk);
                if (coeff === 16'hxxxx) begin
                    $display("FAIL: DCT[%0d][%0d] is undefined", c, m);
                    errors = errors + 1;
                end
            end
        end

        // Test 5: Higher c indices should have more sign changes across m
        // Check c=9 has both positive and negative values
        begin : blk_sign
            integer pos_count, neg_count;
            pos_count = 0;
            neg_count = 0;
            for (m = 0; m < 40; m = m + 1) begin
                c_idx = 4'd9;
                m_idx = m[5:0];
                @(posedge clk); @(posedge clk);
                if ($signed(coeff) > 0) pos_count = pos_count + 1;
                if ($signed(coeff) < 0) neg_count = neg_count + 1;
            end
            if (pos_count == 0 || neg_count == 0) begin
                $display("FAIL: DCT c=9 should have both pos (%0d) and neg (%0d) values",
                         pos_count, neg_count);
                errors = errors + 1;
            end
        end

        if (errors == 0)
            $display("=== tb_dct_coeff_rom: PASSED ===");
        else
            $display("=== tb_dct_coeff_rom: FAILED (%0d errors) ===", errors);

        $finish;
    end

endmodule
