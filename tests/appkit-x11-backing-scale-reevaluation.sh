#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Ancillary test tooling, GPL-3.0; the patched cocotron sources keep their own licence.
# Drives tests/appkit-x11-backing-scale-reevaluation.m: runs the guest test and, when it
# prints READY1 and READY2, changes the RandR mode of the X server with xrandr.
# Usage (host, Xvfb :99 started with +extension RANDR; the test binary built for Darling):
#   DISPLAY=:99 tests/appkit-x11-backing-scale-reevaluation.sh darling shell /path/to/test
# The arguments are the command that runs the test with DISPLAY=:99 visible to it.
set -euo pipefail
: "${DISPLAY:?set DISPLAY to the X server the test uses, e.g. :99}"
[ $# -gt 0 ] || { echo "usage: $0 <command running the test>" >&2; exit 2; }
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
output=$(xrandr | awk '/ connected/ { print $1; exit }')
original=$(xrandr | awk '/ connected/ { f = 1; next } f && /\*/ { print $1; exit }')
[ -n "$output" ] && [ -n "$original" ] || { echo "no active RandR output" >&2; exit 2; }

"$@" > "$temp/log" 2>&1 &
pid=$!
wait_for() {
    for _ in $(seq 1 300); do
        grep -q "$1" "$temp/log" && return 0
        sleep 0.2
    done
    echo "timed out waiting for $1" >&2
    kill "$pid" 2>/dev/null || true
    return 1
}
wait_for READY1
xrandr --newmode vdscale1 60.0 1024 1050 1100 1200 600 610 620 650 2>/dev/null || true
xrandr --addmode "$output" vdscale1
xrandr --output "$output" --mode vdscale1
wait_for READY2
xrandr --output "$output" --mode "$original"
status=0
wait "$pid" || status=$?
cat "$temp/log"
xrandr --output "$output" --mode "$original" || true
exit $status
