#!/usr/bin/env bash
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OBJ="$(mktemp /tmp/rwpi-reloc-crash.XXXXXX.o)"
CRT0_OBJ="$(mktemp /tmp/rwpi-reloc-crash.XXXXXX.crt0.o)"
ELF="$(mktemp /tmp/rwpi-reloc-crash.XXXXXX.elf)"
QEMU="${QEMU:-/opt/homebrew/bin/qemu-system-riscv32}"

trap 'rm -f "$OBJ" "$CRT0_OBJ" "$ELF"' EXIT

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

"$ROOT/build-rwpi-moved/bin/lld" \
  -flavor gnu \
  -m elf32lriscv \
  --emit-relocs \
  -T "$ROOT/experiments/classic/linker-qemu-virt.ld" \
  "$CRT0_OBJ" \
  "$OBJ" \
  -o "$ELF"

set +e
OUTPUT="$(
  timeout 5s "$QEMU" \
    -machine virt \
    -bios none \
    -nographic \
    -semihosting \
    -kernel "$ELF" 2>&1
)"
STATUS=$?
set -e

if [ "$STATUS" -ne 124 ]; then
  printf '%s\n' "$OUTPUT"
  echo "expected QEMU to time out inside crt0 when .rela.dataramro is non-empty" >&2
  exit 1
fi

if printf '%s' "$OUTPUT" | rg -q 'RWPI relocation matrix OK'; then
  printf '%s\n' "$OUTPUT"
  echo "program unexpectedly reached main without applying runtime relocations" >&2
  exit 1
fi

echo "Runtime relocation absence blocks execution as expected"
