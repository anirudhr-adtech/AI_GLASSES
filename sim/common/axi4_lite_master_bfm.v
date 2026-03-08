`timescale 1ns/1ps
//============================================================================
// Module: axi4_lite_master_bfm
//
// Description:
//   Reusable AXI4-Lite Master Bus Functional Model (BFM) for testbenches.
//   Provides tasks for register read/write transactions. Verilog-2005 only.
//
//   Usage:
//     Instantiate in your testbench and call axi_write / axi_read tasks
//     to drive AXI4-Lite slave devices.
//
//   Note: Tasks use @(posedge clk) event controls and are guarded with
//   ifdef so that Verilator lint-only passes cleanly. For Verilator
//   simulation, use --timing. For other simulators (iverilog, VCS,
//   Xcelium), tasks work as-is.
//
//============================================================================

module axi4_lite_master_bfm #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
)(
    // Clock and reset
    input  wire                        clk,
    input  wire                        rst_n,

    // Write address channel
    output reg  [ADDR_WIDTH-1:0]       m_axil_awaddr,
    output reg                         m_axil_awvalid,
    input  wire                        m_axil_awready,
    output reg  [2:0]                  m_axil_awprot,

    // Write data channel
    output reg  [DATA_WIDTH-1:0]       m_axil_wdata,
    output reg  [DATA_WIDTH/8-1:0]     m_axil_wstrb,
    output reg                         m_axil_wvalid,
    input  wire                        m_axil_wready,

    // Write response channel
    input  wire [1:0]                  m_axil_bresp,
    input  wire                        m_axil_bvalid,
    output reg                         m_axil_bready,

    // Read address channel
    output reg  [ADDR_WIDTH-1:0]       m_axil_araddr,
    output reg                         m_axil_arvalid,
    input  wire                        m_axil_arready,
    output reg  [2:0]                  m_axil_arprot,

    // Read data channel
    input  wire [DATA_WIDTH-1:0]       m_axil_rdata,
    input  wire [1:0]                  m_axil_rresp,
    input  wire                        m_axil_rvalid,
    output reg                         m_axil_rready
);

    //------------------------------------------------------------------------
    // Transaction timeout (clock cycles)
    //------------------------------------------------------------------------
    localparam TIMEOUT_CYCLES = 1000;

    //------------------------------------------------------------------------
    // Status registers
    //------------------------------------------------------------------------
    reg [1:0] last_bresp;   // Last write response code
    reg [1:0] last_rresp;   // Last read response code
    reg       bfm_busy;     // 1 during a transaction, 0 at idle

    //------------------------------------------------------------------------
    // Internal timeout counter
    //------------------------------------------------------------------------
    integer timeout_cnt;

    //------------------------------------------------------------------------
    // Synchronous reset -- idle all outputs
    //------------------------------------------------------------------------
    initial begin
        m_axil_awaddr  = {ADDR_WIDTH{1'b0}};
        m_axil_awvalid = 1'b0;
        m_axil_awprot  = 3'b000;
        m_axil_wdata   = {DATA_WIDTH{1'b0}};
        m_axil_wstrb   = {DATA_WIDTH/8{1'b0}};
        m_axil_wvalid  = 1'b0;
        m_axil_bready  = 1'b0;
        m_axil_araddr  = {ADDR_WIDTH{1'b0}};
        m_axil_arvalid = 1'b0;
        m_axil_arprot  = 3'b000;
        m_axil_rready  = 1'b0;
        last_bresp     = 2'b00;
        last_rresp     = 2'b00;
        bfm_busy       = 1'b0;
        timeout_cnt    = 0;
    end

`ifndef VERILATOR
    //========================================================================
    // Task: axi_idle
    //   Deassert all valid/ready signals to idle state.
    //========================================================================
    task axi_idle;
    begin
        @(posedge clk);
        m_axil_awaddr  <= {ADDR_WIDTH{1'b0}};
        m_axil_awvalid <= 1'b0;
        m_axil_awprot  <= 3'b000;
        m_axil_wdata   <= {DATA_WIDTH{1'b0}};
        m_axil_wstrb   <= {DATA_WIDTH/8{1'b0}};
        m_axil_wvalid  <= 1'b0;
        m_axil_bready  <= 1'b0;
        m_axil_araddr  <= {ADDR_WIDTH{1'b0}};
        m_axil_arvalid <= 1'b0;
        m_axil_arprot  <= 3'b000;
        m_axil_rready  <= 1'b0;
        bfm_busy       <= 1'b0;
    end
    endtask

    //========================================================================
    // Task: axi_write
    //   Full AXI4-Lite write transaction.
    //
    //   1. Assert AWVALID+AWADDR and WVALID+WDATA+WSTRB simultaneously.
    //   2. Wait for AWREADY and WREADY handshakes (may occur on same or
    //      different cycles).
    //   3. Assert BREADY, wait for BVALID.
    //   4. Capture BRESP, deassert all signals, return.
    //========================================================================
    task axi_write;
        input [ADDR_WIDTH-1:0]   addr;
        input [DATA_WIDTH-1:0]   data;
        input [DATA_WIDTH/8-1:0] strb;

        reg aw_done;
        reg w_done;
        reg timed_out;
    begin
        bfm_busy   = 1'b1;
        timeout_cnt = 0;
        aw_done    = 1'b0;
        w_done     = 1'b0;
        timed_out  = 1'b0;

        // Drive address and data channels on the next rising edge
        @(posedge clk);
        m_axil_awaddr  <= addr;
        m_axil_awvalid <= 1'b1;
        m_axil_awprot  <= 3'b000;
        m_axil_wdata   <= data;
        m_axil_wstrb   <= strb;
        m_axil_wvalid  <= 1'b1;

        //--------------------------------------------------------------------
        // Phase 1: Wait for both AW and W handshakes
        //--------------------------------------------------------------------
        while ((!aw_done || !w_done) && (timeout_cnt < TIMEOUT_CYCLES)) begin
            @(posedge clk);
            timeout_cnt = timeout_cnt + 1;

            // Check write-address handshake
            if (m_axil_awvalid && m_axil_awready) begin
                aw_done = 1'b1;
                m_axil_awvalid <= 1'b0;
            end

            // Check write-data handshake
            if (m_axil_wvalid && m_axil_wready) begin
                w_done = 1'b1;
                m_axil_wvalid <= 1'b0;
            end
        end

        if (timeout_cnt >= TIMEOUT_CYCLES) begin
            $display("ERROR: AXI-Lite BFM timeout during write address/data phase (addr=0x%h)", addr);
            m_axil_awvalid <= 1'b0;
            m_axil_wvalid  <= 1'b0;
            bfm_busy       <= 1'b0;
            timed_out       = 1'b1;
        end

        //--------------------------------------------------------------------
        // Phase 2: Wait for write response
        //--------------------------------------------------------------------
        if (!timed_out) begin
            m_axil_bready <= 1'b1;

            while (!m_axil_bvalid && (timeout_cnt < TIMEOUT_CYCLES)) begin
                @(posedge clk);
                timeout_cnt = timeout_cnt + 1;
            end

            if (timeout_cnt >= TIMEOUT_CYCLES) begin
                $display("ERROR: AXI-Lite BFM timeout during write response phase (addr=0x%h)", addr);
                m_axil_bready <= 1'b0;
                bfm_busy      <= 1'b0;
                timed_out      = 1'b1;
            end
        end

        if (!timed_out) begin
            // Capture response
            last_bresp = m_axil_bresp;

            if (m_axil_bresp != 2'b00) begin
                $display("WARNING: AXI-Lite BFM write got non-OKAY response: %b (addr=0x%h)", m_axil_bresp, addr);
            end

            // Deassert and return to idle
            @(posedge clk);
            m_axil_awaddr  <= {ADDR_WIDTH{1'b0}};
            m_axil_awvalid <= 1'b0;
            m_axil_wdata   <= {DATA_WIDTH{1'b0}};
            m_axil_wstrb   <= {DATA_WIDTH/8{1'b0}};
            m_axil_wvalid  <= 1'b0;
            m_axil_bready  <= 1'b0;
            bfm_busy       <= 1'b0;
        end
    end
    endtask

    //========================================================================
    // Task: axi_read
    //   Full AXI4-Lite read transaction.
    //
    //   1. Assert ARVALID+ARADDR.
    //   2. Wait for ARREADY handshake.
    //   3. Assert RREADY, wait for RVALID.
    //   4. Capture RDATA and RRESP, deassert all signals, return.
    //========================================================================
    task axi_read;
        input  [ADDR_WIDTH-1:0] addr;
        output [DATA_WIDTH-1:0] data;

        reg timed_out;
    begin
        bfm_busy    = 1'b1;
        timeout_cnt = 0;
        timed_out   = 1'b0;

        // Drive read address channel
        @(posedge clk);
        m_axil_araddr  <= addr;
        m_axil_arvalid <= 1'b1;
        m_axil_arprot  <= 3'b000;

        //--------------------------------------------------------------------
        // Phase 1: Wait for AR handshake
        //--------------------------------------------------------------------
        while (!(m_axil_arvalid && m_axil_arready) && (timeout_cnt < TIMEOUT_CYCLES)) begin
            @(posedge clk);
            timeout_cnt = timeout_cnt + 1;
        end

        if (timeout_cnt >= TIMEOUT_CYCLES) begin
            $display("ERROR: AXI-Lite BFM timeout during read address phase (addr=0x%h)", addr);
            m_axil_arvalid <= 1'b0;
            bfm_busy       <= 1'b0;
            data = {DATA_WIDTH{1'b0}};
            timed_out = 1'b1;
        end

        if (!timed_out) begin
            // AR handshake complete -- deassert ARVALID
            m_axil_arvalid <= 1'b0;

            //--------------------------------------------------------------------
            // Phase 2: Wait for read data
            //--------------------------------------------------------------------
            m_axil_rready <= 1'b1;

            while (!m_axil_rvalid && (timeout_cnt < TIMEOUT_CYCLES)) begin
                @(posedge clk);
                timeout_cnt = timeout_cnt + 1;
            end

            if (timeout_cnt >= TIMEOUT_CYCLES) begin
                $display("ERROR: AXI-Lite BFM timeout during read data phase (addr=0x%h)", addr);
                m_axil_rready <= 1'b0;
                bfm_busy      <= 1'b0;
                data = {DATA_WIDTH{1'b0}};
                timed_out = 1'b1;
            end
        end

        if (!timed_out) begin
            // Capture read data and response
            data       = m_axil_rdata;
            last_rresp = m_axil_rresp;

            if (m_axil_rresp != 2'b00) begin
                $display("WARNING: AXI-Lite BFM read got non-OKAY response: %b (addr=0x%h)", m_axil_rresp, addr);
            end

            // Deassert and return to idle
            @(posedge clk);
            m_axil_araddr  <= {ADDR_WIDTH{1'b0}};
            m_axil_arvalid <= 1'b0;
            m_axil_rready  <= 1'b0;
            bfm_busy       <= 1'b0;
        end
    end
    endtask

    //========================================================================
    // Task: axi_write32
    //   Convenience wrapper for 32-bit writes with full byte strobes.
    //========================================================================
    task axi_write32;
        input [ADDR_WIDTH-1:0] addr;
        input [31:0]           data;
    begin
        axi_write(addr, data, 4'hF);
    end
    endtask

    //========================================================================
    // Task: axi_read32
    //   Convenience wrapper for 32-bit reads.
    //========================================================================
    task axi_read32;
        input  [ADDR_WIDTH-1:0] addr;
        output [31:0]           data;

        reg [DATA_WIDTH-1:0] rdata_full;
    begin
        axi_read(addr, rdata_full);
        data = rdata_full[31:0];
    end
    endtask
`endif // VERILATOR

endmodule
