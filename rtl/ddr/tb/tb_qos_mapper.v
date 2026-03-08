`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — DDR Subsystem
// Testbench: tb_qos_mapper
// Description: Self-checking testbench for qos_mapper module.
//////////////////////////////////////////////////////////////////////////////

module tb_qos_mapper;

    parameter ID_WIDTH = 6;

    reg                  clk;
    reg                  rst_n;
    reg  [ID_WIDTH-1:0]  axi_id_i;
    wire [3:0]           qos_o;

    integer pass_count;
    integer fail_count;

    initial clk = 0;
    always #5 clk = ~clk;

    qos_mapper #(.ID_WIDTH(ID_WIDTH)) uut (
        .clk      (clk),
        .rst_n    (rst_n),
        .axi_id_i (axi_id_i),
        .qos_o    (qos_o)
    );

    task check_qos;
        input [ID_WIDTH-1:0] id_val;
        input [3:0]          expected;
    begin
        axi_id_i = id_val;
        @(posedge clk); // combinational -> register
        @(posedge clk); // read registered output
        if (qos_o === expected) begin
            $display("  PASS: ID=%b -> QoS=%h (expected %h)", id_val, qos_o, expected);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL: ID=%b -> QoS=%h (expected %h)", id_val, qos_o, expected);
            fail_count = fail_count + 1;
        end
    end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        rst_n      = 0;
        axi_id_i   = 0;
        @(posedge clk);
        @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        $display("[TEST] QoS mapper lookup table");

        // CPU iBus M0: top 3 bits = 000 -> 0x4
        check_qos(6'b000_000, 4'h4);
        check_qos(6'b000_111, 4'h4);

        // CPU dBus M1: top 3 bits = 001 -> 0x8
        check_qos(6'b001_000, 4'h8);
        check_qos(6'b001_101, 4'h8);

        // NPU M2: top 3 bits = 010 -> 0xF
        check_qos(6'b010_000, 4'hF);
        check_qos(6'b010_011, 4'hF);

        // Camera M3: top 3 bits = 011 -> 0xC
        check_qos(6'b011_000, 4'hC);
        check_qos(6'b011_110, 4'hC);

        // Audio M4: top 3 bits = 100 -> 0x2
        check_qos(6'b100_000, 4'h2);
        check_qos(6'b100_001, 4'h2);

        // Unmapped: top 3 bits = 101 -> 0x0
        check_qos(6'b101_000, 4'h0);

        // Unmapped: top 3 bits = 110 -> 0x0
        check_qos(6'b110_000, 4'h0);

        // Unmapped: top 3 bits = 111 -> 0x0
        check_qos(6'b111_000, 4'h0);

        #20;
        $display("===================================");
        $display("qos_mapper TB: %0d PASSED, %0d FAILED", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $display("===================================");
        $finish;
    end

    initial begin
        #10000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
