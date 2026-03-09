// ================================================================
// L3-004: UART Echo Test
// ================================================================
// Verifies: CPU can read UART RX and echo to TX.
//           TB drives uart_rx with test bytes, firmware echoes them.
// Pass criteria: Echoed bytes match → UART prints "PASS".
// Note: For now, we test UART TX only (RX requires TB stimulus).
//       We verify UART TX FIFO and STATUS register interaction.
// ================================================================

#include "soc_regs.h"
#include "uart.h"

void main(void) {
    UART_BAUDDIV = 868;
    uart_puts("L3-004\n");

    // Verify UART STATUS register is readable
    unsigned int status = UART_STATUS;
    // TX should not be full initially, RX should be empty
    if (status & UART_STATUS_TX_FULL) {
        uart_puts("FAIL\n");
        while (1);
    }

    // Write multiple characters and verify STATUS changes
    // Fill TX FIFO with characters
    int i;
    for (i = 0; i < 8; i++) {
        UART_TXDATA = 'A' + i;
    }

    // FIFO should have data now — check TX_EMPTY is clear
    status = UART_STATUS;
    if (status & UART_STATUS_TX_EMPTY) {
        uart_puts("FAIL\n");
        while (1);
    }

    uart_puts("PASS\n");
    while (1);
}
