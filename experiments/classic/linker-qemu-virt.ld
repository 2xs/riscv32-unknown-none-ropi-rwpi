ENTRY(_start)

MEMORY {
  ROM (rx)  : ORIGIN = 0x80000000, LENGTH = 64K
  RAM (rwx) : ORIGIN = 0x80010000, LENGTH = 64K
}

SECTIONS {
  .text : {
    *(.text .text.*)
  } > ROM

  .dataro : {
    *(.rodata .rodata.*)
    *(.srodata .srodata.*)
  } > ROM

  __gp_data_start = ORIGIN(RAM);
  __stack_top = ORIGIN(RAM) + LENGTH(RAM);

  .dataramro __gp_data_start : ALIGN(4) {
    . = ALIGN(4);
    __dataramro_start = .;
    *(.dataramro .dataramro.*)
    *(.ramro .ramro.*)
    __dataramro_end = .;
  } > RAM AT> ROM
  __dataramro_load_start = LOADADDR(.dataramro);
  __dataramro_load_end = LOADADDR(.dataramro) + SIZEOF(.dataramro);

  .datarw : ALIGN(4) {
    . = ALIGN(4);
    __datarw_start = .;
    *(.data .data.*)
    *(.sdata .sdata.*)
    __datarw_end = .;
  } > RAM AT> ROM
  __datarw_load_start = LOADADDR(.datarw);
  __datarw_load_end = LOADADDR(.datarw) + SIZEOF(.datarw);

  .datarw.bss (NOLOAD) : ALIGN(4) {
    . = ALIGN(4);
    __datarw_bss_start = .;
    *(.sbss .sbss.*)
    *(.bss .bss.*)
    *(COMMON)
    __datarw_bss_end = .;
  } > RAM

  .rela.dataramro : {
    *(.rela.dataramro .rela.dataramro.*)
  } > ROM
  __rela_dataramro_start = ADDR(.rela.dataramro);
  __rela_dataramro_end = ADDR(.rela.dataramro) + SIZEOF(.rela.dataramro);

  __gp_data_end = .;

  /DISCARD/ : {
    *(.note.GNU-stack)
  }
}
