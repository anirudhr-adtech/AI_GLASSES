`timescale 1ns/1ps
//============================================================================
// Testbench : tb_uart_tx
// Description : Self-checking testbench for uart_tx (UART 8N1 transmitter)
//============================================================================
module tb_uart_tx;

    reg        clk;
    reg        rst_n;
    reg        tx_start;
    reg  [7:0] tx_data;
    reg        baud_tick;
    wire       tx_busy;
    wire       tx_done;
    wire       tx_out;

    integer pass_count;
    integer fail_count;
    integer i;

    // Captured frame
    reg [9:0] captured_frame;  // start + 8 data + stop
    integer   frame_idx;

    // Clock generation: 100 MHz
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // DUT
    uart_tx u_tx (
        .clk       (clk),
        .rst_n     (rst_n),
        .tx_start  (tx_start),
        .tx_data   (tx_data),
        .baud_tick (baud_tick),
        .tx_busy   (tx_busy),
        .tx_done   (tx_done),
        .tx_out    (tx_out)
    );

    // Generate a single baud tick pulse
    task pulse_baud;
        begin
            @(posedge clk);
            baud_tick = 1'b1;
            @(posedge clk);
            baud_tick = 1'b0;
        end
    endtask

    task check_val;
        input expected;
        input actual;
        input [63:0] test_id;
        begin
            if (actual === expected) begin
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
                $display("FAIL test %0d: got=%b, expected=%b at %0t",
                         test_id, actual, expected, $time);
            end
        end
    endtask

    // Transmit a byte and capture the frame
    task transmit_and_capture;
        input [7:0] data;
        begin
            // Start transmission
            @(posedge clk);
            tx_data  = data;
            tx_start = 1'b1;
            @(posedge clk);
            tx_start = 1'b0;

            // Start bit tick
            pulse_baud;
            #1;
            captured_frame[0] = tx_out;  // should be 0 (start bit)

            // 8 data bit ticks
            for (frame_idx = 0; frame_idx < 8; frame_idx = frame_idx + 1) begin
                pulse_baud;
                #1;
                captured_frame[1 + frame_idx] = tx_out;
            end

            // Stop bit tick
            pulse_baud;
            #1;
            captured_frame[9] = tx_out;  // should be 1 (stop bit)
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;
        rst_n     = 1'b0;
        tx_start  = 1'b0;
        tx_data   = 8'd0;
        baud_tick = 1'b0;

        // Reset
        @(posedge clk); #1;
        @(posedge clk); #1;
        rst_n = 1'b1;
        @(posedge clk); #1;

        // Test 1: tx_out idles HIGH
        check_val(1'b1, tx_out, 1);
        check_val(1'b0, tx_busy, 2);

        // Test 3: Transmit 0x55 (01010101)
        transmit_and_capture(8'h55);
        check_val(1'b0, captured_frame[0], 3);  // start bit = 0
        // Data bits LSB first: 1,0,1,0,1,0,1,0
        check_val(1'b1, captured_frame[1], 4);
        check_val(1'b0, captured_frame[2], 5);
        check_val(1'b1, captured_frame[3], 6);
        check_val(1'b0, captured_frame[4], 7);
        check_val(1'b1, captured_frame[5], 8);
        check_val(1'b0, captured_frame[6], 9);
        check_val(1'b1, captured_frame[7], 10);
        check_val(1'b0, captured_frame[8], 11);
        check_val(1'b1, captured_frame[9], 12);  // stop bit = 1

        // Test 13: tx_done should have pulsed
        // (It's already cleared by now, but tx_busy should be 0)
        #1;
        check_val(1'b0, tx_busy, 13);

        // Test 14: Transmit 0xA3 (10100011)
        transmit_and_capture(8'hA3);
        check_val(1'b0, captured_frame[0], 14);  // start
        // LSB first: 1,1,0,0,0,1,0,1
        check_val(1'b1, captured_frame[1], 15);
        check_val(1'b1, captured_frame[2], 16);
        check_val(1'b0, captured_frame[3], 17);
        check_val(1'b0, captured_frame[4], 18);
        check_val(1'b0, captured_frame[5], 19);
        check_val(1'b1, captured_frame[6], 20);
        check_val(1'b0, captured_frame[7], 21);
        check_val(1'b1, captured_frame[8], 22);
        check_val(1'b1, captured_frame[9], 23);  // stop

        // Summary
        $display("---------------------------------------");
        $display("Tests: %0d passed, %0d failed", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        $display("---------------------------------------");
        $finish;
    end

endmodule
