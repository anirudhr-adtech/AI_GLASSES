/* ================================================================
 * AI Glasses SoC — Linker Script (SRAM Execution)
 * Code and data placed in SRAM at 0x10000000.
 * Boot ROM at 0x0 handles initial jump to SRAM.
 * ================================================================ */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    SRAM (rwx)  : ORIGIN = 0x10000000, LENGTH = 512K
}

SECTIONS {
    .text : {
        *(.text.start)    /* _start must be first */
        *(.text.trap)     /* trap handler */
        *(.text*)
    } > SRAM

    .rodata : {
        *(.rodata*)
        *(.srodata*)
    } > SRAM

    .data : {
        *(.data*)
        *(.sdata*)
    } > SRAM

    .bss (NOLOAD) : {
        __bss_start = .;
        *(.bss*)
        *(.sbss*)
        *(COMMON)
        __bss_end = .;
    } > SRAM

    /* Stack at top of SRAM */
    _stack_top = ORIGIN(SRAM) + LENGTH(SRAM);
}
