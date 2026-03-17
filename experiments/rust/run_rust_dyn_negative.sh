#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
QEMU="${QEMU:-/opt/homebrew/bin/qemu-system-riscv32}"
TMPDIR="$(mktemp -d /tmp/rwpi-rust-dyn.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

LINKER_SCRIPT="$TMPDIR/linker-qemu-virt.ld"
CRT0_OBJ="$TMPDIR/crt0.o"
RUST_LL="$TMPDIR/main_dyn.ll"
RUST_OBJ="$TMPDIR/main_dyn.o"
ELF="$TMPDIR/rust-dyn.elf"
LOG="$TMPDIR/qemu.log"
OBJDUMP_LOG="$TMPDIR/objdump.log"

cp "$ROOT/experiments/classic/linker-qemu-virt.ld" "$LINKER_SCRIPT"

"$ROOT/build-rwpi-moved/bin/clang" \
  --target=riscv32-unknown-elf -march=rv32imac -mabi=ilp32 \
  -c "$ROOT/experiments/classic/crt0.s" -o "$CRT0_OBJ"

rustc \
  --target riscv32imac-unknown-none-elf \
  --crate-type bin \
  --emit=llvm-ir \
  -C opt-level=3 \
  -C panic=abort \
  -C debug-assertions=off \
  -C overflow-checks=off \
  -o "$RUST_LL" \
  "$ROOT/experiments/rust/main_dyn.rs"

"$ROOT/build-rwpi-moved/bin/llc" \
  -mtriple=riscv32-unknown-elf \
  -mattr=+rwpi-gp-data \
  -filetype=obj \
  -o "$RUST_OBJ" \
  "$RUST_LL"

echo "Rust dyn object relocations:"
"$ROOT/build-rwpi-moved/bin/llvm-objdump" \
  -dr --no-show-raw-insn -M no-aliases "$RUST_OBJ" | tee "$OBJDUMP_LOG" | sed -n '1,120p'

"$ROOT/build-rwpi-moved/bin/lld" \
  -flavor gnu -m elf32lriscv \
  -T "$LINKER_SCRIPT" \
  "$CRT0_OBJ" "$RUST_OBJ" \
  -o "$ELF"

if ! rg -q 'R_RISCV_CUSTOM19[24].*Lvtable' "$OBJDUMP_LOG"; then
  echo "expected dyn trait lowering to reference a vtable symbol" >&2
  exit 1
fi

set +e
timeout 3s "$QEMU" \
  -machine virt \
  -bios none \
  -nographic \
  -semihosting-config enable=on,target=native \
  -kernel "$ELF" >"$LOG" 2>&1
RC=$?
set -e

if [ "$RC" -ne 0 ]; then
  echo "expected dyn trait test to exit successfully, got rc=$RC" >&2
  cat "$LOG" >&2
  exit 1
fi

if ! rg -q 'Rust dyn trait OK' "$LOG"; then
  echo "dyn trait test did not reach the success output" >&2
  cat "$LOG" >&2
  exit 1
fi

cat "$LOG"
echo "Rust dyn trait dispatch works"
