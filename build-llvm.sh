#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
LLVM_DIR="$ROOT/llvm-project"
BUILD_DIR="$ROOT/build-rwpi-moved"
LLVM_REPO="git@github.com:2xs/llvm-project.git"
LLVM_BRANCH="riscv32-unknown-none-ropi-rwpi-proposal"
LLVM_SOURCE_DIR="$LLVM_DIR/llvm"

if [ ! -d "$LLVM_DIR/.git" ]; then
  git clone --branch "$LLVM_BRANCH" "$LLVM_REPO" "$LLVM_DIR"
fi

if [ ! -f "$BUILD_DIR/build.ninja" ]; then
  cmake -G Ninja -S "$LLVM_SOURCE_DIR" -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Debug \
    -DLLVM_ENABLE_ASSERTIONS=ON \
    -DLLVM_ENABLE_PROJECTS="clang;lld" \
    -DLLVM_TARGETS_TO_BUILD=RISCV
fi

cd "$BUILD_DIR"
ninja clang lld
