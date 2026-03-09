/* Boot ROM linker script — code placed at 0x00000000 */
OUTPUT_ARCH(riscv)
ENTRY(_boot_start)

MEMORY {
    ROM (rx) : ORIGIN = 0x00000000, LENGTH = 4K
}

SECTIONS {
    .text : { *(.text*) } > ROM
}
