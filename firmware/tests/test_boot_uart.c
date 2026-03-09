// ================================================================
// L3-001: Boot + UART Test
// ================================================================
// Verifies: CPU boots from ROM, jumps to SRAM, executes C code,
//           writes to UART peripheral through AXI-Lite fabric.
// Pass criteria: UART monitor in TB sees "PASS" string.
// ================================================================

#include "soc_regs.h"
#include "uart.h"

void main(void) {
    // Configure baud rate (100MHz / 868 ≈ 115200 baud)
    UART_BAUDDIV = 868;

    // Print test banner
    uart_puts("L3-001: Boot + UART Test\n");

    // Simple register read test — read UART status
    (void)UART_STATUS;

    // If we got here, boot + SRAM exec + peripheral access all work
    uart_puts("PASS\n");

    // Halt
    while (1);
}
