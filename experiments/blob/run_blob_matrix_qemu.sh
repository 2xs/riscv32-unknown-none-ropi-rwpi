#!/usr/bin/env bash
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PAYLOAD_SRC="$ROOT/experiments/classic/hello_reloc_matrix.c" \
PAYLOAD_ENTRY="main" \
TEXT_RUNTIME_ADDR="" \
EXPECTED_OUTPUT="RWPI relocation matrix OK" \
bash "$ROOT/experiments/blob/run_blob_qemu.sh"
