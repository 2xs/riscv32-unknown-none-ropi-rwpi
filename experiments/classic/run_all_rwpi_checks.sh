#!/usr/bin/env bash
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
QEMU="${QEMU:-/opt/homebrew/bin/qemu-system-riscv32}"

cd "$ROOT"

ninja -C build-rwpi-moved \
  clang \
  lld \
  llc \
  llvm-mc \
  llvm-readobj \
  llvm-objdump \
  FileCheck \
  count \
  not \
  split-file \
  llvm-config

build-rwpi-moved/bin/llvm-lit -sv \
  llvm-project/clang/test/Driver/riscv-features.c \
  llvm-project/clang/test/CodeGen/RISCV/riscv-rwpi-gp-data.c \
  llvm-project/llvm/test/CodeGen/RISCV/rwpi-gp-data.ll \
  llvm-project/llvm/test/MC/RISCV/Relocations/rwpi-lo.s \
  llvm-project/lld/test/ELF/riscv-rwpi.s \
  llvm-project/lld/test/ELF/riscv-rwpi-missing-anchor.s

QEMU="$QEMU" QEMU_TIMEOUT=20s experiments/classic/run_reloc_matrix_qemu.sh
experiments/classic/check_runtime_reloc_sections.sh
QEMU="$QEMU" bash experiments/classic/check_runtime_reloc_apply.sh

echo "All RWPI checks passed"
