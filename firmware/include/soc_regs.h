#ifndef SOC_REGS_H
#define SOC_REGS_H

// ================================================================
// AI Glasses SoC — Memory Map
// ================================================================
#define BOOT_ROM_BASE       0x00000000
#define SRAM_BASE           0x10000000
#define SRAM_SIZE           0x00080000  // 512 KB
#define SRAM_TOP            (SRAM_BASE + SRAM_SIZE)
#define PERIPH_BASE         0x20000000
#define DDR_BASE            0x80000000

// ================================================================
// Peripheral Base Addresses (AXI-Lite slots, 256B each)
// ================================================================
#define UART_BASE           (PERIPH_BASE + 0x000)
#define TIMER_BASE          (PERIPH_BASE + 0x100)
#define IRQ_BASE            (PERIPH_BASE + 0x200)
#define GPIO_BASE           (PERIPH_BASE + 0x300)
#define CAMERA_BASE         (PERIPH_BASE + 0x400)
#define AUDIO_BASE          (PERIPH_BASE + 0x500)
#define I2C_BASE            (PERIPH_BASE + 0x600)
#define SPI_BASE            (PERIPH_BASE + 0x700)
#define NPU_BASE            (PERIPH_BASE + 0x800)

// ================================================================
// UART Registers (Slot 0)
// ================================================================
#define UART_TXDATA         (*(volatile unsigned int *)(UART_BASE + 0x00))
#define UART_RXDATA         (*(volatile unsigned int *)(UART_BASE + 0x04))
#define UART_STATUS         (*(volatile unsigned int *)(UART_BASE + 0x08))
#define UART_BAUDDIV        (*(volatile unsigned int *)(UART_BASE + 0x0C))
#define UART_IRQ_ENABLE     (*(volatile unsigned int *)(UART_BASE + 0x10))

// UART STATUS bits
#define UART_STATUS_TX_FULL  (1 << 0)
#define UART_STATUS_TX_EMPTY (1 << 1)
#define UART_STATUS_RX_FULL  (1 << 2)
#define UART_STATUS_RX_EMPTY (1 << 3)

// ================================================================
// Timer Registers (Slot 1) — CLINT
// ================================================================
#define TIMER_MTIME_LO      (*(volatile unsigned int *)(TIMER_BASE + 0x00))
#define TIMER_MTIME_HI      (*(volatile unsigned int *)(TIMER_BASE + 0x04))
#define TIMER_MTIMECMP_LO   (*(volatile unsigned int *)(TIMER_BASE + 0x08))
#define TIMER_MTIMECMP_HI   (*(volatile unsigned int *)(TIMER_BASE + 0x0C))
#define TIMER_PRESCALER     (*(volatile unsigned int *)(TIMER_BASE + 0x10))

// ================================================================
// IRQ Controller Registers (Slot 2)
// ================================================================
#define IRQ_PENDING         (*(volatile unsigned int *)(IRQ_BASE + 0x00))
#define IRQ_ENABLE          (*(volatile unsigned int *)(IRQ_BASE + 0x04))
#define IRQ_CLEAR           (*(volatile unsigned int *)(IRQ_BASE + 0x08))
#define IRQ_TYPE            (*(volatile unsigned int *)(IRQ_BASE + 0x0C))
#define IRQ_STATUS          (*(volatile unsigned int *)(IRQ_BASE + 0x10))
#define IRQ_HIGHEST         (*(volatile unsigned int *)(IRQ_BASE + 0x14))

// ================================================================
// GPIO Registers (Slot 3)
// ================================================================
#define GPIO_DIR            (*(volatile unsigned int *)(GPIO_BASE + 0x00))
#define GPIO_OUT            (*(volatile unsigned int *)(GPIO_BASE + 0x04))
#define GPIO_IN             (*(volatile unsigned int *)(GPIO_BASE + 0x08))
#define GPIO_IRQ_ENABLE     (*(volatile unsigned int *)(GPIO_BASE + 0x0C))
#define GPIO_IRQ_PEND       (*(volatile unsigned int *)(GPIO_BASE + 0x10))

// ================================================================
// SPI Registers (Slot 7)
// ================================================================
#define SPI_TXDATA          (*(volatile unsigned int *)(SPI_BASE + 0x00))
#define SPI_RXDATA          (*(volatile unsigned int *)(SPI_BASE + 0x04))
#define SPI_STATUS          (*(volatile unsigned int *)(SPI_BASE + 0x08))
#define SPI_CONFIG          (*(volatile unsigned int *)(SPI_BASE + 0x0C))
#define SPI_CS              (*(volatile unsigned int *)(SPI_BASE + 0x10))
#define SPI_IRQ_EN          (*(volatile unsigned int *)(SPI_BASE + 0x14))
#define SPI_TX_FIFO_CNT     (*(volatile unsigned int *)(SPI_BASE + 0x18))
#define SPI_RX_FIFO_CNT     (*(volatile unsigned int *)(SPI_BASE + 0x1C))

// SPI STATUS bits
#define SPI_STATUS_BUSY      (1 << 0)
#define SPI_STATUS_TX_FULL   (1 << 1)
#define SPI_STATUS_TX_EMPTY  (1 << 2)
#define SPI_STATUS_RX_FULL   (1 << 3)
#define SPI_STATUS_RX_EMPTY  (1 << 4)

// ================================================================
// I2C Registers (Slot 6)
// ================================================================
#define I2C_CONTROL         (*(volatile unsigned int *)(I2C_BASE + 0x00))
#define I2C_STATUS          (*(volatile unsigned int *)(I2C_BASE + 0x04))
#define I2C_SLAVE_ADDR      (*(volatile unsigned int *)(I2C_BASE + 0x08))
#define I2C_TXDATA          (*(volatile unsigned int *)(I2C_BASE + 0x0C))
#define I2C_RXDATA          (*(volatile unsigned int *)(I2C_BASE + 0x10))
#define I2C_XFER_LEN        (*(volatile unsigned int *)(I2C_BASE + 0x14))
#define I2C_START           (*(volatile unsigned int *)(I2C_BASE + 0x18))
#define I2C_PRESCALER       (*(volatile unsigned int *)(I2C_BASE + 0x1C))
#define I2C_IRQ_CLEAR       (*(volatile unsigned int *)(I2C_BASE + 0x20))
#define I2C_FIFO_STATUS     (*(volatile unsigned int *)(I2C_BASE + 0x24))

// I2C STATUS bits
#define I2C_STATUS_BUSY      (1 << 0)
#define I2C_STATUS_DONE      (1 << 1)
#define I2C_STATUS_NACK      (1 << 2)

// ================================================================
// NPU Registers (Slot 8)
// ================================================================
#define NPU_CONTROL         (*(volatile unsigned int *)(NPU_BASE + 0x00))
#define NPU_STATUS          (*(volatile unsigned int *)(NPU_BASE + 0x04))
#define NPU_INPUT_ADDR      (*(volatile unsigned int *)(NPU_BASE + 0x08))
#define NPU_WEIGHT_ADDR     (*(volatile unsigned int *)(NPU_BASE + 0x0C))
#define NPU_OUTPUT_ADDR     (*(volatile unsigned int *)(NPU_BASE + 0x10))
#define NPU_INPUT_SIZE      (*(volatile unsigned int *)(NPU_BASE + 0x14))
#define NPU_WEIGHT_SIZE     (*(volatile unsigned int *)(NPU_BASE + 0x18))
#define NPU_OUTPUT_SIZE     (*(volatile unsigned int *)(NPU_BASE + 0x1C))
#define NPU_LAYER_CONFIG    (*(volatile unsigned int *)(NPU_BASE + 0x20))
#define NPU_CONV_CONFIG     (*(volatile unsigned int *)(NPU_BASE + 0x24))
#define NPU_TENSOR_DIMS     (*(volatile unsigned int *)(NPU_BASE + 0x28))
#define NPU_QUANT_PARAM     (*(volatile unsigned int *)(NPU_BASE + 0x2C))
#define NPU_START           (*(volatile unsigned int *)(NPU_BASE + 0x30))
#define NPU_IRQ_CLEAR       (*(volatile unsigned int *)(NPU_BASE + 0x34))
#define NPU_PERF_CYCLES     (*(volatile unsigned int *)(NPU_BASE + 0x38))
#define NPU_DMA_STATUS      (*(volatile unsigned int *)(NPU_BASE + 0x3C))

// ================================================================
// Helper macros
// ================================================================
#define REG32(addr)  (*(volatile unsigned int *)(addr))

#endif // SOC_REGS_H
