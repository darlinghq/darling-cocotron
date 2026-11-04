#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Ancillary test tooling, GPL-3.0; the patched cocotron sources keep their own licence.
# Builds the real CoreGraphics/CGWindowLevel.m on the host against the real CGWindowLevel.h (no
# display, no network); only CoreFoundation's macros are stubbed. CG_SRC_DIR points at another
# copy of CoreGraphics/ (used to mutation-check the test).
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
src=${CG_SRC_DIR:-$root/CoreGraphics}
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT

mkdir -p "$temp/CoreFoundation"
cat >"$temp/CoreFoundation/CoreFoundation.h" <<'STUB'
#include <stdint.h>
#define CF_ENUM(type, name) type name; enum
#define CF_IMPLICIT_BRIDGING_ENABLED
#define CF_IMPLICIT_BRIDGING_DISABLED
#define COREGRAPHICS_EXPORT extern
STUB

cc -x c -Wall -Wextra -Wno-deprecated -I"$temp" -I"$src/include" \
    "$src/CGWindowLevel.m" "$root/tests/coregraphics-window-level-for-key.c" -o "$temp/level"
"$temp/level"
