# ================================================================
# AI Glasses SoC — C Runtime Startup (crt0.S)
# ================================================================
# This runs from SRAM (0x10000000) after boot ROM jump.
# Assumes SP is already set by boot ROM.
# ================================================================

    .section .text.start
    .global _start
    .type _start, @function

_start:
    # Set stack pointer (in case boot ROM didn't)
    lui     sp, %hi(_stack_top)
    addi    sp, sp, %lo(_stack_top)

    # Set trap vector
    la      t0, _trap_entry
    csrw    mtvec, t0

    # Zero BSS
    la      a0, __bss_start
    la      a1, __bss_end
1:
    bge     a0, a1, 2f
    sw      zero, 0(a0)
    addi    a0, a0, 4
    j       1b
2:
    # Call main
    call    main

    # If main returns, loop forever
3:
    wfi
    j       3b

    .size _start, .-_start

# ================================================================
# Default trap handler
# ================================================================
    .section .text.trap
    .global _trap_entry
    .type _trap_entry, @function
    .align 4  /* mtvec requires 4-byte alignment */

_trap_entry:
    # Save caller-saved registers
    addi    sp, sp, -64
    sw      ra,  0(sp)
    sw      t0,  4(sp)
    sw      t1,  8(sp)
    sw      t2, 12(sp)
    sw      a0, 16(sp)
    sw      a1, 20(sp)
    sw      a2, 24(sp)
    sw      a3, 28(sp)
    sw      a4, 32(sp)
    sw      a5, 36(sp)
    sw      a6, 40(sp)
    sw      a7, 44(sp)
    sw      t3, 48(sp)
    sw      t4, 52(sp)
    sw      t5, 56(sp)
    sw      t6, 60(sp)

    # Call C trap handler (weak, can be overridden)
    csrr    a0, mcause
    csrr    a1, mepc
    call    trap_handler

    # Restore registers
    lw      ra,  0(sp)
    lw      t0,  4(sp)
    lw      t1,  8(sp)
    lw      t2, 12(sp)
    lw      a0, 16(sp)
    lw      a1, 20(sp)
    lw      a2, 24(sp)
    lw      a3, 28(sp)
    lw      a4, 32(sp)
    lw      a5, 36(sp)
    lw      a6, 40(sp)
    lw      a7, 44(sp)
    lw      t3, 48(sp)
    lw      t4, 52(sp)
    lw      t5, 56(sp)
    lw      t6, 60(sp)
    addi    sp, sp, 64

    mret

    .size _trap_entry, .-_trap_entry

# ================================================================
# Default (weak) trap handler — does nothing
# ================================================================
    .weak trap_handler
trap_handler:
    ret
