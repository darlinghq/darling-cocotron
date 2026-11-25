#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Runs tests/appkit-window-reorder-same-pass.m with the Wayland backend and checks, in the protocol trace,
# that windows ordered out and in again within one pass of the run loop keep their xdg_toplevel (no
# xdg_toplevel is destroyed or created in the LOOP section), while a window ordered out for good does lose its
# role (a destroy in the HIDE section) and gets a new one when it is ordered in again (a creation in the SHOW
# section).
# Usage: appkit-window-reorder-same-pass-wayland.sh <command that runs the fixture with WAYLAND_DISPLAY,
#        DARLING_APPKIT_BACKEND=wayland and WAYLAND_DEBUG=client in its environment>
set -u
out=$(mktemp)
"$@" > "$out" 2>&1 < /dev/null &
pid=$!
trap 'kill $pid 2>/dev/null; rm -f "$out"' EXIT
for _ in $(seq 600); do grep -q '^DONE' "$out" && break; kill -0 $pid 2>/dev/null || break; sleep 0.1; done
status=0
fail() { echo "FAIL: $*"; status=1; }
pass() { echo "PASS: $*"; }
grep -q '^DONE' "$out" || { echo "FAIL: the fixture did not finish"; grep -v '^\[' "$out" | head -20; exit 1; }
grep -q 'xdg_surface#[0-9]*.get_toplevel' "$out" || { echo "FAIL: no Wayland protocol trace (WAYLAND_DEBUG=client, Wayland backend)"; exit 1; }
grep '^FAIL' "$out" && status=1
# the lines of one section, from its begin marker to the end marker
section() { sed -n "/^$1-BEGIN/,/^$2/p" "$out"; }
count() { grep -c "$1" || true; }
loop=$(section LOOP LOOP-END)
[ -n "$loop" ] || { echo "FAIL: no LOOP section"; exit 1; }
creates=$(echo "$loop" | count 'xdg_surface#[0-9]*.get_toplevel')
destroys=$(echo "$loop" | count 'xdg_toplevel#[0-9]*.destroy()')
if [ "$creates" -eq 0 ] && [ "$destroys" -eq 0 ]; then
    pass "re-ordering windows out and in within one pass created and destroyed no xdg_toplevel"
else
    fail "re-ordering windows out and in within one pass created $creates and destroyed $destroys xdg_toplevels (want 0 and 0)"
fi
hide=$(section HIDE HIDE-END)
destroys=$(echo "$hide" | count 'xdg_toplevel#[0-9]*.destroy()')
if [ "$destroys" -eq 1 ]; then pass "a window ordered out for good lost its xdg_toplevel"; else fail "a window ordered out for good destroyed $destroys xdg_toplevels (want 1)"; fi
show=$(section SHOW SHOW-END)
creates=$(echo "$show" | count 'xdg_surface#[0-9]*.get_toplevel')
if [ "$creates" -eq 1 ]; then pass "a window ordered in again got an xdg_toplevel"; else fail "a window ordered in again created $creates xdg_toplevels (want 1)"; fi
if grep -q '^PASS' "$out"; then pass "the application stayed active while its windows were re-ordered"; else fail "the fixture reported a failure"; fi
[ $status -eq 0 ] && echo PASS || echo FAIL
exit $status
