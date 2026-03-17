    .ifndef DATA_RUNTIME_BASE
    .set DATA_RUNTIME_BASE, 0x80010000
    .endif

    .ifndef STACK_TOP
    .set STACK_TOP, 0x8003F000
    .endif

    .equ BLOB_MAGIC, 0x30425752

    .equ HDR_MAGIC, 0
    .equ HDR_LINKED_DATA_BASE, 4
    .equ HDR_DATARW_BLOB_OFF, 8
    .equ HDR_DATARW_SIZE, 12
    .equ HDR_DATARW_RUNTIME_OFF, 16
    .equ HDR_DATARW_BSS_RUNTIME_OFF, 20
    .equ HDR_DATARW_BSS_SIZE, 24
    .equ HDR_DATARAMRO_BLOB_OFF, 28
    .equ HDR_DATARAMRO_SIZE, 32
    .equ HDR_DATARAMRO_RUNTIME_OFF, 36
    .equ HDR_TEXT_BLOB_OFF, 40
    .equ HDR_TEXT_SIZE, 44
    .equ HDR_TEXT_RUNTIME_ADDR, 48
    .equ HDR_ENTRY_OFF, 52
    .equ HDR_RW_RELOC_BLOB_OFF, 56
    .equ HDR_RW_RELOC_COUNT, 60
    .equ HDR_RAMRO_RELOC_BLOB_OFF, 64
    .equ HDR_RAMRO_RELOC_COUNT, 68
    .equ HDR_SIZE, 72

    .globl _start
    .type _start, @function

_start:
1:
    auipc s0, %pcrel_hi(_start)
    addi s0, s0, %pcrel_lo(1b)

2:
    auipc s1, %pcrel_hi(.Lafter_code)
    addi s1, s1, %pcrel_lo(2b)

    li t0, BLOB_MAGIC
    lw t1, HDR_MAGIC(s1)
    bne t0, t1, .Lhang

    li sp, STACK_TOP

    lw s2, HDR_LINKED_DATA_BASE(s1)
    li s3, DATA_RUNTIME_BASE
    sub s4, s3, s2

    lw t0, HDR_DATARAMRO_RUNTIME_OFF(s1)
    add a0, s3, t0
    lw t0, HDR_DATARAMRO_SIZE(s1)
    mv a1, t0
    lw t0, HDR_DATARAMRO_BLOB_OFF(s1)
    add a2, s0, t0
    call copy_size

    lw t0, HDR_DATARW_RUNTIME_OFF(s1)
    add a0, s3, t0
    lw t0, HDR_DATARW_SIZE(s1)
    mv a1, t0
    lw t0, HDR_DATARW_BLOB_OFF(s1)
    add a2, s0, t0
    call copy_size

    lw t0, HDR_DATARW_BSS_RUNTIME_OFF(s1)
    add a0, s3, t0
    lw a1, HDR_DATARW_BSS_SIZE(s1)
    call zero_size

    lw a0, HDR_TEXT_RUNTIME_ADDR(s1)
    lw a1, HDR_TEXT_SIZE(s1)
    lw t0, HDR_TEXT_BLOB_OFF(s1)
    add a2, s0, t0
    call copy_size

    lw t0, HDR_DATARAMRO_RUNTIME_OFF(s1)
    add a0, s3, t0
    lw t0, HDR_RAMRO_RELOC_BLOB_OFF(s1)
    add a1, s0, t0
    lw a2, HDR_RAMRO_RELOC_COUNT(s1)
    mv a3, s4
    call apply_reloc_table

    lw t0, HDR_DATARW_RUNTIME_OFF(s1)
    add a0, s3, t0
    lw t0, HDR_RW_RELOC_BLOB_OFF(s1)
    add a1, s0, t0
    lw a2, HDR_RW_RELOC_COUNT(s1)
    mv a3, s4
    call apply_reloc_table

    mv gp, s3
    fence.i

    lw t0, HDR_TEXT_RUNTIME_ADDR(s1)
    lw t1, HDR_ENTRY_OFF(s1)
    add t0, t0, t1
    jr t0

copy_size:
    beqz a1, .Lcopy_done
.Lcopy_loop:
    lbu t0, 0(a2)
    sb t0, 0(a0)
    addi a0, a0, 1
    addi a2, a2, 1
    addi a1, a1, -1
    bnez a1, .Lcopy_loop
.Lcopy_done:
    ret

zero_size:
    beqz a1, .Lzero_done
.Lzero_loop:
    sb zero, 0(a0)
    addi a0, a0, 1
    addi a1, a1, -1
    bnez a1, .Lzero_loop
.Lzero_done:
    ret

apply_reloc_table:
    beqz a2, .Lreloc_done
.Lreloc_loop:
    lw t0, 0(a1)
    add t0, a0, t0
    lw t1, 0(t0)
    add t1, t1, a3
    sw t1, 0(t0)
    addi a1, a1, 4
    addi a2, a2, -1
    bnez a2, .Lreloc_loop
.Lreloc_done:
    ret

.Lhang:
    j .Lhang

.Lafter_code:
    .size _start, . - _start
