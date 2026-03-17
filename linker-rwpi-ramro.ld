ENTRY(_start)

MEMORY {
  ROM (rx)  : ORIGIN = 0x00010000, LENGTH = 256K
  RAM (rwx) : ORIGIN = 0x20000000, LENGTH = 64K
}

SECTIONS {
  .text : {
    *(.text .text.*)
  } > ROM

  .rodata : {
    *(.rodata .rodata.*)
    *(.srodata .srodata.*)
  } > ROM

  __gp_data_start = ORIGIN(RAM);

  .ramro __gp_data_start : ALIGN(4) {
    . = ALIGN(4);
    __ramro_start = .;
    *(.ramro .ramro.*)
    __ramro_end = .;
  } > RAM AT> ROM
  __ramro_load_start = LOADADDR(.ramro);
  __ramro_load_end = LOADADDR(.ramro) + SIZEOF(.ramro);

  .rwpi : ALIGN(4) {
    . = ALIGN(4);
    __rwpi_data_start = .;
    *(.data .data.*)
    *(.sdata .sdata.*)
    __rwpi_data_end = .;
  } > RAM AT> ROM
  __rwpi_data_load_start = LOADADDR(.rwpi);
  __rwpi_data_load_end = LOADADDR(.rwpi) + SIZEOF(.rwpi);

  .rwpi.bss (NOLOAD) : ALIGN(4) {
    . = ALIGN(4);
    __rwpi_bss_start = .;
    *(.sbss .sbss.*)
    *(.bss .bss.*)
    *(COMMON)
    __rwpi_bss_end = .;
  } > RAM

  __gp_data_end = .;
  __image_end = LOADADDR(.rwpi) + SIZEOF(.rwpi);

  /DISCARD/ : {
    *(.note.GNU-stack)
  }
}
