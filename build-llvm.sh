#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
LLVM_DIR="$ROOT/llvm-project"
BUILD_DIR="$ROOT/build-rwpi-moved"
LLVM_REPO="git@github.com:2xs/llvm-project.git"
LLVM_BRANCH="riscv32-unknown-none-ropi-rwpi-proposal"

if [ ! -d "$LLVM_DIR/.git" ]; then
  git clone --branch "$LLVM_BRANCH" "$LLVM_REPO" "$LLVM_DIR"
fi

if [ ! -d "$BUILD_DIR" ]; then
  echo "missing build directory: $BUILD_DIR" >&2
  echo "configure it first, then rerun build-llvm.sh" >&2
  exit 1
fi

cd "$BUILD_DIR"
ninja clang lld
