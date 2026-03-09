// ================================================================
// L3-009: I2C Register Access Test
// ================================================================
// Verifies: CPU can configure I2C master through AXI-Lite fabric.
//           Tests prescaler write/readback and status read.
// Pass criteria: Prescaler readback matches → "PASS".
// ================================================================

#include "soc_regs.h"
#include "uart.h"

static int errors;

void main(void) {
    UART_BAUDDIV = 868;
    uart_puts("L3-009\n");
    errors = 0;

    // Write I2C prescaler for 400kHz (100MHz / (4*400kHz) - 1 = 61)
    I2C_PRESCALER = 61;
    unsigned int readback = I2C_PRESCALER;
    if ((readback & 0xFFFF) != 61) {
        uart_puts("F1\n");
        errors++;
    }

    // Enable I2C
    I2C_CONTROL = 0x01;
    readback = I2C_CONTROL;
    if ((readback & 0x01) != 1) {
        uart_puts("F2\n");
        errors++;
    }

    // Check STATUS is readable (should not be busy)
    unsigned int status = I2C_STATUS;
    if (status & I2C_STATUS_BUSY) {
        uart_puts("F3\n");
        errors++;
    }

    // Set slave address
    I2C_SLAVE_ADDR = 0x50; // EEPROM typical address
    readback = I2C_SLAVE_ADDR;
    if ((readback & 0xFF) != 0x50) {
        uart_puts("F4\n");
        errors++;
    }

    if (errors == 0) {
        uart_puts("PASS\n");
    } else {
        uart_puts("FAIL\n");
    }
    while (1);
}
