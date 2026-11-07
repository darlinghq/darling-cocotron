#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Ancillary test tooling, GPL-3.0; the patched cocotron sources keep their own licence.
# Runs the real NSWorkspaceOpenConfiguration of AppKit/NSWorkspace.m on the host against a minimal mock root class
# (no Foundation, no display). The @interface is extracted from AppKit/include/AppKit/NSWorkspace.h and the
# @implementation (with the file-scope declarations just before it) from AppKit/NSWorkspace.m at test time.
# Usage: tests/workspace-open-configuration-host.sh [OBJC_PREFIX]
#   OBJC_PREFIX holds include/objc/runtime.h and lib/libobjc for a GNUstep-ABI runtime (libobjc2); without it the
#   compiler's default search paths are used. Environment: CC (default cc), OBJC_RUNTIME (default gnustep-1.7),
#   OBJC_LIBS (default "-lobjc -lpthread"), APPKIT_SRC_DIR (another copy of AppKit/, to check the test fails there).
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
src=${APPKIT_SRC_DIR:-$root/AppKit}
prefix_flags=()
[ $# -ge 1 ] && prefix_flags=(-I"$1/include" -L"$1/lib")
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT

awk '/^@interface NSWorkspaceOpenConfiguration[ :]/ {on=1; found=1} on {print} on && /^@end/ {on=0} END {exit !found}' \
    "$src/include/AppKit/NSWorkspace.h" >"$temp/interface.inc" ||
    { echo "FAIL: no @interface NSWorkspaceOpenConfiguration in NSWorkspace.h; update $0" >&2; exit 1; }
# Lines after the previous @end are file-scope declarations that belong to the implementation.
awk '/^@end/ && !on {buf=""; next}
     /^@implementation NSWorkspaceOpenConfiguration$/ {on=1; found=1; printf "%s", buf}
     on {print; if (/^@end/) on=0; next}
     {buf = buf $0 "\n"}
     END {exit !found}' "$src/NSWorkspace.m" >"$temp/implementation.inc" ||
    { echo "FAIL: no @implementation NSWorkspaceOpenConfiguration in NSWorkspace.m; update $0" >&2; exit 1; }

# shellcheck disable=SC2086
${CC:-cc} -x objective-c -fobjc-runtime="${OBJC_RUNTIME:-gnustep-1.7}" -fblocks -fno-objc-arc \
    -Wall -Wno-objc-root-class -Wno-unused-function \
    -DINTERFACE_INC="\"$temp/interface.inc\"" -DIMPLEMENTATION_INC="\"$temp/implementation.inc\"" \
    "${prefix_flags[@]}" "$root/tests/workspace-open-configuration-host.m" ${OBJC_LIBS:--lobjc -lpthread} \
    -o "$temp/open-configuration"
"$temp/open-configuration"
