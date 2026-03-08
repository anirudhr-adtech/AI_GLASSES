`timescale 1ns/1ps
//============================================================================
// Module : ibex_core (simulation stub)
// Project : AI_GLASSES — RISC-V Subsystem
// Description : Minimal stub for the lowRISC Ibex RV32IMC core.
//               Provides port-compatible black box for iverilog compilation.
//               NOT for functional simulation — replace with real Ibex IP.
//============================================================================

module ibex_core #(
    parameter PMPEnable        = 0,
    parameter PMPGranularity   = 0,
    parameter PMPNumRegions    = 4,
    parameter MHPMCounterNum   = 0,
    parameter MHPMCounterWidth = 40,
    parameter RV32E            = 0,
    parameter RV32M            = 2,
    parameter RV32B            = 0,
    parameter RegFile          = 0,
    parameter BranchTargetALU  = 1,
    parameter WritebackStage   = 0,
    parameter ICache           = 0,
    parameter ICacheECC        = 0,
    parameter DbgTriggerEn     = 0,
    parameter SecureIbex       = 0,
    parameter [31:0] DmHaltAddr      = 32'h00000000,
    parameter [31:0] DmExceptionAddr = 32'h00000000
)(
    input  wire        clk_i,
    input  wire        rst_ni,

    // Instruction interface
    output wire        instr_req_o,
    input  wire        instr_gnt_i,
    input  wire        instr_rvalid_i,
    output wire [31:0] instr_addr_o,
    input  wire [31:0] instr_rdata_i,
    input  wire        instr_err_i,

    // Data interface
    output wire        data_req_o,
    input  wire        data_gnt_i,
    input  wire        data_rvalid_i,
    output wire        data_we_o,
    output wire [3:0]  data_be_o,
    output wire [31:0] data_addr_o,
    output wire [31:0] data_wdata_o,
    input  wire [31:0] data_rdata_i,
    input  wire        data_err_i,

    // Interrupts
    input  wire        irq_software_i,
    input  wire        irq_timer_i,
    input  wire        irq_external_i,
    input  wire [14:0] irq_fast_i,
    input  wire        irq_nm_i,

    // Debug
    input  wire        debug_req_i,

    // CPU control
    input  wire [3:0]  fetch_enable_i,
    output wire        alert_minor_o,
    output wire        alert_major_internal_o,
    output wire        alert_major_bus_o,
    output wire        core_sleep_o,

    // Boot
    input  wire [31:0] boot_addr_i,

    // Hart ID
    input  wire [31:0] hart_id_i,

    // Scramble interface
    input  wire        scramble_key_valid_i,
    input  wire [127:0] scramble_key_i,
    input  wire [63:0] scramble_nonce_i,
    output wire        scramble_req_o,

    // Double fault
    output wire        double_fault_seen_o,

    // DFT
    input  wire        scan_rst_ni
);

    // Stub: no instruction or data requests
    assign instr_req_o           = 1'b0;
    assign instr_addr_o          = 32'd0;
    assign data_req_o            = 1'b0;
    assign data_we_o             = 1'b0;
    assign data_be_o             = 4'd0;
    assign data_addr_o           = 32'd0;
    assign data_wdata_o          = 32'd0;
    assign alert_minor_o         = 1'b0;
    assign alert_major_internal_o = 1'b0;
    assign alert_major_bus_o     = 1'b0;
    assign core_sleep_o          = 1'b0;
    assign scramble_req_o        = 1'b0;
    assign double_fault_seen_o   = 1'b0;

endmodule
