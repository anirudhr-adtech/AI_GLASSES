# Agent Swarm — /plan Prompt Templates

## How to Use This Document

1. Open Claude Code session
2. Type `/plan`
3. Paste the relevant prompt below
4. Review the plan Claude generates
5. Approve → Claude codes the modules
6. After plan is locked, launch parallel agents for independent modules

---

## PROMPT 1: NPU Subsystem (Chip 1)

```
You are generating synthesizable Verilog RTL for the NPU subsystem of an AI Glasses SoC.
Target: Xilinx Zynq Z7-20 FPGA (Phase 0), later ASIC 180nm at SCL Mohali.
Clock: 200 MHz system clock. Active-low synchronous reset (rst_n).
Language: Verilog-2005. No SystemVerilog constructs.

ARCHITECTURE SUMMARY:
- 8×8 INT8 MAC array (64 parallel multiply-accumulate units)
- INT8 × INT8 → INT32 accumulation
- Weight Buffer: 128KB dual-port BRAM (DMA write port, MAC read port)
- Activation Buffer: 128KB dual-port BRAM
- DMA Engine: 128-bit AXI4 master, 2 channels (weight + activation)
- Quantization: INT32 → INT8 (shift, scale, clamp to [-128, +127])
- Activation: ReLU, ReLU6, bypass (configurable)
- Control: AXI4-Lite slave register file, layer FSM
- Supported ops: Conv2D, DW-Conv2D (depthwise separable), FC, MaxPool, AvgPool
- AXI ID prefix: 3'b010 (M2 on crossbar). QoS: 4'hF

REGISTER MAP (Base: 0x3000_0000):
- 0x00 CONTROL    [R/W] bit[0]=enable, bit[1]=soft_reset, bit[2]=irq_en
- 0x04 STATUS     [RO]  bit[0]=busy, bit[1]=layer_done, bit[2]=dma_busy, bit[3]=error
- 0x08 INPUT_ADDR [R/W] DDR base address of input activation tensor
- 0x0C WEIGHT_ADDR[R/W] DDR base address of weight tensor
- 0x10 OUTPUT_ADDR[R/W] DDR base address for output tensor
- 0x14 INPUT_SIZE [R/W] Input DMA transfer size (bytes)
- 0x18 WEIGHT_SIZE[R/W] Weight DMA transfer size (bytes)
- 0x1C OUTPUT_SIZE[R/W] Output DMA write size (bytes)
- 0x20 LAYER_CONFIG[R/W] bits[3:0]=layer_type (0=Conv2D,1=FC,2=MaxPool,3=AvgPool,4=DW-Conv2D)
                         bits[7:4]=act_type (0=None,1=ReLU,2=ReLU6)
                         bits[15:8]=input_channels
- 0x24 QUANT_SHIFT[R/W] Right-shift amount for quantization
- 0x28 QUANT_SCALE[R/W] Scale multiplier for quantization
- 0x2C LAYER_DIM  [R/W] bits[15:0]=input_height, bits[31:16]=input_width
- 0x30 KERNEL_DIM [R/W] bits[7:0]=kernel_h, bits[15:8]=kernel_w, bits[23:16]=stride, bits[31:24]=padding
- 0x34 OUT_CHANNELS[R/W] Number of output channels for current layer
- 0x38 IRQ_STATUS [R/W1C] Interrupt status (write-1-to-clear)

AXI4 DMA INTERFACE:
- Data width: 128 bits (16 bytes/beat)
- Max burst: 256 beats (AWLEN/ARLEN = 255)
- Outstanding: 4 read, 2 write
- Byte strobes: full 16-byte aligned transfers

MODULE HIERARCHY (generate in this order):
1. mac_unit.v         — Single INT8×INT8→INT32 MAC cell
2. npu_mac_array.v    — 8×8 array of mac_unit with accumulator bank
3. npu_quantize.v     — INT32→INT8 scale/shift/clamp
4. npu_activation.v   — ReLU/ReLU6/bypass
5. npu_weight_buf.v   — 128KB BRAM wrapper (dual-port)
6. npu_act_buf.v      — 128KB BRAM wrapper (dual-port)
7. npu_regfile.v      — AXI4-Lite slave + register file
8. npu_dma.v          — 128-bit AXI4 master with 2 channels
9. npu_controller.v   — Layer FSM, sequencing all blocks
10. npu_top.v         — Integration wrapper

PLAN REQUIREMENTS:
For each module, define:
(a) Complete port list with signal names, widths, directions
(b) Internal architecture (FSM states, datapath, pipeline stages)
(c) Inter-module interface contracts (handshake signals, ready/valid protocols)
(d) BRAM inference style (Xilinx-compatible reg arrays with synchronous read)
(e) Timing: which signals are registered, pipeline latency per stage
(f) Reset behavior for every stateful element

CRITICAL CONSTRAINTS:
- All outputs must be registered (no combinational outputs at module boundaries)
- Use (* ram_style = "block" *) for BRAM inference on Xilinx
- AXI must be protocol-compliant (no VALID depending on READY)
- Parameterize where sensible (DATA_WIDTH, ADDR_WIDTH, MAC_ROWS, MAC_COLS)
- Include `timescale 1ns/1ps at top of every file
- Every module gets a basic self-checking testbench stub (tb_<module>.v)

Generate the complete plan. I will review before you write any Verilog code.
```

---

## PROMPT 2: Audio/MFCC Subsystem (Chip 2A)

```
You are generating synthesizable Verilog RTL for the Audio/MFCC subsystem of an AI Glasses SoC.
Target: Xilinx Zynq Z7-20 FPGA (Phase 0), later ASIC 180nm at SCL Mohali.
Clock: 100 MHz system clock. Active-low synchronous reset (rst_n).
Language: Verilog-2005. No SystemVerilog constructs.

ARCHITECTURE SUMMARY:
- I2S Slave Receiver (external codec provides BCLK/LRCLK)
- Audio sample rate: 16 kHz, 16-bit mono
- MFCC Pipeline: Frame Buffer → Windowing (Hamming) → 512-pt FFT → Power Spectrum →
  40-bin Mel Filterbank → Log → DCT (10 coefficients) → Output FIFO
- Output: 49×10×1 INT8 MFCC tensor (49 frames, 10 coefficients)
- Frame: 25ms (400 samples), Stride: 10ms (160 samples), 50% overlap
- FFT: 512-point radix-2 DIT, 16-bit fixed-point, uses DSP48 multipliers
- Mel filterbank: 40 triangular filters, stored as coefficient ROM
- DCT: Type-II, 10 outputs from 40 mel bins
- AXI4-Lite slave for register access
- DMA output: writes completed MFCC tensor to DDR for NPU consumption
- Interrupt: MFCC_DONE when full 49-frame tensor is assembled

MODULE HIERARCHY (generate in this order):
1. i2s_receiver.v       — I2S slave, deserializes audio samples
2. audio_fifo.v         — Async FIFO (I2S clock → system clock CDC)
3. frame_buffer.v       — Collects 400-sample frames with 160-sample stride
4. hamming_window.v     — Applies Hamming window coefficients (ROM-based)
5. fft_butterfly.v      — Radix-2 butterfly unit (single stage)
6. fft_engine.v         — 512-point FFT using butterfly + twiddle ROM
7. power_spectrum.v     — |X[k]|² = Re² + Im² computation
8. mel_filterbank.v     — 40-bin triangular filterbank (coefficient ROM)
9. log_compress.v       — Fixed-point log₂ approximation
10. dct_engine.v        — Type-II DCT, 40→10 coefficients
11. mfcc_output_buf.v   — Collects 49 frames into output tensor, triggers DMA
12. audio_regfile.v     — AXI4-Lite slave + registers
13. audio_controller.v  — Pipeline FSM orchestrating all stages
14. audio_top.v         — Integration wrapper

PLAN REQUIREMENTS:
Same as NPU prompt — complete port lists, FSM states, inter-module handshakes,
pipeline latency, reset behavior, BRAM inference style, parameterization.

Additional for audio:
- Clock domain crossing between I2S clock and system clock (async FIFO with gray counters)
- Fixed-point format specification for each pipeline stage (integer bits, fraction bits)
- Twiddle factor ROM generation approach (precomputed, stored as signed fixed-point)
- DSP48 inference hints for Xilinx

Generate the complete plan. I will review before you write any Verilog code.
```

---

## PROMPT 3: Camera/Vision Subsystem (Chip 3)

```
You are generating synthesizable Verilog RTL for the Camera/Vision subsystem of an AI Glasses SoC.
Target: Xilinx Zynq Z7-20 FPGA (Phase 0), later ASIC 180nm at SCL Mohali.
Clock: 100 MHz system clock. Camera pixel clock: ~24 MHz (from OV7670).
Active-low synchronous reset (rst_n).
Language: Verilog-2005. No SystemVerilog constructs.

ARCHITECTURE SUMMARY:
- DVP parallel camera interface (8-bit data, PCLK, VSYNC, HREF) from OV7670
- Input format: YUV422 (YUYV interleaved), 640×480 @ 30 FPS
- ISP-lite pipeline: YUV422→RGB888 (BT.601) → Bilinear Resize (640×480→128×128)
- Pixel packing: 24-bit RGB → 128-bit AXI words
- Video DMA: 128-bit AXI4 master, writes frames to DDR frame buffer
- Double-buffered frame management (write buffer / read buffer swap)
- Crop Engine: reads ROI from DDR, resizes to 112×112, writes back to DDR
  (for face recognition: BlazeFace bbox → crop → MobileFaceNet input)
- AXI4-Lite slave for register access (24 registers)
- Interrupts: FRAME_DONE, CROP_DONE

DVP CAPTURE FSM STATES:
- IDLE → wait for VSYNC rising edge
- WAIT_HREF → wait for HREF high (active line start)
- CAPTURE_LINE → latch 8-bit data on PCLK rising, pair bytes into 16-bit YUV pixels
- Back to WAIT_HREF after HREF deasserts, increment line counter

MODULE HIERARCHY (generate in this order):
1. gray_counter.v       — Gray-code counter for async FIFO pointers
2. dvp_sync.v           — 2-FF synchronizer for PCLK-domain inputs
3. dvp_capture.v        — DVP interface FSM, captures YUV422 pixel pairs
4. pixel_fifo.v         — Async FIFO (PCLK domain → sys_clk domain)
5. yuv2rgb.v            — BT.601 YUV422→RGB888 color conversion
6. line_buffer.v        — Dual-line BRAM buffer for vertical interpolation
7. resize_engine.v      — Bilinear resize (parameterizable input/output dims)
8. pixel_packer.v       — 24-bit RGB → 128-bit AXI word packing
9. video_dma.v          — 128-bit AXI4 master, frame write to DDR
10. frame_buf_ctrl.v    — Double-buffer pointer management + swap
11. crop_dma_reader.v   — AXI4 read controller (fetches ROI rows from DDR)
12. crop_resize.v       — Bilinear resize for crop path
13. crop_dma_writer.v   — AXI4 write controller (writes cropped face to DDR)
14. crop_engine.v       — Crop pipeline wrapper (reader → resize → writer)
15. cam_regfile.v       — AXI4-Lite slave + 24 registers
16. cam_controller.v    — Pipeline FSM, IRQ generation
17. cam_subsys_top.v    — Integration wrapper

PLAN REQUIREMENTS:
Same as NPU/Audio — complete port lists, FSM states, inter-module handshakes,
clock domain crossing details (PCLK↔sys_clk), pipeline latency, BRAM inference.

Additional for camera:
- CDC strategy: all cam_* inputs synchronized through dvp_sync before use
- Bilinear interpolation: fixed-point coefficient calculation
- Line buffer BRAM sizing for 640-pixel and 128-pixel line widths
- Frame buffer address calculation (base + line×stride + pixel×bytes_per_pixel)

Generate the complete plan. I will review before you write any Verilog code.
```

---

## PROMPT 4: RISC-V + AXI Interconnect + DDR Wrapper

```
You are generating synthesizable Verilog RTL for the RISC-V CPU subsystem,
AXI interconnect, and DDR wrapper of an AI Glasses SoC.
Target: Xilinx Zynq Z7-20 FPGA (Phase 0), later ASIC 180nm at SCL Mohali.
Clock: 100 MHz system clock. Active-low synchronous reset (rst_n).
Language: Verilog-2005. No SystemVerilog constructs.

NOTE: The Ibex RISC-V CPU core RTL itself is taken from the open-source
lowRISC/ibex repository. Do NOT regenerate the CPU core.
Generate only: bus adapters, interconnect, memory wrappers, peripherals, and integration.

ARCHITECTURE SUMMARY:
- CPU: Ibex RV32IMC (external IP, instantiated as black-box)
- Bus Adapters: Ibex native iBus/dBus → AXI4 master adapters
- AXI4 Crossbar: 3 masters × 6 slaves, round-robin arbitration
  Masters: M0=CPU_iBus, M1=CPU_dBus, M2=NPU_DMA, M3=Camera_DMA
  Slaves: S0=Boot_ROM, S1=SRAM, S2=NPU_regs, S3=Audio_regs, S4=Camera_regs, S5=DDR
- Boot ROM: 4KB, initialized via $readmemh
- SRAM: 64KB, dual-port BRAM inference
- DDR Wrapper: AXI4 128-bit (SoC side) → AXI3 64-bit (Zynq HP0)
  Performs: burst splitting (256→16 beats), data width conversion (128→64),
  protocol downgrade (AXI4→AXI3)
- Interrupt Controller: aggregates IRQs from NPU, Audio, Camera → CPU IRQ input
- Address Map:
  0x0000_0000 - 0x0000_0FFF : Boot ROM (4KB)
  0x1000_0000 - 0x1000_FFFF : SRAM (64KB)
  0x2000_0000 - 0x2000_00FF : Peripheral registers (UART, GPIO, SPI, I2C)
  0x3000_0000 - 0x3000_00FF : NPU registers
  0x4000_0000 - 0x4000_00FF : Audio registers
  0x5000_0000 - 0x5000_00FF : Camera registers
  0x8000_0000 - 0x9FFF_FFFF : DDR (512MB via Zynq HP0)

MODULE HIERARCHY (generate in this order):
1. ibex_ibus_axi_adapter.v  — iBus native → AXI4 read master
2. ibex_dbus_axi_adapter.v  — dBus native → AXI4 read/write master
3. axi_addr_decoder.v       — Address decode logic for crossbar
4. axi_arbiter.v            — Round-robin arbiter for multi-master
5. axi_crossbar.v           — 4×6 AXI4 crossbar (instantiates decoder + arbiter)
6. boot_rom.v               — 4KB ROM with $readmemh initialization
7. sram_wrapper.v           — 64KB SRAM (BRAM inference)
8. ddr_burst_splitter.v     — AXI4 burst (≤256) → AXI3 sub-bursts (≤16)
9. ddr_width_converter.v    — 128-bit → 64-bit data width conversion
10. ddr_wrapper.v           — Top-level DDR bridge (burst split + width convert + AXI4→AXI3)
11. irq_controller.v        — IRQ aggregator (NPU, Audio, Camera → CPU)
12. soc_top.v               — Full SoC integration (CPU + crossbar + all subsystems)

PLAN REQUIREMENTS:
Same as other subsystems — complete port lists, FSM states, inter-module contracts.

Additional for interconnect:
- AXI crossbar arbitration policy: round-robin per slave port, no starvation
- Address decode: combinational, one-hot slave select
- DDR burst splitting FSM: tracks remaining beats, generates sub-bursts
- DDR width conversion: serializes 128-bit words into 2× 64-bit beats (and reverse for reads)
- Ibex bus adapter: handle Ibex grant/rvalid handshake → AXI VALID/READY

CRITICAL: The Ibex CPU is instantiated as-is from GitHub. Define its port interface
exactly as documented in the Ibex integration guide. Do not modify Ibex internals.

Generate the complete plan. I will review before you write any Verilog code.
```

---

## After /plan → Agent Swarm Execution

Once you approve a plan, launch parallel agents like this:

### Agent Assignment Example (NPU):

| Agent Session | Modules Assigned | Dependencies |
|---|---|---|
| Agent 1 | `mac_unit.v`, `npu_mac_array.v` | None — leaf modules |
| Agent 2 | `npu_quantize.v`, `npu_activation.v` | None — leaf modules |
| Agent 3 | `npu_weight_buf.v`, `npu_act_buf.v` | None — leaf modules |
| Agent 4 | `npu_regfile.v` | None — leaf module |
| Agent 5 | `npu_dma.v` | None — leaf module |
| **After agents 1-5 complete:** | | |
| Agent 6 | `npu_controller.v` | Needs all sub-block interfaces |
| Agent 7 | `npu_top.v` + integration TB | Needs all modules |

### Per-Agent Prompt Template:

```
You are coding Verilog RTL for the AI Glasses SoC NPU subsystem.
Follow the approved plan exactly. Do not deviate from the interface definitions.

Your assigned module(s): [MODULE_NAME]

[PASTE THE RELEVANT SECTION FROM THE APPROVED PLAN HERE]

Rules:
- Verilog-2005 only. No SystemVerilog.
- `timescale 1ns/1ps
- All outputs registered
- Active-low synchronous reset (rst_n)
- Use (* ram_style = "block" *) for BRAMs
- Include basic testbench: tb_[MODULE_NAME].v
- Lint clean: no width mismatches, no unused signals
- Comment every FSM state and every register

Generate the complete Verilog files now.
```
