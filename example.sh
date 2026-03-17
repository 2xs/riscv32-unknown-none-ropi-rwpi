#!/usr/bin/env bash
set -e

"./build-llvm.sh"
"./build-rwpi-moved/bin/clang" -target riscv32-unknown-elf -march=rv32imac -mabi=ilp32 -frwpi -c "./experiments/rwpi_probe_plain.c" -o "./example.o"
"./build-rwpi-moved/bin/lld" -flavor gnu -m elf32lriscv -T "./linker-rwpi-ramro.ld" -e get_g "./example.o" -o "./example.elf"
rm -f "./example.o"
echo "Wrote ./example.elf"
