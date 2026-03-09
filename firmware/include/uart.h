#ifndef UART_H
#define UART_H

#include "soc_regs.h"

static inline void uart_putc(char c) {
    // Wait until TX FIFO is not full
    while (UART_STATUS & UART_STATUS_TX_FULL);
    UART_TXDATA = (unsigned int)c;
}

static inline void uart_puts(const char *s) {
    while (*s) {
        uart_putc(*s++);
    }
}

static inline void uart_puthex(unsigned int val) {
    const char hex[] = "0123456789ABCDEF";
    int i;
    uart_puts("0x");
    for (i = 28; i >= 0; i -= 4) {
        uart_putc(hex[(val >> i) & 0xF]);
    }
}

static inline int uart_getc(void) {
    unsigned int rx;
    // Wait until RX FIFO is not empty
    while (1) {
        rx = UART_RXDATA;
        if (!(rx & (1 << 31)))  // bit 31 = empty flag
            return (int)(rx & 0xFF);
    }
}

#endif // UART_H
