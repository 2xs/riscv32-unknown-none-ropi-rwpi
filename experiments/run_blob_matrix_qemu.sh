#!/usr/bin/env bash
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PAYLOAD_SRC="$ROOT/experiments/hello_reloc_matrix.c" \
PAYLOAD_ENTRY="main" \
TEXT_RUNTIME_ADDR="" \
bash "$ROOT/experiments/run_blob_qemu.sh"
