ENTRY(_start)

MEMORY {
  ROM (rx)  : ORIGIN = 0x80000000, LENGTH = 64K
  RAM (rwx) : ORIGIN = 0x80010000, LENGTH = 64K
}

SECTIONS {
  .text : {
    __text_start = .;
    *(.text .text.*)
    __text_end = .;
  } > ROM

  .dataro : {
    __dataro_start = .;
    *(.rodata .rodata.*)
    *(.srodata .srodata.*)
    __dataro_end = .;
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

  __gp_data_end = .;

  .rela.dataramro : {
    *(.rela.dataramro .rela.dataramro.*)
  } > ROM
  __rela_dataramro_start = ADDR(.rela.dataramro);
  __rela_dataramro_end = ADDR(.rela.dataramro) + SIZEOF(.rela.dataramro);

  .rela.datarw : {
    *(.rela.datarw .rela.datarw.*)
  } > ROM
  __rela_datarw_start = ADDR(.rela.datarw);
  __rela_datarw_end = ADDR(.rela.datarw) + SIZEOF(.rela.datarw);

  /DISCARD/ : {
    *(.note.GNU-stack)
  }
}
