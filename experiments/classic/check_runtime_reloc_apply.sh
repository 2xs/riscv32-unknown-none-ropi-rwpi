#!/usr/bin/env bash
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OBJ="$(mktemp /tmp/rwpi-reloc-crash.XXXXXX.o)"
CRT0_OBJ="$(mktemp /tmp/rwpi-reloc-crash.XXXXXX.crt0.o)"
CRT0_SRC="$(mktemp /tmp/rwpi-reloc-crash.XXXXXX.crt0.s)"
ELF="$(mktemp /tmp/rwpi-reloc-crash.XXXXXX.elf)"
QEMU="${QEMU:-/opt/homebrew/bin/qemu-system-riscv32}"
DATA_RUNTIME_BASE="${DATA_RUNTIME_BASE:-0x80024000}"
STACK_RUNTIME_TOP="${STACK_RUNTIME_TOP:-0x8003F000}"

trap 'rm -f "$OBJ" "$CRT0_OBJ" "$CRT0_SRC" "$ELF"' EXIT

"$ROOT/build-llvm.sh"

{
  printf '.set DATA_RUNTIME_BASE, %s\n' "$DATA_RUNTIME_BASE"
  printf '.set STACK_RUNTIME_TOP, %s\n' "$STACK_RUNTIME_TOP"
  cat "$ROOT/experiments/classic/crt0.s"
} > "$CRT0_SRC"

"$ROOT/build-rwpi-moved/bin/clang" \
  --target=riscv32-unknown-elf \
  -march=rv32imac \
  -mabi=ilp32 \
  -c "$CRT0_SRC" \
  -o "$CRT0_OBJ"

"$ROOT/build-rwpi-moved/bin/clang" \
  --target=riscv32-unknown-elf \
  -march=rv32imac \
  -mabi=ilp32 \
  -frwpi \
  -ffreestanding \
  -c "$ROOT/experiments/classic/hello_reloc_matrix.c" \
  -o "$OBJ"

"$ROOT/build-rwpi-moved/bin/lld" \
  -flavor gnu \
  -m elf32lriscv \
  --emit-relocs \
  -T "$ROOT/experiments/classic/linker-qemu-virt.ld" \
  "$CRT0_OBJ" \
  "$OBJ" \
  -o "$ELF"

echo "Running runtime relocation check with DATA_RUNTIME_BASE = $DATA_RUNTIME_BASE"

"$QEMU" \
  -machine virt \
  -bios none \
  -nographic \
  -semihosting-config enable=on,target=native \
  -kernel "$ELF"

echo "Runtime relocation loop applied retained R_RISCV_32 entries as expected"
