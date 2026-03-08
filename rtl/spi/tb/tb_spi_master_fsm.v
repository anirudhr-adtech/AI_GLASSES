`timescale 1ns / 1ps
//============================================================================
// tb_spi_master_fsm.v — Self-checking testbench for spi_master_fsm
//============================================================================

module tb_spi_master_fsm;

    reg        clk, rst_n;
    reg  [7:0] tx_data;
    reg        tx_valid;
    wire       tx_ready;
    wire [7:0] rx_data;
    wire       rx_valid;
    reg  [7:0] div;
    reg        cpol, cpha, auto_cs;
    wire       busy;
    wire       sclk, mosi, cs_n;
    reg        miso;

    spi_master_fsm uut (
        .clk         (clk),
        .rst_n       (rst_n),
        .tx_data_i   (tx_data),
        .tx_valid_i  (tx_valid),
        .tx_ready_o  (tx_ready),
        .rx_data_o   (rx_data),
        .rx_valid_o  (rx_valid),
        .div_i       (div),
        .cpol_i      (cpol),
        .cpha_i      (cpha),
        .auto_cs_i   (auto_cs),
        .busy_o      (busy),
        .spi_sclk_o  (sclk),
        .spi_mosi_o  (mosi),
        .spi_miso_i  (miso),
        .spi_cs_n_o  (cs_n)
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
    always #5 clk = ~clk;

    // Simple loopback: MISO = MOSI
    always @(*) miso = mosi;

    initial begin
        rst_n = 0; tx_data = 0; tx_valid = 0;
        div = 8'd1; cpol = 0; cpha = 0; auto_cs = 1;
        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        check("idle at start", busy == 1'b0);
        check("CS_n high at idle", cs_n == 1'b1);

        // Send one byte: 0xA5
        tx_data = 8'hA5;
        tx_valid = 1;
        @(posedge clk);
        // Wait for tx_ready
        wait (tx_ready);
        @(posedge clk);
        tx_valid = 0; // no more data after this byte

        check("busy during transfer", busy == 1'b1);
        check("CS_n low during transfer", cs_n == 1'b0);

        // Wait for rx_valid
        wait (rx_valid);
        @(posedge clk);
        check("RX valid asserted", 1'b1);
        // With loopback, rx_data should match tx_data
        check("loopback data correct", rx_data == 8'hA5);

        // Wait for idle
        repeat (100) @(posedge clk);
        check("CS_n high after transfer", cs_n == 1'b1);

        @(posedge clk);
        $display("========================================");
        if (fail_count == 0)
            $display("SPI MASTER FSM TB: ALL %0d TESTS PASSED", pass_count);
        else
            $display("SPI MASTER FSM TB: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        $finish;
    end

endmodule
