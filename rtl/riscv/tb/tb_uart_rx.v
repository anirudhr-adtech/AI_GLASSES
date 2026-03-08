`timescale 1ns/1ps
//============================================================================
// Testbench : tb_uart_rx
// Description : Self-checking testbench for uart_rx (UART 8N1 receiver
//               with 16x oversampling)
//============================================================================
module tb_uart_rx;

    reg        clk;
    reg        rst_n;
    reg        rx_in;
    reg        baud_tick_16x;
    wire [7:0] rx_data;
    wire       rx_valid;
    wire       rx_error;

    integer pass_count;
    integer fail_count;
    integer i;
    integer tick;

    // Clock generation: 100 MHz
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // DUT
    uart_rx u_rx (
        .clk           (clk),
        .rst_n         (rst_n),
        .rx_in         (rx_in),
        .baud_tick_16x (baud_tick_16x),
        .rx_data       (rx_data),
        .rx_valid      (rx_valid),
        .rx_error      (rx_error)
    );

    // Generate one 16x baud tick
    task pulse_tick;
        begin
            @(posedge clk);
            baud_tick_16x = 1'b1;
            @(posedge clk);
            baud_tick_16x = 1'b0;
        end
    endtask

    // Send 16 ticks for one bit period
    task send_bit;
        input val;
        begin
            rx_in = val;
            for (tick = 0; tick < 16; tick = tick + 1) begin
                pulse_tick;
            end
        end
    endtask

    // Send full UART frame: start + 8 data (LSB first) + stop
    task send_frame;
        input [7:0] data;
        input       stop_val;  // 1 = normal, 0 = framing error
        begin
            // Start bit
            send_bit(1'b0);
            // Data bits LSB first
            for (i = 0; i < 8; i = i + 1) begin
                send_bit(data[i]);
            end
            // Stop bit
            send_bit(stop_val);
            // Small idle gap
            rx_in = 1'b1;
            @(posedge clk); @(posedge clk);
        end
    endtask

    task check_rx;
        input [7:0] exp_data;
        input       exp_valid;
        input       exp_error;
        input [63:0] test_id;
        begin
            if (rx_data === exp_data && rx_valid === exp_valid && rx_error === exp_error) begin
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL test %0d: data=%h(%h) valid=%b(%b) error=%b(%b) at %0t",
                         test_id, rx_data, exp_data, rx_valid, exp_valid,
                         rx_error, exp_error, $time);
            end
        end
    endtask

    // Monitor rx_valid and rx_error pulses
    reg       got_valid;
    reg       got_error;
    reg [7:0] got_data;

    always @(posedge clk) begin
        if (rx_valid) begin
            got_valid = 1'b1;
            got_data  = rx_data;
        end
        if (rx_error)
            got_error = 1'b1;
    end

    initial begin
        pass_count    = 0;
        fail_count    = 0;
        rst_n         = 1'b0;
        rx_in         = 1'b1;  // idle HIGH
        baud_tick_16x = 1'b0;
        got_valid     = 1'b0;
        got_error     = 1'b0;
        got_data      = 8'd0;

        // Reset
        @(posedge clk); #1;
        @(posedge clk); #1;
        rst_n = 1'b1;
        @(posedge clk); #1;

        // Test 1: Receive 0x55 (normal frame)
        got_valid = 1'b0;
        got_error = 1'b0;
        send_frame(8'h55, 1'b1);
        @(posedge clk); #1;
        if (got_valid && !got_error && got_data === 8'h55)
            pass_count = pass_count + 1;
        else begin
            fail_count = fail_count + 1;
            $display("FAIL test 1: rx 0x55 — valid=%b error=%b data=%h", got_valid, got_error, got_data);
        end

        // Test 2: Receive 0xA3 (normal frame)
        got_valid = 1'b0;
        got_error = 1'b0;
        send_frame(8'hA3, 1'b1);
        @(posedge clk); #1;
        if (got_valid && !got_error && got_data === 8'hA3)
            pass_count = pass_count + 1;
        else begin
            fail_count = fail_count + 1;
            $display("FAIL test 2: rx 0xA3 — valid=%b error=%b data=%h", got_valid, got_error, got_data);
        end

        // Test 3: Receive 0x00
        got_valid = 1'b0;
        got_error = 1'b0;
        send_frame(8'h00, 1'b1);
        @(posedge clk); #1;
        if (got_valid && !got_error && got_data === 8'h00)
            pass_count = pass_count + 1;
        else begin
            fail_count = fail_count + 1;
            $display("FAIL test 3: rx 0x00 — valid=%b error=%b data=%h", got_valid, got_error, got_data);
        end

        // Test 4: Receive 0xFF
        got_valid = 1'b0;
        got_error = 1'b0;
        send_frame(8'hFF, 1'b1);
        @(posedge clk); #1;
        if (got_valid && !got_error && got_data === 8'hFF)
            pass_count = pass_count + 1;
        else begin
            fail_count = fail_count + 1;
            $display("FAIL test 4: rx 0xFF — valid=%b error=%b data=%h", got_valid, got_error, got_data);
        end

        // Test 5: Framing error (stop bit = 0)
        got_valid = 1'b0;
        got_error = 1'b0;
        send_frame(8'h42, 1'b0);
        @(posedge clk); #1;
        if (got_error && !got_valid)
            pass_count = pass_count + 1;
        else begin
            fail_count = fail_count + 1;
            $display("FAIL test 5: framing error — valid=%b error=%b", got_valid, got_error);
        end

        // Test 6: Normal reception after framing error recovery
        got_valid = 1'b0;
        got_error = 1'b0;
        // Wait a few cycles for idle
        repeat(5) @(posedge clk);
        send_frame(8'hBE, 1'b1);
        @(posedge clk); #1;
        if (got_valid && !got_error && got_data === 8'hBE)
            pass_count = pass_count + 1;
        else begin
            fail_count = fail_count + 1;
            $display("FAIL test 6: recovery rx 0xBE — valid=%b error=%b data=%h", got_valid, got_error, got_data);
        end

        // Summary
        $display("---------------------------------------");
        $display("Tests: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        $display("---------------------------------------");
        $finish;
    end

endmodule
