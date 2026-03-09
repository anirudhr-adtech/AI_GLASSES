// ================================================================
// L3-012: Multi-Peripheral Concurrent Access Test
// ================================================================
// Verifies: CPU can rapidly switch between multiple peripherals
//           through the AXI-Lite fabric without bus conflicts.
//           Tests: UART + GPIO + Timer + SPI config in rapid sequence.
// Pass criteria: All register values consistent → "PASS".
// ================================================================

#include "soc_regs.h"
#include "uart.h"

static int errors;

void main(void) {
    UART_BAUDDIV = 868;
    uart_puts("L3-012\n");
    errors = 0;

    // Configure multiple peripherals in rapid succession
    GPIO_DIR = 0xFF;
    GPIO_OUT = 0xAA;
    SPI_CONFIG = 0x40A; // div=10, auto_cs=1
    TIMER_PRESCALER = 99;

    // Read back all in rapid succession
    unsigned int gpio_dir = GPIO_DIR;
    unsigned int gpio_out = GPIO_OUT;
    unsigned int spi_cfg  = SPI_CONFIG;
    unsigned int tim_pre  = TIMER_PRESCALER;

    if ((gpio_dir & 0xFF) != 0xFF) errors++;
    if ((gpio_out & 0xFF) != 0xAA) errors++;
    if (spi_cfg != 0x40A) errors++;
    if (tim_pre != 99) errors++;

    // Interleaved read/write pattern (stress the fabric)
    for (int i = 0; i < 16; i++) {
        GPIO_OUT = i;
        SPI_CONFIG = (i << 0) | (1 << 10);
        unsigned int g = GPIO_OUT;
        unsigned int s = SPI_CONFIG;
        if ((g & 0xFF) != (unsigned int)(i & 0xFF)) errors++;
        if (s != (unsigned int)((i & 0xFF) | (1 << 10))) errors++;
    }

    if (errors == 0) {
        uart_puts("PASS\n");
    } else {
        uart_puts("FAIL\n");
    }
    while (1);
}
