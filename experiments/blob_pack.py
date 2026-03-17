#!/usr/bin/env python3
"""
Pack a "house" RWPI execution blob for the experiments.

Blob layout
-----------

The output is a single flat binary loaded raw by QEMU at the blob base:

  [crt0 text]
  [header]
  [datarw relocation offsets]
  [dataramro relocation offsets]
  [raw datarw bytes]
  [raw dataramro bytes]
  [raw text bytes]

The startup code is copied first and executes in place. It then reads the
header, copies each payload block to its runtime destination, applies the
runtime relocation tables and finally jumps to the relocated entry point.

Header format
-------------

All header fields are little-endian 32-bit words:

  magic
  linked_data_base
  datarw_blob_off
  datarw_size
  datarw_runtime_off
  datarw_bss_runtime_off
  datarw_bss_size
  dataramro_blob_off
  dataramro_size
  dataramro_runtime_off
  text_blob_off
  text_size
  text_runtime_addr
  entry_off
  datarw_reloc_blob_off
  datarw_reloc_count
  dataramro_reloc_blob_off
  dataramro_reloc_count

Runtime relocation tables
-------------------------

Each runtime relocation table is a compact array of 32-bit offsets within the
destination block. For each offset, crt0 performs:

  *(block_runtime_base + offset) += (runtime_data_base - linked_data_base)

This means the current blob format intentionally supports only absolute 32-bit
data relocations that target the linked RWPI data window. That is enough for
plain data pointers that are rebased when the runtime data window moves.

Deliberate limitations
----------------------

The packer rejects payloads that would require richer runtime metadata:

  - TLS sections (.tdata/.tbss)
  - data relocations with non-R_RISCV_32 semantics
  - data relocations that target symbols outside the linked RWPI data window
    when the runtime text address differs from the linked text address

In particular, relocating text independently from data is currently rejected
when the payload contains function pointers in datarw/dataramro, because those
would need a second relocation domain.
"""

import argparse
import struct
from dataclasses import dataclass
from pathlib import Path


SHT_SYMTAB = 2
SHT_RELA = 4

BLOB_MAGIC = 0x30425752
R_RISCV_32 = 1


@dataclass
class Section:
    name: str
    sh_type: int
    flags: int
    addr: int
    offset: int
    size: int
    link: int
    info: int
    entsize: int


@dataclass
class Symbol:
    name: str
    value: int
    size: int
    info: int
    other: int
    shndx: int


class ELF32:
    def __init__(self, path: Path):
        self.path = path
        self.data = path.read_bytes()
        if self.data[:4] != b"\x7fELF":
            raise ValueError(f"{path} is not an ELF file")
        if self.data[4] != 1 or self.data[5] != 1:
            raise ValueError(f"{path} is not ELF32 little-endian")

        header = struct.unpack_from("<16sHHIIIIIHHHHHH", self.data, 0)
        (
            _ident,
            _e_type,
            _e_machine,
            _e_version,
            _e_entry,
            _e_phoff,
            e_shoff,
            _e_flags,
            _e_ehsize,
            _e_phentsize,
            _e_phnum,
            e_shentsize,
            e_shnum,
            e_shstrndx,
        ) = header

        self.sections = []
        raw_sections = []
        for idx in range(e_shnum):
            off = e_shoff + idx * e_shentsize
            raw_sections.append(struct.unpack_from("<IIIIIIIIII", self.data, off))

        shstr = raw_sections[e_shstrndx]
        shstr_data = self.data[shstr[4] : shstr[4] + shstr[5]]
        for raw in raw_sections:
            name_off, sh_type, flags, addr, offset, size, link, info, _align, entsize = raw
            name = self._cstring(shstr_data, name_off)
            self.sections.append(
                Section(name, sh_type, flags, addr, offset, size, link, info, entsize)
            )

        self.section_by_name = {sec.name: sec for sec in self.sections}
        self.symbols = self._load_symbols()
        self.symbol_by_name = {sym.name: sym for sym in self.symbols}

    @staticmethod
    def _cstring(data: bytes, off: int) -> str:
        end = data.find(b"\0", off)
        if end < 0:
            end = len(data)
        return data[off:end].decode("utf-8")

    def section_data(self, name: str) -> bytes:
        sec = self.section_by_name[name]
        return self.data[sec.offset : sec.offset + sec.size]

    def _load_symbols(self):
        symtab = next((s for s in self.sections if s.sh_type == SHT_SYMTAB), None)
        if symtab is None:
            return []
        strtab = self.sections[symtab.link]
        strtab_data = self.data[strtab.offset : strtab.offset + strtab.size]
        out = []
        for off in range(symtab.offset, symtab.offset + symtab.size, symtab.entsize):
            st_name, st_value, st_size, st_info, st_other, st_shndx = struct.unpack_from(
                "<IIIBBH", self.data, off
            )
            out.append(
                Symbol(
                    self._cstring(strtab_data, st_name),
                    st_value,
                    st_size,
                    st_info,
                    st_other,
                    st_shndx,
                )
            )
        return out

    def relocations(self, name: str):
        sec = self.section_by_name.get(name)
        if sec is None:
            return []
        if sec.sh_type != SHT_RELA:
            raise ValueError(f"{name} is not SHT_RELA")
        out = []
        for off in range(sec.offset, sec.offset + sec.size, sec.entsize):
            r_offset, r_info, r_addend = struct.unpack_from("<III", self.data, off)
            out.append((r_offset, r_info >> 8, r_info & 0xFF, r_addend))
        return out


def collect_runtime_relocs(
    elf: ELF32,
    rela_name: str,
    block_name: str,
    data_lo: int,
    data_hi: int,
    *,
    allow_external: bool,
):
    block = elf.section_by_name.get(block_name)
    if block is None:
        return [], []

    relocs = []
    unsupported = []
    for r_offset, sym_index, r_type, _r_addend in elf.relocations(rela_name):
        if r_type != R_RISCV_32:
            unsupported.append(f"{rela_name}: unsupported relocation type {r_type} at 0x{r_offset:x}")
            continue
        sym = elf.symbols[sym_index]
        if data_lo <= sym.value < data_hi:
            relocs.append(r_offset - block.addr)
        elif not allow_external:
            unsupported.append(
                f"{rela_name}: symbol {sym.name} at 0x{sym.value:x} is outside the linked data window"
            )
    return relocs, unsupported


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--crt0-elf", required=True)
    ap.add_argument("--payload-elf", required=True)
    ap.add_argument("--entry", default="main")
    ap.add_argument("--text-runtime-addr")
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    crt0 = ELF32(Path(args.crt0_elf))
    payload = ELF32(Path(args.payload_elf))

    unsupported_sections = [name for name in (".tdata", ".tbss") if name in payload.section_by_name]
    if unsupported_sections:
        raise SystemExit(f"unsupported TLS sections in payload: {', '.join(unsupported_sections)}")

    crt0_text = crt0.section_data(".text")
    text = payload.section_data(".text")
    dataramro = payload.section_data(".dataramro") if ".dataramro" in payload.section_by_name else b""
    datarw = payload.section_data(".datarw") if ".datarw" in payload.section_by_name else b""
    datarw_bss = payload.section_by_name.get(".datarw.bss")

    linked_data_base = payload.symbol_by_name["__gp_data_start"].value
    text_link_addr = payload.section_by_name[".text"].addr
    text_runtime_addr = int(args.text_runtime_addr, 0) if args.text_runtime_addr else text_link_addr

    dataramro_addr = (
        payload.section_by_name[".dataramro"].addr if ".dataramro" in payload.section_by_name else linked_data_base
    )
    datarw_addr = (
        payload.section_by_name[".datarw"].addr if ".datarw" in payload.section_by_name else linked_data_base
    )
    data_hi = max(dataramro_addr + len(dataramro), datarw_addr + len(datarw))

    allow_external = text_runtime_addr == text_link_addr
    rw_relocs, rw_unsupported = collect_runtime_relocs(
        payload, ".rela.datarw", ".datarw", linked_data_base, data_hi, allow_external=allow_external
    )
    ramro_relocs, ramro_unsupported = collect_runtime_relocs(
        payload,
        ".rela.dataramro",
        ".dataramro",
        linked_data_base,
        data_hi,
        allow_external=allow_external,
    )
    unsupported = rw_unsupported + ramro_unsupported
    if unsupported:
        raise SystemExit("\n".join(unsupported))

    header_size = 18 * 4
    pos = len(crt0_text) + header_size

    rw_reloc_off = pos
    rw_reloc_blob = b"".join(struct.pack("<I", off) for off in rw_relocs)
    pos += len(rw_reloc_blob)

    ramro_reloc_off = pos
    ramro_reloc_blob = b"".join(struct.pack("<I", off) for off in ramro_relocs)
    pos += len(ramro_reloc_blob)

    datarw_off = pos
    pos += len(datarw)

    dataramro_off = pos
    pos += len(dataramro)

    text_off = pos
    pos += len(text)

    entry = payload.symbol_by_name[args.entry].value - text_link_addr
    datarw_bss_runtime_off = 0
    datarw_bss_size = 0
    if datarw_bss is not None:
        datarw_bss_runtime_off = datarw_bss.addr - linked_data_base
        datarw_bss_size = datarw_bss.size

    header = struct.pack(
        "<18I",
        BLOB_MAGIC,
        linked_data_base,
        datarw_off,
        len(datarw),
        datarw_addr - linked_data_base,
        datarw_bss_runtime_off,
        datarw_bss_size,
        dataramro_off,
        len(dataramro),
        dataramro_addr - linked_data_base,
        text_off,
        len(text),
        text_runtime_addr,
        entry,
        rw_reloc_off,
        len(rw_relocs),
        ramro_reloc_off,
        len(ramro_relocs),
    )

    blob = b"".join([crt0_text, header, rw_reloc_blob, ramro_reloc_blob, datarw, dataramro, text])
    Path(args.output).write_bytes(blob)

    print(f"blob: {args.output}")
    print(f"  linked_data_base = 0x{linked_data_base:08x}")
    print(
        f"  datarw: size={len(datarw)} bss={datarw_bss_size} relocs={len(rw_relocs)} runtime_off=0x{datarw_addr - linked_data_base:x}"
    )
    print(
        f"  dataramro: size={len(dataramro)} relocs={len(ramro_relocs)} runtime_off=0x{dataramro_addr - linked_data_base:x}"
    )
    print(
        f"  text: size={len(text)} linked=0x{text_link_addr:08x} runtime=0x{text_runtime_addr:08x} entry_off=0x{entry:x}"
    )


if __name__ == "__main__":
    main()
