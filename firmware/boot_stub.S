# ================================================================
# AI Glasses SoC — Boot ROM Stub
# ================================================================
# This is the first code executed by the CPU at address 0x00000000.
# It sets the stack pointer and jumps to SRAM entry point.
# ================================================================

    .section .text
    .global _boot_start

_boot_start:
    # Set stack pointer to top of SRAM (0x10080000)
    lui     sp, 0x10080

    # Jump to SRAM entry point (0x10000000)
    lui     t0, 0x10000
    jalr    zero, t0, 0

    # Should never reach here
    j       _boot_start
