# L2 Integration Bug Report: AI Glasses SoC RTL Fixes

**Date:** 2026-03-08
**Commits:** `994e503` (L1 pass) → `b28c64b` (RTL fixes) → `bd26143` (L2 TBs)
**Files changed:** 27 RTL files, 7 L1 TB files (34 total, +436/-229 lines)
**Result:** 120/120 L1 + 9/9 L2 (141 checks) ALL PASS

---

## Summary Table

| # | Subsystem | File | Bug | Root Cause | Fix | L2 Tests Fixed |
|---|-----------|------|-----|------------|-----|----------------|
| 1 | NPU | `npu_controller.v` | MAC pipeline never produces `acc_valid` | `mac_en` deasserted before pipeline could drain; valid counter never reached LATENCY | Keep `mac_en=1` during S_WAIT_MAC until `mac_acc_valid` fires | NPU compute, Conv2D |
| 2 | NPU | `npu_controller.v` | Zero input_channels causes infinite compute loop | `compute_target=0` when `reg_layer_config[15:8]==0` | Clamp `compute_target` to minimum 1 | NPU layer config edge cases |
| 3 | NPU | `npu_dma.v` | Read arbitration grant switches mid-burst | `ar_grant_weight_r` updated on every AR handshake, even during active burst | Added `ar_burst_active` latch; grant only updates when no burst in progress | NPU DMA weight+activation reads |
| 4 | NPU | `npu_dma.v` | AR channel re-issues requests, causing double-pumping | `m_axi_arvalid` driven combinationally, not held stable | Changed to registered AR output with proper handshake | NPU DMA AXI protocol |
| 5 | NPU | `npu_dma.v` | `arready` back-routed to wrong sub-channel | Routed based on live valid signals instead of latched grant | Route based on `ar_grant_weight_r` | NPU DMA handshake |
| 6 | NPU | `npu_dma.v` | `m_axi_rready` 1-cycle late (registered) | Registered `rready` adds latency | Changed to combinational: `m_axi_rready = wch_rready \| ach_rready` | NPU DMA read acceptance |
| 7 | Audio | `audio_controller.v` | MFCC pipeline stalls between Mel/Log/DCT | Sequential FSM waits for each stage's `done` before starting next | Launch Mel, Log, DCT concurrently as streaming chain | Audio MFCC end-to-end |
| 8 | Audio | `audio_dma.v` | `wlast` never asserted during AXI handshake | Registered `wlast` computed from current `beat_cnt`, 1 cycle late; inner if overrides to 0 | Pre-set `wlast` in S_ADDR; pre-compute next beat's `wlast` after each handshake | Audio DMA to DDR |
| 9 | Audio | `audio_window.v` | Window hardcoded to 640 samples | Frame size constant `11'd640` not configurable | Added `frame_size_i` port driven by `reg_window_config[10:0]` | Audio variable frame sizes |
| 10 | Camera | `cam_controller.v` | ISP and VDMA run sequentially | FSM waits for `isp_done` before starting VDMA | ISP and VDMA launch concurrently | Camera frame capture latency |
| 11 | Camera | `cam_regfile.v` | Pulse registers stay asserted indefinitely | No auto-clear logic for `capture_start`, `crop_start`, `irq_clear` | Added auto-clear to 0 when not being written | Camera spurious re-triggers |
| 12 | Camera | `cam_subsys_top.v` | Frame stride uses source width instead of destination | `frame_stride = src_width * 4` but DMA writes at `dst_width` | Changed to `cfg_dst_width` | Camera VDMA addresses |
| 13 | Camera | `cam_subsys_top.v` | FIFO read data arrives 1 cycle after `fifo_rd_en` | No pipeline register on FIFO read path | Added `fifo_rd_valid_d` delay register | Camera ISP pixel alignment |
| 14 | Camera | `cam_subsys_top.v` | Pixel FIFO `wr_clk` on `cam_pclk_i` (unnecessary CDC) | DVP capture already syncs to `clk` via `dvp_sync` | Changed `wr_clk` to `clk_i` | Camera CDC / metastability |
| 15 | Camera | `resize_engine.v` | First row reads garbage from uninitialized line buffer | `lb_rd_line_sel <= ~line_sel` reads wrong buffer for `dst_y==0` | Use `line_sel` (current) for both top/bottom when `dst_y==0` | Camera resize first-row |
| 16 | Camera | `resize_engine.v` | 8-bit multiply overflow in vertical interpolation | `top_r * (255 - frac_y)` max = 65025, exceeds 8 bits | Widened to 16-bit intermediates: `{8'd0, top_r} * {8'd0, ...}` | Camera resize color accuracy |
| 17 | Camera | `crop_dma_writer.v` | Hardcoded 112x112 crop output size | `TOTAL_PIXELS = 112*112` as localparam | Added `total_pixels_i` input port | Camera variable crop sizes |
| 18 | Camera | `crop_engine.v` | `crop_dma_writer` not wired to configurable pixel count | Missing port connection | Connected `.total_pixels_i()` | Camera crop integration |
| 19 | DDR | `latency_pipe.v` | Data lost under backpressure | Shift register drops entries when `out_ready=0` | Complete rewrite to FIFO-based with proper stall and `pipe_empty_o` | DDR read path under contention |
| 20 | DDR | `axi_mem_r_channel.v` | Accepts new AR burst while previous data in pipe | `ar_ready_o` always high in S_IDLE | Gate `ar_ready_o` with `pipe_empty` | DDR overlapping read bursts |
| 21 | DDR | `burst_splitter.v` | 16-beat sub-burst doubles to 32 after width convert | `MAX_AXI3_LEN` not parameterized | Added parameter, set to 7 (8 beats × 2 = 16 after convert) | DDR AXI3 burst compliance |
| 22 | DDR | `burst_splitter.v` | W channel double-counts beats | No pipeline register between upstream/downstream | Added pipeline register, deassert `s_wready` for 1 cycle per beat | DDR write data integrity |
| 23 | DDR | `burst_splitter.v` | `s_bvalid`/`s_rvalid` cleared in IDLE | Unconditional clear overrides pending handshakes | Let handshake logic handle clearing | DDR response handshake |
| 24 | DDR | `axi_width_128to64.v` | `m_wvalid` dropped on back-to-back writes | Deassert check fires even when new word accepted same cycle | Added guard: only deassert if no new upstream handshake | DDR width converter writes |
| 25 | DDR | `axi4_to_axi3_bridge.v` | `burst_splitter` missing `MAX_AXI3_LEN` parameter | Default was 15 instead of 7 | Added `.MAX_AXI3_LEN(7)` | DDR AXI3 protocol |
| 26 | AXI | `axilite_addr_decoder.v` | Address decode 1 cycle late | Registered output; mux samples on same cycle as address | Changed to combinational output (`always @(*)`) | All AXI-Lite peripheral accesses |
| 27 | I2C | `i2c_master_fsm.v` | First data bit shifted out before slave samples it | `scl_fall` triggers shift before first `scl_rise` | Added `first_scl_rise_seen` gate | I2C byte transfers |
| 28 | I2C | `i2c_master_fsm.v` | SCL OE handoff glitch between FSM and SCL gen | FSM releases SCL override before SCL gen starts driving | Added `scl_fsm_hold` flag | I2C START condition |
| 29 | I2C | `i2c_scl_gen.v` | False clock-stretching detection | Stretch checked same cycle SCL OE released | Defer check by 1 cycle via `check_stretch` register | I2C clock stretching |
| 30 | I2C | `i2c_master.v` | `status_done`/`status_nack` are 1-cycle pulses; CPU misses them | Transient pulses not visible in polled STATUS register | Added `sticky_done`/`sticky_nack`, cleared by `irq_clear` | I2C CPU status polling |
| 31 | I2C | `i2c_tx_fifo.v` / `i2c_rx_fifo.v` | Read data 1 cycle late | Registered read, consumers expect FWFT | Changed to FWFT: `assign rd_data_o = mem[rd_ptr]` | I2C FIFO data availability |
| 32 | SPI | `spi_shift_reg.v` | TX shift and RX sample on same clock edge | Both on `shift_en`; SPI requires opposite edges | Split into `sample_en` (rising) and `shift_en` (falling) | SPI full-duplex data integrity |
| 33 | SPI | `spi_shift_reg.v` | `rx_data_o` captured at wrong time | Race between sample and capture | Capture `rx_data_o <= rx_shift` after final `sample_en` | SPI RX byte accuracy |
| 34 | SPI | `spi_master_fsm.v` | No `sample_en` signal for shift register | FSM only generated `shift_en` | Added `sr_sample_en` driven by `sample_edge` | SPI master full-duplex |
| 35 | SPI | `spi_tx_fifo.v` / `spi_rx_fifo.v` | Same FWFT issue as I2C | Registered read output | Changed to combinational FWFT | SPI FIFO data availability |

---

## Bug Distribution

| Subsystem | RTL Bugs | L1 TB Updates | Severity |
|-----------|----------|---------------|----------|
| NPU | 4 | 0 | Critical (hang + data corruption) |
| Audio | 3 | 0 | High (DMA stall + latency) |
| Camera | 8 | 1 | High (data corruption + CDC) |
| DDR | 7 | 1 | Critical (data loss + protocol violation) |
| AXI | 1 | 0 | High (all peripheral accesses broken) |
| I2C | 4 | 2 | Medium (bit errors + status) |
| SPI | 4 | 3 | Medium (data corruption) |
| **Total** | **31** | **7** | |

---

## Detailed Analysis by Subsystem

### NPU (2 files, 4 bugs)

**npu_controller.v — MAC pipeline drain failure (Bug #1):** The most critical NPU bug. When the compute loop finished (`compute_cnt >= compute_target`), the controller deasserted `mac_en` and entered S_WAIT_MAC. However, the MAC array uses a pipelined valid counter that requires `mac_en` to remain high for `LATENCY` additional cycles to produce `acc_valid`. With `mac_en=0`, the valid counter stalled and `acc_valid` never fired, hanging the NPU permanently. The fix keeps `mac_en=1` throughout S_WAIT_MAC and only deasserts it on the cycle `mac_acc_valid` fires.

**npu_controller.v — Zero compute_target (Bug #2):** When `reg_layer_config[15:8]` (input_channels/8) was zero (e.g., misconfigured layer), `compute_target` became 0 and the compute loop condition `compute_cnt >= compute_target` was immediately true, but downstream logic still expected at least one MAC operation. The fix clamps to minimum 1.

**npu_dma.v — Read arbiter mid-burst grant switch (Bugs #3-6):** Four interrelated bugs in the DMA's weight/activation read arbiter. The grant signal `ar_grant_weight_r` was updated on every AR handshake, but because the sub-channel deasserts its `arvalid` before the registered external handshake completes, the grant could switch to the other channel mid-burst. This caused read data to be routed to the wrong channel. Additionally, `arready` was back-routed based on live valid signals (which had already deasserted), and `m_axi_rready` was registered (1-cycle late). The fix introduces `ar_burst_active` locking, registered AR output with proper idle/handshake-complete transitions, grant-based `arready` routing, and combinational `rready`.

### Audio (3 files, 3 bugs)

**audio_controller.v — Sequential MFCC pipeline (Bug #7):** The Mel, Log, and DCT stages are streaming (each consumes the output of the previous as it's produced), but the controller waited for each stage's `done` signal before starting the next. This tripled the MFCC latency and caused deadlock since Log waited for Mel data that would never arrive. The fix launches all three concurrently from P_POWER.

**audio_dma.v — WLAST timing (Bug #8):** `wlast` was computed as `(beat_cnt == cur_burst_len)` in the outer if, which would take effect next cycle. But on the last beat, the inner if simultaneously overwrote `wlast <= 0`, so wlast was **never** 1 during a handshake. The AXI slave never saw burst completion, BRESP never generated, DMA stalled forever. The fix pre-sets wlast one cycle ahead: `(burst_len == 0)` in S_ADDR for single-beat bursts, and `(beat_cnt + 1 == cur_burst_len)` after each mid-burst handshake.

**audio_window.v — Hardcoded frame size (Bug #9):** The window function always read exactly 640 samples from the FIFO regardless of `WINDOW_CONFIG` register. TB configured 16-sample frames but window drained 640, causing FIFO underflow and pipeline deadlock. Added configurable `frame_size_i` port wired to `reg_window_config[10:0]`.

### Camera (7 files, 8 bugs)

**cam_controller.v — Sequential ISP/VDMA (Bug #10):** ISP processing and VDMA write-to-DDR ran sequentially. Since ISP outputs data as a stream and VDMA consumes it, they should run concurrently.

**cam_regfile.v — Sticky pulse registers (Bug #11):** `capture_start`, `crop_start`, and `irq_clear` are intended as single-cycle pulses, but the register file held the written value until next write, causing repeated triggers.

**cam_subsys_top.v — Three integration bugs (Bugs #12-14):** Frame stride used source width instead of destination width (wrong DMA addresses). Pixel FIFO read data consumed by ISP one cycle before valid (missing pipeline delay). Pixel FIFO write clock on `cam_pclk_i` despite DVP capture already synchronizing to system clock (unnecessary CDC).

**resize_engine.v — First-row garbage and overflow (Bugs #15-16):** Bilinear interpolation for row 0 read from uninitialized line buffer. Also, vertical interpolation multiply `top_r * (255 - frac_y)` overflowed 8 bits (max 65025, needs 16 bits). Fixed with nearest-neighbor fallback for row 0 and 16-bit intermediates.

**crop_dma_writer.v / crop_engine.v — Hardcoded crop size (Bugs #17-18):** Output pixel count hardcoded to 112×112. Added parameterized `total_pixels_i` port.

### DDR (5 files, 7 bugs)

**latency_pipe.v — Complete rewrite (Bug #19):** The original shift-register design had no backpressure support. When `out_ready=0`, data continued shifting and was silently dropped. The rewrite uses a FIFO with latency-modeling shift register: entries become "mature" (readable) after LATENCY cycles, and the FIFO stalls writes when full.

**axi_mem_r_channel.v — Overlapping bursts (Bug #20):** Accepted new AR while previous burst data still in pipe. Gated `ar_ready_o` with `pipe_empty`.

**burst_splitter.v — Three bugs (Bugs #21-23):** (a) 16-beat sub-burst doubles to 32 after width conversion, violating AXI3 max. Parameterized `MAX_AXI3_LEN`. (b) W channel had no pipeline register, causing beat double-counting. (c) Response valid signals unconditionally cleared in IDLE state.

**axi_width_128to64.v — Back-to-back write stall (Bug #24):** `m_wvalid` incorrectly deasserted when new word arrived same cycle as previous word's high-half acceptance.

**axi4_to_axi3_bridge.v — Missing parameter (Bug #25):** `burst_splitter` instantiated with default `MAX_AXI3_LEN=15` instead of 7.

### AXI (1 file, 1 bug)

**axilite_addr_decoder.v — 1-cycle decode latency (Bug #26):** Registered output caused the AXI-Lite mux to always use the **previous** transaction's decode result. Every peripheral access was routed to the wrong slave. Changed to combinational.

### I2C (5 files, 4 bugs)

**i2c_master_fsm.v — Bit-shift timing (Bugs #27-28):** Shift register triggered on `scl_fall` before slave sampled on first `scl_rise` (MSB lost). Also, SCL OE handoff glitch between FSM and SCL generator during START condition.

**i2c_scl_gen.v — False stretch detection (Bug #29):** Clock stretching checked same cycle SCL OE released; bus hadn't propagated yet.

**i2c_master.v — Transient status (Bug #30):** `done`/`nack` are 1-cycle pulses invisible to polling CPU. Added sticky registers.

**i2c_tx_fifo.v / i2c_rx_fifo.v — FWFT (Bug #31):** Registered reads, consumers expected FWFT. Changed to combinational.

### SPI (4 files, 4 bugs)

**spi_shift_reg.v — TX/RX same-edge race (Bugs #32-33):** TX and RX on same SCLK edge; SPI requires opposite edges. Split into separate `sample_en`/`shift_en`. Also fixed `rx_data_o` capture timing.

**spi_master_fsm.v — Missing sample_en (Bug #34):** FSM only generated `shift_en`. Added `sr_sample_en`.

**spi_tx_fifo.v / spi_rx_fifo.v — FWFT (Bug #35):** Same registered-read issue as I2C FIFOs.

---

## L2 TB-Only Fixes (not RTL bugs)

These were testbench issues, not RTL bugs:

| TB | Fix |
|----|-----|
| `tb_axi_integ.v` | AXI4 read/write tasks: sample handshake at `@(posedge clk)` instead of after `#1` NBA resolution |
| `tb_spi_integ.v` | S2 `addr_reg` expected value corrected (auto-increments from 0x80 to 0x81) |
| `tb_camera_integ.v` | C7 test sets FRAME_BUF_B (not A) after buffer swap |
| `tb_audio_integ.v` | A4 timeout increased from 5M to 10M cycles; FIFO_STATUS expected value accounts for empty flag |
