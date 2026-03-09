// ================================================================
// L3-010: NPU Register Access Test
// ================================================================
// Verifies: CPU can configure NPU through AXI-Lite fabric.
//           Tests address/config register write/readback.
// Pass criteria: All readbacks match → "PASS".
// ================================================================

#include "soc_regs.h"
#include "uart.h"

static int errors;

static void check(const char *tag, unsigned int got, unsigned int exp) {
    if (got != exp) {
        uart_puts(tag);
        errors++;
    }
}

void main(void) {
    UART_BAUDDIV = 868;
    uart_puts("L3-010\n");
    errors = 0;

    // Write and readback all address registers
    NPU_INPUT_ADDR  = 0x80000000;
    NPU_WEIGHT_ADDR = 0x80010000;
    NPU_OUTPUT_ADDR = 0x80020000;

    check("F1", NPU_INPUT_ADDR,  0x80000000);
    check("F2", NPU_WEIGHT_ADDR, 0x80010000);
    check("F3", NPU_OUTPUT_ADDR, 0x80020000);

    // Write and readback size registers
    NPU_INPUT_SIZE  = 1024;
    NPU_WEIGHT_SIZE = 2048;
    NPU_OUTPUT_SIZE = 512;

    check("F4", NPU_INPUT_SIZE,  1024);
    check("F5", NPU_WEIGHT_SIZE, 2048);
    check("F6", NPU_OUTPUT_SIZE, 512);

    // Write and readback config registers
    NPU_LAYER_CONFIG = 0x00010002; // relu + 2x2 pool
    NPU_CONV_CONFIG  = 0x00030101; // 3x3 kernel, stride 1, pad 1
    NPU_TENSOR_DIMS  = 0x001C001C; // 28x28

    check("F7", NPU_LAYER_CONFIG, 0x00010002);
    check("F8", NPU_CONV_CONFIG,  0x00030101);
    check("F9", NPU_TENSOR_DIMS,  0x001C001C);

    // Read STATUS (should be idle)
    unsigned int status = NPU_STATUS;
    (void)status;

    // Read PERF_CYCLES (should be 0 or some value)
    unsigned int perf = NPU_PERF_CYCLES;
    (void)perf;

    if (errors == 0) {
        uart_puts("PASS\n");
    } else {
        uart_puts("FAIL\n");
    }
    while (1);
}
