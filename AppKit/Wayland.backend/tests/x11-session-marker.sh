#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Runs tests/color-session-probe.m in its marker mode on the X11 backend, which has no window-system
# session: the application must leave no "running" marker in its saved-state directory. Usage:
#   x11-session-marker.sh <command that runs color-session-probe, such as "darling shell /path/probe">
# Starts a private Xvfb. Needs Xvfb.
set -u
work=$(mktemp -d /tmp/xsm.XXXXXX)
xvfb_pid=
cleanup() {
    [ -n "$xvfb_pid" ] && kill "$xvfb_pid" 2>/dev/null
    rm -rf "$work"
}
trap cleanup EXIT INT TERM
command -v Xvfb >/dev/null || { echo "need Xvfb" >&2; exit 2; }
display=:${XSM_DISPLAY:-71}
Xvfb "$display" -screen 0 1024x768x24 > "$work/xvfb.out" 2>&1 &
xvfb_pid=$!
for _ in $(seq 50); do [ -e "/tmp/.X11-unix/X${display#:}" ] && break; sleep 0.1; done
unset WAYLAND_DISPLAY
env DARLING_APPKIT_BACKEND=x11 DISPLAY="$display" timeout -s KILL 60 "$@" marker 4 > "$work/guest.out" 2>&1 < /dev/null
cat "$work/guest.out"
status=0
grep -q '^PROBE done failures=0$' "$work/guest.out" || { echo "FAIL: the probe did not finish"; status=1; }
if grep -q '^RUNNING_MARKER present=0$' "$work/guest.out"; then
    echo "PASS: no running marker on X11"
else
    echo "FAIL: a running marker exists on X11"; status=1
fi
exit $status
