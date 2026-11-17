# Status item tests

These test how `NSStatusItem` is shown in the desktop's system tray: over D-Bus, with
the StatusNotifierItem protocol (`org.kde.StatusNotifierItem`, announced to
`org.kde.StatusNotifierWatcher`) and, for the item's menu, `com.canonical.dbusmenu`. D-Bus
does not depend on the window server, so the same test runs on the X11 and the Wayland
backend.

The guest program is `../appkit-status-item-notifier.m`; `run-notifier.py` starts it in a
private session bus (`dbus-run-session`) with a small StatusNotifierWatcher of its own and
makes the calls and listens to the signals of a tray. Build the guest program with the
guest cross-compiler (host clang, ld64 and the SDK of the source tree), then run the script
on the host:

    guest-cc.sh -o /tmp/asin ../appkit-status-item-notifier.m -framework Foundation -framework AppKit
    ./run-notifier.py /tmp/asin --display :99
    # on Wayland (see wayland.sh of the guest testing skill)
    ./run-notifier.py /tmp/asin --env DARLING_APPKIT_BACKEND=wayland \
        --env WAYLAND_DISPLAY=/path/to/wayland-1 --env XDG_RUNTIME_DIR=/path/to/runtime

What it checks:

- With no watcher on the bus the items exist (and can be read) and register nothing; when a
  watcher appears each item registers, and again when the watcher goes away and comes back.
- The properties: `Id` (the application and the autosave name), `Title`, `Category`, `Status`
  (`Passive` while hidden or without content), `Menu`, `ItemIsMenu`, `ToolTip`, and
  `IconPixmap` (22 and 44 pixel squares of the image, light grey for a template image, a
  text pixmap for an item that has only a title).
- `Activate` and `SecondaryActivate` send the item's action according to `sendActionOn:`, on
  the main thread.
- The exported menu (`GetLayout`, `Event`) is the item's `NSMenu`.
- `NewTitle`, `NewToolTip`, `NewIcon`, `NewStatus`, `LayoutUpdated` after the changes to the
  item.
- `removeStatusItem:` makes the item leave the bus.
- With no session bus (an address nobody listens on) the application runs and every change
  goes through.
- `api` mode: the contract of `NSStatusBar` and `NSStatusItem` that needs no tray (lengths,
  visibility, the menu being the object given, the tool tip, the defaults).

Needs on the host: `dbus-run-session`, python3 with dbus-python and PyGObject. The guest
program needs a window server (X11 or Wayland), like every AppKit program.
