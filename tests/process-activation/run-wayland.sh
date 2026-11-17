#!/usr/bin/env bash
# Copyright (C) 2026 Lubos Dolezel
# Wayland variant of run-x11.sh, on the headless sway that darling-guest-testing/scripts/wayland.sh
# starts. The driver asks for the activation of helper A while the harness watches sway's tree:
# the compositor must either focus A's window or mark it urgent. (Focus stealing is refused
# without an input serial, which a headless compositor has none of; sway then marks the window
# urgent. The request reaching the compositor is what is being tested.)
#   DRIVER=<driver in the guest> HELPER=<helper in the guest> WAYLAND_ENV="$(wayland.sh)" run-wayland.sh
set -uo pipefail
temp=$(mktemp -d); trap 'kill $guest 2>/dev/null; rm -rf "$temp"' EXIT
eval "export ${WAYLAND_ENV:?output of wayland.sh}"
export SWAYSOCK=$(ls "$XDG_RUNTIME_DIR"/sway-ipc.*.sock | head -1)
timeout -s KILL 120 darling shell "${DRIVER:?driver in the guest}" "${HELPER:?helper in the guest}" wayland \
    </dev/null >"$temp/guest.log" 2>&1 &
guest=$!
for _ in $(seq 300); do grep -q REQUESTED "$temp/guest.log" && break; sleep 0.2; done
grep -q REQUESTED "$temp/guest.log" || { echo "FAIL: no request was made"; cat "$temp/guest.log"; exit 1; }
verdict=
for _ in $(seq 40); do
    verdict=$(swaymsg -t get_tree | python3 -c '
import json, sys
def walk(n):
    yield n
    for c in n.get("nodes", []) + n.get("floating_nodes", []):
        yield from walk(c)
for n in walk(json.load(sys.stdin)):
    if n.get("name") == "process-activation-A":
        print("focused" if n.get("focused") else "urgent" if n.get("urgent") else "none")
        break
')
    [ "$verdict" = focused ] || [ "$verdict" = urgent ] && break
    sleep 0.2
done
wait $guest
cat "$temp/guest.log"
if [ "$verdict" = focused ] || [ "$verdict" = urgent ]; then echo "PASS: compositor $verdict"; else echo "FAIL: window A is neither focused nor urgent ($verdict)"; exit 1; fi
