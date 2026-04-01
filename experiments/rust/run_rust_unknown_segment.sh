#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR="$(mktemp -d /tmp/rwpi-rust-unknown.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

LINKER_SCRIPT="$TMPDIR/linker-qemu-virt.ld"
USE_LL="$TMPDIR/main_unknown.ll"
DEF_LL="$TMPDIR/defs_unknown.ll"
USE_OBJ="$TMPDIR/main_unknown.o"
DEF_OBJ="$TMPDIR/defs_unknown.o"
ELF="$TMPDIR/rust-unknown.elf"
USE_RELOCS="$TMPDIR/use.relocs"
USE_IR="$TMPDIR/use.ir"
SECTIONS="$TMPDIR/sections.txt"
DISASM="$TMPDIR/disasm.txt"

cp "$ROOT/experiments/classic/linker-qemu-virt.ld" "$LINKER_SCRIPT"

rustc \
  --target riscv32imac-unknown-none-elf \
  --crate-type lib \
  --emit=llvm-ir \
  -C opt-level=3 \
  -C panic=abort \
  -o "$USE_LL" \
  "$ROOT/experiments/rust/main_unknown.rs"

rustc \
  --target riscv32imac-unknown-none-elf \
  --crate-type lib \
  --emit=llvm-ir \
  -C opt-level=3 \
  -C panic=abort \
  -o "$DEF_LL" \
  "$ROOT/experiments/rust/defs_unknown.rs"

echo "Rust unknown-segment use-side LLVM IR:"
sed -n '1,80p' "$USE_LL" | tee "$USE_IR"

if ! rg -q '@P = external dso_local global' "$USE_IR"; then
  echo "expected rustc to lower the foreign static as an external global" >&2
  exit 1
fi

if rg -q '@P = external .*constant' "$USE_IR"; then
  echo "unexpected external constant in use-side Rust IR" >&2
  exit 1
fi

"$ROOT/build-rwpi-moved/bin/llc" \
  -mtriple=riscv32-unknown-elf \
  -mattr=+rwpi-gp-data \
  -filetype=obj \
  -o "$USE_OBJ" \
  "$USE_LL"

"$ROOT/build-rwpi-moved/bin/llc" \
  -mtriple=riscv32-unknown-elf \
  -mattr=+rwpi-gp-data \
  -filetype=obj \
  -o "$DEF_OBJ" \
  "$DEF_LL"

echo "Rust unknown-segment use-side relocations:"
"$ROOT/build-rwpi-moved/bin/llvm-readobj" -r "$USE_OBJ" | tee "$USE_RELOCS"

if ! rg -q 'R_RISCV_CUSTOM194 P' "$USE_RELOCS"; then
  echo "expected the Rust use-side object to emit a direct RWPI hi relocation" >&2
  exit 1
fi

if ! rg -q 'R_RISCV_CUSTOM192 P' "$USE_RELOCS"; then
  echo "expected the Rust use-side object to emit a direct RWPI lo relocation" >&2
  exit 1
fi

if rg -q 'R_RISCV_CUSTOM19[678] P' "$USE_RELOCS"; then
  echo "unexpected ambiguous EPIC relocation in Rust use-side object" >&2
  exit 1
fi

"$ROOT/build-rwpi-moved/bin/lld" \
  -flavor gnu \
  -m elf32lriscv \
  -T "$LINKER_SCRIPT" \
  --entry=0 \
  "$USE_OBJ" \
  "$DEF_OBJ" \
  -o "$ELF"

echo "Rust unknown-segment final disassembly:"
"$ROOT/build-rwpi-moved/bin/llvm-objdump" \
  -d --no-show-raw-insn -M no-aliases "$ELF" | tee "$DISASM"

if ! rg -q 'addi[[:space:]]+a0,[[:space:]]+gp,' "$DISASM"; then
  echo "expected final Rust code to use gp-relative addressing" >&2
  exit 1
fi

echo "Rust unknown-segment final sections:"
"$ROOT/build-rwpi-moved/bin/llvm-readobj" --sections "$ELF" | tee "$SECTIONS"

if ! rg -q 'Name: \.dataramro' "$SECTIONS"; then
  echo "expected final Rust definition to materialize .dataramro" >&2
  exit 1
fi

echo "Rust unknown-segment check reproduced the current lowering behaviour"
