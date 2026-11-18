#!/usr/bin/env bash
# Copyright (C) 2026 Lubos Dolezel
# Runs transparent-window.m (cross-compiled, GUEST_BIN is its path in the guest) against a headless
# sway in the mode given: tiled or floating. Needs sway, swaymsg, wtype, python3 and a started
# compositor: WAYLAND_DISPLAY (absolute socket path), XDG_RUNTIME_DIR and SWAYSOCK are in the
# environment. Checks in the compositor's window tree that nothing of the alpha-0 window is shown,
# then types keys while the compositor's focus is on the visible window.
# Exit status 0 when every check passes.
set -euo pipefail
mode=${1:?tiled or floating}
temp=$(mktemp -d)
kb=
trap 'kill "$kb" 2>/dev/null || true; rm -rf "$temp"' EXIT
DARLING_APPKIT_BACKEND=wayland timeout -s KILL 120 darling shell "${GUEST_BIN:?guest path of the test}" 14 \
    </dev/null >"$temp/guest.log" 2>&1 &
for _ in $(seq 1 300); do
    grep -q READY "$temp/guest.log" && break
    sleep 0.2
done
grep -q READY "$temp/guest.log" || { echo "FAIL: guest never printed READY"; cat "$temp/guest.log"; exit 1; }

if [ "$mode" = tiled ]; then
    swaymsg '[title="tw-visible"] floating disable' >/dev/null
else
    swaymsg '[title="tw-visible"] floating enable' >/dev/null
fi
swaymsg '[title="tw-visible"] focus' >/dev/null
sleep 1
swaymsg -t get_tree >"$temp/tree.json"
fail=0
python3 - "$temp/tree.json" "$mode" <<'PY' || fail=1
import json, sys
tree = json.load(open(sys.argv[1])); mode = sys.argv[2]
nodes = []
def walk(n):
    if n.get("type") in ("con", "floating_con") and (n.get("name") or n.get("app_id")):
        nodes.append(n)
    for c in n.get("nodes", []) + n.get("floating_nodes", []):
        walk(c)
walk(tree)
names = [n.get("name") for n in nodes]
ok = True
def check(cond, what):
    global ok
    print(("PASS " if cond else "FAIL ") + what)
    ok = ok and cond
check("tw-visible" in names, "the visible window is in the tree")
check("tw-hidden" not in names, "the alpha-0 window has no toplevel in the tree")
check(len(nodes) == 1, "exactly one toplevel of the application (%d: %s)" % (len(nodes), names))
vis = [n for n in nodes if n.get("name") == "tw-visible"]
if vis:
    check(vis[0].get("focused"), "the compositor's focus is on the visible window")
    check((vis[0].get("type") == "floating_con") == (mode == "floating"), "the window is %s" % mode)
sys.exit(0 if ok else 1)
PY
# A long-lived virtual keyboard first: a transient one leaves the seat without the keyboard capability.
wtype -k Shift_L -s 9000 -k Shift_L &
kb=$!
sleep 1
wtype -s 100 abc
for _ in $(seq 1 200); do
    grep -q -E '^(DONE|FAILED)' "$temp/guest.log" && break
    sleep 0.2
done
cat "$temp/guest.log"
grep -q '^DONE' "$temp/guest.log" || fail=1
exit $fail
