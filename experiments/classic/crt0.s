    .globl _start
    .type _start, @function

    .extern main
    .extern __stack_top
    .extern __gp_data_start
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

_start:
    la sp, __stack_top

    la a0, __dataramro_start
    la a1, __dataramro_end
    la a2, __dataramro_load_start
    call copy_range

    la a0, __datarw_start
    la a1, __datarw_end
    la a2, __datarw_load_start
    call copy_range

    la a0, __datarw_bss_start
    la a1, __datarw_bss_end
    call zero_range

    call apply_dataramro_relocations

    la gp, __gp_data_start

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
    la t0, __rela_dataramro_start
    la t1, __rela_dataramro_end
    beq t0, t1, .Lrela_done

    /*
     * The current runtime contract keeps the ordinary ELF SHT_RELA format in
     * .rela.dataramro. A fully generic startup relocator therefore still needs
     * a runtime-visible way to resolve r_info symbol indices.
     *
     * Until that symbol-resolution contract is defined, treat the presence of
     * .rela.dataramro entries as a hard stop rather than silently booting with
     * stale pointers in RAM.
     */
    ebreak
.Lrela_trap:
    j .Lrela_trap

.Lrela_done:
    ret

    .size _start, . - _start
