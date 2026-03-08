`timescale 1ns/1ps
//============================================================================
// Module : axi4_master_bfm
// Description : Reusable AXI4 Full Master Bus Functional Model (BFM)
//               Provides tasks for burst read/write transactions.
//               Used by DMA testbenches and L2/L3 integration tests.
//
// Verilog-2005 -- no SystemVerilog constructs.
// Active-low synchronous reset.  All outputs registered.
//
// Note: Tasks use @(posedge clk) event controls and are guarded with
// ifdef so that lint-only passes cleanly. For simulation with the
// --timing flag or other simulators (iverilog, VCS), tasks work as-is.
//============================================================================

module axi4_master_bfm #(
    parameter ADDR_WIDTH    = 32,
    parameter DATA_WIDTH    = 128,
    parameter ID_WIDTH      = 4,
    parameter MAX_BURST_LEN = 256
)(
    // ----------------------------------------------------------------
    // Clock / Reset
    // ----------------------------------------------------------------
    input  wire                          clk,
    input  wire                          rst_n,

    // ----------------------------------------------------------------
    // Write Address Channel (AW)
    // ----------------------------------------------------------------
    output reg  [ID_WIDTH-1:0]           m_axi_awid,
    output reg  [ADDR_WIDTH-1:0]         m_axi_awaddr,
    output reg  [7:0]                    m_axi_awlen,
    output reg  [2:0]                    m_axi_awsize,
    output reg  [1:0]                    m_axi_awburst,
    output reg                           m_axi_awvalid,
    input  wire                          m_axi_awready,

    // ----------------------------------------------------------------
    // Write Data Channel (W)
    // ----------------------------------------------------------------
    output reg  [DATA_WIDTH-1:0]         m_axi_wdata,
    output reg  [DATA_WIDTH/8-1:0]       m_axi_wstrb,
    output reg                           m_axi_wlast,
    output reg                           m_axi_wvalid,
    input  wire                          m_axi_wready,

    // ----------------------------------------------------------------
    // Write Response Channel (B)
    // ----------------------------------------------------------------
    input  wire [ID_WIDTH-1:0]           m_axi_bid,
    input  wire [1:0]                    m_axi_bresp,
    input  wire                          m_axi_bvalid,
    output reg                           m_axi_bready,

    // ----------------------------------------------------------------
    // Read Address Channel (AR)
    // ----------------------------------------------------------------
    output reg  [ID_WIDTH-1:0]           m_axi_arid,
    output reg  [ADDR_WIDTH-1:0]         m_axi_araddr,
    output reg  [7:0]                    m_axi_arlen,
    output reg  [2:0]                    m_axi_arsize,
    output reg  [1:0]                    m_axi_arburst,
    output reg                           m_axi_arvalid,
    input  wire                          m_axi_arready,

    // ----------------------------------------------------------------
    // Read Data Channel (R)
    // ----------------------------------------------------------------
    input  wire [ID_WIDTH-1:0]           m_axi_rid,
    input  wire [DATA_WIDTH-1:0]         m_axi_rdata,
    input  wire [1:0]                    m_axi_rresp,
    input  wire                          m_axi_rlast,
    input  wire                          m_axi_rvalid,
    output reg                           m_axi_rready
);

    // ====================================================================
    // AXI Burst-type constants
    // ====================================================================
    localparam BURST_FIXED = 2'b00;
    localparam BURST_INCR  = 2'b01;
    localparam BURST_WRAP  = 2'b10;

    // ====================================================================
    // AXI Size helpers  (bytes per beat = 2^SIZE)
    // ====================================================================
    localparam SIZE_1B  = 3'd0;   //   1 byte
    localparam SIZE_2B  = 3'd1;   //   2 bytes
    localparam SIZE_4B  = 3'd2;   //   4 bytes
    localparam SIZE_8B  = 3'd3;   //   8 bytes
    localparam SIZE_16B = 3'd4;   //  16 bytes

    // ====================================================================
    // Transaction timeout (clock cycles)
    // ====================================================================
    localparam TIMEOUT = 10000;

    // ====================================================================
    // Internal burst-data storage
    // ====================================================================
    reg [DATA_WIDTH-1:0]     wr_data_buf [0:MAX_BURST_LEN-1];
    reg [DATA_WIDTH/8-1:0]   wr_strb_buf [0:MAX_BURST_LEN-1];
    reg [DATA_WIDTH-1:0]     rd_data_buf [0:MAX_BURST_LEN-1];

    // ====================================================================
    // Status registers
    // ====================================================================
    reg [1:0] last_bresp;    // last write-response code
    reg [1:0] last_rresp;    // last read-response code
    reg       bfm_busy;      // 1 while a transaction is in progress
    reg       rlast_error;   // 1 if RLAST did not arrive on expected beat

    // ====================================================================
    // Timeout counter (shared across tasks)
    // ====================================================================
    integer timeout_cnt;

    // ====================================================================
    // Initialisation / reset
    // ====================================================================
    initial begin
        m_axi_awid    = {ID_WIDTH{1'b0}};
        m_axi_awaddr  = {ADDR_WIDTH{1'b0}};
        m_axi_awlen   = 8'd0;
        m_axi_awsize  = 3'd0;
        m_axi_awburst = 2'b00;
        m_axi_awvalid = 1'b0;

        m_axi_wdata   = {DATA_WIDTH{1'b0}};
        m_axi_wstrb   = {(DATA_WIDTH/8){1'b0}};
        m_axi_wlast   = 1'b0;
        m_axi_wvalid  = 1'b0;

        m_axi_bready  = 1'b0;

        m_axi_arid    = {ID_WIDTH{1'b0}};
        m_axi_araddr  = {ADDR_WIDTH{1'b0}};
        m_axi_arlen   = 8'd0;
        m_axi_arsize  = 3'd0;
        m_axi_arburst = 2'b00;
        m_axi_arvalid = 1'b0;

        m_axi_rready  = 1'b0;

        last_bresp   = 2'b00;
        last_rresp   = 2'b00;
        bfm_busy     = 1'b0;
        rlast_error  = 1'b0;
        timeout_cnt  = 0;
    end

`ifndef VERILATOR
    // ====================================================================
    // Task : axi_idle
    // Deassert every valid/ready output -- return the bus to idle state.
    // ====================================================================
    task axi_idle;
    begin
        @(posedge clk);
        m_axi_awvalid <= 1'b0;
        m_axi_wvalid  <= 1'b0;
        m_axi_wlast   <= 1'b0;
        m_axi_bready  <= 1'b0;
        m_axi_arvalid <= 1'b0;
        m_axi_rready  <= 1'b0;
    end
    endtask

    // ====================================================================
    // Task : axi_write_burst
    //   Perform a full AXI4 write burst: AW phase -> W phase -> B phase.
    //   Caller must pre-load wr_data_buf[] and wr_strb_buf[] with len+1
    //   entries before calling.
    //
    //   id    -- transaction ID
    //   addr  -- start address
    //   len   -- AWLEN (number of beats minus 1)
    //   size  -- AWSIZE (bytes per beat = 2^size)
    //   burst -- AWBURST (FIXED / INCR / WRAP)
    // ====================================================================
    task axi_write_burst;
        input [ID_WIDTH-1:0]   id;
        input [ADDR_WIDTH-1:0] addr;
        input [7:0]            len;
        input [2:0]            size;
        input [1:0]            burst;

        integer beat;
        integer num_beats;
        reg     timed_out;
    begin
        bfm_busy  = 1'b1;
        num_beats = len + 1;
        timed_out = 1'b0;

        // ---------------------------------------------------------------
        // AW phase -- drive address and wait for AWREADY handshake
        // ---------------------------------------------------------------
        @(posedge clk);
        m_axi_awid    <= id;
        m_axi_awaddr  <= addr;
        m_axi_awlen   <= len;
        m_axi_awsize  <= size;
        m_axi_awburst <= burst;
        m_axi_awvalid <= 1'b1;

        // Wait for AWREADY with timeout
        timeout_cnt = 0;
        @(posedge clk);
        while (!m_axi_awready && timeout_cnt < TIMEOUT) begin
            timeout_cnt = timeout_cnt + 1;
            @(posedge clk);
        end
        if (timeout_cnt >= TIMEOUT) begin
            $display("[BFM ERROR] %0t : AW handshake timeout (addr=0x%h)",
                     $time, addr);
            m_axi_awvalid <= 1'b0;
            bfm_busy = 1'b0;
            timed_out = 1'b1;
        end

        if (!timed_out) begin
            // Handshake occurred -- deassert AWVALID on next edge
            m_axi_awvalid <= 1'b0;

            // ---------------------------------------------------------------
            // W phase -- send num_beats data beats from wr_data_buf[]
            // ---------------------------------------------------------------
            beat = 0;
            while (beat < num_beats && !timed_out) begin
                @(posedge clk);
                m_axi_wdata  <= wr_data_buf[beat];
                m_axi_wstrb  <= wr_strb_buf[beat];
                m_axi_wlast  <= (beat == num_beats - 1) ? 1'b1 : 1'b0;
                m_axi_wvalid <= 1'b1;

                // Wait for WREADY handshake
                timeout_cnt = 0;
                @(posedge clk);
                while (!m_axi_wready && timeout_cnt < TIMEOUT) begin
                    timeout_cnt = timeout_cnt + 1;
                    @(posedge clk);
                end
                if (timeout_cnt >= TIMEOUT) begin
                    $display("[BFM ERROR] %0t : W handshake timeout (beat %0d/%0d)",
                             $time, beat, num_beats);
                    m_axi_wvalid <= 1'b0;
                    m_axi_wlast  <= 1'b0;
                    bfm_busy = 1'b0;
                    timed_out = 1'b1;
                end
                beat = beat + 1;
            end
        end

        if (!timed_out) begin
            // Deassert W signals after last beat
            m_axi_wvalid <= 1'b0;
            m_axi_wlast  <= 1'b0;

            // ---------------------------------------------------------------
            // B phase -- wait for write response
            // ---------------------------------------------------------------
            @(posedge clk);
            m_axi_bready <= 1'b1;

            timeout_cnt = 0;
            @(posedge clk);
            while (!m_axi_bvalid && timeout_cnt < TIMEOUT) begin
                timeout_cnt = timeout_cnt + 1;
                @(posedge clk);
            end
            if (timeout_cnt >= TIMEOUT) begin
                $display("[BFM ERROR] %0t : B response timeout (addr=0x%h)",
                         $time, addr);
                m_axi_bready <= 1'b0;
                bfm_busy = 1'b0;
                timed_out = 1'b1;
            end
        end

        if (!timed_out) begin
            last_bresp = m_axi_bresp;

            // Log non-OKAY responses
            if (m_axi_bresp != 2'b00) begin
                $display("[BFM WARN]  %0t : Write response BRESP=%b (addr=0x%h)",
                         $time, m_axi_bresp, addr);
            end

            m_axi_bready <= 1'b0;
            bfm_busy = 1'b0;
        end
    end
    endtask

    // ====================================================================
    // Task : axi_read_burst
    //   Perform a full AXI4 read burst: AR phase -> R phase.
    //   After completion, rd_data_buf[0..len] holds the received data.
    //
    //   id    -- transaction ID
    //   addr  -- start address
    //   len   -- ARLEN (number of beats minus 1)
    //   size  -- ARSIZE (bytes per beat = 2^size)
    //   burst -- ARBURST (FIXED / INCR / WRAP)
    // ====================================================================
    task axi_read_burst;
        input [ID_WIDTH-1:0]   id;
        input [ADDR_WIDTH-1:0] addr;
        input [7:0]            len;
        input [2:0]            size;
        input [1:0]            burst;

        integer beat;
        integer num_beats;
        reg     timed_out;
    begin
        bfm_busy    = 1'b1;
        rlast_error = 1'b0;
        num_beats   = len + 1;
        timed_out   = 1'b0;

        // ---------------------------------------------------------------
        // AR phase -- drive address and wait for ARREADY handshake
        // ---------------------------------------------------------------
        @(posedge clk);
        m_axi_arid    <= id;
        m_axi_araddr  <= addr;
        m_axi_arlen   <= len;
        m_axi_arsize  <= size;
        m_axi_arburst <= burst;
        m_axi_arvalid <= 1'b1;

        // Wait for ARREADY with timeout
        timeout_cnt = 0;
        @(posedge clk);
        while (!m_axi_arready && timeout_cnt < TIMEOUT) begin
            timeout_cnt = timeout_cnt + 1;
            @(posedge clk);
        end
        if (timeout_cnt >= TIMEOUT) begin
            $display("[BFM ERROR] %0t : AR handshake timeout (addr=0x%h)",
                     $time, addr);
            m_axi_arvalid <= 1'b0;
            bfm_busy = 1'b0;
            timed_out = 1'b1;
        end

        if (!timed_out) begin
            // Handshake occurred -- deassert ARVALID
            m_axi_arvalid <= 1'b0;

            // ---------------------------------------------------------------
            // R phase -- capture num_beats data beats into rd_data_buf[]
            // ---------------------------------------------------------------
            @(posedge clk);
            m_axi_rready <= 1'b1;

            beat = 0;
            while (beat < num_beats && !timed_out) begin
                // Wait for RVALID handshake
                timeout_cnt = 0;
                @(posedge clk);
                while (!m_axi_rvalid && timeout_cnt < TIMEOUT) begin
                    timeout_cnt = timeout_cnt + 1;
                    @(posedge clk);
                end
                if (timeout_cnt >= TIMEOUT) begin
                    $display("[BFM ERROR] %0t : R handshake timeout (beat %0d/%0d, addr=0x%h)",
                             $time, beat, num_beats, addr);
                    m_axi_rready <= 1'b0;
                    bfm_busy = 1'b0;
                    timed_out = 1'b1;
                end

                if (!timed_out) begin
                    // Capture data
                    rd_data_buf[beat] = m_axi_rdata;
                    last_rresp        = m_axi_rresp;

                    // Check RLAST on the final beat
                    if (beat == num_beats - 1) begin
                        if (!m_axi_rlast) begin
                            $display("[BFM ERROR] %0t : RLAST not asserted on final beat %0d (addr=0x%h)",
                                     $time, beat, addr);
                            rlast_error = 1'b1;
                        end
                    end else begin
                        // RLAST should NOT be asserted before the final beat
                        if (m_axi_rlast) begin
                            $display("[BFM ERROR] %0t : Unexpected RLAST on beat %0d of %0d (addr=0x%h)",
                                     $time, beat, num_beats, addr);
                            rlast_error = 1'b1;
                        end
                    end

                    // Log non-OKAY responses
                    if (m_axi_rresp != 2'b00) begin
                        $display("[BFM WARN]  %0t : Read response RRESP=%b (beat %0d, addr=0x%h)",
                                 $time, m_axi_rresp, beat, addr);
                    end
                end
                beat = beat + 1;
            end
        end

        if (!timed_out) begin
            m_axi_rready <= 1'b0;
            bfm_busy = 1'b0;
        end
    end
    endtask

    // ====================================================================
    // Task : axi_single_write
    //   Convenience wrapper -- single-beat write (len=0).
    //
    //   id   -- transaction ID
    //   addr -- target address
    //   data -- write data (one beat)
    //   strb -- write strobes
    // ====================================================================
    task axi_single_write;
        input [ID_WIDTH-1:0]       id;
        input [ADDR_WIDTH-1:0]     addr;
        input [DATA_WIDTH-1:0]     data;
        input [DATA_WIDTH/8-1:0]   strb;
    begin
        wr_data_buf[0] = data;
        wr_strb_buf[0] = strb;
        axi_write_burst(id, addr, 8'd0, $clog2(DATA_WIDTH/8), BURST_INCR);
    end
    endtask

    // ====================================================================
    // Task : axi_single_read
    //   Convenience wrapper -- single-beat read (len=0).
    //   Returns the read data via the output argument.
    //
    //   id   -- transaction ID
    //   addr -- target address
    //   data -- (output) captured read data
    // ====================================================================
    task axi_single_read;
        input  [ID_WIDTH-1:0]   id;
        input  [ADDR_WIDTH-1:0] addr;
        output [DATA_WIDTH-1:0] data;
    begin
        axi_read_burst(id, addr, 8'd0, $clog2(DATA_WIDTH/8), BURST_INCR);
        data = rd_data_buf[0];
    end
    endtask
`endif // VERILATOR

endmodule
