#!/usr/bin/env bash
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR="$(mktemp -d /tmp/rwpi-blob.XXXXXX)"
CRT0_OBJ="$TMPDIR/blob-crt0.o"
CRT0_ELF="$TMPDIR/blob-crt0.elf"
PAYLOAD_OBJ="$TMPDIR/hello-blob.o"
PAYLOAD_ELF="$TMPDIR/hello-blob.elf"
PAYLOAD_LD="$TMPDIR/blob-payload.ld"
BLOB="$TMPDIR/blob.bin"

QEMU="${QEMU:-/opt/homebrew/bin/qemu-system-riscv32}"
BLOB_LOAD_BASE="${BLOB_LOAD_BASE:-0x80000000}"
TEXT_LINK_BASE="${TEXT_LINK_BASE:-0x80030000}"
TEXT_RUNTIME_ADDR="${TEXT_RUNTIME_ADDR:-}"
LINKED_DATA_BASE="${LINKED_DATA_BASE:-0x80100000}"
STACK_TOP="${STACK_TOP:-0x8003F000}"
DATA_BASES="${DATA_BASES:-0x80010000 0x80024000}"
PAYLOAD_SRC="${PAYLOAD_SRC:-$ROOT/experiments/hello_blob.c}"
PAYLOAD_ENTRY="${PAYLOAD_ENTRY:-main}"

trap 'rm -rf "$TMPDIR"' EXIT

"$ROOT/build-llvm.sh"

sed \
  -e "s/__TEXT_RUNTIME_BASE__/$TEXT_LINK_BASE/" \
  -e "s/__LINKED_DATA_BASE__/$LINKED_DATA_BASE/" \
  "$ROOT/experiments/blob_payload.ld.in" > "$PAYLOAD_LD"

"$ROOT/build-rwpi-moved/bin/clang" \
  --target=riscv32-unknown-elf \
  -march=rv32imac \
  -mabi=ilp32 \
  -ffreestanding \
  -fno-builtin \
  -frwpi \
  -c "$PAYLOAD_SRC" \
  -o "$PAYLOAD_OBJ"

"$ROOT/build-rwpi-moved/bin/lld" \
  -flavor gnu \
  -m elf32lriscv \
  --emit-relocs \
  -T "$PAYLOAD_LD" \
  "$PAYLOAD_OBJ" \
  -o "$PAYLOAD_ELF"

for DATA_RUNTIME_BASE in $DATA_BASES; do
  "$ROOT/build-rwpi-moved/bin/clang" \
    --target=riscv32-unknown-elf \
    -march=rv32imac \
    -mabi=ilp32 \
    -Wa,-defsym,DATA_RUNTIME_BASE="$DATA_RUNTIME_BASE" \
    -Wa,-defsym,STACK_TOP="$STACK_TOP" \
    -c "$ROOT/experiments/blob_crt0.s" \
    -o "$CRT0_OBJ"

  "$ROOT/build-rwpi-moved/bin/lld" \
    -flavor gnu \
    -m elf32lriscv \
    -Ttext "$BLOB_LOAD_BASE" \
    "$CRT0_OBJ" \
    -o "$CRT0_ELF"

  python3 "$ROOT/experiments/blob_pack.py" \
    --crt0-elf "$CRT0_ELF" \
    --payload-elf "$PAYLOAD_ELF" \
    --entry "$PAYLOAD_ENTRY" \
    ${TEXT_RUNTIME_ADDR:+--text-runtime-addr "$TEXT_RUNTIME_ADDR"} \
    --output "$BLOB"

  echo "Running house blob with DATA_RUNTIME_BASE = $DATA_RUNTIME_BASE"
  "$QEMU" \
    -machine virt \
    -cpu rv32 \
    -nographic \
    -bios "$BLOB" \
    -semihosting
done
