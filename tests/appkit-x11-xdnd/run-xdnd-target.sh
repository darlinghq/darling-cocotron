#!/usr/bin/env bash
# Copyright (C) 2026 Lubos Dolezel
# Runs the XDND drop-target test on the shared Xvfb :99 with xfwm4 (start both
# first, see the guest-testing notes). Builds the host driver, starts the guest
# target in Darling, then lets the driver drop a text/uri-list on it.
# Expected: the target prints "DROPPED /tmp/xdnd test file.txt" and "OK"; the
# driver prints "OK". Before the change no window is XdndAware and the driver
# fails with "target is not XdndAware".
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
temp=$(mktemp -d); trap 'rm -rf "$temp"' EXIT
cc -Wall "$here/xdnd-source-driver.c" -lX11 -o "$temp/driver"
export DISPLAY=:99
darling shell "${GUEST_TARGET:?path of the cross-compiled appkit-x11-xdnd-target in the guest}" >"$temp/target.log" &
tgt=$!
"$temp/driver"
wait $tgt
cat "$temp/target.log"
