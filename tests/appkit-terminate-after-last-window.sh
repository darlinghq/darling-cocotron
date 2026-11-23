#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 Lubos Dolezel
#
# Runs tests/appkit-terminate-after-last-window.m through its scenarios and checks whether the
# application quit (exit status 0) or kept running (77), and the order of the events. A window
# system must be available (DISPLAY, or WAYLAND_DISPLAY with DARLING_APPKIT_BACKEND=wayland).
# Usage: appkit-terminate-after-last-window.sh <fixture binary>
fixture=$1
fails=0

# check NAME EXPECTED-STATUS "EVENT-PATTERN..." fixture-options...
# The patterns must all appear in the output, in that order (each after the previous one).
check() {
    name=$1 want=$2 events=$3
    shift 3
    out=$("$fixture" "$@" 2>&1 < /dev/null)
    rc=$?
    ok=1
    [ "$rc" = "$want" ] || ok=0
    last=0
    oldifs=$IFS
    IFS='|'
    for ev in $events; do
        [ -n "$ev" ] || continue
        n=$(printf '%s\n' "$out" | awk -v l=$last -v e="$ev" 'NR > l && index($0, e) { print NR; exit }')
        if [ -z "$n" ]; then ok=0; else last=$n; fi
    done
    IFS=$oldifs
    if [ $ok = 1 ]; then
        echo "PASS: $name"
    else
        echo "FAIL: $name (status $rc, wanted $want; wanted events: $events)"
        printf '%s\n' "$out" | sed 's/^/    /'
        fails=$((fails + 1))
    fi
}

Q=0 R=77   # quit, kept running

# The setting is off by default: an application without the delegate method keeps running.
check "off: keeps running" $R "windowWillClose a" -delegate none -script "new a; performClose a"
# On: quits after the user closes the last window, after windowWillClose, through terminate.
check "on (domain): quits" $Q "windowWillClose a|applicationShouldTerminate|applicationWillTerminate" \
    -delegate none -setting domain -script "new a; performClose a"
check "on (app domain): quits" $Q "applicationShouldTerminate" -delegate none -setting app \
    -script "new a; performClose a"
check "app domain NO beats the global domain" $R "windowWillClose a" -delegate none -setting app-off \
    -script "new a; performClose a"
# The last of several windows.
check "on: first of two windows" $R "windowWillClose a" -delegate none -setting domain \
    -script "new a; new b; performClose a"
check "on: both windows closed" $Q "windowWillClose a|windowWillClose b|applicationShouldTerminate" \
    -delegate none -setting domain -script "new a; new b; performClose a; performClose b"
# Not closed by the user.
check "on: close by the application is not the user" $R "windowWillClose a" -delegate none \
    -setting domain -script "new a; close a"
check "on: orderOut is not a close" $R "step orderOut a" -delegate none -setting domain \
    -script "new a; orderOut a"
check "on: close refused by windowShouldClose" $R "windowShouldClose" -delegate none -setting domain \
    -shouldclose no -script "new a; performClose a"
# Windows that remain.
check "on: minimized window is still open" $R "windowWillClose b" -delegate none -setting domain \
    -script "new a; new b; miniaturize a; performClose b"
check "on: panel left over does not keep the application" $Q "windowWillClose a|applicationShouldTerminate" \
    -delegate none -setting domain -script "new a; new p panel; performClose a"
check "on: utility panel left over does not keep the application" $Q "applicationShouldTerminate" \
    -delegate none -setting domain -script "new a; new u utility; performClose a"
check "on: borderless window left over keeps the application" $R "windowWillClose a" -delegate none \
    -setting domain -script "new a; new b borderless; performClose a"
check "on: closing a panel is not the last window" $R "windowWillClose p" -delegate none -setting domain \
    -script "new a; new p panel; performClose p"
check "on: closing only a panel" $R "windowWillClose p" -delegate none -setting domain \
    -script "new p panel; performClose p"
# Applications the setting leaves alone.
check "on: status item present" $R "windowWillClose a" -delegate none -setting domain \
    -script "status; new a; performClose a"
check "on: accessory application" $R "windowWillClose a" -delegate none -setting domain \
    -script "policy accessory; new a; performClose a"
# The delegate decides when it implements the method.
check "delegate YES quits with the setting off" $Q \
    "windowWillClose a|ShouldTerminateAfterLastWindowClosed -> 1|applicationShouldTerminate|applicationWillTerminate" \
    -delegate yes -script "new a; performClose a"
check "delegate YES quits after close" $Q "windowWillClose a|ShouldTerminateAfterLastWindowClosed -> 1" \
    -delegate yes -script "new a; close a"
check "delegate YES: miniaturized window keeps running" $R "windowWillClose b" -delegate yes \
    -script "new a; new b; miniaturize a; performClose b"
check "delegate YES: quits when the last window is ordered out" $Q \
    "ShouldTerminateAfterLastWindowClosed -> 1|applicationShouldTerminate" -delegate yes \
    -script "new a; orderOut a"
check "delegate YES: panel left over" $Q "windowWillClose a|ShouldTerminateAfterLastWindowClosed -> 1" \
    -delegate yes -script "new a; new p panel; close a"
check "delegate YES: borderless window left over" $R "windowWillClose a" -delegate yes \
    -script "new a; new b borderless; close a"
check "delegate YES: window without a close button left over" $R "windowWillClose a" -delegate yes \
    -script "new a; new n noclose; close a"
check "delegate NO is asked and wins over the setting" $R "windowWillClose a|ShouldTerminateAfterLastWindowClosed -> 0" \
    -delegate no -setting domain -script "new a; performClose a"
check "delegate NO asked again for each last close" $R \
    "windowWillClose a|ShouldTerminateAfterLastWindowClosed -> 0|step show a|windowWillClose a|ShouldTerminateAfterLastWindowClosed -> 0" \
    -delegate no -script "new a; performClose a; show a; performClose a"
# Termination can be cancelled and the application runs on.
check "on: applicationShouldTerminate cancels" $R "windowWillClose a|applicationShouldTerminate" \
    -delegate none -setting domain -terminate cancel -script "new a; performClose a"
check "delegate YES: applicationShouldTerminate cancels" $R \
    "ShouldTerminateAfterLastWindowClosed -> 1|applicationShouldTerminate" \
    -delegate yes -terminate cancel -script "new a; performClose a"

[ $fails = 0 ] && echo "ALL PASS" || echo "$fails FAILED"
exit $((fails != 0))
