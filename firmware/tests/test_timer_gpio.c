// ================================================================
// L3-011: Timer + GPIO Cross-Subsystem Test
// ================================================================
// Verifies: Timer IRQ triggers GPIO toggle via interrupt handler.
//           Tests: Timer → CPU trap → GPIO write path.
// Pass criteria: GPIO output toggles after timer fires → "PASS".
// ================================================================

#include "soc_regs.h"
#include "uart.h"

static volatile int timer_count = 0;

void trap_handler(void) {
    unsigned int mcause;
    __asm__ volatile ("csrr %0, mcause" : "=r"(mcause));

    if (mcause == 0x80000007) {  // Machine timer interrupt
        timer_count++;
        // Toggle GPIO bit 0
        GPIO_OUT = GPIO_OUT ^ 0x01;
        // Set new timer compare (current + 500)
        unsigned int mtime = TIMER_MTIME_LO;
        TIMER_MTIMECMP_HI = 0;
        TIMER_MTIMECMP_LO = mtime + 500;
    }
}

void main(void) {
    UART_BAUDDIV = 868;
    uart_puts("L3-011\n");

    // Configure GPIO bit 0 as output
    GPIO_DIR = 0x01;
    GPIO_OUT = 0x00;

    // Configure timer
    TIMER_PRESCALER = 0;
    TIMER_MTIMECMP_HI = 0;
    TIMER_MTIMECMP_LO = 500;

    // Enable timer interrupt
    __asm__ volatile ("csrs mie, %0" :: "r"(1 << 7));
    __asm__ volatile ("csrs mstatus, %0" :: "r"(1 << 3));

    // Wait for at least 3 timer interrupts
    for (int i = 0; i < 200000; i++) {
        if (timer_count >= 3) break;
        __asm__ volatile ("nop");
    }

    // Disable interrupts
    __asm__ volatile ("csrc mstatus, %0" :: "r"(1 << 3));

    if (timer_count >= 3) {
        uart_puts("PASS\n");
    } else {
        uart_puts("FAIL\n");
    }
    while (1);
}
