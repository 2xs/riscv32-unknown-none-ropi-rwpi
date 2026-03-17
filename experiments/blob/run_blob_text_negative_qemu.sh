#!/usr/bin/env bash
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR="$(mktemp -d /tmp/rwpi-blob-neg-text.XXXXXX)"
CRT0_OBJ="$TMPDIR/blob-crt0.o"
CRT0_ELF="$TMPDIR/blob-crt0.elf"
PAYLOAD_OBJ="$TMPDIR/neg-text.o"
PAYLOAD_ELF="$TMPDIR/neg-text.elf"
PAYLOAD_LD="$TMPDIR/blob-payload.ld"
BLOB="$TMPDIR/blob.bin"
LOG="$TMPDIR/pack.log"

TEXT_LINK_BASE="${TEXT_LINK_BASE:-0x80030000}"
TEXT_RUNTIME_ADDR="${TEXT_RUNTIME_ADDR:-0x80034030}"
LINKED_DATA_BASE="${LINKED_DATA_BASE:-0x80100000}"
DATA_RUNTIME_BASE="${DATA_RUNTIME_BASE:-0x80010000}"
STACK_TOP="${STACK_TOP:-0x8003F000}"

trap 'rm -rf "$TMPDIR"' EXIT

"$ROOT/build-llvm.sh"

sed \
  -e "s/__TEXT_RUNTIME_BASE__/$TEXT_LINK_BASE/" \
  -e "s/__LINKED_DATA_BASE__/$LINKED_DATA_BASE/" \
  "$ROOT/experiments/blob/blob_payload.ld.in" > "$PAYLOAD_LD"

"$ROOT/build-rwpi-moved/bin/clang" \
  --target=riscv32-unknown-elf \
  -march=rv32imac \
  -mabi=ilp32 \
  -ffreestanding \
  -fno-builtin \
  -frwpi \
  -c "$ROOT/experiments/blob/hello_blob_text_negative.c" \
  -o "$PAYLOAD_OBJ"

"$ROOT/build-rwpi-moved/bin/lld" \
  -flavor gnu \
  -m elf32lriscv \
  --emit-relocs \
  -T "$PAYLOAD_LD" \
  "$PAYLOAD_OBJ" \
  -o "$PAYLOAD_ELF"

"$ROOT/build-rwpi-moved/bin/clang" \
  --target=riscv32-unknown-elf \
  -march=rv32imac \
  -mabi=ilp32 \
  -Wa,-defsym,DATA_RUNTIME_BASE="$DATA_RUNTIME_BASE" \
  -Wa,-defsym,STACK_TOP="$STACK_TOP" \
  -c "$ROOT/experiments/blob/blob_crt0.s" \
  -o "$CRT0_OBJ"

"$ROOT/build-rwpi-moved/bin/lld" \
  -flavor gnu \
  -m elf32lriscv \
  -Ttext 0x80000000 \
  "$CRT0_OBJ" \
  -o "$CRT0_ELF"

set +e
python3 "$ROOT/experiments/blob/blob_pack.py" \
  --crt0-elf "$CRT0_ELF" \
  --payload-elf "$PAYLOAD_ELF" \
  --entry main \
  --text-runtime-addr "$TEXT_RUNTIME_ADDR" \
  --output "$BLOB" >"$LOG" 2>&1
STATUS=$?
set -e

if [ "$STATUS" -eq 0 ]; then
  cat "$LOG"
  echo "expected blob_pack.py to reject relocated text with function-pointer data relocations" >&2
  exit 1
fi

rg -q 'outside the linked data window' "$LOG"
echo "Relocated-text negative rejected as expected"
