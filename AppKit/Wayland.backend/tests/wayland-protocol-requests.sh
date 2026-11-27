#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Runs tests/wayland-protocol-requests.m against a private headless compositor and checks, from the
# client's WAYLAND_DEBUG log, that the AppKit and CoreGraphics Wayland backends send the requests of the
# staging protocols the compositor offers (xdg-system-bell, alpha-modifier, xdg-toplevel-tag,
# xdg-dialog, cursor-shape, pointer-warp, idle-inhibit, color-management, color-representation,
# xdg-session-management, content-type, input-timestamps,
# keyboard-shortcuts-inhibit) and send nothing of a protocol the compositor lacks.
# An idle inhibitor must exist only while the process holds a power assertion that prevents display
# sleep, and the client must never ask the compositor for the user's idle state. Usage:
#   wayland-protocol-requests.sh sway|kwin <command that runs the guest binary, such as "darling shell /path/probe">
# The command's arguments get the number of seconds to wait for the pointer appended. The compositor is a
# private one (sway with the headless backend, or kwin_wayland --virtual --no-lockscreen); nothing of the
# desktop session is used. The pointer steps need an input device: they run on kwin, whose fake input
# protocol moves the pointer (the mover is started first, so the probe finds a pointer when it binds the
# seat), and are skipped on sway, whose headless backend has none.
# Needs sway or kwin_wayland, wayland-info, wayland-scanner, wayland-protocols and a C compiler.
set -u
if [ $# -lt 2 ]; then
    echo "usage: $0 sway|kwin command..." >&2
    exit 2
fi
which=$1; shift
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d /tmp/wpr.XXXXXX)
comp_pid=
cleanup() {
    # WPR_KEEP=<file> keeps the client's log for inspection.
    [ -n "${WPR_KEEP:-}" ] && cp "$work/guest.out" "$WPR_KEEP" 2>/dev/null
    [ -n "$comp_pid" ] && kill "$comp_pid" 2>/dev/null
    rm -rf "$work"
}
trap cleanup EXIT INT TERM
for tool in wayland-info wayland-scanner cc timeout; do
    command -v "$tool" >/dev/null || { echo "need $tool" >&2; exit 2; }
done
mkdir -m 700 "$work/r" "$work/c"
unset DISPLAY WAYLAND_DISPLAY SWAYSOCK I3SOCK
export XDG_RUNTIME_DIR="$work/r" XDG_CONFIG_HOME="$work/c" XDG_CACHE_HOME="$work/c" XDG_DATA_HOME="$work/c"
case "$which" in
sway)
    command -v sway >/dev/null || { echo "need sway" >&2; exit 2; }
    printf 'default_border none\n' > "$work/sway.conf"
    WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 \
        sway -c "$work/sway.conf" > "$work/comp.out" 2>&1 &
    comp_pid=$!
    for _ in $(seq 100); do compose=$(ls "$work"/r/wayland-* 2>/dev/null | grep -v '\.lock$' | head -n 1); [ -n "$compose" ] && break; sleep 0.1; done
    sock=${compose:-}
    ;;
kwin)
    command -v kwin_wayland >/dev/null || { echo "need kwin_wayland" >&2; exit 2; }
    export KWIN_WAYLAND_NO_PERMISSION_CHECKS=1
    kwin_wayland --virtual --no-lockscreen --socket kw --width 1280 --height 800 sleep 600 \
        > "$work/comp.out" 2>&1 &
    comp_pid=$!
    for _ in $(seq 150); do [ -S "$work/r/kw" ] && break; sleep 0.1; done
    sock="$work/r/kw"
    ;;
*) echo "usage: $0 sway|kwin command..." >&2; exit 2 ;;
esac
[ -S "${sock:-/nonexistent}" ] || { echo "FAIL: the compositor did not start"; cat "$work/comp.out"; exit 1; }
# The test types into nothing, but never run it beside a lock screen that could take input.
if pgrep -P "$comp_pid" -f kscreenlocker_greet >/dev/null; then echo "FAIL: a lock screen is running"; exit 1; fi
if [ "$which" = kwin ] && ! ps -o args= -p "$comp_pid" | grep -q -- '--no-lockscreen'; then
    echo "FAIL: kwin without --no-lockscreen"; exit 1
fi

info=$(WAYLAND_DISPLAY=$sock wayland-info 2>/dev/null)
globals=$(printf '%s\n' "$info" | sed -n "s/.*interface: '\([a-z_0-9]*\)'.*/\1/p")
has() { printf '%s\n' "$globals" | grep -qx "$1"; }
global_version() {
    printf '%s\n' "$info" | sed -n "s/.*interface: '$1'.*version: \([0-9][0-9]*\).*/\1/p" | head -n 1
}

# The kwin fake input tool: moves the pointer so that it enters the probe's window.
if [ "$which" = kwin ]; then
    wayland-scanner client-header "$here/../../../tests/kwin-fake-input.xml" "$work/fake-input-client-protocol.h"
    wayland-scanner private-code "$here/../../../tests/kwin-fake-input.xml" "$work/fake-input-protocol.c"
    cc -I"$work" -o "$work/kwin-motion" "$here/kwin-fake-motion.c" "$work/fake-input-protocol.c" -lwayland-client || exit 2
fi

guest_out="$work/guest.out"
mover_pid=
if [ "$which" = kwin ]; then
    WAYLAND_DISPLAY=$sock "$work/kwin-motion" 60 30 20 40 > "$work/mover.out" 2>&1 &
    mover_pid=$!
    sleep 1
fi
env DARLING_APPKIT_BACKEND=wayland WAYLAND_DISPLAY="$sock" WAYLAND_DEBUG=1 \
    timeout -s KILL 90 "$@" 10 > "$guest_out" 2>&1 < /dev/null &
guest_pid=$!
wait_for() { for _ in $(seq 400); do grep -q "$2" "$1" && return 0; sleep 0.1; done; return 1; }
wait_for "$guest_out" '^READY' || { echo "FAIL: the window never appeared"; tail -n 30 "$guest_out"; exit 1; }
wait "$guest_pid"
guest_status=$?
[ -n "$mover_pid" ] && kill "$mover_pid" 2>/dev/null

status=0
fail() { echo "FAIL: $*"; status=1; }
ok() { echo "PASS: $*"; }
skip() { echo "SKIP: $*"; }
# The requests the client sent between two markers.
steps() { # first marker, last marker (or end)
    awk -v a="STEP $1" -v b="${2:+STEP $2}" '
        index($0, a) == 1 { on = 1; next }
        b != "" && index($0, b) == 1 { on = 0 }
        on { print }' "$guest_out" | grep -- ' -> '
}
before() { # the requests sent before a marker
    awk -v b="STEP $1" 'index($0, b) == 1 { exit } { print }' "$guest_out" | grep -- ' -> '
}
expect_req() { # global, step, last step, regex, description
    local out
    out=$(steps "$2" "$3")
    if ! has "$1"; then
        if printf '%s\n' "$out" | grep -Eq "$4"; then fail "$5: sent without the compositor offering $1"
        else ok "$5: not sent, the compositor has no $1"; fi
    elif printf '%s\n' "$out" | grep -Eq "$4"; then ok "$5: $(printf '%s\n' "$out" | grep -E "$4" | head -n 1 | sed 's/^[^-]*-> //')"
    else fail "$5: expected /$4/ during $2"; fi
}
anywhere() { # global, request regex, description
    if ! has "$1"; then
        if grep -Eq -- "-> $2" "$guest_out"; then fail "$3: sent without the compositor offering $1"
        else skip "$3: the compositor has no $1"; fi
    elif grep -Eq -- "-> $2" "$guest_out"; then ok "$3: $(grep -E -- "-> $2" "$guest_out" | head -n 1 | sed 's/^[^-]*-> //')"
    else fail "$3: expected /$2/"; fi
}
anywhere_event() { # global, event regex, description
    if ! has "$1"; then
        if grep -Eq -- "<- $2" "$guest_out"; then fail "$3: received without the compositor offering $1"
        else skip "$3: the compositor has no $1"; fi
    elif grep -Eq -- "<- $2" "$guest_out"; then ok "$3: $(grep -E -- "<- $2" "$guest_out" | head -n 1 | sed 's/^[^-]*<- //')"
    else fail "$3: expected /$2/"; fi
}

grep -q '^PROBE done' "$guest_out" || { fail "the probe did not finish"; grep -E '^(STEP|READY|POINTER|FULLSCREEN|ASLEEP|PROBE)' "$guest_out" | tail -n 8; }
[ "$guest_status" = 0 ] || fail "the probe exited with status $guest_status"
echo "compositor globals: $(printf '%s\n' "$globals" | grep -E 'color_representation|color_manager|content_type|session_manager|pointer_warp|cursor_shape|wm_dialog|system_bell|alpha_modifier|toplevel_tag|shortcuts_inhibit|input_timestamps|idle_' | tr '\n' ' ')"

expect_req xdg_system_bell_v1 bell title 'xdg_system_bell_v1#[0-9]+\.ring\(' "NSBeep rings the compositor bell"
anywhere wp_alpha_modifier_v1 'wp_alpha_modifier_surface_v1#[0-9]+\.set_multiplier\(2147483647\)' "alphaValue 0.5 as a multiplier"
anywhere wp_alpha_modifier_v1 'wp_alpha_modifier_surface_v1#[0-9]+\.set_multiplier\(4294967295\)' "alphaValue 1 as a multiplier"
anywhere xdg_toplevel_tag_manager_v1 'xdg_toplevel_tag_manager_v1#[0-9]+\.set_toplevel_tag\(' "toplevel tag"
anywhere xdg_toplevel_tag_manager_v1 'xdg_toplevel_tag_manager_v1#[0-9]+\.set_toplevel_description\(.*"Protocol probe"' "toplevel description"
expect_req xdg_toplevel_tag_manager_v1 title sheet 'set_toplevel_description\(.*"Retitled probe"' "retitled description"
expect_req xdg_wm_dialog_v1 sheet modal 'xdg_dialog_v1#[0-9]+\.set_modal\(' "a sheet is a modal dialog"
expect_req xdg_wm_dialog_v1 modal pointer 'xdg_dialog_v1#[0-9]+\.set_modal\(' "a window in a modal session is a modal dialog"
# The idle state of the user is not the display's power state: nothing is asked of the compositor.
if grep -Eq -- '-> ext_idle_notifier_v1#[0-9]+\.get_(input_)?idle_notification\(' "$guest_out"; then
    fail "an idle notification was requested"; else ok "no idle notification is requested"; fi
if [ "$(grep -E '^ASLEEP ' "$guest_out" | head -n 1)" = "ASLEEP 0" ]; then ok "the display is not reported asleep"
else fail "CGDisplayIsAsleep() reported the display asleep"; fi
grep -q '^ASSERTION created=1' "$guest_out" || fail "the display sleep assertion could not be created"
grep -q '^ASSERTION released=1' "$guest_out" || fail "the display sleep assertion could not be released"
# A visible window holds an idle inhibitor exactly while the process holds the assertion.
if has zwp_idle_inhibit_manager_v1; then
    if before assert | grep -Eq 'zwp_idle_inhibit_manager_v1#[0-9]+\.create_inhibitor\('; then
        fail "an idle inhibitor was created without a display sleep assertion"
    else ok "no idle inhibitor while no display sleep assertion is held"; fi
    expect_req zwp_idle_inhibit_manager_v1 assert release 'zwp_idle_inhibit_manager_v1#[0-9]+\.create_inhibitor\(' "idle inhibitor while the assertion is held"
    expect_req zwp_idle_inhibit_manager_v1 release alpha 'zwp_idle_inhibitor_v1#[0-9]+\.destroy\(' "idle inhibitor dropped when the assertion is released"
else
    ok "no idle inhibitor: the compositor has no zwp_idle_inhibit_manager_v1"
fi
# The compositor confirms a fullscreen transition asynchronously; only then does the backend own the
# shortcuts or describe the surface as a game. kwin and sway both report the transition here.
if grep -q '^FULLSCREEN entered=1$' "$guest_out" && grep -q '^FULLSCREEN left=1$' "$guest_out"; then
    expect_req zwp_keyboard_shortcuts_inhibit_manager_v1 fullscreen-in fullscreen-out \
        'zwp_keyboard_shortcuts_inhibit_manager_v1#[0-9]+\.inhibit_shortcuts\(' "shortcuts inhibitor follows full screen"
    expect_req zwp_keyboard_shortcuts_inhibit_manager_v1 fullscreen-out idle \
        'zwp_keyboard_shortcuts_inhibitor_v1#[0-9]+\.destroy\(' "shortcuts inhibitor drops with full screen"
    expect_req wp_content_type_manager_v1 fullscreen-in fullscreen-out \
        'wp_content_type_v1#[0-9]+\.set_content_type\(3\)' "a fullscreen surface is a game"
else
    fail "the compositor did not report both fullscreen transitions"
fi
expect_req wp_content_type_manager_v1 assert release \
    'wp_content_type_v1#[0-9]+\.set_content_type\(2\)' "a surface shown under a display sleep assertion is video"
anywhere wp_content_type_manager_v1 'wp_content_type_manager_v1#[0-9]+\.get_surface_content_type\(' \
    "surface content type object"
anywhere wp_color_representation_manager_v1 \
    'wp_color_representation_surface_v1#[0-9]+\.set_coefficients_and_range\(1, 1\)' \
    "RGB surfaces use the identity matrix and full range"
if [ "$which" = kwin ]; then
    # The timestamp objects exist only for devices the seat has; headless sway has none.
    anywhere zwp_input_timestamps_manager_v1 \
        'zwp_input_timestamps_manager_v1#[0-9]+\.get_(pointer|keyboard|touch)_timestamps\(' \
        "a device gets an input timestamp object"
    anywhere_event zwp_input_timestamps_v1 'zwp_input_timestamps_v1#[0-9]+\.timestamp\(' \
        "input timestamps reach the device decoder"
else
    skip "input timestamps need an input device, which the headless sway has none of"
fi
anywhere wp_color_manager_v1 'wp_color_manager_v1#[0-9]+\.get_surface\(' "surface color management object"
anywhere xdg_session_manager_v1 'xdg_session_manager_v1#[0-9]+\.get_session\(' "compositor session"
if [ "$which" = kwin ]; then
    grep -q '^POINTER entered=1' "$guest_out" || fail "the pointer never entered the window"
    expect_req wp_cursor_shape_manager_v1 pointer idle 'wp_cursor_shape_device_v1#[0-9]+\.set_shape\([0-9]+, 4\)' "pointing hand cursor is the pointer shape"
    expect_req wp_cursor_shape_manager_v1 pointer idle 'wp_cursor_shape_device_v1#[0-9]+\.set_shape\([0-9]+, 9\)' "I-beam cursor is the text shape"
    expect_req wp_pointer_warp_v1 pointer idle 'wp_pointer_warp_v1#[0-9]+\.warp_pointer\(' "pointer warp"
else
    echo "SKIP: cursor shape and pointer warp need a pointer, which the headless sway has none of"
fi
# The color manager is one class, the one of the CoreGraphics backend: AppKit's backend must not carry a copy.
if grep -q 'Class WaylandColorManager is implemented in both' "$guest_out"; then
    fail "WaylandColorManager is implemented twice: $(grep 'Class WaylandColorManager is implemented in both' "$guest_out" | head -n 1)"
else ok "one WaylandColorManager class"; fi
kill -0 "$comp_pid" 2>/dev/null || fail "the compositor exited"
grep -Eqi 'protocol error|error:.*wl_|invalid (method|object)' "$work/comp.out" "$guest_out" && fail "a protocol error was reported: $(grep -Ehi 'protocol error' "$work/comp.out" "$guest_out" | head -n 2)"
[ $status = 0 ] && echo "PASS: $which"
exit $status
