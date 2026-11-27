#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Runs wayland-color-surface-client.c against wayland-color-session-server.c in its "surface"
# scenario. The client stands in for a toplevel and two OpenGL subwindow surfaces;
# each one gets its own color-management objects and must react on its own when the compositor
# changes the preferred description. No guest or real compositor is needed.
#
# Needs wayland-scanner, wayland-protocols and C compiler support for wayland-client/server.
set -u
here=$(cd "$(dirname "$0")" && pwd)
protocols_dir="$here/../../../CoreGraphics/WaylandSupport/protocols"
work=$(mktemp -d)
server_pid=
cleanup() {
    [ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null
    rm -rf "$work"
}
trap cleanup EXIT INT TERM

for tool in wayland-scanner pkg-config cc timeout; do
    command -v "$tool" >/dev/null || { echo "need $tool" >&2; exit 2; }
done

protocols=$(pkg-config --variable=pkgdatadir wayland-protocols)
for pair in \
    "$protocols/stable/xdg-shell/xdg-shell.xml:xdg-shell" \
    "$protocols/unstable/tablet/tablet-unstable-v2.xml:tablet-unstable-v2" \
    "$protocols_dir/color-management-v1.xml:color-management-v1" \
    "$protocols_dir/color-representation-v1.xml:color-representation-v1" \
    "$protocols_dir/xdg-session-management-v1.xml:xdg-session-management-v1" \
    "$protocols_dir/linux-dmabuf-v1.xml:linux-dmabuf-v1" \
    "$protocols_dir/linux-drm-syncobj-v1.xml:linux-drm-syncobj-v1" \
    "$protocols_dir/fifo-v1.xml:fifo-v1"; do
    xml=${pair%%:*}
    name=${pair##*:}
    wayland-scanner server-header "$xml" "$work/$name-server-protocol.h" || exit 2
    wayland-scanner private-code "$xml" "$work/$name.c" || exit 2
done
wayland-scanner client-header "$protocols_dir/color-management-v1.xml" \
    "$work/color-management-v1-client-protocol.h" || exit 2

cc -Wall -Wno-incompatible-pointer-types -I"$work" -o "$work/server" \
    "$here/wayland-color-session-server.c" "$work/xdg-shell.c" "$work/tablet-unstable-v2.c" \
    "$work/color-management-v1.c" "$work/color-representation-v1.c" \
    "$work/xdg-session-management-v1.c" "$work/linux-dmabuf-v1.c" \
    "$work/linux-drm-syncobj-v1.c" "$work/fifo-v1.c" \
    $(pkg-config --cflags --libs wayland-server) || exit 2
cc -Wall -I"$work" -o "$work/client" \
    "$here/wayland-color-surface-client.c" "$work/color-management-v1.c" \
    $(pkg-config --cflags --libs wayland-client) || exit 2

mkdir -m 700 "$work/r"
sock="$work/r/w"
server_out="$work/server.out"
client_out="$work/client.out"
export XDG_RUNTIME_DIR="$work/r"
"$work/server" w surface > "$server_out" 2>&1 &
server_pid=$!
for _ in $(seq 50); do [ -S "$sock" ] && break; sleep 0.1; done
[ -S "$sock" ] || { echo "FAIL: the compositor did not start"; cat "$server_out"; exit 1; }

status=0
fail() { echo "FAIL: $*"; status=1; }
wait_for() {
    for _ in $(seq 100); do grep -q "$2" "$1" && return 0; sleep 0.1; done
    return 1
}
expect_count() { # regex, expected count, description
    found=$(grep -Ec "$1" "$2")
    if [ "$found" = "$3" ]; then
        echo "PASS: $3 $4"
    else
        fail "$4: expected $3 matches of /$1/, got $found"
    fi
}

WAYLAND_DISPLAY="$sock" timeout -s KILL 15 "$work/client" > "$client_out" 2>&1
client_status=$?
wait_for "$client_out" '^CLIENT done' || {
    echo "FAIL: the client did not finish"; cat "$client_out" "$server_out"; exit 1;
}

grep -q '^CLIENT done changes=3$' "$client_out" || fail "every surface saw the preference change"
[ "$client_status" = 0 ] || fail "client exited with status $client_status"
expect_count '^SURFACE_HDR surface=[0-9]+ primaries=9 tf=9 min=1 max=400 reference=203 cll=1000 fall=400$' \
    "$server_out" 3 "initial descriptions"
expect_count '^PREFERRED_CHANGED surface=[0-9]+ identity=2$' \
    "$server_out" 3 "first preference identities"
expect_count '^PREFERRED_CHANGED surface=[0-9]+ identity=3$' \
    "$server_out" 3 "preference changes"
expect_count '^SURFACE_HDR surface=[0-9]+ primaries=6 tf=11 min=50 max=1000 reference=203 cll=2000 fall=500$' \
    "$server_out" 3 "per-surface HDR descriptions"
expect_count '^COLOR_FEEDBACK get_preferred_parametric identity=1$' \
    "$server_out" 6 "parametric feedback requests"

# Object ids are shared by the client and the server, so each reported surface can be checked
# individually instead of only counting protocol messages.
while read -r label id; do
    grep -q "^PREFERRED_CHANGED surface=$id identity=3$" "$server_out" || fail "$label: no preference change"
    grep -q "^SURFACE_HDR surface=$id primaries=6 tf=11 " "$server_out" || fail "$label: no HDR description"
done < <(sed -n 's/^CLIENT_SURFACE label=\([^ ]*\) id=\([0-9]*\)$/\1 \2/p' "$client_out")

kill -0 "$server_pid" 2>/dev/null || fail "the compositor exited (protocol error?)"
grep -qi 'error' "$server_out" && { fail "the compositor reported an error"; grep -i error "$server_out"; }
if [ $status = 0 ]; then echo "PASS: surface color changes"; fi
exit $status
