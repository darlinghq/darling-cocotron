#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Runs tests/appkit-window-icon.m against tests/toplevel-icon-server.c, a private compositor that offers the
# xdg-toplevel-icon protocol and reports what each toplevel was given. Usage:
#   wayland-toplevel-icon.sh <scenario> <command that runs the guest binary, such as "darling shell /path/appkit-window-icon">
# The script appends the program's arguments (mode and seconds) and sets DARLING_APPKIT_BACKEND=wayland and
# WAYLAND_DISPLAY (an absolute host path) in the command's environment. Scenarios:
#   bundle    the icon of the application bundle, at the default sizes (16 to 256, scales 1 and 2)
#   sizes     the same icon, at the two sizes the compositor asks for (24 and 48)
#   runtime   the image given to -setApplicationIconImage: before the window is shown
#   change    that image, then another one set while the window is shown
#   removed   as change, but the compositor withdraws the protocol first: nothing may fail
#   absent    a compositor without the protocol: the window works, no icon is sent
# Needs wayland-scanner, wayland-protocols and a C compiler for wayland-server.
set -u
scenario=$1; shift
here=$(cd "$(dirname "$0")" && pwd)
# A Wayland socket path is limited to 107 bytes: keep the directory short.
work=$(mktemp -d)
server_pid=
guest_pid=
cleanup() {
    [ -n "$guest_pid" ] && kill "$guest_pid" 2>/dev/null
    [ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null
    rm -rf "$work"
}
trap cleanup EXIT INT TERM

for tool in wayland-scanner pkg-config cc; do
    command -v "$tool" >/dev/null || { echo "need $tool" >&2; exit 2; }
done
protocols=$(pkg-config --variable=pkgdatadir wayland-protocols)
wayland-scanner server-header "$protocols/stable/xdg-shell/xdg-shell.xml" "$work/xdg-shell-server-protocol.h"
wayland-scanner private-code "$protocols/stable/xdg-shell/xdg-shell.xml" "$work/xdg-shell.c"
icon_xml="$here/../../../CoreGraphics/WaylandSupport/protocols/xdg-toplevel-icon-v1.xml"
wayland-scanner server-header "$icon_xml" "$work/xdg-toplevel-icon-v1-server-protocol.h"
wayland-scanner private-code "$icon_xml" "$work/xdg-toplevel-icon.c"
# The request tables use one do-nothing handler for requests of different signatures.
cc -Wall -Wno-incompatible-pointer-types -I"$work" -o "$work/server" "$here/toplevel-icon-server.c" \
    "$work/xdg-shell.c" "$work/xdg-toplevel-icon.c" $(pkg-config --cflags --libs wayland-server) || exit 2

mkdir -m 700 "$work/r"
sock="$work/r/w"
server_args=()
mode=$scenario
case "$scenario" in
bundle) ;;
sizes) mode=bundle; server_args=(sizes 24,48) ;;
runtime) ;;
change) ;;
removed) mode=change; server_args=(remove-manager 2) ;;
absent) mode=change; server_args=(no-manager) ;;
*) echo "unknown scenario $scenario" >&2; exit 2 ;;
esac
server_out="$work/server.out"; guest_out="$work/guest.out"
export XDG_RUNTIME_DIR="$work/r"
"$work/server" w ${server_args[@]+"${server_args[@]}"} > "$server_out" 2>&1 &
server_pid=$!
for _ in $(seq 50); do [ -S "$sock" ] && break; sleep 0.1; done
[ -S "$sock" ] || { echo "FAIL: the compositor did not start"; cat "$server_out"; exit 1; }

env DARLING_APPKIT_BACKEND=wayland WAYLAND_DISPLAY="$sock" "$@" "$mode" 12 > "$guest_out" 2>&1 < /dev/null &
guest_pid=$!

wait_for() { # file pattern
    for _ in $(seq 300); do grep -q "$2" "$1" && return 0; sleep 0.1; done
    return 1
}
status=0
fail() { echo "FAIL: $*"; status=1; }
icons() { grep '^ICON ' "$server_out"; }
expect_icon() { # line number, what, regex
    local line
    line=$(icons | sed -n "$1p")
    if printf '%s\n' "$line" | grep -Eq "$3"; then echo "PASS: $2: $line"
    else fail "$2: got '$line', expected /$3/"; fi
}

wait_for "$guest_out" '^READY' || { echo "FAIL: the window never appeared"; cat "$guest_out" "$server_out"; exit 1; }
sleep 1.5
case "$scenario" in
bundle) expect_icon 1 "bundle icon" '^ICON icon-test 12 16@1 32@1 48@1 64@1 128@1 256@1 16@2 32@2 48@2 64@2 128@2 256@2 FF00FF00$' ;;
sizes) expect_icon 1 "icon at the requested sizes" '^ICON icon-test 4 24@1 48@1 24@2 48@2 FF00FF00$' ;;
runtime) expect_icon 1 "runtime icon" '^ICON icon-test 12 .* FFFF0000$' ;;
change|removed)
    expect_icon 1 "first icon" '^ICON icon-test 12 .* FFFF0000$'
    wait_for "$guest_out" '^CHANGED' || fail "the image was never changed"
    sleep 1.5
    if [ "$scenario" = change ]; then
        expect_icon 2 "icon after setApplicationIconImage:" '^ICON icon-test 12 .* FF0000FF$'
    else
        [ "$(icons | wc -l)" = 1 ] && echo "PASS: no icon sent after the protocol went away" ||
            fail "an icon was sent after the protocol went away"
    fi
    ;;
absent)
    wait_for "$guest_out" '^CHANGED' || fail "the image was never changed"
    sleep 1
    [ -z "$(icons)" ] && echo "PASS: no icon without the protocol" || fail "an icon was sent without the protocol"
    ;;
esac
grep -q '^APPID icon-test ' "$server_out" && echo "PASS: the toplevel has an app_id" || fail "no app_id"
kill -0 "$server_pid" 2>/dev/null || fail "the compositor exited (protocol error?)"
grep -qi "error" "$server_out" && { fail "compositor reported an error"; grep -i error "$server_out"; }
exit $status
