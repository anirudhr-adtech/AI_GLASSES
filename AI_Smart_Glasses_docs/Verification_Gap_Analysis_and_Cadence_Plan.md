# AI Glasses SoC — Verification Gap Analysis & Cadence Migration Plan

**Date:** 2026-03-09
**Status:** L1 120/120, L2 9/9, L3 11/11 passing (Verilator 5.024 --timing)
**Target:** Cadence Xcelium + Real Ibex + Real Firmware + Real-Time Use Cases

---

## 1. Current Verification Summary

| Level | Tests | Tool | What It Covers |
|-------|-------|------|----------------|
| **L1** | 120/120 | Verilator | Unit-level: logic, FSMs, protocol handshakes per module |
| **L2** | 9/9 | Verilator | Subsystem integration: single-master DMA, register access, BFM-driven |
| **L3** | 11/11 | Verilator | Cross-subsystem: CPU boot chain, all 9 peripherals, IRQ, GPIO, multi-periph |

### L3 Test List

| Test | Subsystems Verified |
|------|---------------------|
| L3-001 Boot+UART | CPU, Boot ROM, SRAM, UART, AXI-Lite fabric |
| L3-002 SRAM R/W | CPU, SRAM (4 banks), word/byte/halfword access |
| L3-003 Periph Walk | CPU, all 9 AXI-Lite peripheral slots |
| L3-004 UART Echo | CPU, UART TX FIFO, STATUS register |
| L3-005 Timer IRQ | CPU, Timer CLINT, CSR trap handler, MRET |
| L3-006 GPIO I/O | CPU, GPIO direction/output/input loopback |
| L3-008 SPI Regs | CPU, SPI config/status/CS registers |
| L3-009 I2C Regs | CPU, I2C prescaler/control/slave_addr registers |
| L3-010 NPU Regs | CPU, NPU addr/size/config/layer registers |
| L3-011 Timer+GPIO | Timer IRQ triggers GPIO toggle (cross-subsystem) |
| L3-012 Multi-Periph | Rapid fabric switching: GPIO+SPI+Timer interleaved |

---

## 2. CPU Model Limitations (Critical)

The current `ibex_core.v` is a **behavioral RV32IM model** — NOT the real Ibex. It replaced a non-functional stub (all outputs hardwired to zero).

### What the Behavioral Model Does

- Full RV32I base integer + M extension (MUL/MULH/DIV/REM)
- Machine-mode CSRs: mstatus, mie, mtvec, mepc, mcause, mip, mcycle, minstret
- Interrupt handling: prioritized (MEI > MSI > MTI), WFI support
- OBI bus interface: instruction + data buses with grant/valid handshake
- Sequential FSM: RESET -> FETCH_REQ -> FETCH_GNT -> FETCH_WAIT -> EXECUTE -> MEM_REQ/GNT/WAIT

### What It Does NOT Do

| Feature | Real Ibex | Behavioral Model | Impact |
|---------|-----------|------------------|--------|
| Pipeline | 2-stage (F/D + E/WB) | Sequential FSM (4-7 cycles/instr) | Software timing assumptions invalid; loops ~4x slower |
| Branch prediction | Simple static predictor | No speculation; all branches sequential | Compiler cannot validate branch timing |
| Instruction prefetch | Prefetch buffer (2-4 entries) | Every fetch = full AXI transaction | Memory bandwidth over-estimated per instruction |
| Load-use forwarding | Pipeline forwarding | No forwarding; load always stalls | Data hazard timing incorrect |
| Compressed ISA (C ext) | RV32IMC (16-bit instrs) | RV32IM only (32-bit only) | Code density different; fetch patterns differ |
| Debug module | JTAG debug support | None | Cannot test debug attach/halt/step |
| PMP (Physical Memory Protection) | Configurable PMP entries | None | Memory protection not validated |
| Performance counters | Hardware cycle/instret counters | Software-incremented counters | mcycle/minstret timing inaccurate |

### Adapter Simplifications Made for Behavioral CPU

1. **ibex_core_wrapper.v** — Changed from registered outputs to pass-through
   - Real Ibex needs registered outputs for timing closure
   - Pass-through was needed because registered outputs caused OBI protocol mismatch with sequential CPU

2. **ibus_axi_adapter.v** — Removed pending request queue
   - Real Ibex issues pipelined fetches; adapter needs queue to handle overlapping requests
   - Sequential CPU only issues one fetch at a time, so queue captured spurious requests

3. **dbus_axi_adapter.v** — Not modified (already simple, single-beat only)

### What Must Change for Real Ibex

- Replace `ibex_core.v` with actual lowrisc/ibex SystemVerilog source
- Restore registered pipeline stage in `ibex_core_wrapper.v`
- Restore pending request queue in `ibus_axi_adapter.v`
- Requires SystemVerilog support (Xcelium, not Verilator)

---

## 3. Verilator Tool Limitations

### Current Verilator Flags
```makefile
VFLAGS := --cc --exe --build -j 4 --trace --timing
VFLAGS += -Wno-lint
```

### Limitations vs Event-Driven Simulators

| Limitation | Impact on Verification | Cadence Xcelium Fix |
|-----------|----------------------|---------------------|
| **2-state logic (0/1 only)** | Cannot detect X-propagation from uninitialized registers; undriven signals silently read as 0 | 4-state (0/1/X/Z); catches uninitialized regs immediately |
| **No CDC analysis** | Camera CDC bug (#14 in L2 Bug Report) found by code review, not simulation | Conformal CDC: formal proof of all clock domain crossings |
| **No SystemVerilog constructs** | Cannot compile real Ibex (packages, interfaces, enums, typedefs) | Native SV compilation |
| **No SVA/PSL assertions** | Cannot write `assert property` for protocol compliance | Full assertion support with coverage |
| **Cycle-based (no sub-cycle events)** | Cannot detect glitches, setup/hold violations, combinational hazards | Event-driven, picosecond resolution |
| **No gate-level simulation** | Cannot verify post-synthesis netlist timing | SDF back-annotated gate-level sim |
| **No UVM/OVM** | Cannot use constrained-random verification methodology | Full UVM 1.2 support |
| **No coverage metrics** | No way to know what % of RTL is exercised by tests | Line/toggle/FSM/branch/condition coverage |
| **No power analysis** | Cannot estimate dynamic/static power | Integration with Joules/Voltus |
| **No formal verification hooks** | Cannot prove properties, only simulate them | Integration with JasperGold/Conformal |
| **Behavioral memory only** | `$readmemh` for SRAM/ROM; no SRAM compiler timing models | Real SRAM macros with timing |

### Bugs That Verilator Cannot Catch

1. **Uninitialized register X-prop**: A register that is never reset will be 0 in Verilator but X in Xcelium. If downstream logic depends on it, Xcelium shows X-propagation through the design.

2. **CDC metastability**: Signal crossing from cam_pclk to sys_clk domain without synchronizer. Verilator treats both as ideal clocks; Xcelium with CDC assertions would flag the crossing.

3. **Combinational glitches**: AXI address decoder has a combinational mux. If address lines change asynchronously, output may glitch for a sub-cycle pulse. Verilator skips to stable value; Xcelium captures the transient.

4. **Tri-state resolution**: I2C SDA/SCL are open-drain with pull-ups. Verilator converts tri-state to combinational; Xcelium models the actual bus contention and pull-up settling.

---

## 4. Multi-Master Bus Contention (Never Tested)

The SoC has **5 AXI masters** competing for DDR through `axi_crossbar` (5M x 5S):

| Master | ID | Bus Width | Traffic Pattern | Est. Bandwidth |
|--------|-----|-----------|----------------|----------------|
| RISC-V CPU (M0) | 3-bit | 128-bit AXI4 | Instruction fetch + data load/store | ~5 MB/s |
| SPI DMA (M1) | 3-bit | 32-bit AXI4 | ESP32 data transfer | ~0.5 MB/s |
| NPU DMA (M2) | 3-bit | 128-bit AXI4 | Weight/activation burst R/W | ~10 MB/s |
| Camera VDMA (M3) | 3-bit | 128-bit AXI4 | Frame line burst writes | ~2.3 MB/s |
| Audio DMA (M4) | 3-bit | 32-bit AXI4 | MFCC block writes | ~1 MB/s |

### What Has Never Been Tested

- All 5 masters issuing transactions simultaneously
- Arbiter fairness under sustained contention (round-robin vs priority)
- QoS field effectiveness (DDR wrapper accepts QoS but behavior unvalidated)
- Deadlock scenarios (master A holds read channel waiting for write; master B holds write waiting for read)
- Out-of-order completion with different AXI IDs across masters
- Bandwidth saturation (total ~19 MB/s vs Zynq HP0 limit ~400 MB/s — headroom exists but latency under contention unknown)
- Starvation (low-priority master never gets access)

### DDR Memory Model Limitations

Current L3 TB uses a behavioral 512KB model:
```verilog
reg [63:0] ddr_mem [0:65535]; // 64K x 64-bit
// Simple FSM: IDLE -> DATA -> RESP, no burst pipelining
```

| Feature | Real DDR3 (Zynq) | Behavioral Model |
|---------|-------------------|------------------|
| Access pattern | Row-based (open/close); row-buffer hits/misses | Any address, any time |
| Refresh | Auto-refresh every 64ms; stalls access | No refresh modeled |
| Burst length | BL4/BL8 with address interleaving | Linear address increment |
| Timing constraints | tRAS, tRCD, tRP, tRRD | Fixed 1-cycle latency |
| Write masking | Per-byte granular write enable | Full word writes only |
| Bandwidth limit | ~400 MB/s on HP0 | Unlimited (instant response) |

---

## 5. Error Handling (Never Tested)

| Error Scenario | Current Behavior | Required Behavior |
|----------------|-----------------|-------------------|
| CPU accesses unmapped address (e.g., 0x90000000) | DDR model returns 0 | Should return DECERR; CPU raises exception |
| DMA burst to misaligned address | Silently wraps | Should raise bus error or handle gracefully |
| FIFO overflow (audio at high sample rate) | Data dropped silently | Firmware should detect via status register |
| I2C NACK from slave device | Not tested | Firmware retry logic required |
| SPI timeout (ESP32 not responding) | Not tested | Watchdog timeout needed |
| NPU computation overflow (INT8 saturation) | Tested in L1 unit | Not tested with real tensor data in system context |
| AXI slave error response (SLVERR) | Never injected | CPU/DMA error handlers untested |
| Stack overflow into code/data region | No detection | MPU/guard page needed (requires PMP in Ibex) |

---

## 6. Timing-Sensitive Protocol Gaps

| Protocol | Current Model | Real Requirement | Gap |
|----------|--------------|-----------------|-----|
| I2S | Fixed samples, no jitter | 16kHz +/-0.1%, bit-clock phase matters | Jitter tolerance untested |
| UART | FIFO snoop (bypasses serial line) | 115200 baud, 8N1, real bit timing | Baud rate mismatch would fail on FPGA |
| I2C | Behavioral slave, instant response | Clock stretching, arbitration, repeated START | Multi-master I2C and stretching untested |
| SPI | Behavioral slave, mode 0 only | CPOL/CPHA modes 0-3, CS timing, clock phase | Only mode 0 tested |
| DVP Camera | Fixed frame, ideal pixel timing | PCLK jitter, HREF/VSYNC timing margins | Camera timing margins untested |
| AXI Burst | Single outstanding, always OKAY | Pipelined outstanding, error responses | Pipeline and error paths untested |

---

## 7. Interrupt & Exception Gaps

### What IS Tested
- Timer interrupt fires and CPU enters trap handler (L3-005)
- Timer interrupt triggers GPIO toggle and re-arms (L3-011)
- mie/mstatus CSR enable/disable (L3-005)

### What is NOT Tested

| Scenario | Risk |
|----------|------|
| Simultaneous IRQs (timer + external + software) | Priority resolution untested |
| Interrupt nesting (IRQ during ISR) | Stack overflow risk in nested handlers |
| IRQ pending bit persistence across mask changes | Race condition between enable and pending |
| IRQ asserts exactly as global MIE is cleared | 1-cycle window race |
| ECALL/EBREAK exception in interrupt context | Exception during ISR handling untested |
| MRET from wrong privilege level | CSR state corruption possible |
| Multiple external IRQ sources competing | IRQ controller priority logic untested with real CPU |
| IRQ latency under DMA contention | CPU fetch stalled by DMA; IRQ response delayed |

---

## 8. Real-Time Use Case Simulations Required

### UC-1: Wake Word Detection Pipeline
```
Microphone -> I2S RX -> Audio FIFO -> FFT -> Mel -> Log -> DCT -> MFCC
  -> Audio DMA -> DDR -> NPU DMA read -> 8x8 MAC array -> NPU DMA write -> DDR
  -> CPU reads result -> triggers ESP32 via SPI
```
**Verify:** 10ms MFCC frame budget, sustained 16kHz sample rate, NPU inference within frame, DDR bandwidth sharing (Audio DMA + NPU DMA concurrent)

### UC-2: Camera Capture + Object Detection
```
OV7670 -> DVP capture -> ISP (debayer/WB/gamma) -> Resize -> Crop
  -> Camera VDMA -> DDR -> NPU DMA read -> Conv layers -> NPU DMA write -> DDR
  -> CPU reads classification -> SPI command to ESP32
```
**Verify:** QVGA 30fps (33ms budget), ISP line latency, VDMA vs NPU DMA arbitration, SPI command within inter-frame gap

### UC-3: Concurrent Audio + Camera + NPU
```
Audio MFCC running continuously (background wake-word)
Camera capturing frames (triggered or periodic)
NPU time-multiplexed: audio inference <-> camera inference
CPU orchestrates via IRQs and DMA descriptor chains
```
**Verify:** No DMA starvation (5 masters), IRQ priority (audio > camera > NPU done), CPU context switch overhead, total DDR bandwidth < 400 MB/s limit

### UC-4: I2C IMU + Head Gesture Detection
```
MPU6050 -> I2C read (6B accel + 6B gyro) at 100Hz
  -> CPU processes -> gesture detection -> SPI command to ESP32
```
**Verify:** I2C transfer within 10ms budget, clock stretching handling, CPU polling vs IRQ-driven, SPI response timeout

### UC-5: Boot + WiFi Initialization
```
Power on -> clk_rst_mgr resets -> Boot ROM -> jump to SRAM
  -> CPU init: UART(debug), GPIO(LED), Timer(systick), IRQ(enable all)
  -> SPI to ESP32: config command, wait handshake GPIO
  -> Enter main loop
```
**Verify:** Reset sequence timing (periph->cpu->npu), boot ROM to SRAM with real Ibex, ESP32 SPI+GPIO handshake protocol, total boot < 100ms

### UC-6: Low-Power Standby + Wake
```
CPU WFI -> clock gating -> only timer running
  -> Timer or GPIO wake event -> resume -> re-init peripherals
```
**Verify:** WFI halts pipeline, timer keeps counting, IRQ wakes CPU within spec latency, peripheral state preserved

---

## 9. Cadence Migration Action Plan

### Phase 1: Setup & Baseline (Week 1)

| # | Task | Deliverable |
|---|------|-------------|
| 1 | Install Xcelium, compile full SoC (120 modules) | Clean compilation report |
| 2 | Drop in real Ibex RTL (lowrisc/ibex SystemVerilog) | ibex_core + ibex_pkg compiling |
| 3 | Restore ibex_core_wrapper registered outputs | Wrapper matches real Ibex timing |
| 4 | Restore ibus_axi_adapter pending request queue | Pipelined fetch support |
| 5 | Run L1 regression on Xcelium | 120/120 baseline (may find X-prop bugs) |
| 6 | Enable 4-state X-propagation checks | List of uninitialized register bugs |

### Phase 2: Real Firmware (Week 1-2)

| # | Task | Deliverable |
|---|------|-------------|
| 7 | Boot real Ibex with boot ROM + crt0 (RV32IMC) | Verified boot chain on real CPU |
| 8 | Port all 11 L3 tests to real Ibex | 11/11 passing with real pipeline |
| 9 | Write UC-5 firmware (boot + ESP32 init) | Full boot sequence validated |
| 10 | Write UC-1 firmware (audio MFCC + NPU inference) | First real-time use case |
| 11 | Write UC-2 firmware (camera + NPU classify) | Second real-time use case |

### Phase 3: Advanced Verification (Week 2-3)

| # | Task | Deliverable |
|---|------|-------------|
| 12 | Multi-master contention test (5 AXI masters) | Arbitration fairness report |
| 13 | Formal CDC verification (Conformal CDC) | CDC proof for all clock crossings |
| 14 | SVA protocol assertions (AXI4, AXI-Lite, OBI) | Protocol compliance checks |
| 15 | Code coverage collection (line/toggle/FSM/branch) | Coverage report, identify gaps |
| 16 | Fault injection in AXI slaves (SLVERR/DECERR) | Error handling validation |

### Phase 4: Real-Time Use Case Validation (Week 3-4)

| # | Task | Deliverable |
|---|------|-------------|
| 17 | UC-3 firmware: concurrent audio + camera + NPU | Multi-DMA stress test |
| 18 | UC-4 firmware: I2C IMU + gesture | I2C timing validation |
| 19 | UC-6 firmware: WFI + wake | Low-power scenario |
| 20 | Performance profiling: DDR bandwidth, IRQ latency, DMA throughput | Timing budgets validated |
| 21 | IRQ stress test: simultaneous multi-source interrupts | Priority and nesting validation |

### Phase 5: FPGA Sign-Off (Week 4+)

| # | Task | Deliverable |
|---|------|-------------|
| 22 | Vivado synthesis for Zynq Z7-20 | Timing closure report |
| 23 | Post-synthesis simulation (gate-level + SDF) | Timing-annotated simulation |
| 24 | FPGA bring-up: compare sim results to hardware | Correlation report |
| 25 | Full regression on FPGA (L1+L2+L3+UC) | Hardware validation complete |

---

## 10. Summary: What Cadence Unlocks

| Capability | Verilator (Current) | Cadence Xcelium |
|-----------|---------------------|-----------------|
| Real Ibex CPU (SystemVerilog) | Not possible | Yes |
| Real RV32IMC firmware execution | Behavioral only | Yes |
| 4-state X-propagation | No | Yes |
| Formal CDC proof | No | Yes (Conformal) |
| SVA/PSL assertions | No | Yes |
| UVM constrained-random | No | Yes |
| Code coverage metrics | No | Yes |
| Gate-level simulation with SDF | No | Yes |
| Multi-clock domain (event-driven) | Partial | Full |
| Real-time use case end-to-end | Limited (behavioral CPU) | Full (real Ibex + firmware) |
| Power analysis integration | No | Yes (Joules/Voltus) |
| Formal property verification | No | Yes (JasperGold) |

---

## 11. Risk Assessment

| Risk | Severity | Likelihood | Mitigation |
|------|----------|-----------|------------|
| Real Ibex exposes timing bugs in AXI adapters | High | High | Restore original adapter designs; run L3 regression |
| X-propagation reveals uninitialized registers | Medium | High | Fix all X-prop issues before firmware tests |
| Multi-master DDR contention causes starvation | High | Medium | Add QoS configuration; tune arbiter weights |
| CDC bugs in camera/audio clock crossings | Critical | Medium | Run Conformal CDC before FPGA |
| Real firmware exceeds 512KB SRAM | Medium | Low | Profile firmware size; optimize if needed |
| NPU inference exceeds real-time budget | High | Medium | Profile with real tensors; optimize MAC utilization |
| I2C clock stretching causes bus hang | Medium | Medium | Add timeout and recovery in I2C master |

---

## Appendix A: Files Modified for L3 (Behavioral CPU)

These files were modified from their original state and **MUST be reverted** when switching to real Ibex:

| File | Change | Revert Action |
|------|--------|---------------|
| `rtl/riscv/ibex_core.v` | Replaced stub with behavioral RV32IM | Replace with real Ibex SV source |
| `rtl/riscv/ibex_core_wrapper.v` | Removed registered outputs (pass-through) | Restore registered pipeline stage |
| `rtl/riscv/ibus_axi_adapter.v` | Removed pending request queue | Restore pipelined fetch support |

## Appendix B: L2 Bugs Found (35 Total, All Fixed)

Reference: L2_Bug_Report.md (commit c29079b)

| Subsystem | Bug Count | Key Issues |
|-----------|-----------|------------|
| NPU | 6 | MAC pipeline flush, DMA read arbiter mid-burst switch |
| Audio | 5 | MFCC pipeline deadlock, DMA wlast missing, streaming stall |
| Camera | 5 | Frame stride mismatch, pixel FIFO CDC, resize overflow |
| DDR | 5 | Latency pipe data loss, burst splitter edge case, width convert |
| AXI | 5 | Address decoder 1-cycle latency, crossbar ID routing |
| I2C | 4 | Clock stretching, repeated START, NACK handling |
| SPI | 3 | CS timing, FIFO threshold, clock phase |
| RISC-V | 2 | Boot ROM parameter, AXI-Lite fabric slot 8 |

## Appendix C: Regression Commands

```bash
# L1 Unit Tests (120 tests)
bash sim/common/scripts/run_l1_regression.sh

# L2 Integration Tests (9 tests)
bash sim/common/scripts/run_l2_regression.sh

# L3 Cross-Subsystem Tests (11 tests)
bash sim/common/scripts/run_l3_regression.sh
```
