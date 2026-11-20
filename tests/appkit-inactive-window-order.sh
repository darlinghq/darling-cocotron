#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Checks that an application that is not the active one cannot take the focus or get a task-bar entry by
# ordering a borderless window in and out (tests/appkit-inactive-window-order.m), on the backend the
# environment selects (DARLING_APPKIT_BACKEND=x11 with DISPLAY, or =wayland with WAYLAND_DISPLAY).
# Application A has a titled key window and is active. Application B orders a window of its own in and out
# repeatedly. While B does so, sampled through KWIN_QUERY (a command that prints one "KWINWIN <caption>
# k=v ..." line per window, see the impl note), no sample may
#  - list wmh-b-win in the task bar (skipTaskbar=false and not related to a parent), or
#  - have any window active but A's.
# On X11 the same is checked from the protocol, without KWin: wmh-b-win carries _NET_WM_STATE_SKIP_TASKBAR
# whenever it is mapped, and _NET_ACTIVE_WINDOW stays A's window.
# Usage: appkit-inactive-window-order.sh <command that runs the fixture, to which "a <secs>" and
#        "b <w> <h> <cycles>" are appended>
# COMPOSITOR_FOCUSES_NEW_TOPLEVELS=1 reports instead of failing on a focus change (KWin on Wayland).
# LATER=<behavior>: B changes its window's collection behavior to this after the window is on screen (use
# BEHAVIOR=0 LATER=0x248: it must leave the task bar; BEHAVIOR=0x248 LATER=0: it must enter it).
# ACCESSORY=1: B is an accessory application (use with BEHAVIOR=0 EXPECT_LISTED=1: still listed).
# BEHAVIOR=<collection behavior of B's window> (default 0x248); EXPECT_LISTED=1 expects the task-bar entry instead
# (with BEHAVIOR=0). SOLO=1 runs application B alone (it is active until it orders its window out the first time, so the window
# is mapped; it must still not be listed). Environment: BSIZE="<w> <h>" (default "90 70"), CYCLES (default 12), BACKEND_X11=1 for the protocol check.
set -u
size=${BSIZE:-90 70}
cycles=${CYCLES:-12}
outa=$(mktemp)
outb=$(mktemp)
samples=$(mktemp)
pida=
pidb=
trap '[ -z "$pida$pidb" ] || kill $pida $pidb 2>/dev/null; rm -f "$outa" "$outb" "$samples"' EXIT
if [ -z "${SOLO:-}" ]; then
    "$@" a 60 > "$outa" 2>&1 < /dev/null &
    pida=$!
    for _ in $(seq 400); do grep -q '^READY' "$outa" && break; sleep 0.1; done
    grep -q '^READY' "$outa" || { echo "FAIL: application A never became ready"; cat "$outa"; exit 1; }
    sleep 1
fi
status=0
fail() { echo "FAIL: $*"; status=1; }
pass() { echo "PASS: $*"; }

# shellcheck disable=SC2086
mode=b; [ -z "${ACCESSORY:-}" ] || mode=ba
"$@" $mode $size $cycles ${BEHAVIOR:-0x248} ${LATER:-} > "$outb" 2>&1 < /dev/null &
pidb=$!
n=0
[ -n "${SOLO:-}" ] || for _ in $(seq 100); do grep -q '^WARM' "$outb" && break; sleep 0.1; done
while kill -0 $pidb 2>/dev/null; do
    if [ -n "${KWIN_QUERY:-}" ]; then
        { echo "SAMPLE $n"; $KWIN_QUERY; } >> "$samples"
    elif [ -n "${BACKEND_X11:-}" ]; then
        {
            echo "SAMPLE $n"
            echo "ACTIVE $(xprop -root _NET_ACTIVE_WINDOW)"
            echo "A $(xdotool search --name '^wmh-a-main$' | head -1)"
            for id in $(xdotool search --onlyvisible --name '^wmh-b-win$' 2>/dev/null); do
                state=$(xprop -id "$id" _NET_WM_STATE | tr -d '\n')
                # The window manager removes the state when it unmaps the window: a window that is not
                # visible any more by the time the state was read does not count.
                case $state in *'not found'*) xdotool search --onlyvisible --name '^wmh-b-win$' 2>/dev/null | grep -qx "$id" || continue;; esac
                echo "BWIN $id $state"
            done
        } >> "$samples"
    fi
    n=$((n + 1))
    sleep 0.1
done
wait $pidb 2>/dev/null
grep -q '^DONE' "$outb" || { fail "application B did not finish"; cat "$outb"; }

if [ -n "${KWIN_QUERY:-}" ]; then
    listed=$(grep '^KWINWIN wmh-b-win ' "$samples" | grep 'skipTaskbar=false' | grep -vc 'transient=true')
    seen=$(grep -c '^KWINWIN wmh-b-win ' "$samples")
    stolen=$(grep '^KWINWIN ' "$samples" | grep 'active=true' | grep -vc '^KWINWIN wmh-a-main ')
    samplecount=$(grep -c '^SAMPLE' "$samples")
    if [ -n "${EXPECT_LISTED:-}" ]; then
        # A normal window of a regular application has a task-bar entry (control for the checks below).
        if [ "$listed" -gt 0 ]; then pass "KWin lists wmh-b-win in the task bar ($listed of $samplecount samples)"; else fail "KWin never listed wmh-b-win"; fi
    elif [ -n "${LATER:-}" ] && [ "$seen" = 0 ]; then fail "wmh-b-win was never mapped"
    elif [ "$listed" = 0 ]; then pass "KWin never listed wmh-b-win in the task bar ($samplecount samples, seen in $seen)"; else fail "KWin listed wmh-b-win in the task bar in $listed of $samplecount samples"; fi
    if [ -n "${LATER:-}" ]; then
        # B's only window is shown while B still counts as active (just launched), so it may take the focus.
        :
    elif [ -n "${SOLO:-}" ]; then
        # The application is the only one: its window is mapped while it is active (it counts as active
        # from launch), so it must be seen, and KWin must still keep it out of the task bar.
        if [ "$seen" -gt 0 ]; then pass "wmh-b-win was mapped (seen in $seen samples)"; else fail "wmh-b-win was never mapped"; fi
    elif [ "$stolen" = 0 ]; then pass "wmh-a-main stayed the only active window"
    elif [ -n "${COMPOSITOR_FOCUSES_NEW_TOPLEVELS:-}" ]; then
        # KWin on Wayland gives the focus to every toplevel that is mapped without an activation token, and the
        # client has no way to prevent it (xdg-shell, plasma-shell roles and an invalid xdg-activation token
        # were tried), so the focus is reported but not required there.
        echo "INFO: a window other than wmh-a-main was active in $stolen of $samplecount samples (the compositor focuses new toplevels)"
    else fail "a window other than wmh-a-main was active in $stolen of $samplecount samples"; fi
elif [ -n "${BACKEND_X11:-}" ]; then
    bad=$(grep '^BWIN ' "$samples" | grep -vc 'SKIP_TASKBAR')
    mapped=$(grep -c '^BWIN ' "$samples")
    moved=$(awk '/^ACTIVE/ { a = $NF } /^A / { if (a != "" && a != "0x0" && a != $2 && a != sprintf("0x%x", $2)) c++ } END { print c + 0 }' "$samples")
    if [ -n "${EXPECT_LISTED:-}" ]; then
        good=$(grep '^BWIN ' "$samples" | grep -vc 'SKIP_TASKBAR')
        if [ "$good" -gt 0 ] && [ "$bad" = "$mapped" ]; then pass "wmh-b-win never carries SKIP_TASKBAR ($mapped samples)"; else fail "wmh-b-win carried SKIP_TASKBAR"; fi
    elif [ "$bad" = 0 ]; then pass "wmh-b-win always carries SKIP_TASKBAR while mapped (seen mapped in $mapped samples)"; else fail "wmh-b-win without SKIP_TASKBAR in $bad samples: $(grep "^BWIN " "$samples" | grep -v SKIP_TASKBAR | head -2)"; fi
    if [ -n "${LATER:-}" ]; then :
    elif [ "$moved" = 0 ]; then pass "_NET_ACTIVE_WINDOW stayed on wmh-a-main"; else fail "the active window was not wmh-a-main in $moved samples"; fi
fi
[ -z "$pida" ] || { kill $pida 2>/dev/null; wait $pida 2>/dev/null; }
[ $status = 0 ] || { echo "--- A:"; cat "$outa"; echo "--- B:"; cat "$outb"; }
exit $status
