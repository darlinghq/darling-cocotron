# Wayland AppKit backend

AppKit windows are xdg-shell toplevels drawn into wl_shm buffers. The protocols used are the
core protocol, [xdg-shell](https://gitlab.freedesktop.org/wayland/wayland-protocols/-/blob/main/stable/xdg-shell/xdg-shell.xml),
xdg-decoration, xdg-output and pointer-gestures from
[wayland-protocols](https://gitlab.freedesktop.org/wayland/wayland-protocols); the core protocol is described at
<https://wayland.freedesktop.org/docs/html/>.

## Selecting it

The backend is used when a compositor is advertised (`WAYLAND_DISPLAY`) and X11 otherwise. Two settings
override that, the environment variable first:

- `DARLING_APPKIT_BACKEND` set to `wayland` or `x11`;
- the `DisplayBackend` string preference of the `org.darlinghq.AppKit` domain, with the same two values.

If the compositor or a required native library cannot be reached, the backend logs the reason and AppKit
continues with X11. `WAYLAND_DISPLAY` must be a **host filesystem path** when it is passed into Darling,
because the native libwayland resolves it outside the container. The choice is made by
`WaylandBackendSelected()` in `CoreGraphics/WaylandSupport/WaylandLibrary.m`, which CoreGraphics shares.

`WaylandDecorations` (`org.darlinghq.AppKit`) or `DARLING_WAYLAND_DECORATIONS`, set to `client`, makes the
backend draw the window frame itself even when the compositor offers server-side decorations.

## What it provides

- Windows: xdg toplevels, resize, hide and show, compositor close, nested popup menus, client or
  server-side decorations.
- Input: pointer with click grouping and scroll frames, keyboard through xkbcommon with the compositor's
  keymap and key repeat, aggregate and left/right modifier changes, touchpad pinch as magnify and rotate
  events.
- Cursors: themed cursors and `NSImage` cursors with their hotspot.
- Outputs: output batches are applied atomically, rotation and the xdg-output logical layout feed `NSScreen`,
  integer buffer scale follows the outputs a window is on.

Native libraries (libwayland-client, libwayland-cursor, libxkbcommon) are loaded with `dlopen` through the
loader's native-call table only when the backend is selected, so the bundle has no link-time dependency on
them. Every native call takes a fixed number of arguments: requests go through
`wl_proxy_marshal_array_flags` and events through `wl_proxy_add_dispatcher`, which avoids the variadic and
listener-struct differences between the Darwin and Linux calling conventions. The hand-written opcodes in
`CoreGraphics/WaylandSupport/WaylandProtocol.h` are checked against the generated protocol tables at startup.

## Building

Needs wayland-client 1.20 or newer (for `wl_proxy_marshal_array_flags`), wayland-cursor, xkbcommon, the
wayland-protocols XML and `wayland-scanner`; the backend is skipped when any of them is missing.

## Tests

`../../tests/appkit-wayland-backend-selection.m` needs no compositor. `../../tests/appkit-wayland-window-state.m`
needs a compositor and checks screens, scale and window frames through the API. The programs in `tests/` here
are manual fixtures that exercise one feature each against a real or private test compositor; their file
names say what they cover.
