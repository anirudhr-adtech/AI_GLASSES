`timescale 1ns / 1ps
//============================================================================
// tb_i2c_master_fsm.v — Self-checking testbench for i2c_master_fsm
// Simulates a basic I2C write transaction with a simple slave model.
//============================================================================

module tb_i2c_master_fsm;

    reg         clk, rst_n;
    reg         start;
    reg  [7:0]  slave_addr;
    reg  [7:0]  xfer_len;
    reg  [15:0] prescaler;
    reg  [7:0]  tx_data;
    reg         tx_valid;
    wire        tx_ready;
    wire [7:0]  rx_data;
    wire        rx_valid;
    wire        busy, done, nack;
    wire        scl_o, scl_oe, sda_o, sda_oe;
    reg         scl_i, sda_i;

    i2c_master_fsm uut (
        .clk           (clk),
        .rst_n         (rst_n),
        .start_i       (start),
        .slave_addr_i  (slave_addr),
        .xfer_len_i    (xfer_len),
        .prescaler_i   (prescaler),
        .tx_data_i     (tx_data),
        .tx_valid_i    (tx_valid),
        .tx_ready_o    (tx_ready),
        .rx_data_o     (rx_data),
        .rx_valid_o    (rx_valid),
        .busy_o        (busy),
        .done_o        (done),
        .nack_o        (nack),
        .i2c_scl_o     (scl_o),
        .i2c_scl_oe_o  (scl_oe),
        .i2c_scl_i     (scl_i),
        .i2c_sda_o     (sda_o),
        .i2c_sda_oe_o  (sda_oe),
        .i2c_sda_i     (sda_i)
    );

    // Open-drain bus model
    wire scl_line = scl_oe ? 1'b0 : 1'b1;
    wire sda_line = sda_oe ? 1'b0 : sda_i;

    // Feed bus back
    always @(*) scl_i = scl_line;

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

    // Simple slave ACK model: always ACK (pull SDA low when addressed)
    // In real test this would be more complex; here we just ACK everything
    reg slave_ack;
    always @(*) begin
        if (!sda_oe && slave_ack)
            sda_i = 1'b0; // slave pulls low for ACK
        else if (!sda_oe)
            sda_i = 1'b1; // released
        else
            sda_i = 1'b0; // master driving
    end

    initial begin
        rst_n = 0; start = 0; slave_addr = 0; xfer_len = 0;
        prescaler = 16'd2; // fast sim
        tx_data = 0; tx_valid = 0; slave_ack = 0;
        sda_i = 1;
        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        check("idle at start", busy == 1'b0);

        // Start a 1-byte write to address 0x50 (write: bit0=0)
        slave_addr = 8'hA0; // 0x50 << 1 | 0 = 0xA0
        xfer_len   = 8'd1;
        tx_data    = 8'h55;
        tx_valid   = 1;
        slave_ack  = 1; // slave will ACK

        start = 1;
        @(posedge clk);
        start = 0;

        check("busy after start", busy == 1'b1);

        // Wait for done (while-loop timeout pattern)
        begin : wait_done_blk
            integer i2c_countdown;
            i2c_countdown = 5000;
            while (!done && i2c_countdown > 0) begin
                @(posedge clk);
                i2c_countdown = i2c_countdown - 1;
            end
            if (done) begin
                check("done asserted", 1'b1);
            end else begin
                check("transfer completed in time", 1'b0);
            end
        end

        @(posedge clk);
        tx_valid = 0;
        repeat (10) @(posedge clk);

        $display("========================================");
        if (fail_count == 0)
            $display("I2C MASTER FSM TB: ALL %0d TESTS PASSED", pass_count);
        else
            $display("I2C MASTER FSM TB: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("========================================");
        $finish;
    end

endmodule
