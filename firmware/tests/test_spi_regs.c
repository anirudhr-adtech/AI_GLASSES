// ================================================================
// L3-008: SPI Register Access Test
// ================================================================
// Verifies: CPU can configure SPI master through AXI-Lite fabric.
//           Tests config register write/readback and status read.
// Pass criteria: Config readback matches → "PASS".
// ================================================================

#include "soc_regs.h"
#include "uart.h"

static int errors;

void main(void) {
    UART_BAUDDIV = 868;
    uart_puts("L3-008\n");
    errors = 0;

    // Write SPI config: div=10, cpol=0, cpha=0, auto_cs=1
    unsigned int cfg = (10 & 0xFF) | (1 << 10); // div=10, auto_cs=1
    SPI_CONFIG = cfg;
    unsigned int readback = SPI_CONFIG;
    if (readback != cfg) {
        uart_puts("F1\n");
        errors++;
    }

    // Check STATUS is readable (should show TX empty, RX empty)
    unsigned int status = SPI_STATUS;
    if (!(status & SPI_STATUS_TX_EMPTY)) {
        uart_puts("F2\n");
        errors++;
    }

    // Write CS register
    SPI_CS = 1;
    readback = SPI_CS;
    if ((readback & 1) != 1) {
        uart_puts("F3\n");
        errors++;
    }

    if (errors == 0) {
        uart_puts("PASS\n");
    } else {
        uart_puts("FAIL\n");
    }
    while (1);
}
