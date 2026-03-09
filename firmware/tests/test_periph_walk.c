// ================================================================
// L3-003: Peripheral Register Walk Test
// ================================================================
// Verifies: CPU can access all 9 peripheral slots through the
//           AXI-Lite fabric. Reads register offset 0x00 from each.
// Pass criteria: No bus hang → UART prints "PASS".
// ================================================================

#include "soc_regs.h"
#include "uart.h"

static int errors;

static void test_slot(const char *name, unsigned int base) {
    volatile unsigned int val;

    // Read offset 0x00 (usually a status/data register)
    val = REG32(base);
    (void)val; // Just verify access doesn't hang

    // Read offset 0x08 (another register)
    val = REG32(base + 0x08);
    (void)val;

    uart_putc('.');
}

void main(void) {
    UART_BAUDDIV = 868;
    uart_puts("L3-003\n");
    errors = 0;

    // Walk all 9 peripheral slots — just read, don't modify UART baud
    test_slot("UART", UART_BASE);
    test_slot("TMR",  TIMER_BASE);
    test_slot("IRQ",  IRQ_BASE);
    test_slot("GPIO", GPIO_BASE);
    test_slot("CAM",  CAMERA_BASE);
    test_slot("AUD",  AUDIO_BASE);
    test_slot("I2C",  I2C_BASE);
    test_slot("SPI",  SPI_BASE);
    test_slot("NPU",  NPU_BASE);

    uart_puts("\nPASS\n");
    while (1);
}
