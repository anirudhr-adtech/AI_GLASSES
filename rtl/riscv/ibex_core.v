`timescale 1ns/1ps
//============================================================================
// Module : ibex_core (behavioral simulation model)
// Project : AI_GLASSES — RISC-V Subsystem
// Description : Behavioral RV32IM CPU model for simulation. Replaces the
//               non-functional stub with a fully-functional instruction
//               set implementation using the same OBI bus interface.
//               Supports: RV32I base + M extension (multiply/divide),
//               machine-mode CSRs, interrupts, WFI, MRET, ECALL/EBREAK.
//               NOT cycle-accurate to real Ibex — sequential fetch/execute.
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

    // Instruction interface (OBI)
    output wire        instr_req_o,
    input  wire        instr_gnt_i,
    input  wire        instr_rvalid_i,
    output wire [31:0] instr_addr_o,
    input  wire [31:0] instr_rdata_i,
    input  wire        instr_err_i,

    // Data interface (OBI)
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

    // ================================================================
    // Static outputs (unused features)
    // ================================================================
    assign alert_minor_o         = 1'b0;
    assign alert_major_internal_o = 1'b0;
    assign alert_major_bus_o     = 1'b0;
    assign scramble_req_o        = 1'b0;
    assign double_fault_seen_o   = 1'b0;

    // ================================================================
    // FSM States
    // ================================================================
    localparam S_RESET      = 4'd0;
    localparam S_FETCH_REQ  = 4'd1;
    localparam S_FETCH_GNT  = 4'd2;
    localparam S_FETCH_WAIT = 4'd3;
    localparam S_EXECUTE    = 4'd4;
    localparam S_MEM_REQ    = 4'd5;
    localparam S_MEM_GNT    = 4'd6;
    localparam S_MEM_WAIT   = 4'd7;
    localparam S_WFI        = 4'd8;

    // ================================================================
    // Opcodes
    // ================================================================
    localparam OP_LUI    = 7'b0110111;
    localparam OP_AUIPC  = 7'b0010111;
    localparam OP_JAL    = 7'b1101111;
    localparam OP_JALR   = 7'b1100111;
    localparam OP_BRANCH = 7'b1100011;
    localparam OP_LOAD   = 7'b0000011;
    localparam OP_STORE  = 7'b0100011;
    localparam OP_OPIMM  = 7'b0010011;
    localparam OP_OP     = 7'b0110011;
    localparam OP_FENCE  = 7'b0001111;
    localparam OP_SYSTEM = 7'b1110011;

    // ================================================================
    // Register File (x0 hardwired to 0)
    // ================================================================
    reg [31:0] rf [0:31];
    reg [31:0] pc;

    // ================================================================
    // CSRs
    // ================================================================
    reg [31:0] csr_mstatus;
    reg [31:0] csr_mie;
    reg [31:0] csr_mtvec;
    reg [31:0] csr_mepc;
    reg [31:0] csr_mcause;
    reg [31:0] csr_mscratch;
    reg [63:0] csr_mcycle;
    reg [63:0] csr_minstret;

    // mip is combinational from interrupt inputs
    wire [31:0] csr_mip = {20'd0, irq_external_i, 3'd0,
                           irq_timer_i, 3'd0,
                           irq_software_i, 3'd0};

    // ================================================================
    // FSM Registers
    // ================================================================
    reg [3:0]  state;
    reg [31:0] instr_r;       // Captured instruction
    reg [31:0] mem_addr_r;    // Memory access address
    reg [31:0] mem_wdata_r;   // Memory write data
    reg [3:0]  mem_be_r;      // Byte enables
    reg        mem_we_r;      // Write enable
    reg [4:0]  mem_rd_r;      // Destination register for loads
    reg [2:0]  mem_funct3_r;  // Load type for sign/zero extension

    // ================================================================
    // Output Registers
    // ================================================================
    reg        instr_req_r;
    reg [31:0] instr_addr_r;
    reg        data_req_r;
    reg        data_we_r;
    reg [3:0]  data_be_r;
    reg [31:0] data_addr_r;
    reg [31:0] data_wdata_r;

    assign instr_req_o  = instr_req_r;
    assign instr_addr_o = instr_addr_r;
    assign data_req_o   = data_req_r;
    assign data_we_o    = data_we_r;
    assign data_be_o    = data_be_r;
    assign data_addr_o  = data_addr_r;
    assign data_wdata_o = data_wdata_r;
    assign core_sleep_o = (state == S_WFI);

    // ================================================================
    // Instruction Decode (combinational from instr_r)
    // ================================================================
    wire [6:0]  opcode  = instr_r[6:0];
    wire [4:0]  rd      = instr_r[11:7];
    wire [2:0]  funct3  = instr_r[14:12];
    wire [4:0]  rs1     = instr_r[19:15];
    wire [4:0]  rs2     = instr_r[24:20];
    wire [6:0]  funct7  = instr_r[31:25];
    wire [11:0] csr_addr_w = instr_r[31:20];

    // Immediate decoding
    wire [31:0] imm_i = {{20{instr_r[31]}}, instr_r[31:20]};
    wire [31:0] imm_s = {{20{instr_r[31]}}, instr_r[31:25], instr_r[11:7]};
    wire [31:0] imm_b = {{19{instr_r[31]}}, instr_r[31], instr_r[7],
                          instr_r[30:25], instr_r[11:8], 1'b0};
    wire [31:0] imm_u = {instr_r[31:12], 12'b0};
    wire [31:0] imm_j = {{11{instr_r[31]}}, instr_r[31], instr_r[19:12],
                          instr_r[20], instr_r[30:21], 1'b0};

    // Source register values
    wire [31:0] rs1_val = (rs1 == 5'd0) ? 32'd0 : rf[rs1];
    wire [31:0] rs2_val = (rs2 == 5'd0) ? 32'd0 : rf[rs2];

    // ================================================================
    // Interrupt Logic
    // ================================================================
    wire        mie_global = csr_mstatus[3];
    wire [31:0] irq_pending = csr_mie & csr_mip;
    wire        irq_active  = mie_global && (irq_pending != 32'd0);

    // Highest priority: external(11) > software(3) > timer(7)
    // Actually RISC-V priority: MEI(11) > MSI(3) > MTI(7)
    wire [4:0]  irq_cause = irq_pending[11] ? 5'd11 :
                            irq_pending[3]  ? 5'd3  :
                            irq_pending[7]  ? 5'd7  : 5'd0;

    // ================================================================
    // CSR Read Function
    // ================================================================
    function [31:0] csr_read_val;
        input [11:0] addr;
        begin
            case (addr)
                12'h300: csr_read_val = csr_mstatus;
                12'h304: csr_read_val = csr_mie;
                12'h305: csr_read_val = csr_mtvec;
                12'h340: csr_read_val = csr_mscratch;
                12'h341: csr_read_val = csr_mepc;
                12'h342: csr_read_val = csr_mcause;
                12'h344: csr_read_val = csr_mip;
                12'hF11: csr_read_val = 32'd0;       // mvendorid
                12'hF12: csr_read_val = 32'd0;       // marchid
                12'hF13: csr_read_val = 32'd0;       // mimpid
                12'hF14: csr_read_val = hart_id_i;   // mhartid
                12'hB00: csr_read_val = csr_mcycle[31:0];
                12'hB02: csr_read_val = csr_minstret[31:0];
                12'hB80: csr_read_val = csr_mcycle[63:32];
                12'hB82: csr_read_val = csr_minstret[63:32];
                default: csr_read_val = 32'd0;
            endcase
        end
    endfunction

    // ================================================================
    // ALU result (computed combinationally for use in S_EXECUTE)
    // ================================================================
    reg [31:0] alu_result;
    reg [31:0] next_pc_comb;
    reg        take_branch;
    reg        do_mem_access;
    reg        do_writeback;

    // ================================================================
    // Main FSM
    // ================================================================
    integer i;
    reg [63:0] mul_tmp;
    reg [31:0] csr_old_val;
    reg [31:0] csr_new_val;
    reg [31:0] csr_write_val;
    reg [4:0]  zimm;
    reg [31:0] load_data;
    reg [1:0]  byte_offset;

    always @(posedge clk_i) begin
        if (!rst_ni) begin
            state        <= S_RESET;
            pc           <= boot_addr_i;
            instr_r      <= 32'h00000013; // NOP (ADDI x0, x0, 0)
            instr_req_r  <= 1'b0;
            instr_addr_r <= 32'd0;
            data_req_r   <= 1'b0;
            data_we_r    <= 1'b0;
            data_be_r    <= 4'd0;
            data_addr_r  <= 32'd0;
            data_wdata_r <= 32'd0;
            mem_addr_r   <= 32'd0;
            mem_wdata_r  <= 32'd0;
            mem_be_r     <= 4'd0;
            mem_we_r     <= 1'b0;
            mem_rd_r     <= 5'd0;
            mem_funct3_r <= 3'd0;
            csr_mstatus  <= 32'h00001800; // MPP=M-mode
            csr_mie      <= 32'd0;
            csr_mtvec    <= 32'd0;
            csr_mepc     <= 32'd0;
            csr_mcause   <= 32'd0;
            csr_mscratch <= 32'd0;
            csr_mcycle   <= 64'd0;
            csr_minstret <= 64'd0;
            for (i = 0; i < 32; i = i + 1)
                rf[i] <= 32'd0;
        end else begin
            // Cycle counter always increments
            csr_mcycle <= csr_mcycle + 64'd1;

            case (state)
                // --------------------------------------------------------
                // S_RESET: Wait for fetch enable
                // --------------------------------------------------------
                S_RESET: begin
                    if (fetch_enable_i == 4'b0101) begin
                        state <= S_FETCH_REQ;
                    end
                end

                // --------------------------------------------------------
                // S_FETCH_REQ: Check interrupts, then issue fetch
                // --------------------------------------------------------
                S_FETCH_REQ: begin
                    if (irq_active) begin
                        // Enter trap
                        csr_mepc           <= pc;
                        csr_mcause         <= {1'b1, 26'd0, irq_cause};
                        csr_mstatus[7]     <= csr_mstatus[3]; // MPIE = MIE
                        csr_mstatus[3]     <= 1'b0;           // MIE = 0
                        csr_mstatus[12:11] <= 2'b11;          // MPP = M
                        pc                 <= csr_mtvec & 32'hFFFFFFFC;
                        // Don't start fetch yet — re-enter S_FETCH_REQ with new PC
                    end else begin
                        instr_req_r  <= 1'b1;
                        instr_addr_r <= pc;
                        state        <= S_FETCH_GNT;
                    end
                end

                // --------------------------------------------------------
                // S_FETCH_GNT: Wait for instruction grant
                // --------------------------------------------------------
                S_FETCH_GNT: begin
                    if (instr_gnt_i) begin
                        instr_req_r <= 1'b0;
                        state       <= S_FETCH_WAIT;
                    end
                end

                // --------------------------------------------------------
                // S_FETCH_WAIT: Wait for instruction data
                // --------------------------------------------------------
                S_FETCH_WAIT: begin
                    if (instr_rvalid_i) begin
                        instr_r <= instr_rdata_i;
                        state   <= S_EXECUTE;
                    end
                end

                // --------------------------------------------------------
                // S_EXECUTE: Decode and execute instruction
                // --------------------------------------------------------
                S_EXECUTE: begin
                    csr_minstret <= csr_minstret + 64'd1;

                    case (opcode)
                        // ---- LUI ----
                        OP_LUI: begin
                            if (rd != 5'd0) rf[rd] <= imm_u;
                            pc    <= pc + 32'd4;
                            state <= S_FETCH_REQ;
                        end

                        // ---- AUIPC ----
                        OP_AUIPC: begin
                            if (rd != 5'd0) rf[rd] <= pc + imm_u;
                            pc    <= pc + 32'd4;
                            state <= S_FETCH_REQ;
                        end

                        // ---- JAL ----
                        OP_JAL: begin
                            if (rd != 5'd0) rf[rd] <= pc + 32'd4;
                            pc    <= pc + imm_j;
                            state <= S_FETCH_REQ;
                        end

                        // ---- JALR ----
                        OP_JALR: begin
                            if (rd != 5'd0) rf[rd] <= pc + 32'd4;
                            pc    <= (rs1_val + imm_i) & 32'hFFFFFFFE;
                            state <= S_FETCH_REQ;
                        end

                        // ---- BRANCH ----
                        OP_BRANCH: begin
                            take_branch = 1'b0;
                            case (funct3)
                                3'b000: take_branch = (rs1_val == rs2_val);           // BEQ
                                3'b001: take_branch = (rs1_val != rs2_val);           // BNE
                                3'b100: take_branch = ($signed(rs1_val) < $signed(rs2_val));  // BLT
                                3'b101: take_branch = ($signed(rs1_val) >= $signed(rs2_val)); // BGE
                                3'b110: take_branch = (rs1_val < rs2_val);            // BLTU
                                3'b111: take_branch = (rs1_val >= rs2_val);           // BGEU
                                default: take_branch = 1'b0;
                            endcase
                            if (take_branch)
                                pc <= pc + imm_b;
                            else
                                pc <= pc + 32'd4;
                            state <= S_FETCH_REQ;
                        end

                        // ---- LOAD ----
                        OP_LOAD: begin
                            mem_addr_r   <= rs1_val + imm_i;
                            mem_we_r     <= 1'b0;
                            mem_rd_r     <= rd;
                            mem_funct3_r <= funct3;
                            // Byte enables based on size and address
                            case (funct3)
                                3'b000, 3'b100: begin // LB, LBU
                                    case ((rs1_val + imm_i) & 32'h3)
                                        2'd0: mem_be_r <= 4'b0001;
                                        2'd1: mem_be_r <= 4'b0010;
                                        2'd2: mem_be_r <= 4'b0100;
                                        2'd3: mem_be_r <= 4'b1000;
                                    endcase
                                end
                                3'b001, 3'b101: begin // LH, LHU
                                    case ((rs1_val + imm_i) & 32'h2)
                                        2'd0: mem_be_r <= 4'b0011;
                                        2'd2: mem_be_r <= 4'b1100;
                                        default: mem_be_r <= 4'b0011;
                                    endcase
                                end
                                3'b010: begin // LW
                                    mem_be_r <= 4'b1111;
                                end
                                default: mem_be_r <= 4'b1111;
                            endcase
                            state <= S_MEM_REQ;
                        end

                        // ---- STORE ----
                        OP_STORE: begin
                            mem_addr_r <= rs1_val + imm_s;
                            mem_we_r   <= 1'b1;
                            mem_rd_r   <= 5'd0;
                            // Place data in correct byte lane
                            case (funct3)
                                3'b000: begin // SB
                                    case ((rs1_val + imm_s) & 32'h3)
                                        2'd0: begin mem_wdata_r <= {24'd0, rs2_val[7:0]};       mem_be_r <= 4'b0001; end
                                        2'd1: begin mem_wdata_r <= {16'd0, rs2_val[7:0], 8'd0}; mem_be_r <= 4'b0010; end
                                        2'd2: begin mem_wdata_r <= {8'd0, rs2_val[7:0], 16'd0}; mem_be_r <= 4'b0100; end
                                        2'd3: begin mem_wdata_r <= {rs2_val[7:0], 24'd0};       mem_be_r <= 4'b1000; end
                                    endcase
                                end
                                3'b001: begin // SH
                                    case ((rs1_val + imm_s) & 32'h2)
                                        2'd0: begin mem_wdata_r <= {16'd0, rs2_val[15:0]}; mem_be_r <= 4'b0011; end
                                        2'd2: begin mem_wdata_r <= {rs2_val[15:0], 16'd0}; mem_be_r <= 4'b1100; end
                                        default: begin mem_wdata_r <= {16'd0, rs2_val[15:0]}; mem_be_r <= 4'b0011; end
                                    endcase
                                end
                                3'b010: begin // SW
                                    mem_wdata_r <= rs2_val;
                                    mem_be_r    <= 4'b1111;
                                end
                                default: begin
                                    mem_wdata_r <= rs2_val;
                                    mem_be_r    <= 4'b1111;
                                end
                            endcase
                            state <= S_MEM_REQ;
                        end

                        // ---- OP-IMM (register-immediate ALU) ----
                        OP_OPIMM: begin
                            case (funct3)
                                3'b000: alu_result = rs1_val + imm_i;                           // ADDI
                                3'b010: alu_result = ($signed(rs1_val) < $signed(imm_i)) ? 32'd1 : 32'd0; // SLTI
                                3'b011: alu_result = (rs1_val < imm_i) ? 32'd1 : 32'd0;        // SLTIU
                                3'b100: alu_result = rs1_val ^ imm_i;                           // XORI
                                3'b110: alu_result = rs1_val | imm_i;                           // ORI
                                3'b111: alu_result = rs1_val & imm_i;                           // ANDI
                                3'b001: alu_result = rs1_val << rs2;                            // SLLI (shamt=rs2)
                                3'b101: begin
                                    if (funct7[5])
                                        alu_result = $signed(rs1_val) >>> rs2;                  // SRAI
                                    else
                                        alu_result = rs1_val >> rs2;                            // SRLI
                                end
                                default: alu_result = 32'd0;
                            endcase
                            if (rd != 5'd0) rf[rd] <= alu_result;
                            pc    <= pc + 32'd4;
                            state <= S_FETCH_REQ;
                        end

                        // ---- OP (register-register ALU + M extension) ----
                        OP_OP: begin
                            if (funct7 == 7'b0000001) begin
                                // M extension
                                case (funct3)
                                    3'b000: begin // MUL
                                        mul_tmp = {{32{rs1_val[31]}}, rs1_val} * {{32{rs2_val[31]}}, rs2_val};
                                        alu_result = mul_tmp[31:0];
                                    end
                                    3'b001: begin // MULH (signed x signed)
                                        mul_tmp = $signed({{32{rs1_val[31]}}, rs1_val}) *
                                                  $signed({{32{rs2_val[31]}}, rs2_val});
                                        alu_result = mul_tmp[63:32];
                                    end
                                    3'b010: begin // MULHSU (signed x unsigned)
                                        mul_tmp = $signed({{32{rs1_val[31]}}, rs1_val}) *
                                                  $signed({1'b0, {31'd0}, rs2_val});
                                        alu_result = mul_tmp[63:32];
                                    end
                                    3'b011: begin // MULHU (unsigned x unsigned)
                                        mul_tmp = {32'd0, rs1_val} * {32'd0, rs2_val};
                                        alu_result = mul_tmp[63:32];
                                    end
                                    3'b100: begin // DIV
                                        if (rs2_val == 32'd0)
                                            alu_result = 32'hFFFFFFFF;
                                        else if (rs1_val == 32'h80000000 && rs2_val == 32'hFFFFFFFF)
                                            alu_result = 32'h80000000;
                                        else
                                            alu_result = $signed(rs1_val) / $signed(rs2_val);
                                    end
                                    3'b101: begin // DIVU
                                        if (rs2_val == 32'd0)
                                            alu_result = 32'hFFFFFFFF;
                                        else
                                            alu_result = rs1_val / rs2_val;
                                    end
                                    3'b110: begin // REM
                                        if (rs2_val == 32'd0)
                                            alu_result = rs1_val;
                                        else if (rs1_val == 32'h80000000 && rs2_val == 32'hFFFFFFFF)
                                            alu_result = 32'd0;
                                        else
                                            alu_result = $signed(rs1_val) % $signed(rs2_val);
                                    end
                                    3'b111: begin // REMU
                                        if (rs2_val == 32'd0)
                                            alu_result = rs1_val;
                                        else
                                            alu_result = rs1_val % rs2_val;
                                    end
                                    default: alu_result = 32'd0;
                                endcase
                            end else begin
                                // Base RV32I register-register ops
                                case (funct3)
                                    3'b000: begin
                                        if (funct7[5])
                                            alu_result = rs1_val - rs2_val;     // SUB
                                        else
                                            alu_result = rs1_val + rs2_val;     // ADD
                                    end
                                    3'b001: alu_result = rs1_val << rs2_val[4:0];   // SLL
                                    3'b010: alu_result = ($signed(rs1_val) < $signed(rs2_val)) ? 32'd1 : 32'd0; // SLT
                                    3'b011: alu_result = (rs1_val < rs2_val) ? 32'd1 : 32'd0; // SLTU
                                    3'b100: alu_result = rs1_val ^ rs2_val;         // XOR
                                    3'b101: begin
                                        if (funct7[5])
                                            alu_result = $signed(rs1_val) >>> rs2_val[4:0]; // SRA
                                        else
                                            alu_result = rs1_val >> rs2_val[4:0];           // SRL
                                    end
                                    3'b110: alu_result = rs1_val | rs2_val;         // OR
                                    3'b111: alu_result = rs1_val & rs2_val;         // AND
                                    default: alu_result = 32'd0;
                                endcase
                            end
                            if (rd != 5'd0) rf[rd] <= alu_result;
                            pc    <= pc + 32'd4;
                            state <= S_FETCH_REQ;
                        end

                        // ---- FENCE (NOP in behavioral model) ----
                        OP_FENCE: begin
                            pc    <= pc + 32'd4;
                            state <= S_FETCH_REQ;
                        end

                        // ---- SYSTEM ----
                        OP_SYSTEM: begin
                            if (funct3 == 3'b000) begin
                                // ECALL / EBREAK / MRET / WFI
                                case (instr_r[31:20])
                                    12'h000: begin // ECALL
                                        csr_mepc           <= pc;
                                        csr_mcause         <= 32'd11; // Environment call from M-mode
                                        csr_mstatus[7]     <= csr_mstatus[3];
                                        csr_mstatus[3]     <= 1'b0;
                                        csr_mstatus[12:11] <= 2'b11;
                                        pc                 <= csr_mtvec & 32'hFFFFFFFC;
                                        state              <= S_FETCH_REQ;
                                    end
                                    12'h001: begin // EBREAK
                                        csr_mepc           <= pc;
                                        csr_mcause         <= 32'd3; // Breakpoint
                                        csr_mstatus[7]     <= csr_mstatus[3];
                                        csr_mstatus[3]     <= 1'b0;
                                        csr_mstatus[12:11] <= 2'b11;
                                        pc                 <= csr_mtvec & 32'hFFFFFFFC;
                                        state              <= S_FETCH_REQ;
                                    end
                                    12'h302: begin // MRET
                                        pc                 <= csr_mepc;
                                        csr_mstatus[3]     <= csr_mstatus[7]; // MIE = MPIE
                                        csr_mstatus[7]     <= 1'b1;           // MPIE = 1
                                        csr_mstatus[12:11] <= 2'b11;          // MPP = M
                                        state              <= S_FETCH_REQ;
                                    end
                                    12'h105: begin // WFI
                                        pc    <= pc + 32'd4;
                                        state <= S_WFI;
                                    end
                                    default: begin
                                        pc    <= pc + 32'd4;
                                        state <= S_FETCH_REQ;
                                    end
                                endcase
                            end else begin
                                // CSR instructions
                                csr_old_val = csr_read_val(csr_addr_w);
                                zimm = rs1; // For CSRRWI/CSRRSI/CSRRCI

                                case (funct3)
                                    3'b001: begin // CSRRW
                                        csr_write_val = rs1_val;
                                        if (rd != 5'd0) rf[rd] <= csr_old_val;
                                    end
                                    3'b010: begin // CSRRS
                                        csr_write_val = csr_old_val | rs1_val;
                                        if (rd != 5'd0) rf[rd] <= csr_old_val;
                                    end
                                    3'b011: begin // CSRRC
                                        csr_write_val = csr_old_val & ~rs1_val;
                                        if (rd != 5'd0) rf[rd] <= csr_old_val;
                                    end
                                    3'b101: begin // CSRRWI
                                        csr_write_val = {27'd0, zimm};
                                        if (rd != 5'd0) rf[rd] <= csr_old_val;
                                    end
                                    3'b110: begin // CSRRSI
                                        csr_write_val = csr_old_val | {27'd0, zimm};
                                        if (rd != 5'd0) rf[rd] <= csr_old_val;
                                    end
                                    3'b111: begin // CSRRCI
                                        csr_write_val = csr_old_val & ~{27'd0, zimm};
                                        if (rd != 5'd0) rf[rd] <= csr_old_val;
                                    end
                                    default: begin
                                        csr_write_val = csr_old_val;
                                    end
                                endcase

                                // Write to CSR (skip for CSRRS/CSRRC with rs1==x0)
                                if (funct3[1:0] != 2'b00) begin // Not ECALL/EBREAK/etc
                                    if (!(funct3[1] && rs1 == 5'd0)) begin // Not CSRRS/CSRRC with rs1=x0
                                        case (csr_addr_w)
                                            12'h300: csr_mstatus  <= csr_write_val;
                                            12'h304: csr_mie      <= csr_write_val;
                                            12'h305: csr_mtvec    <= csr_write_val;
                                            12'h340: csr_mscratch <= csr_write_val;
                                            12'h341: csr_mepc     <= csr_write_val;
                                            12'h342: csr_mcause   <= csr_write_val;
                                            // mip, mvendorid, etc. are read-only
                                            default: ;
                                        endcase
                                    end
                                end

                                pc    <= pc + 32'd4;
                                state <= S_FETCH_REQ;
                            end
                        end

                        // ---- Unknown opcode (NOP) ----
                        default: begin
                            pc    <= pc + 32'd4;
                            state <= S_FETCH_REQ;
                        end
                    endcase
                end

                // --------------------------------------------------------
                // S_MEM_REQ: Issue data bus request
                // --------------------------------------------------------
                S_MEM_REQ: begin
                    data_req_r   <= 1'b1;
                    data_addr_r  <= mem_addr_r & 32'hFFFFFFFC; // Word-align
                    data_we_r    <= mem_we_r;
                    data_be_r    <= mem_be_r;
                    data_wdata_r <= mem_wdata_r;
                    state        <= S_MEM_GNT;
                end

                // --------------------------------------------------------
                // S_MEM_GNT: Wait for data grant
                // --------------------------------------------------------
                S_MEM_GNT: begin
                    if (data_gnt_i) begin
                        data_req_r <= 1'b0;
                        state      <= S_MEM_WAIT;
                    end
                end

                // --------------------------------------------------------
                // S_MEM_WAIT: Wait for data response
                // --------------------------------------------------------
                S_MEM_WAIT: begin
                    if (data_rvalid_i) begin
                        if (!mem_we_r) begin
                            // Load: extract and sign/zero extend
                            byte_offset = mem_addr_r[1:0];
                            case (mem_funct3_r)
                                3'b000: begin // LB (signed byte)
                                    case (byte_offset)
                                        2'd0: load_data = {{24{data_rdata_i[7]}},  data_rdata_i[7:0]};
                                        2'd1: load_data = {{24{data_rdata_i[15]}}, data_rdata_i[15:8]};
                                        2'd2: load_data = {{24{data_rdata_i[23]}}, data_rdata_i[23:16]};
                                        2'd3: load_data = {{24{data_rdata_i[31]}}, data_rdata_i[31:24]};
                                    endcase
                                end
                                3'b001: begin // LH (signed halfword)
                                    if (byte_offset[1])
                                        load_data = {{16{data_rdata_i[31]}}, data_rdata_i[31:16]};
                                    else
                                        load_data = {{16{data_rdata_i[15]}}, data_rdata_i[15:0]};
                                end
                                3'b010: begin // LW
                                    load_data = data_rdata_i;
                                end
                                3'b100: begin // LBU (unsigned byte)
                                    case (byte_offset)
                                        2'd0: load_data = {24'd0, data_rdata_i[7:0]};
                                        2'd1: load_data = {24'd0, data_rdata_i[15:8]};
                                        2'd2: load_data = {24'd0, data_rdata_i[23:16]};
                                        2'd3: load_data = {24'd0, data_rdata_i[31:24]};
                                    endcase
                                end
                                3'b101: begin // LHU (unsigned halfword)
                                    if (byte_offset[1])
                                        load_data = {16'd0, data_rdata_i[31:16]};
                                    else
                                        load_data = {16'd0, data_rdata_i[15:0]};
                                end
                                default: load_data = data_rdata_i;
                            endcase
                            if (mem_rd_r != 5'd0) rf[mem_rd_r] <= load_data;
                        end
                        // For stores, nothing to do on response
                        pc    <= pc + 32'd4;
                        state <= S_FETCH_REQ;
                    end
                end

                // --------------------------------------------------------
                // S_WFI: Wait for interrupt
                // --------------------------------------------------------
                S_WFI: begin
                    if (irq_active) begin
                        state <= S_FETCH_REQ;
                    end
                end

                default: state <= S_RESET;
            endcase
        end
    end

    // ================================================================
    // Debug: optional instruction trace
    // ================================================================
    `ifdef TRACE_CPU
    always @(posedge clk_i) begin
        if (state == S_EXECUTE && rst_ni) begin
            $display("[CPU] PC=%08h INSTR=%08h", pc, instr_r);
        end
    end
    `endif

endmodule
