#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Ancillary test tooling, GPL-3.0; the patched cocotron sources keep their own licence.
# Runs tests/x11-monitors.c on its own Xvfb or Xephyr (never the user's session).
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
temp=$(mktemp -d)
xpid=""

cleanup() {
    if [ -n "$xpid" ]; then
        kill "$xpid" 2>/dev/null || true
    fi
    rm -rf "$temp"
}
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap cleanup EXIT

cc -Wall -Wextra "$root/tests/x11-monitors.c" -lX11 -lXrandr -ldl -lm -o "$temp/probe"

if command -v xvfb-run >/dev/null 2>&1; then
    xvfb-run -a -s '-screen 0 1280x720x24' "$temp/probe"
elif command -v Xephyr >/dev/null 2>&1; then
    disp_num=""
    for i in $(seq 99 120); do
        if [ ! -e "/tmp/.X11-unix/X$i" ]; then
            disp_num="$i"
            break
        fi
    done
    if [ -z "$disp_num" ]; then
        echo "FAIL: could not find a free display number for Xephyr" >&2
        exit 1
    fi
    disp=":$disp_num"
    Xephyr "$disp" +extension RANDR -screen 1280x720 -ac -br -noreset >/dev/null 2>&1 &
    xpid=$!

    ready=0
    for _ in $(seq 1 30); do
        if DISPLAY="$disp" xset q >/dev/null 2>&1 || DISPLAY="$disp" xprop -root >/dev/null 2>&1; then
            ready=1
            break
        fi
        sleep 0.1
    done
    if [ "$ready" -ne 1 ]; then
        echo "FAIL: Xephyr failed to become ready on $disp" >&2
        exit 1
    fi

    DISPLAY="$disp" "$temp/probe"
else
    echo "FAIL: neither xvfb-run nor Xephyr found to run test" >&2
    exit 1
fi
