#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
QEMU="${QEMU:-/opt/homebrew/bin/qemu-system-riscv32}"
TMPDIR="$(mktemp -d /tmp/rwpi-rust.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

LINKER_SCRIPT="$TMPDIR/linker-qemu-virt.ld"
CRT0_OBJ="$TMPDIR/crt0.o"
RUST_LL="$TMPDIR/main.ll"
RUST_OBJ="$TMPDIR/main.o"
ELF="$TMPDIR/rust-rwpi.elf"

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
  "$ROOT/experiments/rust/main.rs"

"$ROOT/build-rwpi-moved/bin/llc" \
  -mtriple=riscv32-unknown-elf \
  -mattr=+rwpi-gp-data \
  -filetype=obj \
  -o "$RUST_OBJ" \
  "$RUST_LL"

echo "Rust object RWPI relocations:"
"$ROOT/build-rwpi-moved/bin/llvm-objdump" \
  -dr --no-show-raw-insn -M no-aliases "$RUST_OBJ" | sed -n '1,80p'

"$ROOT/build-rwpi-moved/bin/lld" \
  -flavor gnu -m elf32lriscv \
  -T "$LINKER_SCRIPT" \
  "$CRT0_OBJ" "$RUST_OBJ" \
  -o "$ELF"

"$QEMU" \
  -machine virt \
  -bios none \
  -nographic \
  -semihosting-config enable=on,target=native \
  -kernel "$ELF"
