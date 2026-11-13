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
- Clipboard and drag-and-drop, OpenGL and scale: see below.
- Outputs: output batches are applied atomically, rotation and the xdg-output logical layout feed `NSScreen`,
  integer buffer scale follows the outputs a window is on.

## Clipboard and drag-and-drop

The general pasteboard is the selection of `wl_data_device` (core protocol, `wl_data_device_manager`
version 3 for drag actions). Text maps to `text/plain;charset=utf-8`, `text/plain` and `UTF8_STRING`, PNG and
TIFF images to `image/png` and `image/tiff`, file lists (`NSFilenamesPboardType`) to `text/uri-list`; other
types travel under their own names. Other named pasteboards are process-local. Publishing needs keyboard
focus and an input serial, so writes made earlier stay local until input arrives. Transfers are limited to
16 MiB and five seconds, a reader that stalls or an oversized transfer yields nil rather than truncated data.

Incoming drops use AppKit's drag hit testing and the same enter, update, exit and perform sequence as the
other backends; copy and move are negotiated, the drag pasteboard is separate from the clipboard, and
callbacks run after native dispatch. Outgoing drags start from a mouse press and show a drag icon at the
output scale. A drag whose source and target are the same process stays in the process and keeps the
original Cocoa data. File lists are converted by `AppKit/DarlingFileURIList.m`, shared with the X11 backend:
only paths below `/Volumes/SystemRoot` (host paths) are offered to other processes.

## OpenGL, layers and scale

OpenGL views and layer-backed content are EGL child surfaces (`wl_subsurface`, `wl_egl_window`,
[viewporter](https://gitlab.freedesktop.org/wayland/wayland-protocols/-/blob/main/stable/viewporter/viewporter.xml))
of the window surface, clipped and committed together with it. The EGL display is handed to OpenGL through
`CGLRegisterNativeDisplayForPlatform`. Rendering and presentation happen on the main thread only
(`requiresMainThreadPresentation`); the drawable size in pixels and the scale are reported by the subwindow
(`drawablePixelSize`, `backingScaleFactor`), and `NSOpenGLView` reshapes when the allocation changes.

Scale follows the output a surface is on: the integer `wl_surface.set_buffer_scale`, or, when the compositor offers
[wp-fractional-scale-v1](https://gitlab.freedesktop.org/wayland/wayland-protocols/-/blob/main/staging/fractional-scale/fractional-scale-v1.xml)
together with viewporter, the preferred scale in 120ths with the buffer cropped and scaled through a viewport. Cursors
and drag icons use the same scale; a compositor without viewporter gets an integer scale only. Swaps are paced to the
refresh rate of the window's output (`refreshMillihertz`).

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
