`timescale 1ns / 1ps
//============================================================================
// L3 Cross-Subsystem Testbench
// Instantiates soc_top with DDR model and UART monitor.
// CPU executes real RISC-V firmware from Boot ROM → SRAM.
// PASS/FAIL determined by UART output string.
//============================================================================

module tb_l3_top;

    // ================================================================
    // Parameters
    // ================================================================
    parameter CLK_PERIOD = 10; // 100 MHz
    parameter TIMEOUT_US = 50000; // Simulation timeout in microseconds (50ms)
    parameter TIMEOUT_CYCLES = TIMEOUT_US * 1000 / CLK_PERIOD;

    // ================================================================
    // Clock and Reset
    // ================================================================
    reg clk;
    reg rst_n;

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ================================================================
    // AXI3 DDR Model signals (64-bit, Zynq HP0 interface)
    // ================================================================
    wire [5:0]  hp0_awid;
    wire [31:0] hp0_awaddr;
    wire [3:0]  hp0_awlen;
    wire [2:0]  hp0_awsize;
    wire [1:0]  hp0_awburst;
    wire [3:0]  hp0_awqos;
    wire        hp0_awvalid;
    wire        hp0_awready;
    wire [63:0] hp0_wdata;
    wire [7:0]  hp0_wstrb;
    wire        hp0_wlast;
    wire        hp0_wvalid;
    wire        hp0_wready;
    wire [5:0]  hp0_bid;
    wire [1:0]  hp0_bresp;
    wire        hp0_bvalid;
    wire        hp0_bready;
    wire [5:0]  hp0_arid;
    wire [31:0] hp0_araddr;
    wire [3:0]  hp0_arlen;
    wire [2:0]  hp0_arsize;
    wire [1:0]  hp0_arburst;
    wire [3:0]  hp0_arqos;
    wire        hp0_arvalid;
    wire        hp0_arready;
    wire [5:0]  hp0_rid;
    wire [63:0] hp0_rdata;
    wire [1:0]  hp0_rresp;
    wire        hp0_rlast;
    wire        hp0_rvalid;
    wire        hp0_rready;

    // ================================================================
    // Peripheral signals
    // ================================================================
    wire        uart_tx;
    reg         uart_rx;
    reg         cam_pclk;
    reg         cam_vsync;
    reg         cam_href;
    reg  [7:0]  cam_data;
    reg         i2s_sck;
    reg         i2s_ws;
    reg         i2s_sd;
    wire        spi_sclk;
    wire        spi_mosi;
    reg         spi_miso;
    wire        spi_cs_n;
    wire        i2c_scl_o;
    wire        i2c_scl_oe;
    reg         i2c_scl_in;
    wire        i2c_sda_o;
    wire        i2c_sda_oe;
    reg         i2c_sda_in;
    reg  [7:0]  gpio_i;
    wire [7:0]  gpio_o;
    wire [7:0]  gpio_oe;
    reg         esp32_handshake;
    wire        esp32_reset_n;

    // ================================================================
    // DUT: soc_top
    // ================================================================
    soc_top u_dut (
        .sys_clk_i          (clk),
        .sys_rst_ni         (rst_n),
        .npu_clk_i          (clk),  // Same clock domain for Phase 0

        // AXI3 HP0 interface
        .m_axi_hp0_awid     (hp0_awid),
        .m_axi_hp0_awaddr   (hp0_awaddr),
        .m_axi_hp0_awlen    (hp0_awlen),
        .m_axi_hp0_awsize   (hp0_awsize),
        .m_axi_hp0_awburst  (hp0_awburst),
        .m_axi_hp0_awqos    (hp0_awqos),
        .m_axi_hp0_awvalid  (hp0_awvalid),
        .m_axi_hp0_awready  (hp0_awready),
        .m_axi_hp0_wdata    (hp0_wdata),
        .m_axi_hp0_wstrb    (hp0_wstrb),
        .m_axi_hp0_wlast    (hp0_wlast),
        .m_axi_hp0_wvalid   (hp0_wvalid),
        .m_axi_hp0_wready   (hp0_wready),
        .m_axi_hp0_bid      (hp0_bid),
        .m_axi_hp0_bresp    (hp0_bresp),
        .m_axi_hp0_bvalid   (hp0_bvalid),
        .m_axi_hp0_bready   (hp0_bready),
        .m_axi_hp0_arid     (hp0_arid),
        .m_axi_hp0_araddr   (hp0_araddr),
        .m_axi_hp0_arlen    (hp0_arlen),
        .m_axi_hp0_arsize   (hp0_arsize),
        .m_axi_hp0_arburst  (hp0_arburst),
        .m_axi_hp0_arqos    (hp0_arqos),
        .m_axi_hp0_arvalid  (hp0_arvalid),
        .m_axi_hp0_arready  (hp0_arready),
        .m_axi_hp0_rid      (hp0_rid),
        .m_axi_hp0_rdata    (hp0_rdata),
        .m_axi_hp0_rresp    (hp0_rresp),
        .m_axi_hp0_rlast    (hp0_rlast),
        .m_axi_hp0_rvalid   (hp0_rvalid),
        .m_axi_hp0_rready   (hp0_rready),

        // Peripherals
        .uart_tx_o          (uart_tx),
        .uart_rx_i          (uart_rx),
        .cam_pclk_i         (cam_pclk),
        .cam_vsync_i        (cam_vsync),
        .cam_href_i         (cam_href),
        .cam_data_i         (cam_data),
        .i2s_sck_i          (i2s_sck),
        .i2s_ws_i           (i2s_ws),
        .i2s_sd_i           (i2s_sd),
        .spi_sclk_o         (spi_sclk),
        .spi_mosi_o         (spi_mosi),
        .spi_miso_i         (spi_miso),
        .spi_cs_n_o         (spi_cs_n),
        .i2c_scl_o          (i2c_scl_o),
        .i2c_scl_oe_o       (i2c_scl_oe),
        .i2c_scl_i          (i2c_scl_in),
        .i2c_sda_o          (i2c_sda_o),
        .i2c_sda_oe_o       (i2c_sda_oe),
        .i2c_sda_i          (i2c_sda_in),
        .gpio_i             (gpio_i),
        .gpio_o             (gpio_o),
        .gpio_oe            (gpio_oe),
        .esp32_handshake_i  (esp32_handshake),
        .esp32_reset_n_o    (esp32_reset_n)
    );

    // ================================================================
    // AXI3 DDR Memory Model (64-bit, simple behavioral)
    // ================================================================
    // Simple memory model: accepts AXI3 read/write with registered responses
    reg [63:0] ddr_mem [0:65535]; // 64K x 64-bit = 512KB DDR model

    // --- AXI3 Write Channel ---
    reg        ddr_awready_r;
    reg        ddr_wready_r;
    reg        ddr_bvalid_r;
    reg [5:0]  ddr_bid_r;
    reg [31:0] ddr_aw_addr;
    reg [3:0]  ddr_aw_len;
    reg [5:0]  ddr_aw_id;
    reg [3:0]  ddr_w_cnt;

    localparam DW_IDLE = 2'd0, DW_DATA = 2'd1, DW_RESP = 2'd2;
    reg [1:0] ddr_w_state;

    assign hp0_awready = ddr_awready_r;
    assign hp0_wready  = ddr_wready_r;
    assign hp0_bvalid  = ddr_bvalid_r;
    assign hp0_bid     = ddr_bid_r;
    assign hp0_bresp   = 2'b00;

    always @(posedge clk) begin
        if (!rst_n) begin
            ddr_w_state  <= DW_IDLE;
            ddr_awready_r <= 1'b1;
            ddr_wready_r  <= 1'b0;
            ddr_bvalid_r  <= 1'b0;
            ddr_bid_r     <= 6'd0;
            ddr_aw_addr   <= 32'd0;
            ddr_aw_len    <= 4'd0;
            ddr_aw_id     <= 6'd0;
            ddr_w_cnt     <= 4'd0;
        end else begin
            case (ddr_w_state)
                DW_IDLE: begin
                    if (hp0_awvalid && ddr_awready_r) begin
                        ddr_aw_addr   <= hp0_awaddr;
                        ddr_aw_len    <= hp0_awlen;
                        ddr_aw_id     <= hp0_awid;
                        ddr_awready_r <= 1'b0;
                        ddr_wready_r  <= 1'b1;
                        ddr_w_cnt     <= 4'd0;
                        ddr_w_state   <= DW_DATA;
                    end
                end
                DW_DATA: begin
                    if (hp0_wvalid && ddr_wready_r) begin
                        // Write to memory (byte-enable)
                        // Address: use word address [18:3] for 64-bit words
                        ddr_mem[(ddr_aw_addr >> 3) + ddr_w_cnt] <= hp0_wdata;
                        ddr_w_cnt <= ddr_w_cnt + 4'd1;
                        if (hp0_wlast) begin
                            ddr_wready_r <= 1'b0;
                            ddr_bvalid_r <= 1'b1;
                            ddr_bid_r    <= ddr_aw_id;
                            ddr_w_state  <= DW_RESP;
                        end
                    end
                end
                DW_RESP: begin
                    if (hp0_bready && ddr_bvalid_r) begin
                        ddr_bvalid_r  <= 1'b0;
                        ddr_awready_r <= 1'b1;
                        ddr_w_state   <= DW_IDLE;
                    end
                end
                default: ddr_w_state <= DW_IDLE;
            endcase
        end
    end

    // --- AXI3 Read Channel ---
    reg        ddr_arready_r;
    reg        ddr_rvalid_r;
    reg [63:0] ddr_rdata_r;
    reg [5:0]  ddr_rid_r;
    reg        ddr_rlast_r;
    reg [31:0] ddr_ar_addr;
    reg [3:0]  ddr_ar_len;
    reg [5:0]  ddr_ar_id;
    reg [3:0]  ddr_r_cnt;

    localparam DR_IDLE = 2'd0, DR_DATA = 2'd1;
    reg [1:0] ddr_r_state;

    assign hp0_arready = ddr_arready_r;
    assign hp0_rvalid  = ddr_rvalid_r;
    assign hp0_rdata   = ddr_rdata_r;
    assign hp0_rid     = ddr_rid_r;
    assign hp0_rlast   = ddr_rlast_r;
    assign hp0_rresp   = 2'b00;

    always @(posedge clk) begin
        if (!rst_n) begin
            ddr_r_state   <= DR_IDLE;
            ddr_arready_r <= 1'b1;
            ddr_rvalid_r  <= 1'b0;
            ddr_rdata_r   <= 64'd0;
            ddr_rid_r     <= 6'd0;
            ddr_rlast_r   <= 1'b0;
            ddr_ar_addr   <= 32'd0;
            ddr_ar_len    <= 4'd0;
            ddr_ar_id     <= 6'd0;
            ddr_r_cnt     <= 4'd0;
        end else begin
            case (ddr_r_state)
                DR_IDLE: begin
                    if (hp0_arvalid && ddr_arready_r) begin
                        ddr_ar_addr   <= hp0_araddr;
                        ddr_ar_len    <= hp0_arlen;
                        ddr_ar_id     <= hp0_arid;
                        ddr_arready_r <= 1'b0;
                        ddr_r_cnt     <= 4'd0;
                        ddr_r_state   <= DR_DATA;
                    end
                end
                DR_DATA: begin
                    if (!ddr_rvalid_r || hp0_rready) begin
                        ddr_rdata_r <= ddr_mem[(ddr_ar_addr >> 3) + ddr_r_cnt];
                        ddr_rid_r   <= ddr_ar_id;
                        ddr_rvalid_r <= 1'b1;
                        ddr_rlast_r <= (ddr_r_cnt == ddr_ar_len);
                        if (ddr_rvalid_r && hp0_rready) begin
                            if (ddr_rlast_r) begin
                                ddr_rvalid_r  <= 1'b0;
                                ddr_rlast_r   <= 1'b0;
                                ddr_arready_r <= 1'b1;
                                ddr_r_state   <= DR_IDLE;
                            end else begin
                                ddr_r_cnt <= ddr_r_cnt + 4'd1;
                            end
                        end
                    end
                end
                default: ddr_r_state <= DR_IDLE;
            endcase
        end
    end

    // ================================================================
    // UART TX Monitor — direct FIFO snoop (bypasses serial line)
    // ================================================================
    // Directly monitors UART TX FIFO write events via hierarchical access.
    // More reliable than parsing the serial line for simulation.

    // Received string buffer
    reg [7:0]  uart_buf [0:255];
    reg [7:0]  uart_buf_idx;
    reg [7:0]  uart_char;

    // Result flags
    reg        test_pass;
    reg        test_fail;
    reg        test_done;

    initial begin
        uart_buf_idx  = 0;
        test_pass     = 0;
        test_fail     = 0;
        test_done     = 0;
    end

    // Snoop UART TX FIFO write events
    always @(posedge clk) begin
        if (rst_n && u_dut.u_riscv.u_uart.tx_fifo_wr_pulse) begin
            uart_char = u_dut.u_riscv.u_uart.tx_fifo_wr_byte;

            // Store in buffer
            uart_buf[uart_buf_idx] <= uart_char;
            uart_buf_idx <= uart_buf_idx + 8'd1;

            // Print character
            if (uart_char >= 8'h20 && uart_char < 8'h7F)
                $write("%c", uart_char);
            else if (uart_char == 8'h0A)
                $write("\n");

            // Check for "PASS" — 4 consecutive chars
            if (uart_buf_idx >= 8'd3) begin
                if (uart_buf[uart_buf_idx-3] == "P" &&
                    uart_buf[uart_buf_idx-2] == "A" &&
                    uart_buf[uart_buf_idx-1] == "S" &&
                    uart_char == "S") begin
                    test_pass <= 1;
                end
            end

            // Check for "FAIL" — 4 consecutive chars
            if (uart_buf_idx >= 8'd3) begin
                if (uart_buf[uart_buf_idx-3] == "F" &&
                    uart_buf[uart_buf_idx-2] == "A" &&
                    uart_buf[uart_buf_idx-1] == "I" &&
                    uart_char == "L") begin
                    test_fail <= 1;
                end
            end
        end
    end

    // ================================================================
    // Tie off unused inputs + GPIO loopback
    // ================================================================
    // Loop GPIO outputs back to inputs (for L3-006 GPIO test)
    always @(*) begin
        gpio_i = gpio_o;
    end

    initial begin
        uart_rx    = 1'b1;  // UART idle high
        cam_pclk   = 1'b0;
        cam_vsync  = 1'b0;
        cam_href   = 1'b0;
        cam_data   = 8'd0;
        i2s_sck    = 1'b0;
        i2s_ws     = 1'b0;
        i2s_sd     = 1'b0;
        spi_miso   = 1'b0;
        i2c_scl_in = 1'b1;
        i2c_sda_in = 1'b1;
        esp32_handshake = 1'b0;
    end

    // ================================================================
    // SRAM Preloading
    // ================================================================
    // Load firmware into SRAM bank 0 (firmware < 128KB, fits in bank 0)
    initial begin
        $readmemh("test_firmware.hex",
            u_dut.u_riscv.u_sram.gen_banks[0].u_sram_bank.mem);
    end

    // ================================================================
    // Main Test Sequence
    // ================================================================
    integer cycle_count;

    initial begin
        $display("================================================================");
        $display("L3 Cross-Subsystem Test Starting");
        $display("================================================================");

        // Reset
        rst_n = 0;
        cycle_count = 0;
        #(CLK_PERIOD * 20);
        rst_n = 1;
        $display("[%0t] Reset released", $time);

        // Wait for test completion or timeout
        while (!test_pass && !test_fail && cycle_count < TIMEOUT_CYCLES) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end

        $display("");
        $display("================================================================");
        if (test_pass) begin
            $display("RESULT: ALL TESTS PASSED (cycle %0d)", cycle_count);
        end else if (test_fail) begin
            $display("RESULT: TEST FAILED (cycle %0d)", cycle_count);
        end else begin
            $display("RESULT: TIMEOUT after %0d cycles", cycle_count);
        end
        $display("================================================================");

        #(CLK_PERIOD * 10);
        $finish;
    end

    // ================================================================
    // Progress monitoring
    // ================================================================
    always @(posedge clk) begin
        if (rst_n && !test_pass && !test_fail && (cycle_count % 50000 == 0) && cycle_count > 0) begin
            $display("[%0t] Cycle %0d — still running...", $time, cycle_count);
        end
    end

    // ================================================================
    // Optional VCD dump
    // ================================================================
    `ifdef VCD_DUMP
    initial begin
        $dumpfile("tb_l3_top.vcd");
        $dumpvars(0, tb_l3_top);
    end
    `endif

endmodule
