`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////////////
// test_result_monitor.v
// Watches a memory-mapped AXI4-Lite address for firmware PASS/FAIL result.
// AXI4-Lite slave: firmware writes PASS_CODE or FAIL_CODE to WATCH_ADDR.
// Read channel tied off with SLVERR.
//////////////////////////////////////////////////////////////////////////////
module test_result_monitor #(
    parameter [31:0] WATCH_ADDR = 32'h1000_FF00,
    parameter [31:0] PASS_CODE  = 32'h0000_600D,
    parameter [31:0] FAIL_CODE  = 32'hDEAD_BEEF
)(
    input  wire        clk,
    input  wire        rst_n,

    // AXI4-Lite slave — write address channel
    input  wire [31:0] s_axil_awaddr,
    input  wire        s_axil_awvalid,
    output wire        s_axil_awready,

    // AXI4-Lite slave — write data channel
    input  wire [31:0] s_axil_wdata,
    input  wire [3:0]  s_axil_wstrb,
    input  wire        s_axil_wvalid,
    output wire        s_axil_wready,

    // AXI4-Lite slave — write response channel
    output wire [1:0]  s_axil_bresp,
    output wire        s_axil_bvalid,
    input  wire        s_axil_bready,

    // AXI4-Lite slave — read address channel (tied off)
    input  wire [31:0] s_axil_araddr,
    input  wire        s_axil_arvalid,
    output wire        s_axil_arready,

    // AXI4-Lite slave — read data channel (tied off with SLVERR)
    output wire [31:0] s_axil_rdata,
    output wire [1:0]  s_axil_rresp,
    output wire        s_axil_rvalid,
    input  wire        s_axil_rready,

    // Test result outputs
    output reg         test_done,
    output reg         test_pass
);

    // -----------------------------------------------------------------------
    // Write channel — always ready
    // -----------------------------------------------------------------------
    assign s_axil_awready = 1'b1;
    assign s_axil_wready  = 1'b1;

    // -----------------------------------------------------------------------
    // Write response — OKAY
    // -----------------------------------------------------------------------
    reg        bvalid_r;
    assign s_axil_bresp  = 2'b00;   // OKAY
    assign s_axil_bvalid = bvalid_r;

    // -----------------------------------------------------------------------
    // Read channel — tied off with SLVERR (2'b10)
    // -----------------------------------------------------------------------
    reg        rvalid_r;
    assign s_axil_arready = 1'b1;
    assign s_axil_rdata   = 32'd0;
    assign s_axil_rresp   = 2'b10;  // SLVERR
    assign s_axil_rvalid  = rvalid_r;

    // -----------------------------------------------------------------------
    // Latch write address — need both AW and W to fire
    // -----------------------------------------------------------------------
    reg        aw_fire;
    reg        w_fire;
    reg [31:0] latched_addr;
    reg [31:0] latched_data;

    // -----------------------------------------------------------------------
    // Write handling — synchronous, active-low reset
    // -----------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            aw_fire      <= 1'b0;
            w_fire       <= 1'b0;
            latched_addr <= 32'd0;
            latched_data <= 32'd0;
            bvalid_r     <= 1'b0;
            rvalid_r     <= 1'b0;
            test_done    <= 1'b0;
            test_pass    <= 1'b0;
        end else begin
            // ---- Write response handshake ----
            if (bvalid_r && s_axil_bready)
                bvalid_r <= 1'b0;

            // ---- Read response handshake (always SLVERR) ----
            if (s_axil_arvalid && !rvalid_r)
                rvalid_r <= 1'b1;
            else if (rvalid_r && s_axil_rready)
                rvalid_r <= 1'b0;

            // ---- Capture AW ----
            if (s_axil_awvalid && s_axil_awready) begin
                latched_addr <= s_axil_awaddr;
                aw_fire      <= 1'b1;
            end

            // ---- Capture W ----
            if (s_axil_wvalid && s_axil_wready) begin
                latched_data <= s_axil_wdata;
                w_fire       <= 1'b1;
            end

            // ---- Both channels fired — process write ----
            if (aw_fire && w_fire) begin
                aw_fire  <= 1'b0;
                w_fire   <= 1'b0;
                bvalid_r <= 1'b1;

                // Check if write targets the watch address
                if (latched_addr == WATCH_ADDR) begin
                    test_done <= 1'b1;

                    if (latched_data == PASS_CODE) begin
                        test_pass <= 1'b1;
                        $display("[%0t] TEST RESULT: PASS", $time);
                    end else if (latched_data == FAIL_CODE) begin
                        test_pass <= 1'b0;
                        $display("[%0t] TEST RESULT: FAIL", $time);
                    end else begin
                        test_pass <= 1'b0;
                        $display("[%0t] TEST RESULT: UNKNOWN CODE 0x%08X", $time, latched_data);
                    end
                end
            end
        end
    end

endmodule
