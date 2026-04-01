    .globl _start
    .type _start, @function

    .extern main
    .extern __stack_top
    .extern __text_start
    .extern __dataro_end
    .extern __gp_data_start
    .extern __gp_data_end
    .extern __dataramro_start
    .extern __dataramro_end
    .extern __dataramro_load_start
    .extern __datarw_start
    .extern __datarw_end
    .extern __datarw_load_start
    .extern __datarw_bss_start
    .extern __datarw_bss_end
    .extern __rela_dataramro_start
    .extern __rela_dataramro_end
    .extern __rela_datarw_start
    .extern __rela_datarw_end

    .equ ELF32_RELA_SIZE, 12
    .equ ELF32_R_TYPE_MASK, 0xff
    .equ R_RISCV_32, 1

_start:
    la s0, __gp_data_start
    la s3, __text_start
    la s6, __gp_data_end
    la s7, __dataro_end

    .ifndef DATA_RUNTIME_BASE
    mv s1, s0
    .else
    li s1, DATA_RUNTIME_BASE
    .endif
    sub s2, s1, s0

    .ifndef TEXT_RUNTIME_BASE
    mv s4, s3
    .else
    li s4, TEXT_RUNTIME_BASE
    .endif
    sub s5, s4, s3

    .ifndef STACK_RUNTIME_TOP
    la sp, __stack_top
    .else
    li sp, STACK_RUNTIME_TOP
    .endif

    la a0, __dataramro_start
    add a0, a0, s2
    la a1, __dataramro_end
    add a1, a1, s2
    la a2, __dataramro_load_start
    call copy_range

    la a0, __datarw_start
    add a0, a0, s2
    la a1, __datarw_end
    add a1, a1, s2
    la a2, __datarw_load_start
    call copy_range

    la a0, __datarw_bss_start
    add a0, a0, s2
    la a1, __datarw_bss_end
    add a1, a1, s2
    call zero_range

    call apply_dataramro_relocations
    call apply_datarw_relocations

    mv gp, s1

    call main

.Lhang:
    j .Lhang

copy_range:
    beq a0, a1, .Lcopy_done
.Lcopy_loop:
    lbu t0, 0(a2)
    sb t0, 0(a0)
    addi a0, a0, 1
    addi a2, a2, 1
    bne a0, a1, .Lcopy_loop
.Lcopy_done:
    ret

zero_range:
    beq a0, a1, .Lzero_done
.Lzero_loop:
    sb zero, 0(a0)
    addi a0, a0, 1
    bne a0, a1, .Lzero_loop
.Lzero_done:
    ret

apply_dataramro_relocations:
    la a0, __rela_dataramro_start
    la a1, __rela_dataramro_end
    tail apply_runtime_relocations

apply_datarw_relocations:
    la a0, __rela_datarw_start
    la a1, __rela_datarw_end
    tail apply_runtime_relocations

apply_runtime_relocations:
    beq a0, a1, .Lrela_done
.Lrela_loop:
    lw t0, 0(a0)
    lw t1, 4(a0)
    andi t1, t1, ELF32_R_TYPE_MASK
    li t2, R_RISCV_32
    bne t1, t2, .Lrela_unsupported

    add t0, t0, s2
    lw t3, 0(t0)

    bltu t3, s0, .Lcheck_text_range
    bltu t3, s6, .Lapply_data_delta

.Lcheck_text_range:
    bltu t3, s3, .Lrela_next
    bltu t3, s7, .Lapply_text_delta
    j .Lrela_next

.Lapply_data_delta:
    add t3, t3, s2
    j .Lstore_relocated_value

.Lapply_text_delta:
    add t3, t3, s5

.Lstore_relocated_value:
    sw t3, 0(t0)

.Lrela_next:
    addi a0, a0, ELF32_RELA_SIZE
    bne a0, a1, .Lrela_loop

.Lrela_done:
    ret

.Lrela_unsupported:
    ebreak
.Lrela_trap:
    j .Lrela_trap

    .size _start, . - _start
