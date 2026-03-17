#!/usr/bin/env bash
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OBJ="$(mktemp /tmp/rwpi-reloc-sections.XXXXXX.o)"
CRT0_OBJ="$(mktemp /tmp/rwpi-reloc-crt0.XXXXXX.o)"
ELF="$(mktemp /tmp/rwpi-reloc-sections.XXXXXX.elf)"
RELOCS_OBJ="$(mktemp /tmp/rwpi-reloc-sections.XXXXXX.obj.txt)"
RELOCS_ELF="$(mktemp /tmp/rwpi-reloc-sections.XXXXXX.elf.txt)"
SYMS_ELF="$(mktemp /tmp/rwpi-reloc-sections.XXXXXX.sym.txt)"

trap 'rm -f "$OBJ" "$CRT0_OBJ" "$ELF" "$RELOCS_OBJ" "$RELOCS_ELF" "$SYMS_ELF"' EXIT

"$ROOT/build-llvm.sh"

"$ROOT/build-rwpi-moved/bin/clang" \
  --target=riscv32-unknown-elf \
  -march=rv32imac \
  -mabi=ilp32 \
  -c "$ROOT/experiments/classic/crt0.s" \
  -o "$CRT0_OBJ"

"$ROOT/build-rwpi-moved/bin/clang" \
  --target=riscv32-unknown-elf \
  -march=rv32imac \
  -mabi=ilp32 \
  -frwpi \
  -ffreestanding \
  -c "$ROOT/experiments/classic/hello_reloc_matrix.c" \
  -o "$OBJ"

"$ROOT/build-rwpi-moved/bin/llvm-readobj" -r "$OBJ" > "$RELOCS_OBJ"

rg -q '\.rela\.data' "$RELOCS_OBJ"
rg -q '\.rela\.dataramro' "$RELOCS_OBJ"
rg -q 'R_RISCV_32 target_a' "$RELOCS_OBJ"
rg -q 'R_RISCV_32 fn0' "$RELOCS_OBJ"

"$ROOT/build-rwpi-moved/bin/lld" \
  -flavor gnu \
  -m elf32lriscv \
  --emit-relocs \
  -T "$ROOT/experiments/classic/linker-qemu-virt.ld" \
  "$CRT0_OBJ" \
  "$OBJ" \
  -o "$ELF"

"$ROOT/build-rwpi-moved/bin/llvm-readobj" --sections --section-relocations "$ELF" \
  > "$RELOCS_ELF"
"$ROOT/build-rwpi-moved/bin/llvm-readobj" --symbols "$ELF" > "$SYMS_ELF"

rg -q 'Name: \.rela\.dataramro' "$RELOCS_ELF"
rg -q 'Name: \.rela\.text' "$RELOCS_ELF"
rg -q 'R_RISCV_32 target_a' "$RELOCS_ELF"
rg -q 'R_RISCV_32 fn0' "$RELOCS_ELF"
rg -q 'Name: __rela_dataramro_start' "$SYMS_ELF"
rg -q 'Value: 0x[1-9A-Fa-f][0-9A-Fa-f]*' "$SYMS_ELF"
python3 - <<'PY' "$SYMS_ELF"
import re
import sys

text = open(sys.argv[1], "r", encoding="utf-8").read()

def value(name: str) -> int:
    m = re.search(rf"Name: {re.escape(name)} .*?Value: 0x([0-9A-Fa-f]+)", text, re.S)
    if not m:
        raise SystemExit(f"missing symbol {name}")
    return int(m.group(1), 16)

start = value("__rela_dataramro_start")
end = value("__rela_dataramro_end")
if not start:
    raise SystemExit("__rela_dataramro_start is zero")
if end <= start:
    raise SystemExit("__rela_dataramro_end does not extend past start")
PY
python3 - <<'PY' "$RELOCS_ELF"
import re
import sys

text = open(sys.argv[1], "r", encoding="utf-8").read()
m = re.search(r"Name: \.rela\.dataramro.*?Flags \[ \((.*?)\)\n(.*?)\n    \]", text, re.S)
if not m or "SHF_ALLOC" not in m.group(2):
    raise SystemExit(".rela.dataramro is not allocatable in the final ELF")
PY

echo "Relocation section checks OK"
