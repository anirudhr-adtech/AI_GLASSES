// ================================================================
// L3-005: Timer Interrupt Test
// ================================================================
// Verifies: Timer counts up, fires IRQ when mtime >= mtimecmp,
//           CPU trap handler runs, clears interrupt.
// Pass criteria: Trap handler runs and sets flag → UART prints "PASS".
// ================================================================

#include "soc_regs.h"
#include "uart.h"

// IRQ source bit assignments
#define IRQ_SRC_TIMER   4  // Timer via irq_dma_done_i? Let me check...

// Actually, timer IRQ goes directly to ibex_core's irq_timer_i, not through IRQ controller.
// So we need to use CSR mie bit 7 (MTIE) and mip bit 7 (MTIP).

static volatile int timer_fired = 0;

// This is called from crt0.S trap handler
void trap_handler(void) {
    unsigned int mcause;
    __asm__ volatile ("csrr %0, mcause" : "=r"(mcause));

    if (mcause == 0x80000007) {  // Machine timer interrupt
        timer_fired = 1;
        // Disable timer interrupt to prevent re-entry
        // Clear MIE.MTIE (bit 7)
        __asm__ volatile ("csrc mie, %0" :: "r"(1 << 7));
    }
}

void main(void) {
    UART_BAUDDIV = 868;
    uart_puts("L3-005\n");

    // Set prescaler to 0 (mtime increments every clock cycle)
    TIMER_PRESCALER = 0;

    // Set mtimecmp to a small value (fire after ~1000 cycles)
    TIMER_MTIMECMP_HI = 0;
    TIMER_MTIMECMP_LO = 1000;

    // Enable machine timer interrupt: mie.MTIE = bit 7
    __asm__ volatile ("csrs mie, %0" :: "r"(1 << 7));
    // Enable global interrupts: mstatus.MIE = bit 3
    __asm__ volatile ("csrs mstatus, %0" :: "r"(1 << 3));

    // Wait for interrupt (with timeout)
    for (int i = 0; i < 100000; i++) {
        if (timer_fired) break;
        __asm__ volatile ("nop");
    }

    if (timer_fired) {
        uart_puts("PASS\n");
    } else {
        uart_puts("FAIL\n");
    }
    while (1);
}
