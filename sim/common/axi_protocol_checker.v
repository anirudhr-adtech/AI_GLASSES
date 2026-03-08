`timescale 1ns/1ps
//============================================================================
// Module: axi_protocol_checker
//
// Description:
//   Passive AXI4 protocol monitor/checker. Instantiate alongside any AXI4
//   interface to detect protocol violations during simulation. All ports are
//   inputs — this module never drives any signal.
//
//   Checks implemented (per AXI4 specification):
//     R001 - VALID stability (must hold until READY handshake)
//     R002 - Signal stability (payload stable while VALID && !READY)
//     R003 - WLAST must assert on final write beat
//     R004 - WSTRB must be non-zero when WVALID (warning)
//     R005 - BID must match outstanding AWID
//     R006 - RLAST on final read beat, RID must match ARID
//     R007 - BVALID/RVALID stability
//     R008 - No X/Z on control/data when VALID
//     R009 - Timeout (VALID without READY too long)
//     R010 - 4KB boundary crossing
//
//   Verilog-2005 only. No SystemVerilog constructs.
//
//============================================================================

module axi_protocol_checker #(
    parameter ADDR_WIDTH       = 32,
    parameter DATA_WIDTH       = 32,
    parameter ID_WIDTH         = 4,
    parameter MAX_OUTSTANDING  = 16,
    parameter TIMEOUT_CYCLES   = 1000,
    parameter LABEL            = "AXI_CHK"
)(
    // Clock and reset
    input wire                        clk,
    input wire                        rst_n,

    // Write address channel
    input wire [ID_WIDTH-1:0]         awid,
    input wire [ADDR_WIDTH-1:0]       awaddr,
    input wire [7:0]                  awlen,
    input wire [2:0]                  awsize,
    input wire [1:0]                  awburst,
    input wire                        awvalid,
    input wire                        awready,

    // Write data channel
    input wire [DATA_WIDTH-1:0]       wdata,
    input wire [DATA_WIDTH/8-1:0]     wstrb,
    input wire                        wlast,
    input wire                        wvalid,
    input wire                        wready,

    // Write response channel
    input wire [ID_WIDTH-1:0]         bid,
    input wire [1:0]                  bresp,
    input wire                        bvalid,
    input wire                        bready,

    // Read address channel
    input wire [ID_WIDTH-1:0]         arid,
    input wire [ADDR_WIDTH-1:0]       araddr,
    input wire [7:0]                  arlen,
    input wire [2:0]                  arsize,
    input wire [1:0]                  arburst,
    input wire                        arvalid,
    input wire                        arready,

    // Read data channel
    input wire [ID_WIDTH-1:0]         rid,
    input wire [DATA_WIDTH-1:0]       rdata,
    input wire [1:0]                  rresp,
    input wire                        rlast,
    input wire                        rvalid,
    input wire                        rready
);

    // ========================================================================
    // Local parameters
    // ========================================================================
    localparam STRB_WIDTH = DATA_WIDTH / 8;

    // ========================================================================
    // Output counters
    // ========================================================================
    reg [31:0] error_count;
    reg [31:0] warning_count;
    reg [31:0] aw_txn_count;
    reg [31:0] w_beat_count;
    reg [31:0] b_txn_count;
    reg [31:0] ar_txn_count;
    reg [31:0] r_beat_count;

    // ========================================================================
    // Previous-cycle signal registers (for stability checks)
    // ========================================================================

    // AW channel previous values
    reg                        prev_awvalid;
    reg [ID_WIDTH-1:0]         prev_awid;
    reg [ADDR_WIDTH-1:0]       prev_awaddr;
    reg [7:0]                  prev_awlen;
    reg [2:0]                  prev_awsize;
    reg [1:0]                  prev_awburst;
    reg                        prev_awready;

    // W channel previous values
    reg                        prev_wvalid;
    reg [DATA_WIDTH-1:0]       prev_wdata;
    reg [STRB_WIDTH-1:0]       prev_wstrb;
    reg                        prev_wlast;
    reg                        prev_wready;

    // AR channel previous values
    reg                        prev_arvalid;
    reg [ID_WIDTH-1:0]         prev_arid;
    reg [ADDR_WIDTH-1:0]       prev_araddr;
    reg [7:0]                  prev_arlen;
    reg [2:0]                  prev_arsize;
    reg [1:0]                  prev_arburst;
    reg                        prev_arready;

    // B channel previous values
    reg                        prev_bvalid;
    reg                        prev_bready;

    // R channel previous values
    reg                        prev_rvalid;
    reg                        prev_rready;

    // ========================================================================
    // Outstanding transaction FIFOs — write channel
    // ========================================================================
    reg [ID_WIDTH-1:0]  aw_id_fifo  [0:MAX_OUTSTANDING-1];
    reg [7:0]           aw_len_fifo [0:MAX_OUTSTANDING-1];
    reg [31:0]          aw_fifo_wr_ptr;
    reg [31:0]          aw_fifo_rd_ptr;
    reg [31:0]          aw_fifo_count;

    // Write beat counter — tracks beats against expected from AW
    reg [8:0]           w_beat_cnt;       // counts W handshakes for current burst
    reg [7:0]           w_expected_len;   // awlen of current burst
    reg                 w_burst_active;   // tracking a write burst

    // ========================================================================
    // Outstanding transaction FIFOs — write response
    // ========================================================================
    // Separate FIFO to track AWID for B-channel matching
    reg [ID_WIDTH-1:0]  b_id_fifo   [0:MAX_OUTSTANDING-1];
    reg [31:0]          b_fifo_wr_ptr;
    reg [31:0]          b_fifo_rd_ptr;
    reg [31:0]          b_fifo_count;

    // ========================================================================
    // Outstanding transaction FIFOs — read channel
    // ========================================================================
    reg [ID_WIDTH-1:0]  ar_id_fifo  [0:MAX_OUTSTANDING-1];
    reg [7:0]           ar_len_fifo [0:MAX_OUTSTANDING-1];
    reg [31:0]          ar_fifo_wr_ptr;
    reg [31:0]          ar_fifo_rd_ptr;
    reg [31:0]          ar_fifo_count;

    // Read beat counter
    reg [8:0]           r_beat_cnt;
    reg [7:0]           r_expected_len;
    reg [ID_WIDTH-1:0]  r_expected_id;
    reg                 r_burst_active;

    // ========================================================================
    // Timeout counters
    // ========================================================================
    reg [31:0] aw_timeout_cnt;
    reg [31:0] w_timeout_cnt;
    reg [31:0] b_timeout_cnt;
    reg [31:0] ar_timeout_cnt;
    reg [31:0] r_timeout_cnt;

    // Timeout fired flags (report once per stall)
    reg        aw_timeout_fired;
    reg        w_timeout_fired;
    reg        b_timeout_fired;
    reg        ar_timeout_fired;
    reg        r_timeout_fired;

    // ========================================================================
    // FIFO initialisation
    // ========================================================================
    integer i;

    // ========================================================================
    // Reset and counter management
    // ========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            error_count    <= 32'd0;
            warning_count  <= 32'd0;
            aw_txn_count   <= 32'd0;
            w_beat_count   <= 32'd0;
            b_txn_count    <= 32'd0;
            ar_txn_count   <= 32'd0;
            r_beat_count   <= 32'd0;

            prev_awvalid   <= 1'b0;
            prev_awready   <= 1'b0;
            prev_wvalid    <= 1'b0;
            prev_wready    <= 1'b0;
            prev_arvalid   <= 1'b0;
            prev_arready   <= 1'b0;
            prev_bvalid    <= 1'b0;
            prev_bready    <= 1'b0;
            prev_rvalid    <= 1'b0;
            prev_rready    <= 1'b0;

            prev_awid      <= {ID_WIDTH{1'b0}};
            prev_awaddr    <= {ADDR_WIDTH{1'b0}};
            prev_awlen     <= 8'd0;
            prev_awsize    <= 3'd0;
            prev_awburst   <= 2'd0;

            prev_wdata     <= {DATA_WIDTH{1'b0}};
            prev_wstrb     <= {STRB_WIDTH{1'b0}};
            prev_wlast     <= 1'b0;

            prev_arid      <= {ID_WIDTH{1'b0}};
            prev_araddr    <= {ADDR_WIDTH{1'b0}};
            prev_arlen     <= 8'd0;
            prev_arsize    <= 3'd0;
            prev_arburst   <= 2'd0;

            aw_fifo_wr_ptr <= 32'd0;
            aw_fifo_rd_ptr <= 32'd0;
            aw_fifo_count  <= 32'd0;

            b_fifo_wr_ptr  <= 32'd0;
            b_fifo_rd_ptr  <= 32'd0;
            b_fifo_count   <= 32'd0;

            ar_fifo_wr_ptr <= 32'd0;
            ar_fifo_rd_ptr <= 32'd0;
            ar_fifo_count  <= 32'd0;

            w_beat_cnt     <= 9'd0;
            w_expected_len <= 8'd0;
            w_burst_active <= 1'b0;

            r_beat_cnt     <= 9'd0;
            r_expected_len <= 8'd0;
            r_expected_id  <= {ID_WIDTH{1'b0}};
            r_burst_active <= 1'b0;

            aw_timeout_cnt   <= 32'd0;
            w_timeout_cnt    <= 32'd0;
            b_timeout_cnt    <= 32'd0;
            ar_timeout_cnt   <= 32'd0;
            r_timeout_cnt    <= 32'd0;

            aw_timeout_fired <= 1'b0;
            w_timeout_fired  <= 1'b0;
            b_timeout_fired  <= 1'b0;
            ar_timeout_fired <= 1'b0;
            r_timeout_fired  <= 1'b0;
        end
    end

    // ========================================================================
    // Previous-cycle capture (always runs — checks use prev vs current)
    // ========================================================================
    always @(posedge clk) begin
        if (rst_n) begin
            prev_awvalid <= awvalid;
            prev_awready <= awready;
            prev_awid    <= awid;
            prev_awaddr  <= awaddr;
            prev_awlen   <= awlen;
            prev_awsize  <= awsize;
            prev_awburst <= awburst;

            prev_wvalid  <= wvalid;
            prev_wready  <= wready;
            prev_wdata   <= wdata;
            prev_wstrb   <= wstrb;
            prev_wlast   <= wlast;

            prev_arvalid <= arvalid;
            prev_arready <= arready;
            prev_arid    <= arid;
            prev_araddr  <= araddr;
            prev_arlen   <= arlen;
            prev_arsize  <= arsize;
            prev_arburst <= arburst;

            prev_bvalid  <= bvalid;
            prev_bready  <= bready;

            prev_rvalid  <= rvalid;
            prev_rready  <= rready;
        end
    end

    // ========================================================================
    // Rule AXI-R001: VALID stability
    //   Once asserted, VALID must not deassert until READY handshake.
    // ========================================================================
    always @(posedge clk) begin
        if (rst_n) begin
            // AWVALID stability
            if (prev_awvalid && !prev_awready && !awvalid) begin
                $display("[%0t] %s ERROR R001: AWVALID deasserted without AWREADY handshake",
                         $time, LABEL);
                error_count <= error_count + 1;
            end
            // WVALID stability
            if (prev_wvalid && !prev_wready && !wvalid) begin
                $display("[%0t] %s ERROR R001: WVALID deasserted without WREADY handshake",
                         $time, LABEL);
                error_count <= error_count + 1;
            end
            // ARVALID stability
            if (prev_arvalid && !prev_arready && !arvalid) begin
                $display("[%0t] %s ERROR R001: ARVALID deasserted without ARREADY handshake",
                         $time, LABEL);
                error_count <= error_count + 1;
            end
        end
    end

    // ========================================================================
    // Rule AXI-R002: Signal stability
    //   Payload must remain stable while VALID is high and READY is low.
    // ========================================================================
    always @(posedge clk) begin
        if (rst_n) begin
            // AW channel stability
            if (prev_awvalid && !prev_awready && awvalid) begin
                if (awid !== prev_awid) begin
                    $display("[%0t] %s ERROR R002: AWID changed while AWVALID && !AWREADY (0x%0h -> 0x%0h)",
                             $time, LABEL, prev_awid, awid);
                    error_count <= error_count + 1;
                end
                if (awaddr !== prev_awaddr) begin
                    $display("[%0t] %s ERROR R002: AWADDR changed while AWVALID && !AWREADY (0x%0h -> 0x%0h)",
                             $time, LABEL, prev_awaddr, awaddr);
                    error_count <= error_count + 1;
                end
                if (awlen !== prev_awlen) begin
                    $display("[%0t] %s ERROR R002: AWLEN changed while AWVALID && !AWREADY (0x%0h -> 0x%0h)",
                             $time, LABEL, prev_awlen, awlen);
                    error_count <= error_count + 1;
                end
                if (awsize !== prev_awsize) begin
                    $display("[%0t] %s ERROR R002: AWSIZE changed while AWVALID && !AWREADY (0x%0h -> 0x%0h)",
                             $time, LABEL, prev_awsize, awsize);
                    error_count <= error_count + 1;
                end
                if (awburst !== prev_awburst) begin
                    $display("[%0t] %s ERROR R002: AWBURST changed while AWVALID && !AWREADY (0x%0h -> 0x%0h)",
                             $time, LABEL, prev_awburst, awburst);
                    error_count <= error_count + 1;
                end
            end

            // W channel stability
            if (prev_wvalid && !prev_wready && wvalid) begin
                if (wdata !== prev_wdata) begin
                    $display("[%0t] %s ERROR R002: WDATA changed while WVALID && !WREADY",
                             $time, LABEL);
                    error_count <= error_count + 1;
                end
                if (wstrb !== prev_wstrb) begin
                    $display("[%0t] %s ERROR R002: WSTRB changed while WVALID && !WREADY (0x%0h -> 0x%0h)",
                             $time, LABEL, prev_wstrb, wstrb);
                    error_count <= error_count + 1;
                end
                if (wlast !== prev_wlast) begin
                    $display("[%0t] %s ERROR R002: WLAST changed while WVALID && !WREADY (%0b -> %0b)",
                             $time, LABEL, prev_wlast, wlast);
                    error_count <= error_count + 1;
                end
            end

            // AR channel stability
            if (prev_arvalid && !prev_arready && arvalid) begin
                if (arid !== prev_arid) begin
                    $display("[%0t] %s ERROR R002: ARID changed while ARVALID && !ARREADY (0x%0h -> 0x%0h)",
                             $time, LABEL, prev_arid, arid);
                    error_count <= error_count + 1;
                end
                if (araddr !== prev_araddr) begin
                    $display("[%0t] %s ERROR R002: ARADDR changed while ARVALID && !ARREADY (0x%0h -> 0x%0h)",
                             $time, LABEL, prev_araddr, araddr);
                    error_count <= error_count + 1;
                end
                if (arlen !== prev_arlen) begin
                    $display("[%0t] %s ERROR R002: ARLEN changed while ARVALID && !ARREADY (0x%0h -> 0x%0h)",
                             $time, LABEL, prev_arlen, arlen);
                    error_count <= error_count + 1;
                end
                if (arsize !== prev_arsize) begin
                    $display("[%0t] %s ERROR R002: ARSIZE changed while ARVALID && !ARREADY (0x%0h -> 0x%0h)",
                             $time, LABEL, prev_arsize, arsize);
                    error_count <= error_count + 1;
                end
                if (arburst !== prev_arburst) begin
                    $display("[%0t] %s ERROR R002: ARBURST changed while ARVALID && !ARREADY (0x%0h -> 0x%0h)",
                             $time, LABEL, prev_arburst, arburst);
                    error_count <= error_count + 1;
                end
            end
        end
    end

    // ========================================================================
    // Rule AXI-R007: BVALID / RVALID stability
    //   Once asserted, must not deassert until corresponding READY handshake.
    // ========================================================================
    always @(posedge clk) begin
        if (rst_n) begin
            // BVALID stability
            if (prev_bvalid && !prev_bready && !bvalid) begin
                $display("[%0t] %s ERROR R007: BVALID deasserted without BREADY handshake",
                         $time, LABEL);
                error_count <= error_count + 1;
            end
            // RVALID stability
            if (prev_rvalid && !prev_rready && !rvalid) begin
                $display("[%0t] %s ERROR R007: RVALID deasserted without RREADY handshake",
                         $time, LABEL);
                error_count <= error_count + 1;
            end
        end
    end

    // ========================================================================
    // Rule AXI-R008: No X/Z on signals when VALID is asserted
    //   Use === to detect unknown/high-impedance values.
    // ========================================================================
    always @(posedge clk) begin
        if (rst_n) begin
            // AW channel X/Z check
            if (awvalid) begin
                if (awvalid !== 1'b1) begin
                    $display("[%0t] %s ERROR R008: AWVALID contains X/Z", $time, LABEL);
                    error_count <= error_count + 1;
                end
                if (^awid === 1'bx) begin
                    $display("[%0t] %s ERROR R008: AWID contains X/Z while AWVALID", $time, LABEL);
                    error_count <= error_count + 1;
                end
                if (^awaddr === 1'bx) begin
                    $display("[%0t] %s ERROR R008: AWADDR contains X/Z while AWVALID", $time, LABEL);
                    error_count <= error_count + 1;
                end
                if (^awlen === 1'bx) begin
                    $display("[%0t] %s ERROR R008: AWLEN contains X/Z while AWVALID", $time, LABEL);
                    error_count <= error_count + 1;
                end
                if (^awsize === 1'bx) begin
                    $display("[%0t] %s ERROR R008: AWSIZE contains X/Z while AWVALID", $time, LABEL);
                    error_count <= error_count + 1;
                end
                if (^awburst === 1'bx) begin
                    $display("[%0t] %s ERROR R008: AWBURST contains X/Z while AWVALID", $time, LABEL);
                    error_count <= error_count + 1;
                end
            end

            // W channel X/Z check
            if (wvalid) begin
                if (wvalid !== 1'b1) begin
                    $display("[%0t] %s ERROR R008: WVALID contains X/Z", $time, LABEL);
                    error_count <= error_count + 1;
                end
                if (^wdata === 1'bx) begin
                    $display("[%0t] %s ERROR R008: WDATA contains X/Z while WVALID", $time, LABEL);
                    error_count <= error_count + 1;
                end
                if (^wstrb === 1'bx) begin
                    $display("[%0t] %s ERROR R008: WSTRB contains X/Z while WVALID", $time, LABEL);
                    error_count <= error_count + 1;
                end
                if (wlast === 1'bx) begin
                    $display("[%0t] %s ERROR R008: WLAST contains X/Z while WVALID", $time, LABEL);
                    error_count <= error_count + 1;
                end
            end

            // B channel X/Z check
            if (bvalid) begin
                if (bvalid !== 1'b1) begin
                    $display("[%0t] %s ERROR R008: BVALID contains X/Z", $time, LABEL);
                    error_count <= error_count + 1;
                end
                if (^bid === 1'bx) begin
                    $display("[%0t] %s ERROR R008: BID contains X/Z while BVALID", $time, LABEL);
                    error_count <= error_count + 1;
                end
                if (^bresp === 1'bx) begin
                    $display("[%0t] %s ERROR R008: BRESP contains X/Z while BVALID", $time, LABEL);
                    error_count <= error_count + 1;
                end
            end

            // AR channel X/Z check
            if (arvalid) begin
                if (arvalid !== 1'b1) begin
                    $display("[%0t] %s ERROR R008: ARVALID contains X/Z", $time, LABEL);
                    error_count <= error_count + 1;
                end
                if (^arid === 1'bx) begin
                    $display("[%0t] %s ERROR R008: ARID contains X/Z while ARVALID", $time, LABEL);
                    error_count <= error_count + 1;
                end
                if (^araddr === 1'bx) begin
                    $display("[%0t] %s ERROR R008: ARADDR contains X/Z while ARVALID", $time, LABEL);
                    error_count <= error_count + 1;
                end
                if (^arlen === 1'bx) begin
                    $display("[%0t] %s ERROR R008: ARLEN contains X/Z while ARVALID", $time, LABEL);
                    error_count <= error_count + 1;
                end
                if (^arsize === 1'bx) begin
                    $display("[%0t] %s ERROR R008: ARSIZE contains X/Z while ARVALID", $time, LABEL);
                    error_count <= error_count + 1;
                end
                if (^arburst === 1'bx) begin
                    $display("[%0t] %s ERROR R008: ARBURST contains X/Z while ARVALID", $time, LABEL);
                    error_count <= error_count + 1;
                end
            end

            // R channel X/Z check
            if (rvalid) begin
                if (rvalid !== 1'b1) begin
                    $display("[%0t] %s ERROR R008: RVALID contains X/Z", $time, LABEL);
                    error_count <= error_count + 1;
                end
                if (^rid === 1'bx) begin
                    $display("[%0t] %s ERROR R008: RID contains X/Z while RVALID", $time, LABEL);
                    error_count <= error_count + 1;
                end
                if (^rdata === 1'bx) begin
                    $display("[%0t] %s ERROR R008: RDATA contains X/Z while RVALID", $time, LABEL);
                    error_count <= error_count + 1;
                end
                if (^rresp === 1'bx) begin
                    $display("[%0t] %s ERROR R008: RRESP contains X/Z while RVALID", $time, LABEL);
                    error_count <= error_count + 1;
                end
                if (rlast === 1'bx) begin
                    $display("[%0t] %s ERROR R008: RLAST contains X/Z while RVALID", $time, LABEL);
                    error_count <= error_count + 1;
                end
            end
        end
    end

    // ========================================================================
    // Rule AXI-R004: WSTRB consistency (warning — non-zero when WVALID)
    // ========================================================================
    always @(posedge clk) begin
        if (rst_n) begin
            if (wvalid && (wstrb == {STRB_WIDTH{1'b0}})) begin
                $display("[%0t] %s WARN  R004: WSTRB is all-zero while WVALID is asserted",
                         $time, LABEL);
                warning_count <= warning_count + 1;
            end
        end
    end

    // ========================================================================
    // Rule AXI-R010: 4KB boundary crossing check
    //   A burst must not cross a 4KB boundary.
    //   end_addr = start_addr + (len+1) * bytes_per_beat - 1
    //   Violation if start_addr[31:12] != end_addr[31:12]
    //   (Only for INCR bursts — WRAP bursts wrap by definition, FIXED is ok)
    // ========================================================================

    // Combinational calculation wires for AW channel
    reg [ADDR_WIDTH-1:0] aw_end_addr;
    reg [ADDR_WIDTH-1:0] aw_burst_bytes;

    always @(*) begin
        aw_burst_bytes = (awlen + 1) * (1 << awsize);
        aw_end_addr    = awaddr + aw_burst_bytes - 1;
    end

    // Combinational calculation wires for AR channel
    reg [ADDR_WIDTH-1:0] ar_end_addr;
    reg [ADDR_WIDTH-1:0] ar_burst_bytes;

    always @(*) begin
        ar_burst_bytes = (arlen + 1) * (1 << arsize);
        ar_end_addr    = araddr + ar_burst_bytes - 1;
    end

    always @(posedge clk) begin
        if (rst_n) begin
            // AW channel boundary check on handshake
            if (awvalid && awready) begin
                // Only check INCR bursts (awburst == 2'b01)
                if (awburst == 2'b01) begin
                    if (awaddr[ADDR_WIDTH-1:12] != aw_end_addr[ADDR_WIDTH-1:12]) begin
                        $display("[%0t] %s ERROR R010: Write burst crosses 4KB boundary. AWADDR=0x%0h, AWLEN=%0d, AWSIZE=%0d, end=0x%0h",
                                 $time, LABEL, awaddr, awlen, awsize, aw_end_addr);
                        error_count <= error_count + 1;
                    end
                end
            end

            // AR channel boundary check on handshake
            if (arvalid && arready) begin
                // Only check INCR bursts (arburst == 2'b01)
                if (arburst == 2'b01) begin
                    if (araddr[ADDR_WIDTH-1:12] != ar_end_addr[ADDR_WIDTH-1:12]) begin
                        $display("[%0t] %s ERROR R010: Read burst crosses 4KB boundary. ARADDR=0x%0h, ARLEN=%0d, ARSIZE=%0d, end=0x%0h",
                                 $time, LABEL, araddr, arlen, arsize, ar_end_addr);
                        error_count <= error_count + 1;
                    end
                end
            end
        end
    end

    // ========================================================================
    // Transaction counters and outstanding FIFO management
    // ========================================================================

    // --- AW handshake: push to FIFOs, increment counter ---
    always @(posedge clk) begin
        if (rst_n) begin
            if (awvalid && awready) begin
                aw_txn_count <= aw_txn_count + 1;

                // Push to write-beat tracking FIFO (for R003 WLAST check)
                if (aw_fifo_count < MAX_OUTSTANDING) begin
                    aw_id_fifo[aw_fifo_wr_ptr % MAX_OUTSTANDING]  <= awid;
                    aw_len_fifo[aw_fifo_wr_ptr % MAX_OUTSTANDING] <= awlen;
                    aw_fifo_wr_ptr <= aw_fifo_wr_ptr + 1;
                    aw_fifo_count  <= aw_fifo_count + 1;
                end else begin
                    $display("[%0t] %s ERROR R005: AW outstanding FIFO overflow (MAX_OUTSTANDING=%0d)",
                             $time, LABEL, MAX_OUTSTANDING);
                    error_count <= error_count + 1;
                end

                // Push to B-channel ID matching FIFO
                if (b_fifo_count < MAX_OUTSTANDING) begin
                    b_id_fifo[b_fifo_wr_ptr % MAX_OUTSTANDING] <= awid;
                    b_fifo_wr_ptr <= b_fifo_wr_ptr + 1;
                    b_fifo_count  <= b_fifo_count + 1;
                end
            end
        end
    end

    // --- W handshake: beat counting and R003 WLAST check ---
    always @(posedge clk) begin
        if (!rst_n) begin
            w_beat_cnt     <= 9'd0;
            w_expected_len <= 8'd0;
            w_burst_active <= 1'b0;
        end else begin
            if (wvalid && wready) begin
                w_beat_count <= w_beat_count + 1;

                // If no burst is active, pop the next expected length from FIFO
                if (!w_burst_active) begin
                    if (aw_fifo_count > 0) begin
                        w_expected_len <= aw_len_fifo[aw_fifo_rd_ptr % MAX_OUTSTANDING];
                        aw_fifo_rd_ptr <= aw_fifo_rd_ptr + 1;
                        aw_fifo_count  <= aw_fifo_count - 1;
                        w_burst_active <= 1'b1;
                        w_beat_cnt     <= 9'd1; // this is the first beat

                        // Rule AXI-R003: Check WLAST on single-beat burst
                        if (aw_len_fifo[aw_fifo_rd_ptr % MAX_OUTSTANDING] == 8'd0) begin
                            if (!wlast) begin
                                $display("[%0t] %s ERROR R003: WLAST not asserted on final write beat (expected after %0d beats)",
                                         $time, LABEL, 1);
                                error_count <= error_count + 1;
                            end
                            w_burst_active <= 1'b0;
                            w_beat_cnt     <= 9'd0;
                        end
                    end else begin
                        // W beat arrived with no outstanding AW — protocol error
                        $display("[%0t] %s ERROR R003: W data beat with no outstanding AW transaction",
                                 $time, LABEL);
                        error_count <= error_count + 1;
                    end
                end else begin
                    // Burst in progress — increment beat counter
                    w_beat_cnt <= w_beat_cnt + 1;

                    // Check if this is the last beat
                    if (w_beat_cnt == {1'b0, w_expected_len}) begin
                        // Rule AXI-R003: WLAST check
                        if (!wlast) begin
                            $display("[%0t] %s ERROR R003: WLAST not asserted on final write beat (beat %0d of %0d)",
                                     $time, LABEL, w_beat_cnt + 1, w_expected_len + 1);
                            error_count <= error_count + 1;
                        end
                        w_burst_active <= 1'b0;
                        w_beat_cnt     <= 9'd0;
                    end else begin
                        // Not the last beat — WLAST should NOT be asserted
                        if (wlast) begin
                            $display("[%0t] %s ERROR R003: WLAST asserted early (beat %0d of %0d expected)",
                                     $time, LABEL, w_beat_cnt + 1, w_expected_len + 1);
                            error_count <= error_count + 1;
                            // Treat as end of burst to resync
                            w_burst_active <= 1'b0;
                            w_beat_cnt     <= 9'd0;
                        end
                    end
                end
            end
        end
    end

    // --- B handshake: Rule AXI-R005 BID matching ---
    always @(posedge clk) begin
        if (rst_n) begin
            if (bvalid && bready) begin
                b_txn_count <= b_txn_count + 1;

                if (b_fifo_count > 0) begin
                    // Rule AXI-R005: BID must match AWID
                    if (bid !== b_id_fifo[b_fifo_rd_ptr % MAX_OUTSTANDING]) begin
                        $display("[%0t] %s ERROR R005: BID mismatch. Expected AWID=0x%0h, got BID=0x%0h",
                                 $time, LABEL,
                                 b_id_fifo[b_fifo_rd_ptr % MAX_OUTSTANDING], bid);
                        error_count <= error_count + 1;
                    end
                    b_fifo_rd_ptr <= b_fifo_rd_ptr + 1;
                    b_fifo_count  <= b_fifo_count - 1;
                end else begin
                    $display("[%0t] %s ERROR R005: B response with no outstanding AW transaction. BID=0x%0h",
                             $time, LABEL, bid);
                    error_count <= error_count + 1;
                end
            end
        end
    end

    // --- AR handshake: push to read FIFO, increment counter ---
    always @(posedge clk) begin
        if (rst_n) begin
            if (arvalid && arready) begin
                ar_txn_count <= ar_txn_count + 1;

                if (ar_fifo_count < MAX_OUTSTANDING) begin
                    ar_id_fifo[ar_fifo_wr_ptr % MAX_OUTSTANDING]  <= arid;
                    ar_len_fifo[ar_fifo_wr_ptr % MAX_OUTSTANDING] <= arlen;
                    ar_fifo_wr_ptr <= ar_fifo_wr_ptr + 1;
                    ar_fifo_count  <= ar_fifo_count + 1;
                end else begin
                    $display("[%0t] %s ERROR R006: AR outstanding FIFO overflow (MAX_OUTSTANDING=%0d)",
                             $time, LABEL, MAX_OUTSTANDING);
                    error_count <= error_count + 1;
                end
            end
        end
    end

    // --- R handshake: Rule AXI-R006 RLAST and RID check ---
    always @(posedge clk) begin
        if (!rst_n) begin
            r_beat_cnt     <= 9'd0;
            r_expected_len <= 8'd0;
            r_expected_id  <= {ID_WIDTH{1'b0}};
            r_burst_active <= 1'b0;
        end else begin
            if (rvalid && rready) begin
                r_beat_count <= r_beat_count + 1;

                if (!r_burst_active) begin
                    // Start of a new read burst — pop from FIFO
                    if (ar_fifo_count > 0) begin
                        r_expected_len <= ar_len_fifo[ar_fifo_rd_ptr % MAX_OUTSTANDING];
                        r_expected_id  <= ar_id_fifo[ar_fifo_rd_ptr % MAX_OUTSTANDING];
                        ar_fifo_rd_ptr <= ar_fifo_rd_ptr + 1;
                        ar_fifo_count  <= ar_fifo_count - 1;
                        r_burst_active <= 1'b1;
                        r_beat_cnt     <= 9'd1;

                        // Rule AXI-R006: RID check
                        if (rid !== ar_id_fifo[ar_fifo_rd_ptr % MAX_OUTSTANDING]) begin
                            $display("[%0t] %s ERROR R006: RID mismatch. Expected ARID=0x%0h, got RID=0x%0h",
                                     $time, LABEL,
                                     ar_id_fifo[ar_fifo_rd_ptr % MAX_OUTSTANDING], rid);
                            error_count <= error_count + 1;
                        end

                        // Single-beat burst
                        if (ar_len_fifo[ar_fifo_rd_ptr % MAX_OUTSTANDING] == 8'd0) begin
                            if (!rlast) begin
                                $display("[%0t] %s ERROR R006: RLAST not asserted on final read beat (expected after 1 beat)",
                                         $time, LABEL);
                                error_count <= error_count + 1;
                            end
                            r_burst_active <= 1'b0;
                            r_beat_cnt     <= 9'd0;
                        end
                    end else begin
                        $display("[%0t] %s ERROR R006: R data beat with no outstanding AR transaction",
                                 $time, LABEL);
                        error_count <= error_count + 1;
                    end
                end else begin
                    // Burst in progress
                    r_beat_cnt <= r_beat_cnt + 1;

                    // Rule AXI-R006: RID must be consistent within burst
                    if (rid !== r_expected_id) begin
                        $display("[%0t] %s ERROR R006: RID changed mid-burst. Expected 0x%0h, got 0x%0h",
                                 $time, LABEL, r_expected_id, rid);
                        error_count <= error_count + 1;
                    end

                    // Check if this is the last beat
                    if (r_beat_cnt == {1'b0, r_expected_len}) begin
                        if (!rlast) begin
                            $display("[%0t] %s ERROR R006: RLAST not asserted on final read beat (beat %0d of %0d)",
                                     $time, LABEL, r_beat_cnt + 1, r_expected_len + 1);
                            error_count <= error_count + 1;
                        end
                        r_burst_active <= 1'b0;
                        r_beat_cnt     <= 9'd0;
                    end else begin
                        // Not the last beat — RLAST should NOT be asserted
                        if (rlast) begin
                            $display("[%0t] %s ERROR R006: RLAST asserted early (beat %0d of %0d expected)",
                                     $time, LABEL, r_beat_cnt + 1, r_expected_len + 1);
                            error_count <= error_count + 1;
                            r_burst_active <= 1'b0;
                            r_beat_cnt     <= 9'd0;
                        end
                    end
                end
            end
        end
    end

    // ========================================================================
    // Rule AXI-R009: Timeout detection
    //   If any channel has VALID high without READY for more than
    //   TIMEOUT_CYCLES, report a timeout error (once per stall episode).
    // ========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            aw_timeout_cnt   <= 32'd0;
            aw_timeout_fired <= 1'b0;
        end else begin
            if (awvalid && !awready) begin
                aw_timeout_cnt <= aw_timeout_cnt + 1;
                if ((aw_timeout_cnt >= TIMEOUT_CYCLES) && !aw_timeout_fired) begin
                    $display("[%0t] %s ERROR R009: AW channel timeout — AWVALID asserted for %0d cycles without AWREADY",
                             $time, LABEL, aw_timeout_cnt);
                    error_count      <= error_count + 1;
                    aw_timeout_fired <= 1'b1;
                end
            end else begin
                aw_timeout_cnt   <= 32'd0;
                aw_timeout_fired <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            w_timeout_cnt   <= 32'd0;
            w_timeout_fired <= 1'b0;
        end else begin
            if (wvalid && !wready) begin
                w_timeout_cnt <= w_timeout_cnt + 1;
                if ((w_timeout_cnt >= TIMEOUT_CYCLES) && !w_timeout_fired) begin
                    $display("[%0t] %s ERROR R009: W channel timeout — WVALID asserted for %0d cycles without WREADY",
                             $time, LABEL, w_timeout_cnt);
                    error_count     <= error_count + 1;
                    w_timeout_fired <= 1'b1;
                end
            end else begin
                w_timeout_cnt   <= 32'd0;
                w_timeout_fired <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            b_timeout_cnt   <= 32'd0;
            b_timeout_fired <= 1'b0;
        end else begin
            if (bvalid && !bready) begin
                b_timeout_cnt <= b_timeout_cnt + 1;
                if ((b_timeout_cnt >= TIMEOUT_CYCLES) && !b_timeout_fired) begin
                    $display("[%0t] %s ERROR R009: B channel timeout — BVALID asserted for %0d cycles without BREADY",
                             $time, LABEL, b_timeout_cnt);
                    error_count     <= error_count + 1;
                    b_timeout_fired <= 1'b1;
                end
            end else begin
                b_timeout_cnt   <= 32'd0;
                b_timeout_fired <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            ar_timeout_cnt   <= 32'd0;
            ar_timeout_fired <= 1'b0;
        end else begin
            if (arvalid && !arready) begin
                ar_timeout_cnt <= ar_timeout_cnt + 1;
                if ((ar_timeout_cnt >= TIMEOUT_CYCLES) && !ar_timeout_fired) begin
                    $display("[%0t] %s ERROR R009: AR channel timeout — ARVALID asserted for %0d cycles without ARREADY",
                             $time, LABEL, ar_timeout_cnt);
                    error_count      <= error_count + 1;
                    ar_timeout_fired <= 1'b1;
                end
            end else begin
                ar_timeout_cnt   <= 32'd0;
                ar_timeout_fired <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            r_timeout_cnt   <= 32'd0;
            r_timeout_fired <= 1'b0;
        end else begin
            if (rvalid && !rready) begin
                r_timeout_cnt <= r_timeout_cnt + 1;
                if ((r_timeout_cnt >= TIMEOUT_CYCLES) && !r_timeout_fired) begin
                    $display("[%0t] %s ERROR R009: R channel timeout — RVALID asserted for %0d cycles without RREADY",
                             $time, LABEL, r_timeout_cnt);
                    error_count     <= error_count + 1;
                    r_timeout_fired <= 1'b1;
                end
            end else begin
                r_timeout_cnt   <= 32'd0;
                r_timeout_fired <= 1'b0;
            end
        end
    end

endmodule
