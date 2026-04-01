#!/usr/bin/env bash
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
QEMU="${QEMU:-/opt/homebrew/bin/qemu-system-riscv32}"

C="$(mktemp /tmp/rwpi-hello-crt0.XXXXXX.o)"
M="$(mktemp /tmp/rwpi-hello-main.XXXXXX.o)"
E="$(mktemp /tmp/rwpi-hello.XXXXXX.elf)"
L="$(mktemp /tmp/linker-qemu-virt.XXXXXX.ld)"

trap 'rm -f "$C" "$M" "$E" "$L"' EXIT

cp "$ROOT/experiments/classic/linker-qemu-virt.ld" "$L"

"$ROOT/build-llvm.sh"

"$ROOT/build-rwpi-moved/bin/clang" \
  --target=riscv32-unknown-elf \
  -march=rv32imac \
  -mabi=ilp32 \
  -c "$ROOT/experiments/classic/crt0.s" \
  -o "$C"

"$ROOT/build-rwpi-moved/bin/clang" \
  --target=riscv32-unknown-elf \
  -march=rv32imac \
  -mabi=ilp32 \
  -frwpi \
  -ffreestanding \
  -c "$ROOT/experiments/classic/hello_semihost.c" \
  -o "$M"

"$ROOT/build-rwpi-moved/bin/lld" \
  -flavor gnu \
  -m elf32lriscv \
  -T "$L" \
  "$C" \
  "$M" \
  -o "$E"

echo "Running with __gp_data_start = 0x80010000"

"$QEMU" \
  -machine virt \
  -bios none \
  -nographic \
  -semihosting-config enable=on,target=native \
  -kernel "$E"
