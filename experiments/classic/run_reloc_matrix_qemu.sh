#!/usr/bin/env bash
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OBJ="$(mktemp /tmp/rwpi-reloc-matrix.XXXXXX.o)"
CRT0_OBJ="$(mktemp /tmp/rwpi-crt0.XXXXXX.o)"
ELF="$(mktemp /tmp/rwpi-reloc-matrix.XXXXXX.elf)"
LINKER_SCRIPT="$(mktemp /tmp/linker-qemu-virt.XXXXXX.ld)"
RAM_BASES="${RAM_BASES:-0x80010000 0x80024000}"
QEMU="${QEMU:-/opt/homebrew/bin/qemu-system-riscv32}"

trap 'rm -f "$OBJ" "$CRT0_OBJ" "$ELF" "$LINKER_SCRIPT"' EXIT

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

echo "Object relocation summary:"
"$ROOT/build-rwpi-moved/bin/llvm-readobj" -r "$OBJ"

for RAM_ORIGIN in $RAM_BASES; do
  sed "s/ORIGIN = 0x80010000/ORIGIN = $RAM_ORIGIN/" \
    "$ROOT/experiments/classic/linker-qemu-virt.ld" > "$LINKER_SCRIPT"

  "$ROOT/build-rwpi-moved/bin/lld" \
    -flavor gnu \
    -m elf32lriscv \
    -T "$LINKER_SCRIPT" \
    "$CRT0_OBJ" \
    "$OBJ" \
    -o "$ELF"

  echo "Running relocation matrix with __gp_data_start = $RAM_ORIGIN"
  "$QEMU" \
    -machine virt \
    -bios none \
    -nographic \
    -semihosting-config enable=on,target=native \
    -kernel "$ELF"
done
