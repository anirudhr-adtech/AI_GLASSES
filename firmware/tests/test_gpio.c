// ================================================================
// L3-006: GPIO I/O Test
// ================================================================
// Verifies: CPU can set GPIO direction, write output pattern,
//           read back via GPIO_IN (TB loops gpio_o → gpio_i).
// Pass criteria: Read-back matches written pattern → "PASS".
// ================================================================

#include "soc_regs.h"
#include "uart.h"

static int errors;

void main(void) {
    UART_BAUDDIV = 868;
    uart_puts("L3-006\n");
    errors = 0;

    // Set all 8 pins as output
    GPIO_DIR = 0xFF;

    // Write test patterns and verify readback
    // Note: TB must loop gpio_o back to gpio_i for this to work
    unsigned int patterns[] = {0xAA, 0x55, 0x0F, 0xF0, 0xFF, 0x00, 0x01, 0x80};
    int num_patterns = sizeof(patterns) / sizeof(patterns[0]);

    for (int i = 0; i < num_patterns; i++) {
        GPIO_OUT = patterns[i];
        // Small delay for synchronizer (2 cycles + AXI latency)
        __asm__ volatile ("nop; nop; nop; nop; nop; nop; nop; nop");
        __asm__ volatile ("nop; nop; nop; nop; nop; nop; nop; nop");
        unsigned int val = GPIO_IN;
        if ((val & 0xFF) != patterns[i]) {
            uart_puts("F");
            errors++;
        }
    }

    if (errors == 0) {
        uart_puts("PASS\n");
    } else {
        uart_puts("FAIL\n");
    }
    while (1);
}
