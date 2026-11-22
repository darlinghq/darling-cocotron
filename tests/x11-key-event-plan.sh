#!/usr/bin/env bash
# Runs tests/x11-key-event-plan.c: the decision table, then, when fcitx5, dbus-run-session, xdotool and xvfb-run are
# installed, the event pump policy against a real XIM server. The server is a private fcitx5 (its own D-Bus
# session, config and runtime directories) on a private Xvfb, with Shift_L as its trigger key that switches
# between two keyboard input methods; the desktop session is never used. A Shift tap must switch the input method
# when the filter sees it first ("new") and must not when a modifier is handled ahead of the filter ("old"),
# and the application must be told of each press and release once, although this server forwards every Shift
# back as a second, unfiltered copy.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
cc -Wall -Wextra "$root/tests/x11-key-event-plan.c" -lX11 -o "$temp/plan"
"$temp/plan" table

for tool in fcitx5 fcitx5-remote dbus-run-session xdotool xvfb-run; do
    command -v "$tool" > /dev/null || { echo "SKIP: $tool is not installed, the XIM part did not run"; exit 0; }
done

mkdir -p "$temp/config/fcitx5" "$temp/data" "$temp/cache" "$temp/runtime" "$temp/home"
chmod 700 "$temp/runtime"
cat > "$temp/config/fcitx5/profile" <<PROFILE
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=keyboard-us

[Groups/0/Items/0]
Name=keyboard-us
Layout=

[Groups/0/Items/1]
Name=keyboard-de
Layout=

[GroupOrder]
0=Default
PROFILE
cat > "$temp/config/fcitx5/config" <<CONFIG
[Hotkey/TriggerKeys]
0=Shift_L

[Hotkey]
EnumerateWithTriggerKeys=True
CONFIG

cat > "$temp/session.sh" <<'SESSION'
#!/usr/bin/env bash
# $1: plan binary, $2: scratch directory. Runs inside the private X server and D-Bus session.
set -euo pipefail
plan=$1
temp=$2
fcitx5 -D --disable all --enable xcb,xim,dbus,dbusfrontend,keyboard,imselector > "$temp/fcitx5.log" 2>&1 &
server=$!
trap 'kill "$server" 2>/dev/null || true' EXIT
# fcitx5-remote would D-Bus-activate a second, default configured fcitx5 if asked before the name exists.
for _ in $(seq 100); do grep -q 'Service name change' "$temp/fcitx5.log" && break; sleep 0.1; done
grep -q 'Service name change' "$temp/fcitx5.log" || { echo "FAIL: the private fcitx5 did not start"; cat "$temp/fcitx5.log"; exit 1; }
sleep 0.5
for order in old new; do
    # The server selects the first input method of the group again on each run.
    fcitx5-remote -s keyboard-us
    "$plan" pump "$order" 4 > "$temp/$order.out" &
    client=$!
    for _ in $(seq 100); do grep -q READY "$temp/$order.out" && break; sleep 0.1; done
    grep -q READY "$temp/$order.out" || { echo "FAIL: the $order client did not start"; exit 1; }
    sleep 0.5
    xdotool key Shift_L
    sleep 1
    echo "$order: input method after a Shift tap: $(fcitx5-remote -n)" | tee -a "$temp/results"
    wait "$client"
    cat "$temp/$order.out"
done
SESSION
chmod +x "$temp/session.sh"

env -u DBUS_SESSION_BUS_ADDRESS -u WAYLAND_DISPLAY -u WAYLAND_SOCKET -u XDG_SESSION_TYPE \
    HOME="$temp/home" XDG_CONFIG_HOME="$temp/config" XDG_DATA_HOME="$temp/data" XDG_CACHE_HOME="$temp/cache" \
    XDG_RUNTIME_DIR="$temp/runtime" XMODIFIERS=@im=fcitx \
    xvfb-run -a -s '-screen 0 800x600x24' dbus-run-session -- "$temp/session.sh" "$temp/plan" "$temp" \
    | tee "$temp/log"

grep -q '^old: input method after a Shift tap: keyboard-us$' "$temp/log" ||
    { echo "FAIL: a modifier handled ahead of the filter changed the input method"; exit 1; }
grep -q '^new: input method after a Shift tap: keyboard-de$' "$temp/log" ||
    { echo "FAIL: the input method never saw the Shift tap"; exit 1; }
test "$(grep -c '^SUMMARY posted=2 texts=0 shift=0$' "$temp/log")" = 2 ||
    { echo "FAIL: a Shift tap was not reported exactly once per press and release, ending released"; exit 1; }
echo "PASS: the input method sees modifier keys, and each is reported once"
