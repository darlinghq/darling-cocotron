#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Ancillary test tooling, GPL-3.0; the patched cocotron sources keep their own licence.
# Drives tests/appkit-label-text-no-overdraw.m: the guest test prints STATE lines and waits for an
# acknowledgement; this script captures the screen at each state and compares, with
# appkit-label-text-no-overdraw-compare.py, the window after a change with a window built directly in
# the final state.
# Usage (host): appkit-label-text-no-overdraw.sh <x11|wayland> <command running the test> [args...]
#   x11:     DISPLAY names the X server (import from ImageMagick captures the root window)
#   wayland: WAYLAND_DISPLAY and XDG_RUNTIME_DIR name the compositor (grim captures its output)
# The state directory is appended to the command as its last argument; when the guest sees the host's
# files under a prefix (Darling: /Volumes/SystemRoot), set GUEST_ROOT to that prefix.
set -euo pipefail
backend=$1; shift
[ $# -gt 0 ] || { echo "usage: $0 <x11|wayland> <command running the test>" >&2; exit 2; }
here=$(cd "$(dirname "$0")" && pwd)
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
capture() {
    case $backend in
    x11) import -window root "$1" ;;
    wayland) grim "$1" ;;
    *) echo "unknown backend $backend" >&2; exit 2 ;;
    esac
}
"$@" "${GUEST_ROOT:-}$dir" < /dev/null > "$dir/log" 2>&1 &
pid=$!
done=0
for _ in $(seq 1 1500); do
    for state in "$dir"/*.state; do
        [ -e "$state" ] || continue
        name=$(basename "$state" .state)
        [ -e "$dir/$name.ack" ] && continue
        capture "$dir/$name.png"
        touch "$dir/$name.ack"
    done
    if grep -q '^DONE' "$dir/log"; then done=1; break; fi
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.2
done
[ $done = 1 ] || { echo "the test did not finish" >&2; cat "$dir/log" >&2; kill "$pid" 2>/dev/null || true; exit 1; }
wait "$pid" || true
python3 -I "$here/appkit-label-text-no-overdraw-compare.py" "$dir"
