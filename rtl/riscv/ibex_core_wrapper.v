`timescale 1ns/1ps
//============================================================================
// Module : ibex_core_wrapper
// Project : AI_GLASSES — RISC-V Subsystem
// Description : Wrapper around external Ibex RISC-V CPU core (black-box)
//============================================================================

module ibex_core_wrapper (
    input  wire        clk,
    input  wire        rst_n,

    // Instruction bus
    output wire        instr_req_o,
    input  wire        instr_gnt_i,
    input  wire        instr_rvalid_i,
    output wire [31:0] instr_addr_o,
    input  wire [31:0] instr_rdata_i,
    input  wire        instr_err_i,

    // Data bus
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
    input  wire        irq_timer_i,
    input  wire        irq_external_i,
    input  wire        irq_software_i,

    // Boot address
    input  wire [31:0] boot_addr_i
);

    // ----------------------------------------------------------------
    // Internal wires from ibex_core
    // ----------------------------------------------------------------
    wire        core_instr_req;
    wire [31:0] core_instr_addr;
    wire        core_data_req;
    wire        core_data_we;
    wire [3:0]  core_data_be;
    wire [31:0] core_data_addr;
    wire [31:0] core_data_wdata;

    // ----------------------------------------------------------------
    // Registered outputs at module boundary
    // ----------------------------------------------------------------
    reg        instr_req_r;
    reg [31:0] instr_addr_r;
    reg        data_req_r;
    reg        data_we_r;
    reg [3:0]  data_be_r;
    reg [31:0] data_addr_r;
    reg [31:0] data_wdata_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            instr_req_r  <= 1'b0;
            instr_addr_r <= 32'd0;
            data_req_r   <= 1'b0;
            data_we_r    <= 1'b0;
            data_be_r    <= 4'd0;
            data_addr_r  <= 32'd0;
            data_wdata_r <= 32'd0;
        end else begin
            instr_req_r  <= core_instr_req;
            instr_addr_r <= core_instr_addr;
            data_req_r   <= core_data_req;
            data_we_r    <= core_data_we;
            data_be_r    <= core_data_be;
            data_addr_r  <= core_data_addr;
            data_wdata_r <= core_data_wdata;
        end
    end

    assign instr_req_o  = instr_req_r;
    assign instr_addr_o = instr_addr_r;
    assign data_req_o   = data_req_r;
    assign data_we_o    = data_we_r;
    assign data_be_o    = data_be_r;
    assign data_addr_o  = data_addr_r;
    assign data_wdata_o = data_wdata_r;

    // ----------------------------------------------------------------
    // Ibex core instantiation (black-box, external IP)
    // ----------------------------------------------------------------
    ibex_core #(
        .PMPEnable       (0),
        .PMPGranularity  (0),
        .PMPNumRegions   (4),
        .MHPMCounterNum  (0),
        .MHPMCounterWidth(40),
        .RV32E           (0),
        .RV32M           (2),   // RV32MSingleCycle
        .RV32B           (0),   // RV32BNone
        .RegFile         (0),   // RegFileFF
        .BranchTargetALU (1),
        .WritebackStage  (0),
        .ICache          (0),
        .ICacheECC       (0),
        .DbgTriggerEn    (0),
        .SecureIbex      (0),
        .DmHaltAddr      (32'h00000000),
        .DmExceptionAddr (32'h00000000)
    ) u_ibex_core (
        .clk_i               (clk),
        .rst_ni              (rst_n),

        // Instruction interface
        .instr_req_o         (core_instr_req),
        .instr_gnt_i         (instr_gnt_i),
        .instr_rvalid_i      (instr_rvalid_i),
        .instr_addr_o        (core_instr_addr),
        .instr_rdata_i       (instr_rdata_i),
        .instr_err_i         (instr_err_i),

        // Data interface
        .data_req_o          (core_data_req),
        .data_gnt_i          (data_gnt_i),
        .data_rvalid_i       (data_rvalid_i),
        .data_we_o           (core_data_we),
        .data_be_o           (core_data_be),
        .data_addr_o         (core_data_addr),
        .data_wdata_o        (core_data_wdata),
        .data_rdata_i        (data_rdata_i),
        .data_err_i          (data_err_i),

        // Interrupts
        .irq_software_i      (irq_software_i),
        .irq_timer_i         (irq_timer_i),
        .irq_external_i      (irq_external_i),
        .irq_fast_i          (15'd0),
        .irq_nm_i            (1'b0),

        // Debug
        .debug_req_i         (1'b0),

        // CPU control
        .fetch_enable_i      (4'b0101),
        .alert_minor_o       (),
        .alert_major_internal_o (),
        .alert_major_bus_o   (),
        .core_sleep_o        (),

        // Boot
        .boot_addr_i         (boot_addr_i),

        // Hart ID
        .hart_id_i           (32'd0),

        // Scramble interface (tie off)
        .scramble_key_valid_i(1'b0),
        .scramble_key_i      (128'd0),
        .scramble_nonce_i    (64'd0),
        .scramble_req_o      (),

        // Double fault
        .double_fault_seen_o (),

        // DFT
        .scan_rst_ni         (1'b1)
    );

endmodule
