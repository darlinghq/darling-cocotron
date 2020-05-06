#!/bin/sh

LLVM_VERSION='10.0.0'

set -e

if [ -d llvm ]; then
    rm -rf llvm
fi
git clone --depth 1 https://github.com/llvm/llvm-project.git -b "llvmorg-${LLVM_VERSION}" llvm

cd llvm

patch -p1 < ../cocotron-styling.patch

mkdir build
cd build

cmake -DCMAKE_BUILD_TYPE=Release -DLLVM_ENABLE_PROJECTS=clang -G 'Unix Makefiles' ../llvm
make -j$(nproc) clang-format
