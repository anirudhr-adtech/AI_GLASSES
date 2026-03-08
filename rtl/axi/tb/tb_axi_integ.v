`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — AXI Interconnect
// Testbench: tb_axi_integ (L2 Integration)
// Description: L2 integration testbench for axilite_fabric.
//              Tests the full AXI4 -> AXI-Lite bridge -> address decoder ->
//              mux -> 11 peripheral slave ports path.
//              TB acts as AXI4 master, 11 simple register-bank slave
//              responders simulate peripherals.
//////////////////////////////////////////////////////////////////////////////

module tb_axi_integ;

    // -----------------------------------------------------------------------
    // Parameters
    // -----------------------------------------------------------------------
    parameter DATA_WIDTH  = 32;
    parameter ADDR_WIDTH  = 32;
    parameter ID_WIDTH    = 6;
    parameter NUM_PERIPHS = 11;
    parameter STRB_WIDTH  = DATA_WIDTH / 8;

    // -----------------------------------------------------------------------
    // Clock and reset
    // -----------------------------------------------------------------------
    reg clk;
    reg rst_n;

    initial clk = 0;
    always #5 clk = ~clk;  // 100 MHz

    // -----------------------------------------------------------------------
    // AXI4 Slave interface signals (TB is master)
    // -----------------------------------------------------------------------
    reg  [ID_WIDTH-1:0]     s_axi_awid;
    reg  [ADDR_WIDTH-1:0]   s_axi_awaddr;
    reg  [7:0]              s_axi_awlen;
    reg  [2:0]              s_axi_awsize;
    reg  [1:0]              s_axi_awburst;
    reg                     s_axi_awvalid;
    wire                    s_axi_awready;

    reg  [DATA_WIDTH-1:0]   s_axi_wdata;
    reg  [STRB_WIDTH-1:0]   s_axi_wstrb;
    reg                     s_axi_wlast;
    reg                     s_axi_wvalid;
    wire                    s_axi_wready;

    wire [ID_WIDTH-1:0]     s_axi_bid;
    wire [1:0]              s_axi_bresp;
    wire                    s_axi_bvalid;
    reg                     s_axi_bready;

    reg  [ID_WIDTH-1:0]     s_axi_arid;
    reg  [ADDR_WIDTH-1:0]   s_axi_araddr;
    reg  [7:0]              s_axi_arlen;
    reg  [2:0]              s_axi_arsize;
    reg  [1:0]              s_axi_arburst;
    reg                     s_axi_arvalid;
    wire                    s_axi_arready;

    wire [ID_WIDTH-1:0]     s_axi_rid;
    wire [DATA_WIDTH-1:0]   s_axi_rdata;
    wire [1:0]              s_axi_rresp;
    wire                    s_axi_rlast;
    wire                    s_axi_rvalid;
    reg                     s_axi_rready;

    // -----------------------------------------------------------------------
    // 11 AXI-Lite slave ports (packed arrays from fabric)
    // -----------------------------------------------------------------------
    wire [NUM_PERIPHS*ADDR_WIDTH-1:0]       m_axil_awaddr;
    wire [NUM_PERIPHS*3-1:0]                m_axil_awprot;
    wire [NUM_PERIPHS-1:0]                  m_axil_awvalid;
    reg  [NUM_PERIPHS-1:0]                  m_axil_awready;

    wire [NUM_PERIPHS*DATA_WIDTH-1:0]       m_axil_wdata;
    wire [NUM_PERIPHS*STRB_WIDTH-1:0]       m_axil_wstrb;
    wire [NUM_PERIPHS-1:0]                  m_axil_wvalid;
    reg  [NUM_PERIPHS-1:0]                  m_axil_wready;

    reg  [NUM_PERIPHS*2-1:0]                m_axil_bresp;
    reg  [NUM_PERIPHS-1:0]                  m_axil_bvalid;
    wire [NUM_PERIPHS-1:0]                  m_axil_bready;

    wire [NUM_PERIPHS*ADDR_WIDTH-1:0]       m_axil_araddr;
    wire [NUM_PERIPHS*3-1:0]                m_axil_arprot;
    wire [NUM_PERIPHS-1:0]                  m_axil_arvalid;
    reg  [NUM_PERIPHS-1:0]                  m_axil_arready;

    reg  [NUM_PERIPHS*DATA_WIDTH-1:0]       m_axil_rdata;
    reg  [NUM_PERIPHS*2-1:0]                m_axil_rresp;
    reg  [NUM_PERIPHS-1:0]                  m_axil_rvalid;
    wire [NUM_PERIPHS-1:0]                  m_axil_rready;

    // -----------------------------------------------------------------------
    // Test infrastructure
    // -----------------------------------------------------------------------
    integer pass_count;
    integer fail_count;
    integer i;

    // Captured write/read response data
    reg [1:0]               cap_bresp;
    reg [5:0]               cap_bid;
    reg [DATA_WIDTH-1:0]    cap_rdata;
    reg [1:0]               cap_rresp;
    reg [5:0]               cap_rid;

    // -----------------------------------------------------------------------
    // DUT: axilite_fabric
    // -----------------------------------------------------------------------
    axilite_fabric #(
        .DATA_WIDTH  (DATA_WIDTH),
        .ADDR_WIDTH  (ADDR_WIDTH),
        .ID_WIDTH    (ID_WIDTH),
        .NUM_PERIPHS (NUM_PERIPHS)
    ) u_fabric (
        .clk             (clk),
        .rst_n           (rst_n),
        // AXI4 slave (from TB master)
        .s_axi_awid      (s_axi_awid),
        .s_axi_awaddr    (s_axi_awaddr),
        .s_axi_awlen     (s_axi_awlen),
        .s_axi_awsize    (s_axi_awsize),
        .s_axi_awburst   (s_axi_awburst),
        .s_axi_awvalid   (s_axi_awvalid),
        .s_axi_awready   (s_axi_awready),
        .s_axi_wdata     (s_axi_wdata),
        .s_axi_wstrb     (s_axi_wstrb),
        .s_axi_wlast     (s_axi_wlast),
        .s_axi_wvalid    (s_axi_wvalid),
        .s_axi_wready    (s_axi_wready),
        .s_axi_bid       (s_axi_bid),
        .s_axi_bresp     (s_axi_bresp),
        .s_axi_bvalid    (s_axi_bvalid),
        .s_axi_bready    (s_axi_bready),
        .s_axi_arid      (s_axi_arid),
        .s_axi_araddr    (s_axi_araddr),
        .s_axi_arlen     (s_axi_arlen),
        .s_axi_arsize    (s_axi_arsize),
        .s_axi_arburst   (s_axi_arburst),
        .s_axi_arvalid   (s_axi_arvalid),
        .s_axi_arready   (s_axi_arready),
        .s_axi_rid       (s_axi_rid),
        .s_axi_rdata     (s_axi_rdata),
        .s_axi_rresp     (s_axi_rresp),
        .s_axi_rlast     (s_axi_rlast),
        .s_axi_rvalid    (s_axi_rvalid),
        .s_axi_rready    (s_axi_rready),
        // 11 AXI-Lite peripheral ports
        .m_axil_awaddr   (m_axil_awaddr),
        .m_axil_awprot   (m_axil_awprot),
        .m_axil_awvalid  (m_axil_awvalid),
        .m_axil_awready  (m_axil_awready),
        .m_axil_wdata    (m_axil_wdata),
        .m_axil_wstrb    (m_axil_wstrb),
        .m_axil_wvalid   (m_axil_wvalid),
        .m_axil_wready   (m_axil_wready),
        .m_axil_bresp    (m_axil_bresp),
        .m_axil_bvalid   (m_axil_bvalid),
        .m_axil_bready   (m_axil_bready),
        .m_axil_araddr   (m_axil_araddr),
        .m_axil_arprot   (m_axil_arprot),
        .m_axil_arvalid  (m_axil_arvalid),
        .m_axil_arready  (m_axil_arready),
        .m_axil_rdata    (m_axil_rdata),
        .m_axil_rresp    (m_axil_rresp),
        .m_axil_rvalid   (m_axil_rvalid),
        .m_axil_rready   (m_axil_rready)
    );

    // -----------------------------------------------------------------------
    // 11 Simple AXI-Lite Slave Register Banks
    // Each slave has 4 x 32-bit registers (at offsets 0x00..0x0C)
    // Slave responds with OKAY. Register content initialized to
    // (slot << 24) | reg_offset to allow identification.
    // -----------------------------------------------------------------------
    reg [31:0] slave_regs [0:NUM_PERIPHS-1][0:3];  // 11 slaves x 4 regs

    // Initialize slave registers with identifiable patterns
    integer si, ri;
    initial begin
        for (si = 0; si < NUM_PERIPHS; si = si + 1) begin
            for (ri = 0; ri < 4; ri = ri + 1) begin
                slave_regs[si][ri] = (si << 24) | (ri << 2);
            end
        end
    end

    // Generate slave responders for each of the 11 peripheral ports
    genvar g;
    generate
        for (g = 0; g < NUM_PERIPHS; g = g + 1) begin : slave_resp
            // Write channel responder
            always @(posedge clk) begin
                if (!rst_n) begin
                    m_axil_awready[g] <= 1'b0;
                    m_axil_wready[g]  <= 1'b0;
                    m_axil_bvalid[g]  <= 1'b0;
                    m_axil_bresp[g*2 +: 2] <= 2'b00;
                end else begin
                    // AW channel — always accept
                    m_axil_awready[g] <= 1'b1;

                    // W channel — always accept and perform write
                    m_axil_wready[g] <= 1'b1;
                    if (m_axil_wvalid[g] && m_axil_wready[g]) begin
                        // Extract byte address from awaddr for this slave
                        // The fabric routes the full 32-bit address; use low bits
                        // The address on the slave port has offset bits in [7:0]
                        // Register index = addr[3:2]
                        // Apply strobe
                        if (m_axil_wstrb[g*STRB_WIDTH +: STRB_WIDTH] != 0) begin
                            slave_regs[g][m_axil_awaddr[g*ADDR_WIDTH+2 +: 2]] <=
                                m_axil_wdata[g*DATA_WIDTH +: DATA_WIDTH];
                        end
                    end

                    // B channel — assert bvalid one cycle after w handshake
                    if (m_axil_wvalid[g] && m_axil_wready[g]) begin
                        m_axil_bvalid[g] <= 1'b1;
                        m_axil_bresp[g*2 +: 2] <= 2'b00;  // OKAY
                    end else if (m_axil_bvalid[g] && m_axil_bready[g]) begin
                        m_axil_bvalid[g] <= 1'b0;
                    end
                end
            end

            // Read channel responder
            always @(posedge clk) begin
                if (!rst_n) begin
                    m_axil_arready[g] <= 1'b0;
                    m_axil_rvalid[g]  <= 1'b0;
                    m_axil_rdata[g*DATA_WIDTH +: DATA_WIDTH]  <= 0;
                    m_axil_rresp[g*2 +: 2] <= 2'b00;
                end else begin
                    m_axil_arready[g] <= 1'b1;

                    if (m_axil_arvalid[g] && m_axil_arready[g]) begin
                        m_axil_rvalid[g] <= 1'b1;
                        m_axil_rdata[g*DATA_WIDTH +: DATA_WIDTH] <=
                            slave_regs[g][m_axil_araddr[g*ADDR_WIDTH+2 +: 2]];
                        m_axil_rresp[g*2 +: 2] <= 2'b00;  // OKAY
                    end else if (m_axil_rvalid[g] && m_axil_rready[g]) begin
                        m_axil_rvalid[g] <= 1'b0;
                    end
                end
            end
        end
    endgenerate

    // -----------------------------------------------------------------------
    // AXI4 single-beat write task (len=0, burst write through bridge)
    // The bridge converts AXI4 single-beat to AXI-Lite
    // -----------------------------------------------------------------------
    task axi4_write;
        input [5:0]  id;
        input [31:0] addr;
        input [31:0] data;
        input [3:0]  strb;
        integer timeout;
    begin
        // AW + W simultaneously (single beat)
        @(posedge clk); #1;
        s_axi_awid    = id;
        s_axi_awaddr  = addr;
        s_axi_awlen   = 8'd0;   // single beat
        s_axi_awsize  = 3'd2;   // 4 bytes
        s_axi_awburst = 2'b01;  // INCR
        s_axi_awvalid = 1;
        s_axi_wdata   = data;
        s_axi_wstrb   = strb;
        s_axi_wlast   = 1;
        s_axi_wvalid  = 1;
        s_axi_bready  = 0;

        // Wait for AW handshake — hold awvalid until awready sampled high
        timeout = 500;
        begin : aw_hsk
            while (timeout > 0) begin
                @(posedge clk);
                if (s_axi_awready) begin
                    #1;
                    s_axi_awvalid = 0;
                    timeout = 0;
                end else begin
                    #1;
                    timeout = timeout - 1;
                end
            end
        end

        // Wait for W handshake
        if (s_axi_wvalid) begin
            timeout = 500;
            begin : w_hsk
                while (timeout > 0) begin
                    @(posedge clk);
                    if (s_axi_wready) begin
                        #1;
                        timeout = 0;
                    end else begin
                        #1;
                        timeout = timeout - 1;
                    end
                end
            end
        end
        s_axi_wvalid = 0;
        s_axi_wlast  = 0;

        // B phase — wait for bvalid WITHOUT bready first, then acknowledge
        timeout = 500;
        begin : b_hsk
            while (timeout > 0) begin
                @(posedge clk); #1;
                if (s_axi_bvalid) begin
                    cap_bresp = s_axi_bresp;
                    cap_bid   = s_axi_bid;
                    timeout   = 0;
                end else begin
                    timeout = timeout - 1;
                end
            end
        end
        // Now assert bready for one cycle to complete the handshake
        s_axi_bready = 1;
        @(posedge clk); #1;
        s_axi_bready = 0;
    end
    endtask

    // -----------------------------------------------------------------------
    // AXI4 single-beat read task
    // -----------------------------------------------------------------------
    task axi4_read;
        input [5:0]  id;
        input [31:0] addr;
        integer timeout;
    begin
        @(posedge clk); #1;
        s_axi_arid    = id;
        s_axi_araddr  = addr;
        s_axi_arlen   = 8'd0;
        s_axi_arsize  = 3'd2;
        s_axi_arburst = 2'b01;
        s_axi_arvalid = 1;
        s_axi_rready  = 0;

        // Wait for AR handshake — sample arready at posedge before NBA
        timeout = 500;
        begin : ar_hsk
            while (timeout > 0) begin
                @(posedge clk);
                if (s_axi_arready) begin
                    #1;
                    s_axi_arvalid = 0;
                    timeout = 0;
                end else begin
                    #1;
                    timeout = timeout - 1;
                end
            end
        end

        // R phase — wait for rvalid WITHOUT rready, then acknowledge
        timeout = 500;
        begin : r_hsk
            while (timeout > 0) begin
                @(posedge clk); #1;
                if (s_axi_rvalid) begin
                    cap_rdata = s_axi_rdata;
                    cap_rresp = s_axi_rresp;
                    cap_rid   = s_axi_rid;
                    timeout   = 0;
                end else begin
                    timeout = timeout - 1;
                end
            end
        end
        // Now assert rready for one cycle to complete the handshake
        s_axi_rready = 1;
        @(posedge clk); #1;
        s_axi_rready = 0;
    end
    endtask

    // -----------------------------------------------------------------------
    // Signal initialization
    // -----------------------------------------------------------------------
    task init_signals;
    begin
        s_axi_awid    = 0;
        s_axi_awaddr  = 0;
        s_axi_awlen   = 0;
        s_axi_awsize  = 0;
        s_axi_awburst = 0;
        s_axi_awvalid = 0;
        s_axi_wdata   = 0;
        s_axi_wstrb   = 0;
        s_axi_wlast   = 0;
        s_axi_wvalid  = 0;
        s_axi_bready  = 0;
        s_axi_arid    = 0;
        s_axi_araddr  = 0;
        s_axi_arlen   = 0;
        s_axi_arsize  = 0;
        s_axi_arburst = 0;
        s_axi_arvalid = 0;
        s_axi_rready  = 0;
        cap_bresp     = 0;
        cap_bid       = 0;
        cap_rdata     = 0;
        cap_rresp     = 0;
        cap_rid       = 0;
    end
    endtask

    // -----------------------------------------------------------------------
    // Peripheral slot address map:
    //   P0 (UART):   0x2000_0000
    //   P1 (Timer):  0x2000_0100
    //   P2 (IRQ):    0x2000_0200
    //   P3 (GPIO):   0x2000_0300
    //   P4 (Camera): 0x2000_0400
    //   P5 (Audio):  0x2000_0500
    //   P6 (I2C):    0x2000_0600
    //   P7 (SPI):    0x2000_0700
    //   P8 (NPU):    0x3000_0000
    //   P9 (DMA):    0x4000_0000
    //   P10 (Error): unmapped
    // -----------------------------------------------------------------------

    // Slot base addresses
    reg [31:0] slot_addr [0:9];
    initial begin
        slot_addr[0] = 32'h2000_0000;  // UART
        slot_addr[1] = 32'h2000_0100;  // Timer
        slot_addr[2] = 32'h2000_0200;  // IRQ
        slot_addr[3] = 32'h2000_0300;  // GPIO
        slot_addr[4] = 32'h2000_0400;  // Camera
        slot_addr[5] = 32'h2000_0500;  // Audio
        slot_addr[6] = 32'h2000_0600;  // I2C
        slot_addr[7] = 32'h2000_0700;  // SPI
        slot_addr[8] = 32'h3000_0000;  // NPU
        slot_addr[9] = 32'h4000_0000;  // DMA
    end

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    initial begin
        $display("============================================================");
        $display("  TB: tb_axi_integ — AXI-Lite Fabric L2 Integration Test");
        $display("============================================================");
        pass_count = 0;
        fail_count = 0;

        init_signals;
        rst_n = 0;
        repeat (20) @(posedge clk);
        rst_n = 1;
        repeat (10) @(posedge clk);

        // ==============================================================
        // X1: Read Default Values from Each Slot (0-7)
        // Verify address decode routes to correct slave
        // ==============================================================
        $display("\n--- X1: Read default values from slots 0-7 ---");
        begin : x1_block
            reg x1_ok;
            reg [31:0] expected;
            x1_ok = 1;
            for (i = 0; i < 8; i = i + 1) begin
                axi4_read(6'd1, slot_addr[i]);
                // Default value: (slot << 24) | 0 (reg 0)
                expected = (i << 24) | 0;
                if (cap_rdata !== expected) begin
                    $display("  FAIL X1: slot %0d read 0x%08h expected 0x%08h",
                             i, cap_rdata, expected);
                    x1_ok = 0;
                end
                if (cap_rresp !== 2'b00) begin
                    $display("  FAIL X1: slot %0d rresp=%b expected OKAY", i, cap_rresp);
                    x1_ok = 0;
                end
            end
            if (x1_ok) begin
                $display("  PASS X1: all 8 peripheral slots decoded correctly");
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
            end
        end

        // ==============================================================
        // X2: Write and Readback to Each Slot
        // Write unique data to reg[0] of each slot, read back
        // ==============================================================
        $display("\n--- X2: Write+Read each slot 0-7 ---");
        begin : x2_block
            reg x2_ok;
            reg [31:0] wr_val;
            x2_ok = 1;
            for (i = 0; i < 8; i = i + 1) begin
                wr_val = 32'hCAFE_0000 | (i << 4);
                axi4_write(6'd1, slot_addr[i], wr_val, 4'hF);
                repeat (2) @(posedge clk);
                axi4_read(6'd1, slot_addr[i]);
                if (cap_rdata !== wr_val) begin
                    $display("  FAIL X2: slot %0d wrote 0x%08h read 0x%08h",
                             i, wr_val, cap_rdata);
                    x2_ok = 0;
                end
            end
            if (x2_ok) begin
                $display("  PASS X2: write+readback correct for slots 0-7");
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
            end
        end

        // ==============================================================
        // X3: NPU Slot (P8) at 0x3000_0000
        // ==============================================================
        $display("\n--- X3: NPU slot (P8) access ---");
        begin : x3_block
            reg x3_ok;
            x3_ok = 1;
            // Write to NPU slot
            axi4_write(6'd1, 32'h3000_0000, 32'hA5A5_1234, 4'hF);
            repeat (2) @(posedge clk);
            axi4_read(6'd1, 32'h3000_0000);
            if (cap_rdata !== 32'hA5A5_1234) begin
                $display("  FAIL X3: NPU slot wrote 0xA5A51234 read 0x%08h", cap_rdata);
                x3_ok = 0;
            end
            if (x3_ok) begin
                $display("  PASS X3: NPU slot (0x3000_0000) access OK");
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
            end
        end

        // ==============================================================
        // X4: DMA Slot (P9) at 0x4000_0000
        // ==============================================================
        $display("\n--- X4: DMA slot (P9) access ---");
        begin : x4_block
            reg x4_ok;
            x4_ok = 1;
            axi4_write(6'd1, 32'h4000_0000, 32'hDEAD_BEEF, 4'hF);
            repeat (2) @(posedge clk);
            axi4_read(6'd1, 32'h4000_0000);
            if (cap_rdata !== 32'hDEAD_BEEF) begin
                $display("  FAIL X4: DMA slot wrote 0xDEADBEEF read 0x%08h", cap_rdata);
                x4_ok = 0;
            end
            // Also write to reg offset 0x04 (reg 1)
            axi4_write(6'd1, 32'h4000_0004, 32'h1234_5678, 4'hF);
            repeat (2) @(posedge clk);
            axi4_read(6'd1, 32'h4000_0004);
            if (cap_rdata !== 32'h1234_5678) begin
                $display("  FAIL X4: DMA reg1 wrote 0x12345678 read 0x%08h", cap_rdata);
                x4_ok = 0;
            end
            if (x4_ok) begin
                $display("  PASS X4: DMA slot (0x4000_0000) access OK");
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
            end
        end

        // ==============================================================
        // X5: Multiple Register Offsets Within Single Slave
        // Write to 4 registers of UART (slot 0), read all back
        // ==============================================================
        $display("\n--- X5: Multiple register offsets (UART slot) ---");
        begin : x5_block
            reg x5_ok;
            reg [31:0] expected;
            x5_ok = 1;
            // Write 4 registers
            axi4_write(6'd1, 32'h2000_0000, 32'hAA00_FF00, 4'hF);
            repeat (2) @(posedge clk);
            axi4_write(6'd1, 32'h2000_0004, 32'h1111_1111, 4'hF);
            repeat (2) @(posedge clk);
            axi4_write(6'd1, 32'h2000_0008, 32'h2222_2222, 4'hF);
            repeat (2) @(posedge clk);
            axi4_write(6'd1, 32'h2000_000C, 32'h3333_3333, 4'hF);
            repeat (2) @(posedge clk);

            // Read them back
            axi4_read(6'd1, 32'h2000_0000);
            if (cap_rdata !== 32'hAA00_FF00) begin
                $display("  FAIL X5: UART reg0 expected 0xAA00FF00 got 0x%08h", cap_rdata);
                x5_ok = 0;
            end
            axi4_read(6'd1, 32'h2000_0004);
            if (cap_rdata !== 32'h1111_1111) begin
                $display("  FAIL X5: UART reg1 expected 0x11111111 got 0x%08h", cap_rdata);
                x5_ok = 0;
            end
            axi4_read(6'd1, 32'h2000_0008);
            if (cap_rdata !== 32'h2222_2222) begin
                $display("  FAIL X5: UART reg2 expected 0x22222222 got 0x%08h", cap_rdata);
                x5_ok = 0;
            end
            axi4_read(6'd1, 32'h2000_000C);
            if (cap_rdata !== 32'h3333_3333) begin
                $display("  FAIL X5: UART reg3 expected 0x33333333 got 0x%08h", cap_rdata);
                x5_ok = 0;
            end
            if (x5_ok) begin
                $display("  PASS X5: multi-register access within UART slot");
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
            end
        end

        // ==============================================================
        // X6: Sequential Access to Different Slaves (no idle between)
        // Write slot0, write slot3, write slot7, read slot3, read slot0
        // ==============================================================
        $display("\n--- X6: Sequential cross-slave access ---");
        begin : x6_block
            reg x6_ok;
            x6_ok = 1;
            axi4_write(6'd1, 32'h2000_0000, 32'hAA00_0001, 4'hF);
            axi4_write(6'd1, 32'h2000_0300, 32'hBB00_0003, 4'hF);
            axi4_write(6'd1, 32'h2000_0700, 32'hCC00_0007, 4'hF);
            repeat (2) @(posedge clk);
            // Read them back in different order
            axi4_read(6'd1, 32'h2000_0300);
            if (cap_rdata !== 32'hBB00_0003) begin
                $display("  FAIL X6: GPIO read expected 0xBB000003 got 0x%08h", cap_rdata);
                x6_ok = 0;
            end
            axi4_read(6'd1, 32'h2000_0000);
            if (cap_rdata !== 32'hAA00_0001) begin
                $display("  FAIL X6: UART read expected 0xAA000001 got 0x%08h", cap_rdata);
                x6_ok = 0;
            end
            axi4_read(6'd1, 32'h2000_0700);
            if (cap_rdata !== 32'hCC00_0007) begin
                $display("  FAIL X6: SPI read expected 0xCC000007 got 0x%08h", cap_rdata);
                x6_ok = 0;
            end
            if (x6_ok) begin
                $display("  PASS X6: sequential cross-slave access OK");
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
            end
        end

        // ==============================================================
        // X7: AXI ID Preservation
        // Write/read with different AXI IDs, verify ID returned correctly
        // ==============================================================
        $display("\n--- X7: AXI ID preservation ---");
        begin : x7_block
            reg x7_ok;
            x7_ok = 1;

            // Write with ID=0x05
            axi4_write(6'h05, 32'h2000_0100, 32'hBEEF_0005, 4'hF);
            if (cap_bid !== 6'h05) begin
                $display("  FAIL X7: write BID expected 0x05 got 0x%02h", cap_bid);
                x7_ok = 0;
            end

            // Read with ID=0x1A
            repeat (2) @(posedge clk);
            axi4_read(6'h1A, 32'h2000_0100);
            if (cap_rid !== 6'h1A) begin
                $display("  FAIL X7: read RID expected 0x1A got 0x%02h", cap_rid);
                x7_ok = 0;
            end
            if (cap_rdata !== 32'hBEEF_0005) begin
                $display("  FAIL X7: data expected 0xBEEF0005 got 0x%08h", cap_rdata);
                x7_ok = 0;
            end

            // Write with ID=0x3F (max 6-bit)
            axi4_write(6'h3F, 32'h2000_0200, 32'hFACE_003F, 4'hF);
            if (cap_bid !== 6'h3F) begin
                $display("  FAIL X7: write BID expected 0x3F got 0x%02h", cap_bid);
                x7_ok = 0;
            end
            repeat (2) @(posedge clk);
            axi4_read(6'h3F, 32'h2000_0200);
            if (cap_rid !== 6'h3F) begin
                $display("  FAIL X7: read RID expected 0x3F got 0x%02h", cap_rid);
                x7_ok = 0;
            end

            if (x7_ok) begin
                $display("  PASS X7: AXI ID preservation through bridge");
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
            end
        end

        // ==============================================================
        // X8: Back-to-Back Access to Same Slave
        // Rapid writes then rapid reads to TIMER slot
        // ==============================================================
        $display("\n--- X8: Back-to-back same-slave access ---");
        begin : x8_block
            reg x8_ok;
            x8_ok = 1;

            // 4 back-to-back writes to timer registers
            axi4_write(6'd1, 32'h2000_0100, 32'hBB00_0000, 4'hF);
            axi4_write(6'd1, 32'h2000_0104, 32'hBB00_0001, 4'hF);
            axi4_write(6'd1, 32'h2000_0108, 32'hBB00_0002, 4'hF);
            axi4_write(6'd1, 32'h2000_010C, 32'hBB00_0003, 4'hF);

            // 4 back-to-back reads
            axi4_read(6'd1, 32'h2000_0100);
            if (cap_rdata !== 32'hBB00_0000) begin
                $display("  FAIL X8: timer reg0 expected 0xBB000000 got 0x%08h", cap_rdata);
                x8_ok = 0;
            end
            axi4_read(6'd1, 32'h2000_0104);
            if (cap_rdata !== 32'hBB00_0001) begin
                $display("  FAIL X8: timer reg1 expected 0xBB000001 got 0x%08h", cap_rdata);
                x8_ok = 0;
            end
            axi4_read(6'd1, 32'h2000_0108);
            if (cap_rdata !== 32'hBB00_0002) begin
                $display("  FAIL X8: timer reg2 expected 0xBB000002 got 0x%08h", cap_rdata);
                x8_ok = 0;
            end
            axi4_read(6'd1, 32'h2000_010C);
            if (cap_rdata !== 32'hBB00_0003) begin
                $display("  FAIL X8: timer reg3 expected 0xBB000003 got 0x%08h", cap_rdata);
                x8_ok = 0;
            end

            if (x8_ok) begin
                $display("  PASS X8: back-to-back same-slave access OK");
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
            end
        end

        // ==============================================================
        // X9: Write Response Check (OKAY)
        // Verify all writes to valid addresses get OKAY response
        // ==============================================================
        $display("\n--- X9: Write response verification ---");
        begin : x9_block
            reg x9_ok;
            x9_ok = 1;
            for (i = 0; i < 8; i = i + 1) begin
                axi4_write(6'd1, slot_addr[i], 32'h9900_0000 | i, 4'hF);
                if (cap_bresp !== 2'b00) begin
                    $display("  FAIL X9: slot %0d bresp=%b expected OKAY", i, cap_bresp);
                    x9_ok = 0;
                end
            end
            // NPU slot
            axi4_write(6'd1, 32'h3000_0000, 32'h9900_0008, 4'hF);
            if (cap_bresp !== 2'b00) begin
                $display("  FAIL X9: NPU slot bresp=%b expected OKAY", cap_bresp);
                x9_ok = 0;
            end
            // DMA slot
            axi4_write(6'd1, 32'h4000_0000, 32'h9900_0009, 4'hF);
            if (cap_bresp !== 2'b00) begin
                $display("  FAIL X9: DMA slot bresp=%b expected OKAY", cap_bresp);
                x9_ok = 0;
            end
            if (x9_ok) begin
                $display("  PASS X9: all 10 valid slots return OKAY write response");
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
            end
        end

        // ==============================================================
        // X10: Full Slot Sweep — write unique, read all back
        // Writes to all 10 valid peripheral slots, then reads all back
        // ==============================================================
        $display("\n--- X10: Full 10-slot sweep ---");
        begin : x10_block
            reg x10_ok;
            reg [31:0] expected;
            x10_ok = 1;

            // Write unique values to all 10 slots
            for (i = 0; i < 10; i = i + 1) begin
                axi4_write(6'd1, slot_addr[i], 32'hF000_0000 | (i << 8), 4'hF);
                repeat (2) @(posedge clk);
            end

            // Read all back and verify
            for (i = 0; i < 10; i = i + 1) begin
                axi4_read(6'd1, slot_addr[i]);
                expected = 32'hF000_0000 | (i << 8);
                if (cap_rdata !== expected) begin
                    $display("  FAIL X10: slot %0d expected 0x%08h got 0x%08h",
                             i, expected, cap_rdata);
                    x10_ok = 0;
                end
            end

            if (x10_ok) begin
                $display("  PASS X10: full 10-slot sweep verified");
                pass_count = pass_count + 1;
            end else begin
                fail_count = fail_count + 1;
            end
        end

        // ==============================================================
        // Summary
        // ==============================================================
        $display("\n============================================================");
        $display("  TB SUMMARY: %0d PASSED, %0d FAILED", pass_count, fail_count);
        if (fail_count == 0)
            $display("  >>> ALL TESTS PASSED <<<");
        else
            $display("  >>> SOME TESTS FAILED <<<");
        $display("============================================================");
        $finish;
    end

    // -----------------------------------------------------------------------
    // Watchdog timer
    // -----------------------------------------------------------------------
    initial begin
        #500000;
        $display("ERROR: Watchdog timeout at %0t ns", $time);
        $finish;
    end

endmodule
