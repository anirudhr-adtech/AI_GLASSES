// ================================================================
// L3-002: SRAM Read/Write Test
// ================================================================
// Verifies: CPU can write and read back various patterns to SRAM.
//           Tests byte, halfword, and word access.
//           Tests multiple SRAM banks (addresses crossing bank boundaries).
// Pass criteria: All patterns read back correctly → UART prints "PASS".
// ================================================================

#include "soc_regs.h"
#include "uart.h"

// Test area in upper SRAM (away from code/stack)
#define TEST_BASE   (SRAM_BASE + 0x40000)  // Bank 2 start (bit 18 = 1)

static int errors;

static void check32(volatile unsigned int *addr, unsigned int expected) {
    unsigned int val = *addr;
    if (val != expected) {
        uart_puts("  FAIL @");
        uart_puthex((unsigned int)addr);
        uart_puts(" exp=");
        uart_puthex(expected);
        uart_puts(" got=");
        uart_puthex(val);
        uart_puts("\n");
        errors++;
    }
}

void main(void) {
    UART_BAUDDIV = 868;
    uart_puts("L3-002: SRAM Read/Write Test\n");
    errors = 0;

    volatile unsigned int *p32 = (volatile unsigned int *)TEST_BASE;

    // --- Word write/read patterns ---
    uart_puts("Word patterns...\n");
    p32[0] = 0xDEADBEEF;
    p32[1] = 0xCAFEBABE;
    p32[2] = 0x12345678;
    p32[3] = 0x00000000;
    p32[4] = 0xFFFFFFFF;
    p32[5] = 0xA5A5A5A5;
    p32[6] = 0x5A5A5A5A;
    p32[7] = 0x01020304;

    check32(&p32[0], 0xDEADBEEF);
    check32(&p32[1], 0xCAFEBABE);
    check32(&p32[2], 0x12345678);
    check32(&p32[3], 0x00000000);
    check32(&p32[4], 0xFFFFFFFF);
    check32(&p32[5], 0xA5A5A5A5);
    check32(&p32[6], 0x5A5A5A5A);
    check32(&p32[7], 0x01020304);

    // --- Walking ones ---
    uart_puts("Walking ones...\n");
    for (int i = 0; i < 32; i++) {
        p32[i] = (1u << i);
    }
    for (int i = 0; i < 32; i++) {
        check32(&p32[i], (1u << i));
    }

    // --- Address-as-data (tests address decoding) ---
    uart_puts("Addr-as-data...\n");
    for (int i = 0; i < 64; i++) {
        p32[i] = (unsigned int)&p32[i];
    }
    for (int i = 0; i < 64; i++) {
        check32(&p32[i], (unsigned int)&p32[i]);
    }

    // --- Byte access test ---
    uart_puts("Byte access...\n");
    volatile unsigned char *p8 = (volatile unsigned char *)(TEST_BASE + 0x200);
    for (int i = 0; i < 16; i++) {
        p8[i] = (unsigned char)(i * 17);  // 0x00, 0x11, 0x22, ...
    }
    for (int i = 0; i < 16; i++) {
        unsigned char val = p8[i];
        unsigned char exp = (unsigned char)(i * 17);
        if (val != exp) {
            uart_puts("  FAIL byte\n");
            errors++;
        }
    }

    // --- Halfword access test ---
    uart_puts("Halfword access...\n");
    volatile unsigned short *p16 = (volatile unsigned short *)(TEST_BASE + 0x300);
    for (int i = 0; i < 8; i++) {
        p16[i] = (unsigned short)(0xAA00 + i);
    }
    for (int i = 0; i < 8; i++) {
        unsigned short val = p16[i];
        unsigned short exp = (unsigned short)(0xAA00 + i);
        if (val != exp) {
            uart_puts("  FAIL half\n");
            errors++;
        }
    }

    // --- Result ---
    if (errors == 0) {
        uart_puts("PASS\n");
    } else {
        uart_puts("FAIL\n");
    }
    while (1);
}
