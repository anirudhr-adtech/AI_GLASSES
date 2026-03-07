# Agent Swarm — Corrected /plan Prompt Templates (v2)

## CRITICAL LESSON LEARNED

Never paraphrase specs from memory into agent prompts. The design documents
ARE the spec. Feed them directly. This v2 approach attaches the actual
design doc and gives the agent clear instructions on what to extract.

## Document Version Authority

| Subsystem | Authoritative Document | Key Specs |
|---|---|---|
| NPU | NPU_Subsystem_Design_Document_v2.docx | 8×8 MAC, 128KB buffers, 128-bit AXI4 DMA, DW-Conv2D support |
| Audio | Audio_Subsystem_RTL_Implementation_v2.docx | **1024-pt FFT**, 640-sample frame, 320-sample stride, 40ms window, 20ms hop |
| Camera | Camera_Vision_Subsystem_RTL_Implementation.docx | DVP 8-bit, YUV422, 640×480→128×128 resize, crop engine |
| RISC-V | RISCV_Subsystem_RTL_Implementation_v2.docx | Ibex RV32IMC, 512KB SRAM, AXI4-Lite peripheral fabric |
| AXI + DDR | AXI_Interconnect_DDR_Subsystem_RTL_Implementation.docx | **5×5 crossbar** (5 masters, 5 slaves), 6-bit AXI ID, tiered arbiter, width converters, DDR wrapper |
| DDR | DDR_Subsystem_RTL_Implementation.docx | Zynq HP0 AXI3 64-bit, burst splitting, width conversion 128→64 |

---

## How to Use These Prompts

### Step 1: /plan session
1. Open Claude Code
2. Type `/plan`
3. Paste the PROMPT below
4. **Attach the actual design document** (.docx file) to the session
5. Review the plan Claude generates → approve or correct

### Step 2: Agent swarm coding
1. Launch parallel Claude Code sessions (up to ~5 concurrent)
2. Each agent gets: (a) the approved plan section for their modules, (b) the coding rules template
3. Agents code independently

---

## PROMPT 1: NPU Subsystem

**Attach:** `NPU_Subsystem_Design_Document_v2.docx`

```
I am attaching the NPU Subsystem Design Document v2 for our AI Glasses SoC.
This document is the SINGLE SOURCE OF TRUTH. Do not invent or assume any
spec — extract everything from this document.

Your task: Create a detailed RTL implementation plan for the complete NPU
subsystem in synthesizable Verilog-2005 (NOT SystemVerilog).

Target: Xilinx Zynq Z7-20 FPGA (Phase 0). Later ASIC at SCL Mohali 180nm.

From the document, extract and plan:

1. MODULE HIERARCHY — Use Section 10.1 exactly. List every module with its
   filename (.v extension, not .sv).

2. GENERATION SEQUENCE — Follow Section 10.2 exactly.

3. FOR EACH MODULE, define:
   (a) Complete port list — extract signal names, widths, directions from
       the document's interface tables and block descriptions
   (b) Internal architecture — FSM states (from document's FSM tables),
       datapath, pipeline stages
   (c) Inter-module interface contracts — handshake protocols (ready/valid),
       timing requirements
   (d) BRAM inference — use (* ram_style = "block" *) for Xilinx
   (e) Register map — use Section 4 exactly for npu_regfile
   (f) AXI interface — use Section 7 exactly (128-bit DMA, AXI4-Lite control)

4. RESOLVED DECISIONS — Incorporate all v2 resolved decisions from Section 11.1:
   - DW-Conv2D support (LAYER_CONFIG type 4)
   - MFCC tensor format: 49×10×1 INT8
   - Pooling unit downstream of MAC array

5. OPEN ITEMS — Flag any unresolved items from Section 11 that affect RTL.

CODING CONSTRAINTS:
- Verilog-2005 only (no logic, no always_comb/always_ff, use reg/wire and always @)
- `timescale 1ns/1ps
- Active-low synchronous reset (rst_n)
- All outputs registered (no combinational outputs at module boundaries)
- Parameterize: DATA_WIDTH, ADDR_WIDTH, MAC_ROWS, MAC_COLS, etc.
- Every module gets a testbench stub (tb_<module>.v)

Generate the complete plan. I will review before any Verilog is written.
```

---

## PROMPT 2: Audio/MFCC Subsystem

**Attach:** `Audio_Subsystem_RTL_Implementation_v2.docx`

```
I am attaching the Audio Subsystem RTL Implementation Document v2 for our
AI Glasses SoC. This document is the SINGLE SOURCE OF TRUTH.

IMPORTANT: Use the v2 resolved parameters:
- FFT: 1024-point (NOT 512)
- Frame size: 640 samples / 40ms (NOT 400/25ms)
- Frame stride: 320 samples / 20ms (NOT 160/10ms)
- Hamming ROM: 640 entries (NOT 400)
- FFT stages: 10 (log2(1024)) with 512 butterflies per stage
- Twiddle ROM: 512 entries (quarter-wave symmetry)
- Zero-padding: 640 samples padded to 1024

Your task: Create a detailed RTL implementation plan for the complete Audio
subsystem in synthesizable Verilog-2005 (NOT SystemVerilog).

Target: Xilinx Zynq Z7-20 FPGA (Phase 0). Clock: 100 MHz. Later ASIC 180nm.

From the document, extract and plan:

1. MODULE HIERARCHY — Use Section 8 exactly. Filenames use .v extension.

2. GENERATION SEQUENCE — Follow Section 8.1 exactly.

3. FOR EACH MODULE, define:
   (a) Complete port list from the document
   (b) FSM states — extract from Section 10.4 (FFT controller), Section 3.2.1
       (audio controller), etc.
   (c) Pipeline stages and latency — use Section 10 for FFT details
   (d) Fixed-point format — Q1.15 for Hamming, twiddle factors; specify
       integer/fraction bits per stage
   (e) DSP48 inference — 4 multipliers for butterfly unit
   (f) BRAM sizing — FFT data memory (1024×32), twiddle ROM (512×32),
       Hamming ROM (640×16), Mel coefficient ROM, DCT coefficient ROM

4. CLOCK DOMAIN — Single clock domain (100 MHz sys_clk). I2S SCK is slower,
   samples synchronized into sys_clk domain. No async FIFO needed (per doc).

5. DMA — 32-bit AXI4 master (NOT 128-bit). Low bandwidth (~320 KB/s).

6. OPEN ITEMS — Flag any unresolved items that affect RTL (hardware vs
   firmware MFCC, shared vs independent DMA, hardware VAD).

CODING CONSTRAINTS:
- Verilog-2005 only
- `timescale 1ns/1ps
- Active-low synchronous reset (rst_n)
- All outputs registered
- (* ram_style = "block" *) for BRAMs
- Every module gets a testbench stub

Generate the complete plan. I will review before any Verilog is written.
```

---

## PROMPT 3: Camera/Vision Subsystem

**Attach:** `Camera_Vision_Subsystem_RTL_Implementation.docx`

```
I am attaching the Camera/Vision Subsystem RTL Implementation Document for
our AI Glasses SoC. This document is the SINGLE SOURCE OF TRUTH.

Your task: Create a detailed RTL implementation plan for the complete Camera
subsystem in synthesizable Verilog-2005 (NOT SystemVerilog).

Target: Xilinx Zynq Z7-20 FPGA (Phase 0). System clock: 100 MHz.
Camera pixel clock: ~24 MHz (OV7670). Later ASIC 180nm.

From the document, extract and plan:

1. MODULE HIERARCHY — Use Section 11 exactly. Filenames use .v extension.

2. GENERATION SEQUENCE — Follow Section 11.1 exactly.

3. FOR EACH MODULE, define:
   (a) Complete port list — extract from Section 6 (DVP signals), Section 7
       (ISP-lite), Section 8 (Video DMA), Section 9 (Crop Engine)
   (b) FSM states — from Section 6.2 (DVP Capture FSM), crop engine FSM
   (c) Clock domain crossing — PCLK (~24 MHz) → sys_clk (100 MHz):
       dvp_sync.sv (2-FF synchronizer), pixel_fifo (async FIFO with
       gray_counter.sv)
   (d) Bilinear interpolation — fixed-point coefficients for resize_engine
   (e) Line buffer BRAM sizing — for 640-pixel input and 128-pixel output
   (f) Frame buffer addressing — base + line×stride + pixel×bytes_per_pixel
   (g) AXI interface — 128-bit AXI4 master DMA

4. REGISTER MAP — Use the document's 24 registers exactly for cam_regfile.

5. INTERRUPTS — FRAME_DONE, CROP_DONE (to IRQ controller).

CODING CONSTRAINTS:
- Verilog-2005 only
- `timescale 1ns/1ps
- Active-low synchronous reset (rst_n)
- All outputs registered
- (* ram_style = "block" *) for BRAMs
- Every module gets a testbench stub

Generate the complete plan. I will review before any Verilog is written.
```

---

## PROMPT 4: AXI Interconnect + DDR Subsystem

**Attach BOTH:** `AXI_Interconnect_DDR_Subsystem_RTL_Implementation.docx`
AND `DDR_Subsystem_RTL_Implementation.docx`

```
I am attaching TWO documents:
1. AXI Interconnect & DDR Memory Subsystem RTL Implementation Document
2. DDR Subsystem RTL Implementation Document

These are the SINGLE SOURCE OF TRUTH. The AXI Interconnect doc SUPERSEDES
the preliminary interconnect description in the RISC-V subsystem doc.

Key specs (verify against documents):
- 5 masters: M0=CPU_iBus(32b), M1=CPU_dBus(32b), M2=NPU_DMA(128b),
  M3=Camera_DMA(128b), M4=Audio_DMA(32b)
- 5 slaves: S0=Boot_ROM(32b), S1=SRAM_512KB(32b), S2=Periph_Bridge(32b),
  S3=DDR(128b), S4=Error_Slave(32b)
- AXI ID: 6-bit (3-bit master prefix + 3-bit transaction ID)
- Arbiter: tiered priority (Tier0=NPU, Tier1=Camera, Tier2=CPU+Audio)
  with round-robin within tiers and anti-starvation
- Width converters: 32↔128 upsizer/downsizer
- DDR wrapper: AXI4_128bit → burst_split → width_convert → AXI3_64bit (Zynq HP0)

Your task: Create a detailed RTL implementation plan in Verilog-2005.

From the documents, extract and plan:

1. MODULE HIERARCHY — Combine both docs. Include:
   - axi_addr_decoder.v (Section 3 of AXI doc)
   - axi_arbiter.v (Section 4 — tiered priority with starvation override)
   - axi_width_converter.v (Section 5 — upsizer + downsizer)
   - axi_crossbar.v (top-level interconnect)
   - axi_to_axilite_bridge.v (Section 6)
   - axilite_interconnect.v (Section 6 — peripheral fabric)
   - ddr_burst_splitter.v (DDR doc Section 5.3.1 — AXI4→AXI3 burst split)
   - ddr_width_converter.v (DDR doc Section 5.3 — 128→64 bit)
   - ddr_wrapper.v (DDR doc — top-level bridge)
   - axi_error_slave.v (S4 — returns DECERR)

2. FOR EACH MODULE: complete port lists, FSM states, arbitration logic,
   address decode logic (from doc's casez example), width conversion FSM.

3. ADDRESS MAP — Use Section 3.1 exactly:
   - S0: 0x0000_0000–0x0000_0FFF (Boot ROM, 4KB)
   - S1: 0x1000_0000–0x1007_FFFF (SRAM, 512KB)
   - S2: 0x2000_0000–0x4FFF_FFFF (Peripherals via AXI-Lite bridge)
   - S3: 0x8000_0000–0xFFFF_FFFF (DDR, 2GB)
   - S4: unmapped ranges (Error slave)

4. DDR WRAPPER — From DDR doc Section 5.3:
   - Burst splitting: AXI4 max 256 beats → AXI3 max 16 beats
   - Width: 128-bit SoC side → 64-bit Zynq HP0
   - Protocol: AXI4 → AXI3 (different burst length encoding)

CODING CONSTRAINTS:
- Verilog-2005 only
- `timescale 1ns/1ps
- Active-low synchronous reset (rst_n)
- All outputs registered
- Parameterize: NUM_MASTERS, NUM_SLAVES, ADDR_MAP, DATA_WIDTH per port
- Every module gets a testbench stub

Generate the complete plan. I will review before any Verilog is written.
```

---

## PROMPT 5: RISC-V CPU Subsystem (Wrappers + Peripherals)

**Attach:** `RISCV_Subsystem_RTL_Implementation_v2.docx`

```
I am attaching the RISC-V Subsystem RTL Implementation Document v2 for our
AI Glasses SoC. This document is the SINGLE SOURCE OF TRUTH.

IMPORTANT: The Ibex CPU core (ibex_core.sv) is EXTERNAL — taken from the
lowRISC/ibex GitHub repository. Do NOT regenerate it.

NOTE: The AXI interconnect is covered in a SEPARATE document and separate
/plan session. This session covers ONLY:
- Ibex core wrapper + bus adapters
- Boot ROM, SRAM
- Peripherals (UART, GPIO, Timer, IRQ controller)
- Reset synchronizer
- RISC-V subsystem top-level integration

Your task: Create a detailed RTL implementation plan in Verilog-2005.

From the document, extract and plan:

1. MODULE HIERARCHY — Use Section 2 exactly. Filenames use .v extension.
   Key modules:
   - ibex_core_wrapper.v (instantiates external Ibex with config params)
   - ibus_axi_adapter.v (Ibex iBus native → AXI4 Read Master)
   - dbus_axi_adapter.v (Ibex dBus native → AXI4 R/W Master)
   - boot_rom.v (4KB, $readmemh initialization)
   - onchip_sram.v (512KB dual-port BRAM wrapper)
   - sram_bank.v (configurable single bank)
   - timer_clint.v (MTIME + MTIMECMP, interrupt on mtime >= mtimecmp)
   - irq_controller.v (aggregates: UART, Camera, Audio, DMA, NPU, Timer)
   - uart_peripheral.v + uart_tx.v + uart_rx.v + uart_fifo.v
   - gpio_peripheral.v
   - rst_sync.v (2-FF reset synchronizer)
   - riscv_subsys_top.v (integration wrapper)

2. GENERATION SEQUENCE — Follow Section 2.1 exactly.

3. FOR EACH MODULE: complete port lists, FSM states (especially bus adapters
   from Section 3/4), register maps for peripherals.

4. IBEX INTERFACE — Use the exact Ibex signal names from the document:
   - iBus: instr_req_o, instr_gnt_i, instr_rvalid_i, instr_addr_o, instr_rdata_i
   - dBus: data_req_o, data_gnt_i, data_rvalid_i, data_we_o, data_be_o,
           data_addr_o, data_wdata_o, data_rdata_i
   - Bus adapter FSM states from Section 3 and 4 of the document

5. SRAM — 512KB (NOT 64KB). Verify against document.

CODING CONSTRAINTS:
- Verilog-2005 only
- `timescale 1ns/1ps
- Active-low synchronous reset (rst_n)
- All outputs registered
- (* ram_style = "block" *) for BRAMs
- Every module gets a testbench stub

Generate the complete plan. I will review before any Verilog is written.
```

---

## Per-Agent Coding Prompt (After Plan is Approved)

Once you review and approve a plan, launch parallel agents with this template:

```
You are coding synthesizable Verilog-2005 RTL for the AI Glasses SoC.
Target: Xilinx Zynq Z7-20 FPGA @ 100 MHz (NPU @ 200 MHz).

Your assigned module(s): [MODULE_NAME(s)]

HERE IS THE APPROVED PLAN FOR YOUR MODULE(s):
[PASTE THE RELEVANT SECTION FROM THE APPROVED PLAN]

RULES — follow exactly:
1. Verilog-2005 ONLY. No SystemVerilog (no logic, no always_comb/always_ff,
   no interface, no struct). Use reg, wire, always @(posedge clk).
2. `timescale 1ns/1ps at top of every file
3. Active-low synchronous reset: always @(posedge clk) if (!rst_n) ...
4. All outputs REGISTERED — no combinational outputs at module boundaries
5. Use (* ram_style = "block" *) attribute for BRAM inference on Xilinx
6. AXI protocol: VALID must never depend on READY
7. Parameterize where the plan specifies
8. Comment every FSM state, every register, every major signal
9. No width mismatches, no unused signals, no latches
10. Include testbench: tb_[MODULE_NAME].v with basic self-checking stimulus

DO NOT deviate from the plan's port list or interface definitions.
Other agents are coding other modules in parallel — interface compatibility
is critical.

Generate the complete Verilog file(s) now.
```

---

## Agent Parallelization Map

### NPU (5 parallel agents → 2 sequential)
| Agent | Modules | Parallel? |
|-------|---------|-----------|
| A1 | mac_unit.v, npu_mac_array.v | Yes — leaf |
| A2 | npu_quantize.v, npu_activation.v | Yes — leaf |
| A3 | npu_weight_buf.v, npu_act_buf.v | Yes — leaf |
| A4 | npu_regfile.v | Yes — leaf |
| A5 | npu_dma.v (+ dma_weight_ch.v, dma_act_ch.v) | Yes — leaf |
| A6 | npu_controller.v | Sequential — after A1-A5 |
| A7 | npu_top.v + integration TB | Sequential — after A6 |

### Audio (5 parallel → 2 sequential)
| Agent | Modules | Parallel? |
|-------|---------|-----------|
| A1 | i2s_rx.v, i2s_sync.v, audio_fifo.v | Yes — leaf |
| A2 | audio_window.v, hamming_rom.v | Yes — leaf |
| A3 | fft_butterfly.v, fft_twiddle_rom.v, fft_addr_gen.v, fft_engine.v | Yes — leaf cluster |
| A4 | power_spectrum.v, mel_filterbank.v, mel_coeff_rom.v | Yes — leaf |
| A5 | log_compress.v, log_lut_rom.v, dct_unit.v, dct_coeff_rom.v | Yes — leaf |
| A6 | mfcc_out_buf.v, audio_dma.v, audio_regfile.v, audio_controller.v | Sequential — after A1-A5 |
| A7 | audio_subsys_top.v + integration TB | Sequential — after A6 |

### Camera (5 parallel → 2 sequential)
| Agent | Modules | Parallel? |
|-------|---------|-----------|
| A1 | gray_counter.v, dvp_sync.v, dvp_capture.v, pixel_fifo.v | Yes — leaf cluster |
| A2 | yuv2rgb.v, line_buffer.v, resize_engine.v, pixel_packer.v | Yes — leaf |
| A3 | video_dma.v, frame_buf_ctrl.v | Yes — leaf |
| A4 | crop_dma_reader.v, crop_resize.v, crop_dma_writer.v, crop_engine.v | Yes — leaf cluster |
| A5 | cam_regfile.v | Yes — leaf |
| A6 | cam_controller.v | Sequential — after A1-A5 |
| A7 | cam_subsys_top.v + integration TB | Sequential — after A6 |

### RISC-V + Interconnect (split across two /plan sessions)

**Session A: RISC-V wrappers + peripherals**
| Agent | Modules | Parallel? |
|-------|---------|-----------|
| A1 | rst_sync.v, uart_fifo.v, uart_tx.v, uart_rx.v | Yes — leaf |
| A2 | uart_peripheral.v, gpio_peripheral.v | Yes — leaf |
| A3 | timer_clint.v, irq_controller.v | Yes — leaf |
| A4 | ibus_axi_adapter.v, dbus_axi_adapter.v | Yes — leaf |
| A5 | ibex_core_wrapper.v, boot_rom.v, onchip_sram.v, sram_bank.v | Yes — leaf |
| A6 | riscv_subsys_top.v | Sequential — after A1-A5 |

**Session B: AXI Interconnect + DDR**
| Agent | Modules | Parallel? |
|-------|---------|-----------|
| A1 | axi_addr_decoder.v, axi_error_slave.v | Yes — leaf |
| A2 | axi_arbiter.v (tiered priority) | Yes — leaf |
| A3 | axi_width_converter.v (upsizer + downsizer) | Yes — leaf |
| A4 | axi_to_axilite_bridge.v, axilite_interconnect.v | Yes — leaf |
| A5 | ddr_burst_splitter.v, ddr_width_converter.v, ddr_wrapper.v | Yes — leaf cluster |
| A6 | axi_crossbar.v | Sequential — after A1-A5 |
| A7 | soc_top.v (full chip integration) | Sequential — after everything |
