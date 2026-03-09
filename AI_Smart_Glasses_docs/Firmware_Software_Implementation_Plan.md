# AI Glasses SoC — Firmware & Software Implementation Plan

**Date:** 2026-03-09
**Target Platform:** Phase 0 FPGA (Zynq Z7-20), Phase 1 ASIC (180nm SCL)
**CPU:** RISC-V Ibex RV32IMC @ 100MHz
**Toolchain:** riscv64-unknown-elf-gcc, -march=rv32im_zicsr -mabi=ilp32

---

## 1. Executive Summary

This document defines the complete firmware stack for the AI Glasses SoC, covering:
- Hardware Abstraction Layer (HAL) for all 9 peripherals
- Device drivers for external components (ESP32, MPU6050, OV7670)
- NPU inference engine with multi-layer model support
- DMA coordination manager
- ESP32 SPI communication protocol
- 6 real-time application use cases
- Memory layout for 512KB SRAM + DDR
- Interrupt handling architecture
- Phased implementation plan (12 weeks)

---

## 2. SoC Hardware Reference

### 2.1 Memory Map

| Address Range | Size | Description |
|---------------|------|-------------|
| 0x00000000 - 0x00000FFF | 4KB | Boot ROM (read-only, INIT_FILE parameter) |
| 0x10000000 - 0x1007FFFF | 512KB | On-chip SRAM (4 banks × 128KB, dual-port AXI4) |
| 0x20000000 - 0x200008FF | 2.25KB | Peripheral registers (9 AXI-Lite slots, 256B each) |
| 0x80000000 - 0x8FFFFFFF | 256MB | DDR (via Zynq HP0, AXI3 64-bit) |

### 2.2 Peripheral Slot Map

| Slot | Base Address | Peripheral | Bus Width |
|------|-------------|------------|-----------|
| 0 | 0x20000000 | UART | AXI4-Lite 32-bit |
| 1 | 0x20000100 | Timer CLINT | AXI4-Lite 32-bit |
| 2 | 0x20000200 | IRQ Controller | AXI4-Lite 32-bit |
| 3 | 0x20000300 | GPIO | AXI4-Lite 32-bit |
| 4 | 0x20000400 | Camera Controller | AXI4-Lite 32-bit |
| 5 | 0x20000500 | Audio Controller | AXI4-Lite 32-bit |
| 6 | 0x20000600 | I2C Master | AXI4-Lite 32-bit |
| 7 | 0x20000700 | SPI Master | AXI4-Lite 32-bit |
| 8 | 0x20000800 | NPU | AXI4-Lite 32-bit |

### 2.3 IRQ Source Assignment

Wired in `riscv_subsys_top.v` lines 1019-1028:

| Bit | Source | Type (Default) | Description |
|-----|--------|---------------|-------------|
| [0] | irq_uart_tx | Level | UART TX FIFO empty |
| [1] | irq_uart_rx | Level | UART RX data available |
| [2] | irq_gpio | Edge | GPIO rising edge detected |
| [3] | irq_npu_done | Edge | NPU layer computation complete |
| [4] | irq_dma_done | Edge | (Currently tied to 0 in soc_top) |
| [5] | irq_camera_ready | Edge | Camera frame capture complete |
| [6] | irq_audio_ready | Edge | Audio MFCC frame ready / DMA done |
| [7] | irq_i2c_done | Edge | I2C transfer complete |

Note: Timer interrupt goes directly to Ibex `irq_timer_i` (mcause=0x80000007), NOT through the IRQ controller.

### 2.4 AXI Master Ports (DDR Arbitration)

5 masters compete for DDR through `axi_crossbar` (5M × 5S):

| Master | ID | Width | Traffic |
|--------|-----|-------|---------|
| M0: RISC-V CPU | 3-bit | 128-bit | Instruction fetch + data load/store |
| M1: SPI DMA | 3-bit | 32-bit | ESP32 data transfer |
| M2: NPU DMA | 3-bit | 128-bit | Weight/activation burst R/W |
| M3: Camera VDMA | 3-bit | 128-bit | Frame line burst writes |
| M4: Audio DMA | 3-bit | 32-bit | MFCC block writes |

---

## 3. Complete Register Maps

### 3.1 UART Registers (Slot 0, Base 0x20000000)

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| 0x00 | TXDATA | W | Write byte to TX FIFO [7:0] |
| 0x04 | RXDATA | R | Read byte from RX FIFO [7:0], bit[31]=empty flag |
| 0x08 | STATUS | R | [0]=tx_full, [1]=tx_empty, [2]=rx_full, [3]=rx_empty |
| 0x0C | BAUDDIV | RW | Baud divider: baud = 100MHz / (div+1) |
| 0x10 | IRQ_ENABLE | RW | [0]=tx_empty_irq, [1]=rx_ready_irq |

### 3.2 Timer CLINT Registers (Slot 1, Base 0x20000100)

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| 0x00 | MTIME_LO | R | 64-bit free-running counter [31:0] |
| 0x04 | MTIME_HI | R | 64-bit free-running counter [63:32] |
| 0x08 | MTIMECMP_LO | W | Timer compare value [31:0] |
| 0x0C | MTIMECMP_HI | W | Timer compare value [63:32] |
| 0x10 | PRESCALER | RW | mtime increments every (prescaler+1) clocks |

IRQ fires when mtime >= mtimecmp. Goes directly to `irq_timer_i`.

### 3.3 IRQ Controller Registers (Slot 2, Base 0x20000200)

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| 0x00 | IRQ_PENDING | R | [7:0] Pending interrupt sources |
| 0x04 | IRQ_ENABLE | RW | [7:0] Enable mask per source |
| 0x08 | IRQ_CLEAR | W | [7:0] Write-1-to-clear (edge-triggered only) |
| 0x0C | IRQ_TYPE | RW | [7:0] 0=level, 1=edge. Reset default: 0xFC |
| 0x10 | IRQ_STATUS | R | [7:0] Masked pending (PENDING & ENABLE) |
| 0x14 | IRQ_HIGHEST | R | [7:0] Lowest bit# of pending+enabled (0xFF if none) |

### 3.4 GPIO Registers (Slot 3, Base 0x20000300)

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| 0x00 | GPIO_DIR | RW | [7:0] Direction: 1=output, 0=input |
| 0x04 | GPIO_OUT | RW | [7:0] Output value (driven when DIR=1) |
| 0x08 | GPIO_IN | R | [7:0] Input value (2-FF synchronized) |
| 0x0C | GPIO_IRQ_EN | RW | [7:0] IRQ enable per pin |
| 0x10 | GPIO_IRQ_PEND | RW | [7:0] IRQ pending (Write-1-to-Clear, rising edge) |

### 3.5 Camera Controller Registers (Slot 4, Base 0x20000400)

From `cam_regfile.v` (24 registers, offsets 0x00-0x5C):

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| 0x00 | CAM_CONTROL | RW | [0]=enable, [1]=soft_reset, [2]=irq_enable, [3]=continuous, [4]=isp_bypass |
| 0x04 | CAM_STATUS | R | [0]=busy, [1]=frame_done, [2]=fifo_overflow, [3]=dma_busy |
| 0x08 | CAM_FRAME_WIDTH | RW | [15:0] Source frame width (e.g., 640) |
| 0x0C | CAM_FRAME_HEIGHT | RW | [15:0] Source frame height (e.g., 480) |
| 0x10 | CAM_PIXEL_FORMAT | RW | [1:0] 0=YUV422, 1=RGB565, 2=Raw Bayer |
| 0x14 | CAM_ISP_WB_R | RW | [15:0] White balance red gain (Q8.8, 0x100=unity) |
| 0x18 | CAM_ISP_WB_G | RW | [15:0] White balance green gain |
| 0x1C | CAM_ISP_WB_B | RW | [15:0] White balance blue gain |
| 0x20 | CAM_ISP_GAMMA | RW | [7:0] Gamma correction index (0=1.0, 1=2.2) |
| 0x24 | CAM_RESIZE_OUT_W | RW | [15:0] Resize output width (e.g., 128) |
| 0x28 | CAM_RESIZE_OUT_H | RW | [15:0] Resize output height (e.g., 128) |
| 0x2C | CAM_CROP_X | RW | [15:0] Crop start X |
| 0x30 | CAM_CROP_Y | RW | [15:0] Crop start Y |
| 0x34 | CAM_CROP_W | RW | [15:0] Crop width |
| 0x38 | CAM_CROP_H | RW | [15:0] Crop height |
| 0x3C | CAM_DMA_BASE_A | RW | [31:0] Frame buffer A DDR address |
| 0x40 | CAM_DMA_BASE_B | RW | [31:0] Frame buffer B DDR address |
| 0x44 | CAM_DMA_STRIDE | RW | [15:0] Line stride in bytes |
| 0x48 | CAM_IRQ_CLEAR | W | [0] Write 1 to clear frame_done IRQ |
| 0x4C | CAM_FRAME_COUNT | R | [31:0] Total frames captured (auto-increment) |
| 0x50 | CAM_PERF_CAPTURE | R | [31:0] Cycles for last DVP capture |
| 0x54 | CAM_PERF_ISP | R | [31:0] Cycles for last ISP processing |
| 0x58 | CAM_PERF_RESIZE | R | [31:0] Cycles for last resize operation |
| 0x5C | CAM_PERF_CROP | R | [31:0] Cycles for last crop operation |

### 3.6 Audio Controller Registers (Slot 5, Base 0x20000500)

From `audio_regfile.v` (16 registers, offsets 0x00-0x3C):

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| 0x00 | AUDIO_CONTROL | RW | [0]=enable, [1]=soft_reset, [2]=irq_en_frame, [3]=irq_en_dma, [4]=mode (0=MFCC,1=passthrough) |
| 0x04 | AUDIO_STATUS | R | [0]=busy, [1]=frame_done, [2]=dma_done, [3]=fifo_overflow |
| 0x08 | AUDIO_SAMPLE_RATE | RW | [15:0] I2S divider for sample rate |
| 0x0C | AUDIO_FRAME_SIZE | RW | [15:0] Samples per MFCC frame (e.g., 640 for 40ms) |
| 0x10 | AUDIO_FRAME_STRIDE | RW | [15:0] Samples per stride (e.g., 320 for 20ms) |
| 0x14 | AUDIO_FFT_SIZE | RW | [3:0] FFT log2 size (10 = 1024-point) |
| 0x18 | AUDIO_NUM_MEL | RW | [7:0] Number of mel filters (default 40) |
| 0x1C | AUDIO_NUM_MFCC | RW | [7:0] Number of MFCC coefficients (default 10) |
| 0x20 | AUDIO_DMA_BASE | RW | [31:0] DDR base address for MFCC output |
| 0x24 | AUDIO_DMA_LENGTH | RW | [31:0] DMA transfer length in bytes |
| 0x28 | AUDIO_DMA_WR_PTR | R | [31:0] Current DMA write pointer |
| 0x2C | AUDIO_GAIN | RW | [15:0] Input gain (Q8.8, 0x100 = unity) |
| 0x30 | AUDIO_NOISE_FLOOR | RW | [31:0] Noise floor threshold for VAD |
| 0x34 | AUDIO_IRQ_CLEAR | W | [1:0] [0]=clear frame_done, [1]=clear dma_done |
| 0x38 | AUDIO_PERF_CYCLES | R | [31:0] Cycles for last MFCC computation |
| 0x3C | AUDIO_FRAME_ENERGY | R | [31:0] Energy of last audio frame (for VAD) |

### 3.7 I2C Master Registers (Slot 6, Base 0x20000600)

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| 0x00 | I2C_CONTROL | RW | [0]=enable, [2]=irq_en |
| 0x04 | I2C_STATUS | R | [0]=busy, [1]=done, [2]=nack |
| 0x08 | I2C_SLAVE_ADDR | RW | [7:1]=7-bit addr, [0]=R/W bit |
| 0x0C | I2C_TXDATA | W | [7:0] Write byte to TX FIFO |
| 0x10 | I2C_RXDATA | R | [7:0] Read byte from RX FIFO |
| 0x14 | I2C_XFER_LEN | RW | [7:0] Transfer byte count |
| 0x18 | I2C_START | W | [0] Write 1 to start transfer |
| 0x1C | I2C_PRESCALER | RW | [15:0] SCL = 100MHz / (4*(pre+1)) |
| 0x20 | I2C_IRQ_CLEAR | W | [0] Write 1 to clear done IRQ |
| 0x24 | I2C_FIFO_STATUS | R | [4:0]=tx_count, [12:8]=rx_count, [16]=tx_full, [17]=tx_empty, [18]=rx_full, [19]=rx_empty |

### 3.8 SPI Master Registers (Slot 7, Base 0x20000700)

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| 0x00 | SPI_TXDATA | W | [7:0] Write byte to TX FIFO |
| 0x04 | SPI_RXDATA | R | [7:0] Read byte from RX FIFO |
| 0x08 | SPI_STATUS | R | [0]=busy, [1]=tx_full, [2]=tx_empty, [3]=rx_full, [4]=rx_empty |
| 0x0C | SPI_CONFIG | RW | [7:0]=clock_div, [8]=cpol, [9]=cpha, [10]=auto_cs |
| 0x10 | SPI_CS | RW | [0]=cs_n (active-low) |
| 0x14 | SPI_IRQ_EN | RW | [0]=enable done IRQ |
| 0x18 | SPI_TX_FIFO_CNT | R | [4:0] TX FIFO count |
| 0x1C | SPI_RX_FIFO_CNT | R | [4:0] RX FIFO count |

SPI clock = 100MHz / (2 * (div + 1)). Default div=4 gives 10MHz.

### 3.9 NPU Registers (Slot 8, Base 0x20000800)

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| 0x00 | NPU_CONTROL | RW | [0]=enable, [1]=soft_reset (self-clear), [2]=irq_enable |
| 0x04 | NPU_STATUS | R | [0]=busy, [1]=layer_done, [31:16]=layer_status |
| 0x08 | NPU_INPUT_ADDR | RW | [31:0] Input tensor DDR address |
| 0x0C | NPU_WEIGHT_ADDR | RW | [31:0] Weight tensor DDR address |
| 0x10 | NPU_OUTPUT_ADDR | RW | [31:0] Output tensor DDR address |
| 0x14 | NPU_INPUT_SIZE | RW | [31:0] Input tensor size (bytes) |
| 0x18 | NPU_WEIGHT_SIZE | RW | [31:0] Weight tensor size (bytes) |
| 0x1C | NPU_OUTPUT_SIZE | RW | [31:0] Output tensor size (bytes) |
| 0x20 | NPU_LAYER_CONFIG | RW | [3:0]=layer_type, [7:4]=activation, [15:8]=in_channels, [23:16]=out_channels |
| 0x24 | NPU_CONV_CONFIG | RW | [7:0]=kernel_size, [15:8]=stride, [23:16]=padding |
| 0x28 | NPU_TENSOR_DIMS | RW | [15:0]=width, [31:16]=height |
| 0x2C | NPU_QUANT_PARAM | RW | [7:0]=shift, [15:8]=zero_point |
| 0x30 | NPU_START | W | [0] Write 1 to start (self-clearing pulse) |
| 0x34 | NPU_IRQ_CLEAR | W | [0] Write 1 to clear done IRQ |
| 0x38 | NPU_PERF_CYCLES | R | [31:0] Cycle count for last layer |
| 0x3C | NPU_DMA_STATUS | R | [31:0] DMA activity bits |

---

## 4. Firmware Directory Structure

```
firmware/
├── Makefile                       # Build system (modified for new structure)
├── crt0.S                         # Startup code (enhanced trap dispatch)
├── boot_stub.S                    # Boot ROM code (4 instructions)
├── boot_rom.ld                    # Boot ROM linker script
├── sram_exec.ld                   # SRAM + DDR linker script (enhanced)
│
├── include/
│   ├── types.h                    # Common types: uint8/16/32, hal_status_t
│   ├── soc_regs.h                 # All peripheral register definitions
│   ├── uart.h                     # Polled UART (existing, for debug/tests)
│   │
│   ├── hal/                       # Hardware Abstraction Layer headers
│   │   ├── hal_irq.h
│   │   ├── hal_timer.h
│   │   ├── hal_uart.h             # IRQ-driven UART for applications
│   │   ├── hal_gpio.h
│   │   ├── hal_spi.h
│   │   ├── hal_i2c.h
│   │   ├── hal_camera.h
│   │   ├── hal_audio.h
│   │   └── hal_npu.h
│   │
│   ├── drivers/                   # External device driver headers
│   │   ├── esp32_spi.h            # ESP32-C3 SPI protocol
│   │   ├── mpu6050.h              # IMU sensor driver
│   │   └── ov7670.h               # Camera sensor SCCB init
│   │
│   ├── npu/                       # NPU inference engine headers
│   │   ├── npu_api.h              # High-level inference API
│   │   ├── npu_model.h            # Model descriptor structures
│   │   └── npu_quant.h            # Quantization helpers
│   │
│   ├── app/                       # Application framework headers
│   │   ├── app_common.h           # Shared state machine, event system
│   │   └── dma_manager.h          # DMA resource coordinator
│   │
│   └── system.h                   # System init, clock config
│
├── src/
│   ├── hal/                       # HAL implementations
│   │   ├── hal_irq.c
│   │   ├── hal_timer.c
│   │   ├── hal_uart.c
│   │   ├── hal_gpio.c
│   │   ├── hal_spi.c
│   │   ├── hal_i2c.c
│   │   ├── hal_camera.c
│   │   ├── hal_audio.c
│   │   └── hal_npu.c
│   │
│   ├── drivers/                   # Device driver implementations
│   │   ├── esp32_spi.c
│   │   ├── mpu6050.c
│   │   └── ov7670.c
│   │
│   ├── npu/                       # NPU engine implementations
│   │   ├── npu_api.c
│   │   └── npu_model.c
│   │
│   ├── system.c                   # System init
│   └── dma_manager.c              # DMA coordination
│
├── apps/                          # Application use cases
│   ├── uc1_wake_word.c
│   ├── uc2_object_detect.c
│   ├── uc3_concurrent.c
│   ├── uc4_gesture.c
│   ├── uc5_boot_wifi.c
│   ├── uc6_low_power.c
│   └── main_app.c                 # Integrated application
│
├── models/                        # Pre-quantized model weights (C arrays)
│   ├── ds_cnn_wake.h              # DS-CNN wake word model (~80KB INT8)
│   └── mobilenet_tiny.h           # Tiny MobileNet model (~200KB INT8)
│
└── tests/                         # Existing L3 test firmware (unchanged)
    ├── test_boot_uart.c
    ├── test_sram.c
    ├── test_periph_walk.c
    ├── test_uart_echo.c
    ├── test_timer_irq.c
    ├── test_gpio.c
    ├── test_spi_regs.c
    ├── test_i2c_regs.c
    ├── test_npu_regs.c
    ├── test_timer_gpio.c
    └── test_multi_periph.c
```

---

## 5. Memory Layout

### 5.1 SRAM Layout (512KB: 0x10000000 — 0x1007FFFF)

```
Address         Size    Section
──────────────────────────────────────────
0x10000000      64KB    .text (firmware code)
0x10010000      16KB    .rodata (strings, const tables)
0x10014000       8KB    .data (initialized globals)
0x10016000       8KB    .bss (zero-initialized globals)
0x10018000     128KB    Model weight cache (partial, DMA'd from DDR)
0x10038000      64KB    Scratch buffers (NPU intermediate, MFCC local)
0x10048000       4KB    IRQ stack (separate from main stack)
0x10049000     156KB    Free / heap
0x10070000      64KB    Main stack (grows downward)
0x10080000              ← _stack_top (end of SRAM)
```

### 5.2 DDR Layout (starting at 0x80000000)

```
Address         Size    Section
──────────────────────────────────────────
0x80000000      48KB    Camera Frame Buffer A (128×128×3 RGB)
0x8000C000      48KB    Camera Frame Buffer B (double-buffer)
0x80018000     600KB    Camera Raw Frame (640×480×2 YUV422, if needed)
0x800B0000     128KB    NPU Input Tensor
0x800D0000     256KB    NPU Weight Buffer (per-layer, DMA'd from storage)
0x80110000      64KB    NPU Output Tensor
0x80120000     256KB    NPU Intermediate Buffers (2 × 128KB ping-pong)
0x80160000       2KB    Audio MFCC Feature Frame (49×10×4 bytes)
0x80161000      64KB    Audio PCM Ring Buffer (raw passthrough mode)
0x80171000       2MB    Model Weight Storage (full model, loaded at boot)
0x80371000       8KB    ESP32 TX/RX Buffers
0x80373000       —      Free
```

### 5.3 Linker Script Additions

```ld
MEMORY {
    SRAM (rwx) : ORIGIN = 0x10000000, LENGTH = 512K
    DDR  (rw)  : ORIGIN = 0x80000000, LENGTH = 16M
}

SECTIONS {
    /* ... existing .text, .rodata, .data, .bss in SRAM ... */

    .irq_stack (NOLOAD) : ALIGN(16) {
        _irq_stack_bottom = .;
        . += 4K;
        _irq_stack_top = .;
    } > SRAM

    .dma_buffers (NOLOAD) : ALIGN(16) {
        _dma_buffers_start = .;
        *(.dma_buffers)
        _dma_buffers_end = .;
    } > DDR

    .model_weights (NOLOAD) : ALIGN(16) {
        _model_weights_start = .;
        *(.model_weights)
        _model_weights_end = .;
    } > DDR
}
```

---

## 6. HAL API Specifications

### 6.1 Common Types (`types.h`)

```c
#ifndef TYPES_H
#define TYPES_H

typedef unsigned char      uint8_t;
typedef unsigned short     uint16_t;
typedef unsigned int       uint32_t;
typedef signed char        int8_t;
typedef signed short       int16_t;
typedef signed int         int32_t;
typedef unsigned long long uint64_t;
typedef int                bool;

#define true  1
#define false 0
#define NULL  ((void*)0)

typedef enum {
    HAL_OK       =  0,
    HAL_ERROR    = -1,
    HAL_BUSY     = -2,
    HAL_TIMEOUT  = -3,
    HAL_NACK     = -4
} hal_status_t;

typedef void (*irq_callback_t)(void *ctx);
#endif
```

### 6.2 IRQ HAL API (`hal_irq.h`)

```c
typedef enum {
    IRQ_UART_TX   = 0,   // UART TX FIFO empty (level)
    IRQ_UART_RX   = 1,   // UART RX data ready (level)
    IRQ_GPIO      = 2,   // GPIO rising edge (edge)
    IRQ_NPU_DONE  = 3,   // NPU layer complete (edge)
    IRQ_DMA_DONE  = 4,   // DMA transfer complete (edge)
    IRQ_CAM_READY = 5,   // Camera frame captured (edge)
    IRQ_AUD_READY = 6,   // Audio MFCC frame ready (edge)
    IRQ_I2C_DONE  = 7    // I2C transfer complete (edge)
} irq_source_t;

// Core API
void     hal_irq_init(void);                 // Reset controller, set default types
void     hal_irq_enable(irq_source_t src);   // Enable specific source
void     hal_irq_disable(irq_source_t src);  // Disable specific source
void     hal_irq_clear(irq_source_t src);    // Write-1-to-clear (edge only)
void     hal_irq_set_type(irq_source_t src, int edge); // 0=level, 1=edge
uint32_t hal_irq_pending(void);              // Read pending register
uint32_t hal_irq_highest(void);              // Read highest priority source

// Callback registration
void     hal_irq_register(irq_source_t src, irq_callback_t cb, void *ctx);
void     hal_irq_unregister(irq_source_t src);

// Global enable/disable (mstatus.MIE + mie.MEIE + mie.MTIE)
void     hal_irq_global_enable(void);
void     hal_irq_global_disable(void);
```

**Implementation Notes:**
- `hal_irq_init()` sets IRQ_ENABLE=0, IRQ_TYPE=0xFC (default), clears all pending
- Callback table: static array of 8 function pointers + context pointers
- `trap_handler()` in C reads mcause: bit31=1 means interrupt
  - cause=7: timer interrupt → call timer callback
  - cause=11: external interrupt → read IRQ_HIGHEST → dispatch from callback table → write IRQ_CLEAR

### 6.3 Timer HAL API (`hal_timer.h`)

```c
void     hal_timer_init(uint32_t prescaler);
// prescaler=99 → mtime ticks at 1MHz (1us resolution)
// prescaler=0  → mtime ticks at 100MHz (10ns resolution)

uint64_t hal_timer_get_mtime(void);
void     hal_timer_set_compare(uint64_t value);

// Blocking delays (busy-wait)
void     hal_timer_delay_us(uint32_t us);
void     hal_timer_delay_ms(uint32_t ms);

// Periodic timer interrupt
void     hal_timer_set_periodic(uint32_t interval_us,
                                 irq_callback_t cb, void *ctx);
void     hal_timer_stop_periodic(void);

// One-shot timer
void     hal_timer_set_oneshot(uint32_t delay_us,
                                irq_callback_t cb, void *ctx);
```

### 6.4 GPIO HAL API (`hal_gpio.h`)

```c
void     hal_gpio_init(void);
void     hal_gpio_set_dir(uint8_t mask, uint8_t output_bits);
// Example: hal_gpio_set_dir(0xFF, 0x0F) → pins 0-3 output, 4-7 input

void     hal_gpio_write(uint8_t mask, uint8_t value);
void     hal_gpio_toggle(uint8_t mask);
uint8_t  hal_gpio_read(void);

void     hal_gpio_irq_enable(uint8_t pin_mask);
void     hal_gpio_irq_disable(uint8_t pin_mask);
void     hal_gpio_irq_clear(uint8_t pin_mask);
void     hal_gpio_irq_register(irq_callback_t cb, void *ctx);
```

### 6.5 SPI HAL API (`hal_spi.h`)

```c
typedef struct {
    uint8_t clock_div;    // SPI_CLK = 100MHz / (2*(div+1))
    uint8_t cpol;         // Clock polarity: 0 or 1
    uint8_t cpha;         // Clock phase: 0 or 1
    uint8_t auto_cs;      // 1=auto CS per byte, 0=manual CS
} spi_config_t;

void         hal_spi_init(const spi_config_t *cfg);
void         hal_spi_cs_assert(void);
void         hal_spi_cs_deassert(void);

// Full-duplex transfer (simultaneous TX+RX)
hal_status_t hal_spi_transfer(const uint8_t *tx, uint8_t *rx, uint32_t len);

// Convenience: write-only, read-only
hal_status_t hal_spi_write(const uint8_t *data, uint32_t len);
hal_status_t hal_spi_read(uint8_t *data, uint32_t len);

// FIFO status
bool         hal_spi_tx_empty(void);
bool         hal_spi_rx_available(void);
```

### 6.6 I2C HAL API (`hal_i2c.h`)

```c
typedef struct {
    uint16_t prescaler;   // SCL = 100MHz / (4*(pre+1))
                          // pre=249 → 100kHz, pre=61 → ~400kHz
} i2c_config_t;

void         hal_i2c_init(const i2c_config_t *cfg);

// Basic byte-level transfers
hal_status_t hal_i2c_write(uint8_t addr7, const uint8_t *data, uint32_t len);
hal_status_t hal_i2c_read(uint8_t addr7, uint8_t *data, uint32_t len);

// Register access helpers (common I2C device pattern)
hal_status_t hal_i2c_write_reg(uint8_t addr7, uint8_t reg, uint8_t val);
hal_status_t hal_i2c_read_reg(uint8_t addr7, uint8_t reg, uint8_t *val);
hal_status_t hal_i2c_read_burst(uint8_t addr7, uint8_t start_reg,
                                 uint8_t *buf, uint32_t len);

// Async (IRQ-driven) transfer
hal_status_t hal_i2c_write_async(uint8_t addr7, const uint8_t *data,
                                  uint32_t len, irq_callback_t cb, void *ctx);
hal_status_t hal_i2c_read_async(uint8_t addr7, uint8_t *data,
                                 uint32_t len, irq_callback_t cb, void *ctx);
```

### 6.7 Camera HAL API (`hal_camera.h`)

```c
typedef struct {
    uint16_t src_width;      // Source frame width (e.g., 640)
    uint16_t src_height;     // Source frame height (e.g., 480)
    uint8_t  pixel_format;   // 0=YUV422, 1=RGB565, 2=Raw Bayer
    uint16_t out_width;      // Resize output width (e.g., 128)
    uint16_t out_height;     // Resize output height (e.g., 128)
    uint8_t  isp_bypass;     // 0=ISP enabled, 1=raw passthrough
    uint32_t frame_buf_a;    // DDR address for frame buffer A
    uint32_t frame_buf_b;    // DDR address for frame buffer B (double-buffer)
    uint8_t  continuous;     // 0=single-shot, 1=continuous capture
} cam_config_t;

typedef struct {
    uint16_t x, y;           // Crop origin
    uint16_t width, height;  // Crop size
} cam_crop_t;

// Core API
void     hal_cam_init(const cam_config_t *cfg);
void     hal_cam_start(void);
void     hal_cam_stop(void);

// ISP configuration
void     hal_cam_set_white_balance(uint16_t r, uint16_t g, uint16_t b);
void     hal_cam_set_gamma(uint8_t gamma_idx);

// Crop control
void     hal_cam_set_crop(const cam_crop_t *crop);

// Status
bool     hal_cam_frame_ready(void);
bool     hal_cam_busy(void);
uint32_t hal_cam_get_active_buf(void);
uint32_t hal_cam_frame_count(void);

// IRQ
void     hal_cam_irq_enable(void);
void     hal_cam_irq_clear(void);
void     hal_cam_irq_register(irq_callback_t cb, void *ctx);

// Performance counters
uint32_t hal_cam_perf_capture(void);
uint32_t hal_cam_perf_isp(void);
uint32_t hal_cam_perf_resize(void);
uint32_t hal_cam_perf_crop(void);
```

### 6.8 Audio HAL API (`hal_audio.h`)

```c
typedef enum {
    AUDIO_MODE_MFCC        = 0,  // Full MFCC pipeline
    AUDIO_MODE_PASSTHROUGH = 1   // Raw PCM to DDR
} audio_mode_t;

typedef struct {
    audio_mode_t mode;
    uint16_t sample_rate_div;     // I2S divider
    uint16_t frame_size_samples;  // Samples per frame (640 = 40ms @ 16kHz)
    uint16_t frame_stride_samples;// Stride (320 = 20ms overlap)
    uint8_t  fft_log2;           // FFT size: 10 = 1024-point
    uint8_t  num_mel_filters;    // Mel filter count (default 40)
    uint8_t  num_mfcc_coeffs;    // MFCC output coeffs (default 10)
    uint32_t dma_base_addr;      // DDR address for output
    uint32_t dma_length;         // DMA transfer length (bytes)
    uint16_t gain;               // Q8.8 gain (0x100 = unity)
    uint32_t noise_floor;        // VAD threshold
} audio_config_t;

// Core API
void     hal_audio_init(const audio_config_t *cfg);
void     hal_audio_start(void);
void     hal_audio_stop(void);

// Status
bool     hal_audio_frame_ready(void);
bool     hal_audio_dma_done(void);
bool     hal_audio_busy(void);
uint32_t hal_audio_dma_wr_ptr(void);
uint32_t hal_audio_frame_energy(void);  // For VAD

// IRQ
void     hal_audio_irq_enable_frame(void);
void     hal_audio_irq_enable_dma(void);
void     hal_audio_irq_clear_frame(void);
void     hal_audio_irq_clear_dma(void);
void     hal_audio_irq_register(irq_callback_t cb, void *ctx);

// Performance
uint32_t hal_audio_perf_cycles(void);
```

### 6.9 NPU HAL API (`hal_npu.h`)

```c
typedef enum {
    NPU_LAYER_CONV2D    = 0,
    NPU_LAYER_FC        = 1,
    NPU_LAYER_MAXPOOL   = 2,
    NPU_LAYER_AVGPOOL   = 3,
    NPU_LAYER_DW_CONV2D = 4
} npu_layer_type_t;

typedef enum {
    NPU_ACT_NONE  = 0,
    NPU_ACT_RELU  = 1,
    NPU_ACT_RELU6 = 2
} npu_activation_t;

typedef struct {
    npu_layer_type_t  type;
    npu_activation_t  activation;
    uint8_t           in_channels;
    uint8_t           out_channels;
    uint8_t           kernel_size;    // 1 or 3
    uint8_t           stride;         // 1 or 2
    uint8_t           padding;        // 0=VALID, 1=SAME
    uint32_t          input_addr;     // DDR address
    uint32_t          weight_addr;    // DDR address
    uint32_t          output_addr;    // DDR address
    uint32_t          input_size;     // bytes
    uint32_t          weight_size;    // bytes
    uint32_t          output_size;    // bytes
    uint16_t          tensor_h;
    uint16_t          tensor_w;
    int8_t            quant_shift;
    int8_t            quant_zero_point;
} npu_layer_desc_t;

// Core API
void     hal_npu_init(void);
void     hal_npu_reset(void);           // Soft reset (self-clearing)
void     hal_npu_configure(const npu_layer_desc_t *layer);
void     hal_npu_start(void);           // Trigger computation

// Status
bool     hal_npu_busy(void);
bool     hal_npu_done(void);
uint32_t hal_npu_status(void);
uint32_t hal_npu_dma_status(void);

// IRQ
void     hal_npu_irq_enable(void);
void     hal_npu_irq_disable(void);
void     hal_npu_irq_clear(void);
void     hal_npu_irq_register(irq_callback_t cb, void *ctx);

// Performance
uint32_t hal_npu_perf_cycles(void);
```

---

## 7. NPU Inference Engine API (`npu_api.h`)

### 7.1 Model Descriptor

```c
#define NPU_MAX_LAYERS 32

typedef struct {
    const char           *name;
    uint32_t              num_layers;
    npu_layer_desc_t      layers[NPU_MAX_LAYERS];
    const uint8_t        *weight_data;        // Pointer to weight blob
    uint32_t              total_weight_bytes;
    uint32_t              weight_ddr_addr;     // DDR address after loading
} npu_model_t;

typedef struct {
    uint32_t input_addr;    // DDR address of input tensor
    uint32_t output_addr;   // DDR address of final output
    uint32_t output_size;   // bytes
    uint32_t total_cycles;  // performance counter (filled after inference)
} npu_inference_result_t;
```

### 7.2 High-Level Inference API

```c
// Model management
hal_status_t npu_load_model(npu_model_t *model);
// Loads weight data from SRAM/flash to DDR at model->weight_ddr_addr.
// Sets up per-layer weight_addr offsets.

// Synchronous inference (blocking)
hal_status_t npu_run_inference(const npu_model_t *model,
                                uint32_t input_addr,
                                npu_inference_result_t *result);
// Executes all layers sequentially. Uses ping-pong DDR buffers
// for intermediate results. Returns top-level output address and size.

// Asynchronous inference (non-blocking)
hal_status_t npu_run_inference_async(const npu_model_t *model,
                                      uint32_t input_addr,
                                      irq_callback_t done_cb, void *ctx);
// Starts first layer. On each NPU_DONE IRQ, configures next layer.
// Calls done_cb when final layer completes.

bool         npu_inference_complete(void);

// Result interpretation
int          npu_get_top_class(const int8_t *output, int num_classes);
// Returns index of maximum value in output tensor.

int8_t       npu_get_confidence(const int8_t *output, int class_idx);
// Returns raw INT8 confidence for given class.
```

### 7.3 Layer Execution Flow

For each layer in the model:
1. Write `NPU_INPUT_ADDR` = layer input DDR address
2. Write `NPU_WEIGHT_ADDR` = layer weight DDR address
3. Write `NPU_OUTPUT_ADDR` = layer output DDR address
4. Write `NPU_INPUT_SIZE`, `NPU_WEIGHT_SIZE`, `NPU_OUTPUT_SIZE`
5. Write `NPU_LAYER_CONFIG` = `type | (activation << 4) | (in_ch << 8) | (out_ch << 16)`
6. Write `NPU_CONV_CONFIG` = `kernel | (stride << 8) | (padding << 16)`
7. Write `NPU_TENSOR_DIMS` = `(height << 16) | width`
8. Write `NPU_QUANT_PARAM` = `(zero_point << 8) | shift`
9. Write `NPU_START = 1` (self-clearing pulse)
10. Wait for `NPU_STATUS` bit[1] (layer_done) or NPU_DONE IRQ
11. Swap ping-pong buffers for next layer: output becomes input

### 7.4 Ping-Pong Buffer Strategy

```
Layer 0: Input(0x800B0000) → Output(0x80120000)  [Buf A]
Layer 1: Input(0x80120000) → Output(0x80140000)  [Buf B]
Layer 2: Input(0x80140000) → Output(0x80120000)  [Buf A]
Layer 3: Input(0x80120000) → Output(0x80140000)  [Buf B]
...
Final:   Output → result->output_addr
```

---

## 8. DMA Manager API (`dma_manager.h`)

```c
typedef enum {
    DMA_CHAN_NPU    = 0,
    DMA_CHAN_CAMERA = 1,
    DMA_CHAN_AUDIO  = 2,
    DMA_CHAN_COUNT  = 3
} dma_channel_t;

typedef enum {
    DMA_PRIO_LOW    = 0,
    DMA_PRIO_MEDIUM = 1,
    DMA_PRIO_HIGH   = 2
} dma_priority_t;

void         dma_mgr_init(void);
hal_status_t dma_mgr_request(dma_channel_t ch, dma_priority_t prio);
void         dma_mgr_release(dma_channel_t ch);
bool         dma_mgr_channel_busy(dma_channel_t ch);
void         dma_mgr_set_callback(dma_channel_t ch, irq_callback_t cb, void *ctx);
```

**Design Note:** The SoC hardware crossbar handles DDR arbitration automatically (5 masters → DDR slave). The DMA manager's role is **software coordination**:
- Prevents CPU from starting NPU inference while Camera VDMA writes to the same buffer
- Tracks completion via IRQ callbacks
- Provides priority hints (future: could map to AXI QoS field)

---

## 9. ESP32 Communication Protocol (`esp32_spi.h`)

### 9.1 SPI Frame Format

```
TX Frame:  [CMD:1] [LEN_HI:1] [LEN_LO:1] [PAYLOAD:0..4096] [CRC8:1]
RX Frame:  [STATUS:1] [LEN_HI:1] [LEN_LO:1] [PAYLOAD:0..4096] [CRC8:1]

CRC8: x^8 + x^2 + x + 1 (polynomial 0x07)
```

### 9.2 Command Set

```c
typedef enum {
    // System commands (0x01-0x0F)
    ESP_CMD_PING          = 0x01,  // Echo test, payload: none
    ESP_CMD_VERSION       = 0x02,  // Get ESP32 firmware version
    ESP_CMD_RESET         = 0x03,  // Reset ESP32

    // WiFi commands (0x10-0x1F)
    ESP_CMD_WIFI_INIT     = 0x10,  // Initialize WiFi stack
    ESP_CMD_WIFI_STATUS   = 0x11,  // Query connection status
    ESP_CMD_WIFI_CONNECT  = 0x12,  // Connect to AP. Payload: [SSID_LEN:1][SSID][PASS_LEN:1][PASS]
    ESP_CMD_WIFI_DISCONNECT = 0x13,

    // BLE commands (0x20-0x2F)
    ESP_CMD_BLE_INIT      = 0x20,  // Initialize BLE stack
    ESP_CMD_BLE_ADVERTISE = 0x21,  // Start BLE advertising
    ESP_CMD_BLE_NOTIFY    = 0x22,  // Send BLE notification

    // Data commands (0x30-0x3F)
    ESP_CMD_SEND_DATA     = 0x30,  // Upload data. Payload: [TYPE:1][DATA]
    ESP_CMD_RECV_DATA     = 0x31,  // Poll for incoming data
    ESP_CMD_SEND_RESULT   = 0x32,  // Send inference result. Payload: [CLASS:1][CONF:1][EXTRA]

    // Power commands (0x50-0x5F)
    ESP_CMD_SLEEP         = 0x50,  // Enter ESP32 light sleep
    ESP_CMD_WAKE          = 0x51,  // Wake from sleep (via CS assert)

    // OTA commands (0x40-0x4F)
    ESP_CMD_OTA_START     = 0x40,  // Begin OTA update
    ESP_CMD_OTA_DATA      = 0x41,  // OTA data chunk
    ESP_CMD_OTA_FINISH    = 0x42,  // Finalize OTA update
} esp_cmd_t;

typedef enum {
    ESP_STATUS_OK       = 0x00,
    ESP_STATUS_BUSY     = 0x01,
    ESP_STATUS_NO_DATA  = 0x02,
    ESP_STATUS_ERROR    = 0xFF,
} esp_status_t;
```

### 9.3 Driver API

```c
// Initialization
hal_status_t esp32_init(void);       // SPI config + ping + version check
hal_status_t esp32_ping(void);       // Verify ESP32 is responding
hal_status_t esp32_reset(void);      // Hard reset via esp32_reset_n GPIO

// WiFi
hal_status_t esp32_wifi_init(void);
hal_status_t esp32_wifi_connect(const char *ssid, const char *pass);
hal_status_t esp32_wifi_disconnect(void);
hal_status_t esp32_wifi_status(uint8_t *connected);

// BLE
hal_status_t esp32_ble_init(void);
hal_status_t esp32_ble_advertise(const char *name);
hal_status_t esp32_ble_notify(const uint8_t *data, uint32_t len);

// Data transfer
hal_status_t esp32_send_result(uint8_t class_id, uint8_t confidence,
                                const uint8_t *extra, uint32_t extra_len);
hal_status_t esp32_send_data(const uint8_t *data, uint32_t len);
hal_status_t esp32_receive(uint8_t *buf, uint32_t *len);

// Power
hal_status_t esp32_sleep(void);
hal_status_t esp32_wake(void);
```

### 9.4 SPI Configuration

```c
// ESP32 SPI settings
spi_config_t esp32_spi_cfg = {
    .clock_div = 4,    // 100MHz / (2*(4+1)) = 10MHz
    .cpol = 0,         // Mode 0
    .cpha = 0,
    .auto_cs = 0       // Manual CS for multi-byte frames
};
```

Protocol flow: Assert CS → send CMD frame → 1μs delay → read STATUS frame → deassert CS → 10μs inter-frame gap.

---

## 10. Device Drivers

### 10.1 MPU6050 IMU Driver (`mpu6050.h`)

```c
// I2C address
#define MPU6050_ADDR       0x68

// Key registers
#define MPU6050_WHO_AM_I   0x75  // Should return 0x68
#define MPU6050_PWR_MGMT_1 0x6B  // Power management
#define MPU6050_ACCEL_XOUT 0x3B  // Start of 14-byte burst (accel+temp+gyro)
#define MPU6050_GYRO_CONFIG 0x1B
#define MPU6050_ACCEL_CONFIG 0x1C
#define MPU6050_SMPLRT_DIV 0x19

typedef struct {
    int16_t accel_x, accel_y, accel_z;  // Raw accelerometer (±2g default)
    int16_t temp;                        // Raw temperature
    int16_t gyro_x, gyro_y, gyro_z;     // Raw gyroscope (±250°/s default)
} mpu6050_data_t;

hal_status_t mpu6050_init(void);
// Wake from sleep, set accel ±2g, gyro ±250°/s, sample rate 100Hz

hal_status_t mpu6050_who_am_i(uint8_t *id);
hal_status_t mpu6050_read_all(mpu6050_data_t *data);
// Burst read 14 bytes starting at ACCEL_XOUT

hal_status_t mpu6050_read_accel(int16_t *ax, int16_t *ay, int16_t *az);
hal_status_t mpu6050_read_gyro(int16_t *gx, int16_t *gy, int16_t *gz);
```

### 10.2 OV7670 Camera Driver (`ov7670.h`)

```c
// SCCB (I2C-like) address
#define OV7670_ADDR  0x21

hal_status_t ov7670_init(void);
// Sends ~170 register writes via I2C to configure:
// - QVGA (320x240) or VGA (640x480)
// - YUV422 output format
// - Auto white balance, auto exposure
// - PCLK divider, HREF/VSYNC timing

hal_status_t ov7670_set_resolution(uint16_t width, uint16_t height);
hal_status_t ov7670_set_format(uint8_t format);  // 0=YUV422, 1=RGB565
hal_status_t ov7670_set_test_pattern(uint8_t pattern);  // For debug
```

---

## 11. Interrupt Handling Architecture

### 11.1 Two-Level Interrupt Model

```
Ibex Core Inputs:
  irq_timer_i    ← Timer CLINT (direct)     → mcause = 0x80000007
  irq_external_i ← IRQ Controller output    → mcause = 0x8000000B
  irq_software_i ← tied to 0               → (unused)
```

### 11.2 Enhanced Trap Handler (crt0.S)

```asm
_trap_entry:
    # Save all caller-saved registers (16 regs)
    addi sp, sp, -64
    sw   ra, 0(sp)
    sw   t0, 4(sp)
    # ... (save t1-t6, a0-a7)

    # Read mcause, mepc → pass as arguments to C handler
    csrr a0, mcause
    csrr a1, mepc
    call trap_dispatch     # C function

    # Restore registers
    lw   ra, 0(sp)
    lw   t0, 4(sp)
    # ...
    addi sp, sp, 64
    mret
```

### 11.3 C Dispatch Function

```c
// In hal_irq.c
static irq_callback_t ext_irq_table[8] = {NULL};
static void          *ext_irq_ctx[8]   = {NULL};
static irq_callback_t timer_callback   = NULL;
static void          *timer_ctx        = NULL;

void trap_dispatch(uint32_t mcause, uint32_t mepc) {
    if (mcause & 0x80000000) {
        // Interrupt
        uint32_t cause = mcause & 0x1F;
        if (cause == 7) {
            // Machine Timer Interrupt
            if (timer_callback) timer_callback(timer_ctx);
        } else if (cause == 11) {
            // Machine External Interrupt
            uint32_t src = IRQ_HIGHEST;
            if (src < 8 && ext_irq_table[src]) {
                ext_irq_table[src](ext_irq_ctx[src]);
            }
            IRQ_CLEAR = (1u << src);
        }
    } else {
        // Exception (illegal instr, ecall, etc.)
        // For debug: print mcause + mepc via UART
        uart_puts("EXCEPTION mcause=");
        uart_puthex(mcause);
        uart_puts(" mepc=");
        uart_puthex(mepc);
        uart_puts("\n");
        while (1);  // Halt
    }
}
```

### 11.4 Latency Budget

| IRQ Source | Max Latency | Budget | Rationale |
|------------|-------------|--------|-----------|
| Timer | 100μs | 10,000 cycles | Periodic scheduling tick |
| Audio ready [6] | 20ms | 2,000,000 cycles | MFCC stride (must process before next frame) |
| Camera ready [5] | 33ms | 3,300,000 cycles | 30fps inter-frame gap |
| NPU done [3] | 1ms | 100,000 cycles | Start next layer or signal completion |
| I2C done [7] | 10ms | 1,000,000 cycles | IMU at 100Hz sample rate |
| UART RX [1] | 1ms | 100,000 cycles | Debug console responsiveness |
| GPIO [2] | 10ms | 1,000,000 cycles | Button debouncing |

**Design Rule:** All ISR handlers must be short (< 100 cycles). Set flags and update state only. All heavy processing in main loop.

---

## 12. Real-Time Use Case Specifications

### UC-1: Wake Word Detection

**Pipeline:**
```
Microphone → I2S RX → Audio FIFO → FFT (1024-pt)
  → 40 Mel filters → Log → DCT → 10 MFCC coefficients
  → Audio DMA → DDR MFCC buffer (49 frames × 10 coeffs × 4 bytes = 1960 bytes)
  → NPU: DS-CNN inference (5-7 layers)
  → CPU reads output → classification
```

**Timing:**
- Audio frame: 40ms window, 20ms stride → new frame every 20ms
- MFCC pipeline: fully hardware, ~2ms per frame
- Feature buffer: 49 frames × 20ms = ~1 second of audio context
- NPU inference: ~5ms for DS-CNN (estimated, 5 layers × ~1ms/layer)
- Total latency: ~25ms from speech end to detection

**Firmware Flow:**
```c
void uc1_wake_word_main(void) {
    // 1. Configure audio in MFCC mode
    audio_config_t aud_cfg = {
        .mode = AUDIO_MODE_MFCC,
        .frame_size_samples = 640,     // 40ms @ 16kHz
        .frame_stride_samples = 320,   // 20ms
        .fft_log2 = 10,               // 1024-point FFT
        .num_mel_filters = 40,
        .num_mfcc_coeffs = 10,
        .dma_base_addr = 0x80160000,
        .dma_length = 49 * 10 * 4,    // 1960 bytes
        .gain = 0x100,                 // Unity gain
        .noise_floor = 1000,
    };
    hal_audio_init(&aud_cfg);

    // 2. Load DS-CNN model weights to DDR
    npu_load_model(&ds_cnn_wake_model);

    // 3. Register audio IRQ callback
    hal_audio_irq_register(audio_frame_cb, NULL);
    hal_audio_irq_enable_dma();

    // 4. Start audio pipeline
    hal_audio_start();

    // 5. Main loop
    while (1) {
        if (audio_feature_ready) {
            audio_feature_ready = false;
            // Check VAD (voice activity)
            if (hal_audio_frame_energy() > aud_cfg.noise_floor) {
                // Run NPU inference
                npu_inference_result_t result;
                npu_run_inference(&ds_cnn_wake_model, 0x80160000, &result);
                int class_id = npu_get_top_class(
                    (int8_t*)result.output_addr, NUM_WAKE_WORDS);
                if (npu_get_confidence(
                    (int8_t*)result.output_addr, class_id) > THRESHOLD) {
                    // Wake word detected!
                    hal_gpio_write(0x01, 0x01);  // LED on
                    esp32_send_result(class_id, confidence, NULL, 0);
                }
            }
        }
        __asm__ volatile("wfi");  // Sleep until next IRQ
    }
}

static volatile bool audio_feature_ready = false;

static void audio_frame_cb(void *ctx) {
    hal_audio_irq_clear_dma();
    audio_feature_ready = true;
}
```

### UC-2: Camera Object Detection

**Pipeline:**
```
OV7670 (640×480 YUV422) → DVP capture → ISP (debayer, WB, gamma)
  → Resize (640×480 → 128×128) → Camera VDMA → DDR Frame Buffer
  → NPU: MobileNet-tiny inference (10-15 layers)
  → CPU reads classification → SPI to ESP32 → WiFi/BLE
```

**Timing:**
- Frame capture: ~33ms at 30fps
- ISP + Resize: ~5ms (hardware pipeline)
- VDMA to DDR: ~0.3ms (128×128×3 = 48KB @ 400MB/s)
- NPU inference: ~20ms for MobileNet-tiny (estimated)
- SPI to ESP32: ~1ms
- Total: ~60ms per frame → effective 15-20fps inference rate

**Firmware Flow:**
```c
void uc2_object_detect_main(void) {
    // 1. Init camera sensor via I2C (SCCB)
    ov7670_init();

    // 2. Configure camera pipeline
    cam_config_t cam_cfg = {
        .src_width = 640, .src_height = 480,
        .pixel_format = 0,  // YUV422
        .out_width = 128, .out_height = 128,
        .isp_bypass = 0,
        .frame_buf_a = 0x80000000,
        .frame_buf_b = 0x8000C000,
        .continuous = 1,
    };
    hal_cam_init(&cam_cfg);

    // 3. Load MobileNet-tiny model
    npu_load_model(&mobilenet_tiny_model);

    // 4. Register camera IRQ
    hal_cam_irq_register(camera_frame_cb, NULL);
    hal_cam_irq_enable();

    // 5. Start capture
    hal_cam_start();

    // 6. Main loop
    while (1) {
        if (frame_ready) {
            frame_ready = false;
            uint32_t buf = hal_cam_get_active_buf();

            // Run NPU inference on captured frame
            npu_inference_result_t result;
            npu_run_inference(&mobilenet_tiny_model, buf, &result);

            int class_id = npu_get_top_class(
                (int8_t*)result.output_addr, NUM_CLASSES);
            int8_t conf = npu_get_confidence(
                (int8_t*)result.output_addr, class_id);

            // Send to ESP32 if confident
            if (conf > DETECTION_THRESHOLD) {
                esp32_send_result(class_id, (uint8_t)conf, NULL, 0);
            }
        }
        __asm__ volatile("wfi");
    }
}
```

### UC-3: Concurrent Audio + Camera + NPU

**Strategy:** Time-multiplex NPU between audio and camera workloads. Audio has priority (wake-word detection is always active).

**State Machine:**
```c
typedef enum {
    APP_IDLE,               // Waiting for events
    APP_AUDIO_INFERENCE,    // NPU running wake-word model
    APP_CAMERA_CAPTURE,     // Camera capturing frame
    APP_CAMERA_INFERENCE,   // NPU running object detection model
} app_state_t;

void uc3_concurrent_main(void) {
    app_state_t state = APP_IDLE;

    // Init audio (always running in background)
    // ... (same as UC-1 audio config)
    hal_audio_start();

    // Init camera (triggered periodically)
    // ... (same as UC-2 camera config, but continuous=0)

    // Set up periodic camera trigger (every 500ms)
    hal_timer_set_periodic(500000, camera_trigger_cb, NULL);

    while (1) {
        switch (state) {
            case APP_IDLE:
                if (audio_feature_ready && energy_above_threshold()) {
                    state = APP_AUDIO_INFERENCE;
                    npu_run_inference_async(&ds_cnn_model, MFCC_ADDR,
                                            audio_npu_done, &state);
                } else if (camera_trigger_flag) {
                    camera_trigger_flag = false;
                    state = APP_CAMERA_CAPTURE;
                    hal_cam_start();  // Single-shot
                }
                break;

            case APP_AUDIO_INFERENCE:
                if (npu_inference_complete()) {
                    // Process audio result
                    handle_wake_word_result();
                    state = APP_IDLE;
                }
                break;

            case APP_CAMERA_CAPTURE:
                if (frame_ready) {
                    frame_ready = false;
                    if (!audio_feature_ready) {
                        // NPU free, start camera inference
                        state = APP_CAMERA_INFERENCE;
                        npu_run_inference_async(&mobilenet_model, cam_buf,
                                                camera_npu_done, &state);
                    } else {
                        // Audio has priority → do audio first
                        state = APP_AUDIO_INFERENCE;
                        npu_run_inference_async(&ds_cnn_model, MFCC_ADDR,
                                                audio_npu_done_then_camera,
                                                &state);
                    }
                }
                break;

            case APP_CAMERA_INFERENCE:
                if (npu_inference_complete()) {
                    handle_detection_result();
                    state = APP_IDLE;
                }
                // Audio preemption check
                if (audio_feature_ready && energy_above_threshold()) {
                    // Can't preempt mid-layer, but queue for next layer gap
                    audio_pending = true;
                }
                break;
        }
        __asm__ volatile("wfi");
    }
}
```

### UC-4: I2C IMU Gesture Detection

**Pipeline:**
```
Timer (100Hz) → I2C burst read MPU6050 (14 bytes)
  → CPU ring buffer → gesture algorithm → SPI to ESP32
```

**Firmware Flow:**
```c
#define IMU_BUF_SIZE 32  // 32 samples = 320ms window

static mpu6050_data_t imu_buffer[IMU_BUF_SIZE];
static int imu_idx = 0;
static volatile bool imu_data_ready = false;

void uc4_gesture_main(void) {
    // 1. Init I2C and MPU6050
    i2c_config_t i2c_cfg = { .prescaler = 61 };  // 400kHz
    hal_i2c_init(&i2c_cfg);
    mpu6050_init();

    // 2. Verify sensor
    uint8_t who;
    mpu6050_who_am_i(&who);
    if (who != 0x68) { uart_puts("IMU FAIL\n"); while(1); }

    // 3. Set up 100Hz timer for periodic reads
    hal_timer_set_periodic(10000, imu_timer_cb, NULL);  // 10ms = 100Hz

    // 4. Main loop
    while (1) {
        if (imu_data_ready) {
            imu_data_ready = false;

            // Simple gesture detection: check for tap (sudden accel spike)
            int gesture = detect_gesture(imu_buffer, IMU_BUF_SIZE, imu_idx);
            if (gesture >= 0) {
                esp32_send_result(gesture, 100, NULL, 0);
                hal_gpio_write(0x02, 0x02);  // LED 1
                hal_timer_delay_ms(200);
                hal_gpio_write(0x02, 0x00);
            }
        }
        __asm__ volatile("wfi");
    }
}

static void imu_timer_cb(void *ctx) {
    // Read IMU data (blocking I2C, ~200μs at 400kHz for 14 bytes)
    mpu6050_read_all(&imu_buffer[imu_idx]);
    imu_idx = (imu_idx + 1) % IMU_BUF_SIZE;
    imu_data_ready = true;
}

static int detect_gesture(mpu6050_data_t *buf, int size, int head) {
    // Check last 3 samples for acceleration spike > threshold
    for (int i = 0; i < 3; i++) {
        int idx = (head - 1 - i + size) % size;
        int32_t mag = (int32_t)buf[idx].accel_x * buf[idx].accel_x
                    + (int32_t)buf[idx].accel_y * buf[idx].accel_y
                    + (int32_t)buf[idx].accel_z * buf[idx].accel_z;
        if (mag > TAP_THRESHOLD) return 1;  // Tap detected
    }
    return -1;  // No gesture
}
```

### UC-5: Boot + WiFi Initialization

**Sequence:**
```
Power On → clk_rst_mgr sequences resets → Boot ROM
  → Jump to SRAM → crt0: SP, mtvec, zero BSS, call main()
  → system_init(): UART, Timer, IRQ, GPIO
  → ESP32 init: SPI config, ping, version check
  → WiFi connect: send SSID/password, wait for connection
  → Enter operational mode
```

**Firmware Flow:**
```c
void uc5_boot_wifi_main(void) {
    // 1. System init (UART, Timer, IRQ, GPIO)
    system_init();
    uart_puts("AI Glasses SoC v1.0\n");

    // 2. LED: booting
    hal_gpio_set_dir(0x07, 0x07);  // 3 LEDs as output
    hal_gpio_write(0x01, 0x01);    // LED 0: power on

    // 3. Init ESP32
    uart_puts("ESP32 init...\n");
    hal_status_t st = esp32_init();
    if (st != HAL_OK) {
        uart_puts("ESP32 FAIL\n");
        error_blink(0x01);
    }
    uart_puts("ESP32 OK\n");

    // 4. WiFi connect
    uart_puts("WiFi connecting...\n");
    hal_gpio_write(0x02, 0x02);  // LED 1: connecting
    st = esp32_wifi_connect("SmartGlasses_AP", "password123");
    if (st != HAL_OK) {
        uart_puts("WiFi FAIL\n");
        error_blink(0x02);
    }

    // 5. Wait for connection (with timeout)
    uint32_t timeout = 10000;  // 10 seconds
    uint8_t connected = 0;
    while (timeout > 0 && !connected) {
        esp32_wifi_status(&connected);
        hal_timer_delay_ms(100);
        timeout -= 100;
    }

    if (connected) {
        uart_puts("WiFi CONNECTED\n");
        hal_gpio_write(0x04, 0x04);  // LED 2: connected
    } else {
        uart_puts("WiFi TIMEOUT\n");
        error_blink(0x04);
    }

    // 6. Enter operational mode
    uart_puts("Ready.\n");
    // ... start UC-1, UC-2, UC-4 as needed
}
```

### UC-6: Low-Power Standby + Wake

**Sequence:**
```
Running → disable peripherals → configure wake source → WFI
  → Timer/GPIO wake → re-init active subsystems → resume
```

**Firmware Flow:**
```c
typedef enum {
    WAKE_TIMER = 0,
    WAKE_GPIO  = 1
} wake_source_t;

void uc6_enter_standby(uint32_t wake_interval_s) {
    uart_puts("Entering standby...\n");
    hal_timer_delay_ms(10);  // Flush UART

    // 1. Stop active subsystems
    hal_audio_stop();
    hal_cam_stop();
    hal_npu_reset();
    esp32_sleep();

    // 2. Disable unnecessary IRQs
    hal_irq_disable(IRQ_NPU_DONE);
    hal_irq_disable(IRQ_CAM_READY);
    hal_irq_disable(IRQ_AUD_READY);
    hal_irq_disable(IRQ_I2C_DONE);

    // 3. Configure wake sources
    // Timer wake: set compare to current + interval
    if (wake_interval_s > 0) {
        uint64_t wake_time = hal_timer_get_mtime()
                           + (uint64_t)wake_interval_s * 1000000;
        hal_timer_set_compare(wake_time);
        // Enable timer interrupt
        __asm__ volatile("csrs mie, %0" :: "r"(1 << 7));
    }

    // GPIO wake: button on GPIO pin 7
    hal_gpio_irq_enable(0x80);  // Pin 7
    hal_irq_enable(IRQ_GPIO);

    // 4. WFI — CPU halts, clock gating
    __asm__ volatile("wfi");

    // 5. Woken up — determine source
    wake_source_t src = WAKE_TIMER;
    if (hal_gpio_read() & 0x80) src = WAKE_GPIO;

    // 6. Resume
    uart_puts("Wake: ");
    uart_puts(src == WAKE_GPIO ? "GPIO\n" : "Timer\n");

    // 7. Re-init subsystems as needed
    esp32_wake();
    hal_audio_start();      // Resume audio monitoring
    // Camera stays off until triggered
}
```

---

## 13. System Initialization API (`system.h`)

```c
// Full system bring-up
void system_init(void);

// Individual subsystem init (called by system_init)
void system_init_uart(void);
void system_init_irq(void);
void system_init_timer(void);
void system_init_gpio(void);

// System info
uint32_t system_get_cpu_freq(void);    // Returns 100000000
uint64_t system_get_uptime_us(void);   // mtime-based uptime

// Critical section helpers
uint32_t system_enter_critical(void);  // Disable IRQ, return old mstatus
void     system_exit_critical(uint32_t saved_mstatus);

// Soft reset
void     system_reset(void);           // Jump to boot ROM
```

---

## 14. Implementation Timeline

### Phase A: Foundation (Week 1-2)

| Task | Files | Dependencies |
|------|-------|-------------|
| Common types | `include/types.h` | None |
| Update soc_regs.h (Camera + Audio regs) | `include/soc_regs.h` | None |
| IRQ HAL | `hal/hal_irq.c/h` | types.h |
| Enhanced crt0.S trap dispatch | `crt0.S` | hal_irq |
| Timer HAL | `hal/hal_timer.c/h` | hal_irq |
| UART HAL (IRQ-driven) | `hal/hal_uart.c/h` | hal_irq |
| Linker script (DDR + sections) | `sram_exec.ld` | None |
| Makefile restructure | `Makefile` | None |
| System init | `src/system.c`, `include/system.h` | All HAL |

**Validation:** Recompile all 11 existing tests. New test: timer periodic + IRQ dispatch.

### Phase B: Peripheral HAL (Week 3-4)

| Task | Files | Dependencies |
|------|-------|-------------|
| GPIO HAL | `hal/hal_gpio.c/h` | hal_irq |
| SPI HAL | `hal/hal_spi.c/h` | None |
| I2C HAL | `hal/hal_i2c.c/h` | hal_irq |
| Camera HAL | `hal/hal_camera.c/h` | hal_irq |
| Audio HAL | `hal/hal_audio.c/h` | hal_irq |
| NPU HAL | `hal/hal_npu.c/h` | hal_irq |

**Validation:** Per-HAL test firmware: camera single-shot, audio MFCC start, NPU single-layer, I2C read, SPI transfer.

### Phase C: Device Drivers (Week 5-6)

| Task | Files | Dependencies |
|------|-------|-------------|
| ESP32 SPI protocol | `drivers/esp32_spi.c/h` | hal_spi, hal_gpio |
| MPU6050 IMU driver | `drivers/mpu6050.c/h` | hal_i2c |
| OV7670 camera init | `drivers/ov7670.c/h` | hal_i2c |
| DMA manager | `src/dma_manager.c`, `app/dma_manager.h` | hal_npu, hal_camera, hal_audio |

**Validation:** ESP32 ping, MPU6050 WHO_AM_I, OV7670 register dump.

### Phase D: NPU Inference Engine (Week 7-8)

| Task | Files | Dependencies |
|------|-------|-------------|
| Model descriptor | `npu/npu_model.c/h` | hal_npu |
| Inference API | `npu/npu_api.c/h` | hal_npu, dma_manager |
| Quantization helpers | `npu/npu_quant.h` | None |
| DS-CNN wake word model | `models/ds_cnn_wake.h` | npu_model |
| MobileNet-tiny model | `models/mobilenet_tiny.h` | npu_model |

**Validation:** Single-layer Conv2D test. Full DS-CNN inference. Output vs golden reference.

### Phase E: Application Use Cases (Week 9-12)

| Task | Files | Dependencies |
|------|-------|-------------|
| UC-5: Boot + WiFi | `apps/uc5_boot_wifi.c` | system, esp32_spi |
| UC-4: IMU Gesture | `apps/uc4_gesture.c` | mpu6050, hal_timer, esp32_spi |
| UC-1: Wake Word | `apps/uc1_wake_word.c` | hal_audio, npu_api, esp32_spi |
| UC-2: Object Detect | `apps/uc2_object_detect.c` | hal_camera, ov7670, npu_api, esp32_spi |
| UC-6: Low Power | `apps/uc6_low_power.c` | All HALs |
| UC-3: Concurrent | `apps/uc3_concurrent.c` | All HALs, dma_manager, npu_api |
| Integrated App | `apps/main_app.c` | All of the above |

---

## 15. Build System

### Makefile Structure

```makefile
# Toolchain
CC      = riscv64-unknown-elf-gcc
OBJCOPY = riscv64-unknown-elf-objcopy
OBJDUMP = riscv64-unknown-elf-objdump

CFLAGS  = -march=rv32im_zicsr -mabi=ilp32 -nostdlib -nostartfiles
CFLAGS += -ffreestanding -O2 -Wall -I include

# HAL sources
HAL_SRC = src/hal/hal_irq.c src/hal/hal_timer.c src/hal/hal_uart.c \
          src/hal/hal_gpio.c src/hal/hal_spi.c src/hal/hal_i2c.c \
          src/hal/hal_camera.c src/hal/hal_audio.c src/hal/hal_npu.c

# Driver sources
DRV_SRC = src/drivers/esp32_spi.c src/drivers/mpu6050.c src/drivers/ov7670.c

# NPU engine sources
NPU_SRC = src/npu/npu_api.c src/npu/npu_model.c

# System sources
SYS_SRC = src/system.c src/dma_manager.c

# All library sources
LIB_SRC = $(HAL_SRC) $(DRV_SRC) $(NPU_SRC) $(SYS_SRC)

# Application targets
APPS = uc1_wake_word uc2_object_detect uc3_concurrent \
       uc4_gesture uc5_boot_wifi uc6_low_power main_app

# Build rules
build/%.elf: apps/%.c crt0.S $(LIB_SRC)
    $(CC) $(CFLAGS) -T sram_exec.ld crt0.S $< $(LIB_SRC) -o $@

build/%.hex: build/%.elf
    $(OBJCOPY) -O verilog --verilog-data-width=4 \
        --change-addresses=-0x10000000 $< $@

# Build all apps
apps: $(addprefix build/,$(addsuffix .hex,$(APPS)))

# Existing test targets remain unchanged
```

---

## 16. Testing Strategy for Firmware

### Unit Tests (per HAL module)

| Test | Verifies |
|------|----------|
| test_hal_irq | Callback dispatch, enable/disable, clear, global enable |
| test_hal_timer | Periodic callback, delay_us accuracy, one-shot |
| test_hal_spi | Config write/read, transfer bytes, FIFO status |
| test_hal_i2c | Write/read transaction, NACK detection, burst read |
| test_hal_camera | Single-shot capture, status polling, performance counters |
| test_hal_audio | MFCC config, start/stop, frame energy readback |
| test_hal_npu | Layer config, start, busy/done polling, perf counter |

### Integration Tests (per use case)

| Test | Verifies |
|------|----------|
| test_uc1_audio_npu | Audio MFCC → NPU inference chain |
| test_uc2_cam_npu | Camera capture → NPU inference chain |
| test_uc3_concurrent | Multi-DMA, NPU time-multiplexing |
| test_uc4_imu | I2C read at 100Hz, gesture detection |
| test_uc5_boot | Full boot sequence, ESP32 SPI handshake |
| test_uc6_power | WFI entry/exit, wake source detection |

### System Test

| Test | Verifies |
|------|----------|
| test_full_system | All use cases together, 60-second run, no hangs/errors |

---

## Appendix A: Camera Register Definitions for soc_regs.h

```c
// Camera Controller Registers (Slot 4, Base 0x20000400)
#define CAM_CONTROL       REG32(CAMERA_BASE + 0x00)
#define CAM_STATUS        REG32(CAMERA_BASE + 0x04)
#define CAM_FRAME_WIDTH   REG32(CAMERA_BASE + 0x08)
#define CAM_FRAME_HEIGHT  REG32(CAMERA_BASE + 0x0C)
#define CAM_PIXEL_FORMAT  REG32(CAMERA_BASE + 0x10)
#define CAM_ISP_WB_R      REG32(CAMERA_BASE + 0x14)
#define CAM_ISP_WB_G      REG32(CAMERA_BASE + 0x18)
#define CAM_ISP_WB_B      REG32(CAMERA_BASE + 0x1C)
#define CAM_ISP_GAMMA     REG32(CAMERA_BASE + 0x20)
#define CAM_RESIZE_OUT_W  REG32(CAMERA_BASE + 0x24)
#define CAM_RESIZE_OUT_H  REG32(CAMERA_BASE + 0x28)
#define CAM_CROP_X        REG32(CAMERA_BASE + 0x2C)
#define CAM_CROP_Y        REG32(CAMERA_BASE + 0x30)
#define CAM_CROP_W        REG32(CAMERA_BASE + 0x34)
#define CAM_CROP_H        REG32(CAMERA_BASE + 0x38)
#define CAM_DMA_BASE_A    REG32(CAMERA_BASE + 0x3C)
#define CAM_DMA_BASE_B    REG32(CAMERA_BASE + 0x40)
#define CAM_DMA_STRIDE    REG32(CAMERA_BASE + 0x44)
#define CAM_IRQ_CLEAR     REG32(CAMERA_BASE + 0x48)
#define CAM_FRAME_COUNT   REG32(CAMERA_BASE + 0x4C)
#define CAM_PERF_CAPTURE  REG32(CAMERA_BASE + 0x50)
#define CAM_PERF_ISP      REG32(CAMERA_BASE + 0x54)
#define CAM_PERF_RESIZE   REG32(CAMERA_BASE + 0x58)
#define CAM_PERF_CROP     REG32(CAMERA_BASE + 0x5C)
```

## Appendix B: Audio Register Definitions for soc_regs.h

```c
// Audio Controller Registers (Slot 5, Base 0x20000500)
#define AUD_CONTROL       REG32(AUDIO_BASE + 0x00)
#define AUD_STATUS        REG32(AUDIO_BASE + 0x04)
#define AUD_SAMPLE_RATE   REG32(AUDIO_BASE + 0x08)
#define AUD_FRAME_SIZE    REG32(AUDIO_BASE + 0x0C)
#define AUD_FRAME_STRIDE  REG32(AUDIO_BASE + 0x10)
#define AUD_FFT_SIZE      REG32(AUDIO_BASE + 0x14)
#define AUD_NUM_MEL       REG32(AUDIO_BASE + 0x18)
#define AUD_NUM_MFCC      REG32(AUDIO_BASE + 0x1C)
#define AUD_DMA_BASE      REG32(AUDIO_BASE + 0x20)
#define AUD_DMA_LENGTH    REG32(AUDIO_BASE + 0x24)
#define AUD_DMA_WR_PTR    REG32(AUDIO_BASE + 0x28)
#define AUD_GAIN          REG32(AUDIO_BASE + 0x2C)
#define AUD_NOISE_FLOOR   REG32(AUDIO_BASE + 0x30)
#define AUD_IRQ_CLEAR     REG32(AUDIO_BASE + 0x34)
#define AUD_PERF_CYCLES   REG32(AUDIO_BASE + 0x38)
#define AUD_FRAME_ENERGY  REG32(AUDIO_BASE + 0x3C)
```
