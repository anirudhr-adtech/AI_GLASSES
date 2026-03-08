`timescale 1ns / 1ps
//============================================================================
// tb_i2c_integ.v — L2 Integration testbench for i2c_master
// Tests full I2C master with INLINE I2C slave BFM (Verilator-compatible).
// No pullup primitives or inout ports — uses explicit wired-AND bus model.
// 8 test scenarios: config, single write, register read, multi-byte read,
// NACK handling, IRQ flow, back-to-back transfers, status after reset.
//============================================================================

module tb_i2c_integ;

    // -----------------------------------------------------------------------
    // Clock / Reset
    // -----------------------------------------------------------------------
    reg clk, rst_n;
    initial clk = 0;
    always #5 clk = ~clk; // 100 MHz

    // -----------------------------------------------------------------------
    // AXI4-Lite signals
    // -----------------------------------------------------------------------
    reg  [7:0]  awaddr;
    reg         awvalid;
    wire        awready;
    reg  [31:0] wdata;
    reg  [3:0]  wstrb;
    reg         wvalid;
    wire        wready;
    wire [1:0]  bresp;
    wire        bvalid;
    reg         bready;
    reg  [7:0]  araddr;
    reg         arvalid;
    wire        arready;
    wire [31:0] rdata;
    wire [1:0]  rresp;
    wire        rvalid;
    reg         rready;

    // -----------------------------------------------------------------------
    // I2C bus signals — Verilator-compatible wired-AND model (no pullup)
    // -----------------------------------------------------------------------
    wire scl_o, scl_oe, sda_o, sda_oe;
    wire irq;

    // Slave drive signals (from inline slave BFM below)
    reg slave_sda_drive_low;
    reg slave_scl_drive_low;

    // Wired-AND bus: high unless someone pulls low
    wire scl_bus = (scl_oe | slave_scl_drive_low) ? 1'b0 : 1'b1;
    wire sda_bus = (sda_oe | slave_sda_drive_low) ? 1'b0 : 1'b1;

    // -----------------------------------------------------------------------
    // DUT: i2c_master
    // -----------------------------------------------------------------------
    i2c_master u_dut (
        .clk_i               (clk),
        .rst_ni              (rst_n),
        .s_axi_lite_awaddr   (awaddr),
        .s_axi_lite_awvalid  (awvalid),
        .s_axi_lite_awready  (awready),
        .s_axi_lite_wdata    (wdata),
        .s_axi_lite_wstrb    (wstrb),
        .s_axi_lite_wvalid   (wvalid),
        .s_axi_lite_wready   (wready),
        .s_axi_lite_bresp    (bresp),
        .s_axi_lite_bvalid   (bvalid),
        .s_axi_lite_bready   (bready),
        .s_axi_lite_araddr   (araddr),
        .s_axi_lite_arvalid  (arvalid),
        .s_axi_lite_arready  (arready),
        .s_axi_lite_rdata    (rdata),
        .s_axi_lite_rresp    (rresp),
        .s_axi_lite_rvalid   (rvalid),
        .s_axi_lite_rready   (rready),
        .i2c_scl_o           (scl_o),
        .i2c_scl_oe_o        (scl_oe),
        .i2c_scl_i           (scl_bus),
        .i2c_sda_o           (sda_o),
        .i2c_sda_oe_o        (sda_oe),
        .i2c_sda_i           (sda_bus),
        .irq_i2c_done_o      (irq)
    );

    // -----------------------------------------------------------------------
    // Inline I2C Slave BFM (replaces i2c_slave_model — Verilator compatible)
    // Models BMI160 IMU at address 0x68
    // -----------------------------------------------------------------------
    localparam [6:0] SLAVE_ADDR_BFM = 7'h68;

    // Slave FSM states
    localparam SL_IDLE       = 4'd0;
    localparam SL_GET_ADDR   = 4'd1;
    localparam SL_SEND_ACK   = 4'd2;
    localparam SL_WRITE_REG  = 4'd3;
    localparam SL_WRITE_DATA = 4'd4;
    localparam SL_READ_DATA  = 4'd5;
    localparam SL_WAIT_ACK   = 4'd6;
    localparam SL_SEND_ACK2  = 4'd7;

    reg [3:0]  sl_state;
    reg [3:0]  sl_next_after_ack;
    reg [7:0]  sl_shift;
    reg [3:0]  sl_bit_cnt;
    reg [7:0]  sl_reg_addr;
    reg        sl_rw_bit;
    reg        sl_addr_set;

    // Slave register map (256 bytes)
    reg [7:0] slave_reg_map [0:255];

    // Edge detection — 2-stage sync
    reg sl_sda_r, sl_sda_rr;
    reg sl_scl_r, sl_scl_rr;

    wire sl_sda_posedge = sl_sda_r && !sl_sda_rr;
    wire sl_sda_negedge = !sl_sda_r && sl_sda_rr;
    wire sl_scl_posedge = sl_scl_r && !sl_scl_rr;
    wire sl_scl_negedge = !sl_scl_r && sl_scl_rr;

    wire sl_start_cond = sl_sda_negedge && sl_scl_r;
    wire sl_stop_cond  = sl_sda_posedge && sl_scl_r;

    // Initialize slave register map
    integer sl_init_i;
    initial begin
        for (sl_init_i = 0; sl_init_i < 256; sl_init_i = sl_init_i + 1)
            slave_reg_map[sl_init_i] = 8'h00;
        // BMI160 chip ID
        slave_reg_map[8'h00] = 8'hD1;
        // Dummy accelerometer data (X/Y/Z, little-endian pairs)
        slave_reg_map[8'h02] = 8'h10;  // accel_x low
        slave_reg_map[8'h03] = 8'h27;  // accel_x high
        slave_reg_map[8'h04] = 8'hF0;  // accel_y low
        slave_reg_map[8'h05] = 8'hD8;  // accel_y high
        slave_reg_map[8'h06] = 8'h00;  // accel_z low
        slave_reg_map[8'h07] = 8'h40;  // accel_z high

        slave_sda_drive_low = 1'b0;
        slave_scl_drive_low = 1'b0;
        sl_state = SL_IDLE;
        sl_shift = 8'd0;
        sl_bit_cnt = 4'd0;
        sl_reg_addr = 8'd0;
        sl_rw_bit = 1'b0;
        sl_addr_set = 1'b0;
        sl_next_after_ack = SL_IDLE;
        sl_sda_r = 1'b1;
        sl_sda_rr = 1'b1;
        sl_scl_r = 1'b1;
        sl_scl_rr = 1'b1;
    end

    // Slave FSM — samples the bus wires directly
    always @(posedge clk) begin
        if (!rst_n) begin
            sl_sda_r  <= 1'b1;
            sl_sda_rr <= 1'b1;
            sl_scl_r  <= 1'b1;
            sl_scl_rr <= 1'b1;
            slave_sda_drive_low <= 1'b0;
            slave_scl_drive_low <= 1'b0;
            sl_state <= SL_IDLE;
            sl_shift <= 8'd0;
            sl_bit_cnt <= 4'd0;
            sl_reg_addr <= 8'd0;
            sl_rw_bit <= 1'b0;
            sl_addr_set <= 1'b0;
            sl_next_after_ack <= SL_IDLE;
        end else begin
            // Synchronise bus values (2-stage)
            sl_sda_r  <= sda_bus;
            sl_sda_rr <= sl_sda_r;
            sl_scl_r  <= scl_bus;
            sl_scl_rr <= sl_scl_r;

            // START condition
            if (sl_start_cond) begin
                sl_state <= SL_GET_ADDR;
                sl_bit_cnt <= 4'd0;
                slave_sda_drive_low <= 1'b0;
                slave_scl_drive_low <= 1'b0;
            end

            // STOP condition
            else if (sl_stop_cond) begin
                sl_state <= SL_IDLE;
                slave_sda_drive_low <= 1'b0;
                slave_scl_drive_low <= 1'b0;
                sl_addr_set <= 1'b0;
            end

            // SCL rising edge — sample SDA
            else if (sl_scl_posedge) begin
                case (sl_state)
                    SL_GET_ADDR: begin
                        sl_shift <= {sl_shift[6:0], sl_sda_r};
                        sl_bit_cnt <= sl_bit_cnt + 4'd1;
                        if (sl_bit_cnt == 4'd7) begin
                                if (sl_shift[6:0] == SLAVE_ADDR_BFM) begin
                                sl_rw_bit <= sl_sda_r;
                                sl_next_after_ack <= sl_sda_r ? SL_READ_DATA : SL_WRITE_REG;
                                sl_state <= SL_SEND_ACK;
                            end else begin
                                sl_state <= SL_IDLE;
                            end
                        end
                    end

                    SL_WRITE_REG: begin
                        sl_shift <= {sl_shift[6:0], sl_sda_r};
                        sl_bit_cnt <= sl_bit_cnt + 4'd1;
                        if (sl_bit_cnt == 4'd7) begin
                            sl_reg_addr <= {sl_shift[6:0], sl_sda_r};
                            sl_addr_set <= 1'b1;
                            sl_next_after_ack <= SL_WRITE_DATA;
                            sl_state <= SL_SEND_ACK;
                        end
                    end

                    SL_WRITE_DATA: begin
                        sl_shift <= {sl_shift[6:0], sl_sda_r};
                        sl_bit_cnt <= sl_bit_cnt + 4'd1;
                        if (sl_bit_cnt == 4'd7) begin
                            slave_reg_map[sl_reg_addr] <= {sl_shift[6:0], sl_sda_r};
                            sl_reg_addr <= sl_reg_addr + 8'd1;
                            sl_next_after_ack <= SL_WRITE_DATA;
                            sl_state <= SL_SEND_ACK;
                        end
                    end

                    SL_WAIT_ACK: begin
                        // Check master's SDA OE directly (BFM cheat):
                        // sda_oe=1 means master drives SDA low (ACK)
                        // sda_oe=0 means master released SDA (NACK)
                        if (sda_oe) begin
                            // ACK — master wants more
                            // Go through SL_SEND_ACK2 to pre-drive bit 7
                            sl_reg_addr <= sl_reg_addr + 8'd1;
                            sl_next_after_ack <= SL_READ_DATA;
                            sl_state <= SL_SEND_ACK2;
                            sl_bit_cnt <= 4'd0;
                            slave_sda_drive_low <= 1'b0; // release SDA
                        end else begin
                            // NACK — done
                            slave_sda_drive_low <= 1'b0;
                            sl_state <= SL_IDLE;
                        end
                    end

                    default: ;
                endcase
            end

            // SCL falling edge — drive SDA
            else if (sl_scl_negedge) begin
                case (sl_state)
                    SL_SEND_ACK: begin
                        slave_sda_drive_low <= 1'b1;  // pull SDA low = ACK
                        sl_bit_cnt <= 4'd0;
                        sl_state <= SL_SEND_ACK2;
                    end

                    SL_SEND_ACK2: begin
                        // Release ACK, transition to next state
                        slave_sda_drive_low <= 1'b0;
                        sl_bit_cnt <= 4'd0;

                        if (sl_next_after_ack == SL_READ_DATA) begin
                            sl_shift <= slave_reg_map[sl_reg_addr];
                            slave_sda_drive_low <= ~slave_reg_map[sl_reg_addr][7];
                            sl_state <= SL_READ_DATA;
                        end else begin
                            sl_state <= sl_next_after_ack;
                        end
                    end

                    SL_READ_DATA: begin
                        if (sl_bit_cnt < 4'd8) begin
                            if (sl_bit_cnt == 4'd0) begin
                                sl_shift <= slave_reg_map[sl_reg_addr];
                                slave_sda_drive_low <= ~slave_reg_map[sl_reg_addr][7];
                            end else begin
                                slave_sda_drive_low <= ~sl_shift[6];
                                sl_shift <= {sl_shift[5:0], 1'b0};
                            end
                            sl_bit_cnt <= sl_bit_cnt + 4'd1;

                            if (sl_bit_cnt == 4'd7) begin
                                sl_state <= SL_WAIT_ACK;
                            end
                        end
                    end

                    SL_WAIT_ACK: begin
                        slave_sda_drive_low <= 1'b0;
                    end

                    default: ;
                endcase
            end
        end
    end

    // -----------------------------------------------------------------------
    // Pass / Fail counters
    // -----------------------------------------------------------------------
    integer pass_count = 0;
    integer fail_count = 0;

    task check;
        input [255:0] msg;
        input         cond;
    begin
        if (cond) begin
            pass_count = pass_count + 1;
        end else begin
            fail_count = fail_count + 1;
            $display("FAIL: %0s at time %0t", msg, $time);
        end
    end
    endtask

    // -----------------------------------------------------------------------
    // AXI-Lite Write Task
    // -----------------------------------------------------------------------
    task axil_write;
        input [7:0]  addr;
        input [31:0] data_in;
        integer timeout;
    begin
        @(posedge clk); #1;
        awaddr = addr; awvalid = 1;
        wdata = data_in; wstrb = 4'hF; wvalid = 1;
        bready = 1;
        timeout = 200;
        while (timeout > 0) begin
            @(posedge clk); #1;
            if (awready && wready) timeout = 0;
            else timeout = timeout - 1;
        end
        @(posedge clk); #1;
        awvalid = 0; wvalid = 0;
        timeout = 200;
        while (timeout > 0) begin
            @(posedge clk); #1;
            if (bvalid) timeout = 0;
            else timeout = timeout - 1;
        end
        @(posedge clk); #1;
        bready = 0;
    end
    endtask

    // -----------------------------------------------------------------------
    // AXI-Lite Read Task
    // -----------------------------------------------------------------------
    task axil_read;
        input  [7:0]  addr;
        output [31:0] data_out;
        integer timeout;
    begin
        @(posedge clk); #1;
        araddr = addr; arvalid = 1; rready = 1;
        timeout = 200;
        while (timeout > 0) begin
            @(posedge clk); #1;
            if (arready) timeout = 0;
            else timeout = timeout - 1;
        end
        @(posedge clk); #1;
        arvalid = 0;
        timeout = 200;
        while (timeout > 0) begin
            @(posedge clk); #1;
            if (rvalid) timeout = 0;
            else timeout = timeout - 1;
        end
        data_out = rdata;
        @(posedge clk); #1;
        rready = 0;
    end
    endtask

    // -----------------------------------------------------------------------
    // Wait for transfer done (STATUS.done = bit1)
    // -----------------------------------------------------------------------
    task wait_i2c_done;
        integer timeout;
        reg [31:0] st;
    begin
        timeout = 50000;
        st = 32'd0;
        while (timeout > 0 && st[1] == 1'b0) begin
            axil_read(8'h04, st);
            timeout = timeout - 1;
        end
        if (timeout == 0)
            $display("WARNING: wait_i2c_done timed out at %0t", $time);
    end
    endtask

    // -----------------------------------------------------------------------
    // Register address constants
    // -----------------------------------------------------------------------
    localparam ADDR_CONTROL     = 8'h00;
    localparam ADDR_STATUS      = 8'h04;
    localparam ADDR_SLAVE_ADDR  = 8'h08;
    localparam ADDR_TXDATA      = 8'h0C;
    localparam ADDR_RXDATA      = 8'h10;
    localparam ADDR_XFER_LEN   = 8'h14;
    localparam ADDR_START       = 8'h18;
    localparam ADDR_PRESCALER   = 8'h1C;
    localparam ADDR_IRQ_CLEAR   = 8'h20;
    localparam ADDR_FIFO_STATUS = 8'h24;

    // -----------------------------------------------------------------------
    // Readback variable
    // -----------------------------------------------------------------------
    reg [31:0] rd_val;
    integer i;

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    initial begin
        $display("========================================");
        $display("I2C Integration Testbench — Starting");
        $display("========================================");

        // Initialise
        rst_n = 0; awvalid = 0; wvalid = 0; arvalid = 0;
        bready = 0; rready = 0;
        awaddr = 0; wdata = 0; wstrb = 0; araddr = 0;
        repeat (8) @(posedge clk);
        rst_n = 1;
        repeat (4) @(posedge clk);

        // ==================================================================
        // I8: Status After Reset
        // ==================================================================
        $display("\n--- I8: Status After Reset ---");

        axil_read(ADDR_STATUS, rd_val);
        check("I8: STATUS idle after reset", rd_val[2:0] == 3'b000);

        axil_read(ADDR_FIFO_STATUS, rd_val);
        check("I8: FIFO_STATUS empty after reset", rd_val[4:0] == 5'd0);

        // ==================================================================
        // I1: Register Config
        // ==================================================================
        $display("\n--- I1: Register Config ---");

        axil_write(ADDR_PRESCALER, 32'd100);
        axil_read(ADDR_PRESCALER, rd_val);
        check("I1: PRESCALER readback", rd_val[15:0] == 16'd100);

        axil_write(ADDR_CONTROL, 32'h0000_0001);
        axil_read(ADDR_CONTROL, rd_val);
        check("I1: CONTROL readback", rd_val[0] == 1'b1);

        // ==================================================================
        // I2: Single Byte Write
        // ==================================================================
        $display("\n--- I2: Single Byte Write ---");
        // Configure prescaler — use moderate value for simulation speed
        axil_write(ADDR_PRESCALER, 32'd10);

        // SLAVE_ADDR = 0x68 write: {7'h68, 1'b0} = 0xD0
        axil_write(ADDR_SLAVE_ADDR, 32'h0000_00D0);

        // TX FIFO: register address 0x3B, then data 0xAA
        axil_write(ADDR_TXDATA, 32'h0000_003B);
        axil_write(ADDR_TXDATA, 32'h0000_00AA);

        // XFER_LEN = 2
        axil_write(ADDR_XFER_LEN, 32'd2);

        // START
        axil_write(ADDR_START, 32'd1);

        // Wait for completion
        wait_i2c_done;

        // Check STATUS: done=1, nack=0
        axil_read(ADDR_STATUS, rd_val);
        check("I2: transfer done", rd_val[1] == 1'b1);
        check("I2: no NACK", rd_val[2] == 1'b0);

        // Verify slave BFM received the data
        check("I2: slave reg[0x3B] = 0xAA",
              slave_reg_map[8'h3B] == 8'hAA);

        // Clear done
        axil_write(ADDR_IRQ_CLEAR, 32'd1);
        repeat (4) @(posedge clk);

        // ==================================================================
        // I3: Register Read (Chip ID)
        // ==================================================================
        $display("\n--- I3: Register Read (Chip ID) ---");

        // Phase 1: Write register address 0x00 to slave
        axil_write(ADDR_SLAVE_ADDR, 32'h0000_00D0);
        axil_write(ADDR_TXDATA, 32'h0000_0000);
        axil_write(ADDR_XFER_LEN, 32'd1);
        axil_write(ADDR_START, 32'd1);
        wait_i2c_done;
        axil_read(ADDR_STATUS, rd_val);
        check("I3: write-phase done", rd_val[1] == 1'b1);
        axil_write(ADDR_IRQ_CLEAR, 32'd1);
        repeat (4) @(posedge clk);

        // Phase 2: Read 1 byte from slave
        axil_write(ADDR_SLAVE_ADDR, 32'h0000_00D1);
        axil_write(ADDR_XFER_LEN, 32'd1);
        axil_write(ADDR_START, 32'd1);
        wait_i2c_done;
        axil_read(ADDR_STATUS, rd_val);
        $display("  I3: STATUS = 0x%08h (busy=%b done=%b nack=%b)", rd_val, rd_val[0], rd_val[1], rd_val[2]);
        check("I3: read-phase done", rd_val[1] == 1'b1);

        // Debug: check slave state and reg addr
        $display("  I3: sl_reg_addr=%0d sl_rw_bit=%b sl_addr_set=%b", sl_reg_addr, sl_rw_bit, sl_addr_set);

        axil_read(ADDR_RXDATA, rd_val);
        $display("  I3: RXDATA = 0x%02h (expect 0xD1)", rd_val[7:0]);
        check("I3: chip ID = 0xD1", rd_val[7:0] == 8'hD1);

        axil_write(ADDR_IRQ_CLEAR, 32'd1);
        repeat (4) @(posedge clk);

        // ==================================================================
        // I4: Multi-Byte Read (6 bytes of accelerometer data)
        // ==================================================================
        $display("\n--- I4: Multi-Byte Read ---");

        // Phase 1: Set register pointer to 0x02
        axil_write(ADDR_SLAVE_ADDR, 32'h0000_00D0);
        axil_write(ADDR_TXDATA, 32'h0000_0002);
        axil_write(ADDR_XFER_LEN, 32'd1);
        axil_write(ADDR_START, 32'd1);
        wait_i2c_done;
        axil_write(ADDR_IRQ_CLEAR, 32'd1);
        repeat (4) @(posedge clk);

        // Phase 2: Read 6 bytes
        axil_write(ADDR_SLAVE_ADDR, 32'h0000_00D1);
        axil_write(ADDR_XFER_LEN, 32'd6);
        axil_write(ADDR_START, 32'd1);
        wait_i2c_done;
        axil_read(ADDR_STATUS, rd_val);
        check("I4: multi-read done", rd_val[1] == 1'b1);

        axil_read(ADDR_RXDATA, rd_val);
        $display("  I4: byte0 = 0x%02h (expect 0x10)", rd_val[7:0]);
        check("I4: byte0 = 0x10", rd_val[7:0] == 8'h10);

        axil_read(ADDR_RXDATA, rd_val);
        $display("  I4: byte1 = 0x%02h (expect 0x27)", rd_val[7:0]);
        check("I4: byte1 = 0x27", rd_val[7:0] == 8'h27);

        axil_read(ADDR_RXDATA, rd_val);
        $display("  I4: byte2 = 0x%02h (expect 0xF0)", rd_val[7:0]);
        check("I4: byte2 = 0xF0", rd_val[7:0] == 8'hF0);

        axil_read(ADDR_RXDATA, rd_val);
        $display("  I4: byte3 = 0x%02h (expect 0xD8)", rd_val[7:0]);
        check("I4: byte3 = 0xD8", rd_val[7:0] == 8'hD8);

        axil_read(ADDR_RXDATA, rd_val);
        $display("  I4: byte4 = 0x%02h (expect 0x00)", rd_val[7:0]);
        check("I4: byte4 = 0x00", rd_val[7:0] == 8'h00);

        axil_read(ADDR_RXDATA, rd_val);
        $display("  I4: byte5 = 0x%02h (expect 0x40)", rd_val[7:0]);
        check("I4: byte5 = 0x40", rd_val[7:0] == 8'h40);

        axil_write(ADDR_IRQ_CLEAR, 32'd1);
        repeat (4) @(posedge clk);

        // ==================================================================
        // I5: NACK Handling (non-existent slave at 0x7F)
        // ==================================================================
        $display("\n--- I5: NACK Handling ---");
        axil_write(ADDR_SLAVE_ADDR, 32'h0000_00FE); // 0x7F write
        // No TXDATA needed — NACK happens on address phase
        axil_write(ADDR_XFER_LEN, 32'd1);
        axil_write(ADDR_START, 32'd1);
        wait_i2c_done;

        axil_read(ADDR_STATUS, rd_val);
        check("I5: transfer done after NACK", rd_val[1] == 1'b1);
        check("I5: NACK detected", rd_val[2] == 1'b1);

        axil_write(ADDR_IRQ_CLEAR, 32'd1);
        repeat (4) @(posedge clk);

        // ==================================================================
        // I6: IRQ Flow
        // ==================================================================
        $display("\n--- I6: IRQ Flow ---");

        check("I6: IRQ deasserted before test", irq == 1'b0);

        axil_write(ADDR_SLAVE_ADDR, 32'h0000_00D0);
        axil_write(ADDR_TXDATA, 32'h0000_0010);
        axil_write(ADDR_TXDATA, 32'h0000_0055);
        axil_write(ADDR_XFER_LEN, 32'd2);
        axil_write(ADDR_START, 32'd1);
        wait_i2c_done;

        check("I6: IRQ asserted after done", irq == 1'b1);

        axil_write(ADDR_IRQ_CLEAR, 32'd1);
        repeat (4) @(posedge clk);
        check("I6: IRQ deasserted after clear", irq == 1'b0);

        // ==================================================================
        // I7: Back-to-Back Transfers
        // ==================================================================
        $display("\n--- I7: Back-to-Back Transfers ---");

        for (i = 0; i < 3; i = i + 1) begin
            axil_write(ADDR_SLAVE_ADDR, 32'h0000_00D0);
            axil_write(ADDR_TXDATA, {24'd0, 8'h40 + i[7:0]});
            axil_write(ADDR_TXDATA, {24'd0, 8'hB0 + i[7:0]});
            axil_write(ADDR_XFER_LEN, 32'd2);
            axil_write(ADDR_START, 32'd1);
            wait_i2c_done;

            axil_read(ADDR_STATUS, rd_val);
            check("I7: back-to-back done", rd_val[1] == 1'b1);
            check("I7: back-to-back no NACK", rd_val[2] == 1'b0);

            axil_write(ADDR_IRQ_CLEAR, 32'd1);
            repeat (4) @(posedge clk);
        end

        // Verify all three writes in slave reg map
        check("I7: slave reg[0x40] = 0xB0",
              slave_reg_map[8'h40] == 8'hB0);
        check("I7: slave reg[0x41] = 0xB1",
              slave_reg_map[8'h41] == 8'hB1);
        check("I7: slave reg[0x42] = 0xB2",
              slave_reg_map[8'h42] == 8'hB2);

        // ==================================================================
        // Summary
        // ==================================================================
        $display("\n========================================");
        if (fail_count == 0) begin
            $display("I2C INTEG TB: ALL %0d TESTS PASSED", pass_count);
            $display("ALL TESTS PASSED");
        end else begin
            $display("I2C INTEG TB: %0d PASSED, %0d FAILED",
                     pass_count, fail_count);
            $display("SOME TESTS FAILED");
        end
        $display("========================================");
        $finish;
    end


    // -----------------------------------------------------------------------
    // Timeout watchdog
    // -----------------------------------------------------------------------
    initial begin
        #50_000_000;
        $display("ERROR: Simulation timeout at %0t", $time);
        $finish;
    end

endmodule
