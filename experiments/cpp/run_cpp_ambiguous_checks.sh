#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR="$(mktemp -d /tmp/rwpi-cpp.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

CLANGXX=("$ROOT/build-rwpi-moved/bin/clang" --driver-mode=g++)
LLD="$ROOT/build-rwpi-moved/bin/lld"
OBJDUMP="$ROOT/build-rwpi-moved/bin/llvm-objdump"
READOBJ="$ROOT/build-rwpi-moved/bin/llvm-readobj"

DECL1="$TMPDIR/extern_const_decl.o"
DEF1="$TMPDIR/extern_const_def.o"
ELF1="$TMPDIR/extern_const.elf"

DECL2="$TMPDIR/ctor_unknown_decl.o"
DEF2="$TMPDIR/ctor_unknown_def.o"
ELF2="$TMPDIR/ctor_unknown.elf"

DECL3="$TMPDIR/roreloc_unknown_decl.o"
DEF3="$TMPDIR/roreloc_unknown_def.o"
ELF3="$TMPDIR/roreloc_unknown.elf"

"$ROOT/build-llvm.sh"

"${CLANGXX[@]}" \
  --target=riscv32-unknown-elf \
  -march=rv32imac \
  -mabi=ilp32 \
  -frwpi \
  -ffreestanding \
  -fno-exceptions \
  -fno-rtti \
  -c "$ROOT/experiments/cpp/extern_const_decl.cpp" \
  -o "$DECL1"

"${CLANGXX[@]}" \
  --target=riscv32-unknown-elf \
  -march=rv32imac \
  -mabi=ilp32 \
  -frwpi \
  -ffreestanding \
  -fno-exceptions \
  -fno-rtti \
  -c "$ROOT/experiments/cpp/extern_const_def.cpp" \
  -o "$DEF1"

echo "Extern const declaration relocations:"
"$READOBJ" -r "$DECL1"

if ! "$READOBJ" -r "$DECL1" | grep -q 'R_RISCV_CUSTOM196 extc'; then
  echo "extern const declaration did not emit ambiguous %epic_hi relocation" >&2
  exit 1
fi
if ! "$READOBJ" -r "$DECL1" | grep -q 'R_RISCV_CUSTOM197 extc'; then
  echo "extern const declaration did not emit ambiguous %epic_lo relocation" >&2
  exit 1
fi

"$LLD" \
  -flavor gnu \
  -m elf32lriscv \
  -T "$ROOT/experiments/classic/linker-qemu-virt.ld" \
  --entry=0 \
  "$DECL1" \
  "$DEF1" \
  -o "$ELF1"

echo "Extern const final disassembly:"
DIS1="$("$OBJDUMP" -d --no-show-raw-insn -M no-aliases "$ELF1")"
printf '%s\n' "$DIS1"

if ! grep -q 'auipc' <<<"$DIS1"; then
  echo "extern const final link did not choose PC-relative rewriting" >&2
  exit 1
fi

"${CLANGXX[@]}" \
  --target=riscv32-unknown-elf \
  -march=rv32imac \
  -mabi=ilp32 \
  -frwpi \
  -ffreestanding \
  -fno-exceptions \
  -fno-rtti \
  -c "$ROOT/experiments/cpp/ctor_unknown_decl.cpp" \
  -o "$DECL2"

"${CLANGXX[@]}" \
  --target=riscv32-unknown-elf \
  -march=rv32imac \
  -mabi=ilp32 \
  -frwpi \
  -ffreestanding \
  -fno-exceptions \
  -fno-rtti \
  -c "$ROOT/experiments/cpp/ctor_unknown_def.cpp" \
  -o "$DEF2"

echo "C++ ctor declaration relocations:"
"$READOBJ" -r "$DECL2"

if ! "$READOBJ" -r "$DECL2" | grep -q 'R_RISCV_CUSTOM194'; then
  echo "C++ ctor declaration did not emit RWPI hi relocation" >&2
  exit 1
fi
if ! "$READOBJ" -r "$DECL2" | grep -q 'R_RISCV_CUSTOM192'; then
  echo "C++ ctor declaration did not emit RWPI lo relocation" >&2
  exit 1
fi

echo "Note: this PR-style C++ case already lowers as data-side in the current pipeline;"
echo "it therefore validates final gp-relative addressing, but does not exercise"
echo "the new ambiguous %epic_hi/%epic_lo path."

"$LLD" \
  -flavor gnu \
  -m elf32lriscv \
  -T "$ROOT/experiments/classic/linker-qemu-virt.ld" \
  --entry=0 \
  "$DECL2" \
  "$DEF2" \
  -o "$ELF2"

echo "C++ ctor final disassembly:"
DIS2="$("$OBJDUMP" -d --no-show-raw-insn -M no-aliases "$ELF2")"
printf '%s\n' "$DIS2"

if ! grep -q 'gp' <<<"$DIS2"; then
  echo "C++ ctor final link did not choose gp-relative rewriting" >&2
  exit 1
fi

"${CLANGXX[@]}" \
  --target=riscv32-unknown-elf \
  -march=rv32imac \
  -mabi=ilp32 \
  -frwpi \
  -ffreestanding \
  -fno-exceptions \
  -fno-rtti \
  -c "$ROOT/experiments/cpp/roreloc_unknown_decl.cpp" \
  -o "$DECL3"

"${CLANGXX[@]}" \
  --target=riscv32-unknown-elf \
  -march=rv32imac \
  -mabi=ilp32 \
  -frwpi \
  -ffreestanding \
  -fno-exceptions \
  -fno-rtti \
  -c "$ROOT/experiments/cpp/roreloc_unknown_def.cpp" \
  -o "$DEF3"

echo "C++ const-pointer RO-reloc declaration relocations:"
"$READOBJ" -r "$DECL3"

if ! "$READOBJ" -r "$DECL3" | grep -q 'R_RISCV_CUSTOM196 p'; then
  echo "C++ const-pointer declaration did not emit ambiguous %epic_hi relocation" >&2
  exit 1
fi
if ! "$READOBJ" -r "$DECL3" | grep -q 'R_RISCV_CUSTOM197 p'; then
  echo "C++ const-pointer declaration did not emit ambiguous %epic_lo relocation" >&2
  exit 1
fi

"$LLD" \
  -flavor gnu \
  -m elf32lriscv \
  -T "$ROOT/experiments/classic/linker-qemu-virt.ld" \
  --entry=0 \
  "$DECL3" \
  "$DEF3" \
  -o "$ELF3"

echo "C++ const-pointer RO-reloc final disassembly:"
DIS3="$("$OBJDUMP" -d --no-show-raw-insn -M no-aliases "$ELF3")"
printf '%s\n' "$DIS3"

if ! grep -q 'gp' <<<"$DIS3"; then
  echo "C++ const-pointer final link did not choose gp-relative rewriting" >&2
  exit 1
fi

echo "C++ const-pointer output sections:"
"$READOBJ" --sections "$ELF3"

if ! "$READOBJ" --sections "$ELF3" | grep -q '.dataramro'; then
  echo "C++ const-pointer final link did not materialize a .dataramro section" >&2
  exit 1
fi

echo "C++ ambiguous-segment checks OK"
