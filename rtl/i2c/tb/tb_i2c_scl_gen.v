`timescale 1ns / 1ps
//============================================================================
// tb_i2c_scl_gen.v — Self-checking testbench for i2c_scl_gen
//============================================================================

module tb_i2c_scl_gen;

    reg         clk, rst_n;
    reg  [15:0] prescaler;
    reg         scl_en;
    wire        scl_o, scl_oe_o;
    wire        scl_i;
    wire        scl_rise, scl_fall, stretch_det;

    // Model open-drain: SCL bus is pulled high unless master drives low
    // or external pull-down (stretch_force) holds it low
    reg         stretch_force;
    assign scl_i = (scl_oe_o || stretch_force) ? 1'b0 : 1'b1;

    i2c_scl_gen uut (
        .clk                (clk),
        .rst_n              (rst_n),
        .prescaler_i        (prescaler),
        .scl_en             (scl_en),
        .scl_o              (scl_o),
        .scl_oe_o           (scl_oe_o),
        .scl_i              (scl_i),
        .scl_rise_o         (scl_rise),
        .scl_fall_o         (scl_fall),
        .stretch_detected_o (stretch_det)
    );

    integer pass_count = 0;
    integer fail_count = 0;

    task check;
        input [255:0] msg;
        input         cond;
    begin
        if (cond) pass_count = pass_count + 1;
        else begin
            fail_count = fail_count + 1;
            $display("FAIL: %0s at time %0t", msg, $time);
        end
    end
    endtask

    initial clk = 0;
    always #5 clk = ~clk; // 100MHz

    integer rise_count;
    integer fall_count;

    initial begin
        rst_n = 0; scl_en = 0; prescaler = 16'd4; stretch_force = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk); #1;

        // Check idle state
        check("SCL released when disabled", scl_oe_o == 1'b0);

        // Enable SCL generation with small prescaler for fast sim
        scl_en = 1;
        rise_count = 0;
        fall_count = 0;

        // Run for enough cycles to see several SCL toggles
        repeat (200) begin
            @(posedge clk); #1;
            if (scl_rise) rise_count = rise_count + 1;
            if (scl_fall) fall_count = fall_count + 1;
        end

        check("saw SCL rising edges", rise_count > 0);
        check("saw SCL falling edges", fall_count > 0);
        check("rise and fall counts balanced", (rise_count == fall_count) || (rise_count == fall_count + 1) || (rise_count + 1 == fall_count));

        // Test clock stretching: external device holds SCL low
        stretch_force = 1'b1;
        repeat (100) @(posedge clk); #1;
        check("stretch detected when SCL held low", stretch_det == 1'b1);

        // Release
        stretch_force = 1'b0;
        repeat (10) @(posedge clk); #1;
        check("stretch cleared after release", stretch_det == 1'b0);

        // Disable
        scl_en = 0;
        repeat (5) @(posedge clk); #1;
        check("SCL released after disable", scl_oe_o == 1'b0);

        @(posedge clk);
        $display("========================================");
        if (fail_count == 0) begin
            $display("I2C SCL GEN TB: ALL %0d TESTS PASSED", pass_count);
            $display("ALL TESTS PASSED");
        end else
            $display("I2C SCL GEN TB: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        $finish;
    end

endmodule
