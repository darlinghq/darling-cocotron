
#!/bin/sh

export PATH="$(pwd)/llvm/build/bin:${PATH}"

set -e

cd ../

clang-format --version

find . -path './formatting' -prune -o -path './.git' -prune -o \( \( -name '*.m' -o -name '*.mm' -o -name '*.h' -o -name '*.cpp' -o -name '*.c' \) -a -exec clang-format --verbose --style file -i {} \; \)
