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
A window that shows nothing of a title bar of its own never gets a frame: a titled window with a transparent title
bar and either a full-size content view or a hidden title and hidden close, miniaturize and zoom buttons. It
declares client-side decorations and the backend draws none, as the application draws its own title bar. Changing
the style mask, the transparency or the title visibility of a shown window updates this at once.

A window that is not an application window (see `AppKit/DarlingWindowPresentation.h`) is related to the window it
belongs to: a pop-up window (a borderless window that cannot become main and is a child window, sits at the main
menu level or above, or ignores the mouse) is an ungrabbed `xdg_popup` of its parent window or the main window,
placed at the offset AppKit gave it, and other windows that are not application windows (panels, child windows
with a title bar, windows that cannot become main) are toplevels with `xdg_toplevel.set_parent`. A compositor
neither lists nor centres them, and a popup does not take the keyboard focus. With no mapped window to belong
to, such a window is an ordinary toplevel.

## What it provides

- Windows: xdg toplevels, resize, hide and show, compositor close, nested popup menus, client or
  server-side decorations.
  The windows are CoreGraphics toplevel windows (`CGSWindow.h`, the SPI the X11 backend uses too): CoreGraphics makes the
  wl_surface and, while a window is shown, its xdg-shell, xdg-decoration and layer-shell objects, and tells the backend
  the compositor's configure sequences, close requests and dismissed pop-ups; a window's number is its CoreGraphics
  window's id. CoreGraphics also relates a window to the window the backend names as its parent (`xdg_toplevel.set_parent`),
  asks for fullscreen and minimizing, keeps the state xdg-shell does not tell (minimized, covered, holding the focus),
  asks for activation (xdg-activation, also for another process' request, see `_CGSActivateProcess()`) and keeps the order
  of the windows (`_CGSOrderedToplevelWindowIDs()`: the one activated last first). The backend draws into the surface
  and decides what a window level, a window's presentation or its size mean for those requests, and adds what the
  protocol needs beyond that (session, scale, tags).
- The main menu in Plasma's global menu, or in the windows: see below.
- Input: pointer with click grouping and scroll frames, keyboard through xkbcommon with the compositor's
  keymap and key repeat, aggregate and left/right modifier changes, touchpad pinch as magnify and rotate
  events.
- Cursors: themed cursors and `NSImage` cursors with their hotspot. They are CoreGraphics' (the cursor SPI, `CGSCursor.h`):
  the shape goes to the compositor with cursor-shape-v1, an image or a theme image is the pointer's cursor surface.
- Clipboard and drag-and-drop, OpenGL and scale, fullscreen and pointer lock: see below.
- Window icon: with `xdg_toplevel_icon_manager_v1` (KWin 6.1 and later, others), every toplevel gets the application
  icon, `-[NSApplication applicationIconImage]` (the bundle icon or what the program set), as wl_shm buffers at the
  sizes the compositor asks for (16 to 256 when it names none), at scale 1 and 2. It follows
  `-setApplicationIconImage:`. Without the protocol the compositor picks an icon from the `app_id` (the process
  name), usually a generic one. Tests: `tests/wayland-toplevel-icon.sh`.
- Outputs: output batches are applied atomically, rotation and the xdg-output logical layout feed `NSScreen`,
  integer buffer scale follows the outputs a window is on.

## Main menu

When the compositor offers KDE's appmenu protocol (`org_kde_kwin_appmenu_manager`, from
[plasma-wayland-protocols](https://invent.kde.org/libraries/plasma-wayland-protocols)) and the session bus has an
owner of `com.canonical.AppMenu.Registrar`, the main menu goes to the desktop's global menu: it is exported on
the session bus with the [`com.canonical.dbusmenu`](https://github.com/AyatanaIndicators/libdbusmenu) protocol
(`AppKit/NSDBusMenu.m`, shared with the X11 backend) and every toplevel tells the compositor its address with
`org_kde_kwin_appmenu.set_address`. Plasma owns the registrar name only while a global menu view is in use (the
Global Menu applet or the application menu button of the title bars), so the name is the sign that the menu will
be seen.

Otherwise the windows that can carry it (titled, not panels or sheets, see `+[NSWindow
hasMainMenuForStyleMask:]`) draw the menu in a strip of their own. A compositor with `zwlr_layer_shell_v1` also
gets a menu bar surface along the top of the screen (an `NSMenuBarWindow`, see `NSMenuBarController`), shown only
while the application is active, has a main menu and no visible window carries the strip: an application with
only borderless or utility windows, or none. An xdg-shell client alone cannot place such a surface, so there the
strips are all there is. The bar follows the application's activation: it goes away after a moment when another
client takes the keyboard focus. Closing the last window does not end the activation, because nothing shows
whether another client has the focus then.

The `DarlingMenuBarStyle` preference (application domain, NSGlobalDomain or `org.darlinghq.AppKit`) changes the
choice: `window` always uses the strips (the global menu is not used), `screen` never uses them while the menu
can be shown outside the windows (global menu, or the menu bar surface), and `auto`, the default, is as
described above. The older boolean `DarlingInWindowMenuBar` means `window` when `DarlingMenuBarStyle` is not set.
The choice is made once, before the first window frame is computed.

## Clipboard and drag-and-drop

The general pasteboard is the selection of `wl_data_device` (core protocol, `wl_data_device_manager`
version 3 for drag actions). CoreGraphics owns that: its connection has a data device of its own and keeps the
pasteboard in step with the compositor's clipboard (`CoreGraphics/Wayland.backend/CGSWaylandClipboard.m`), so a
process without windows gets the clipboard too; this backend's data device only handles drag and drop. Text maps to `text/plain;charset=utf-8`, `text/plain` and `UTF8_STRING`, PNG and
TIFF images to `image/png` and `image/tiff`, file lists (`NSFilenamesPboardType`) to `text/uri-list`; other
types travel under their own names. Other named pasteboards are process-local. Publishing needs keyboard
focus and an input serial, so writes made earlier stay local until input arrives. A write made while a key or
click is handled takes that input's serial and is offered at once, even when the focus left in the meantime (a
virtual keyboard removed right after its key, say; `tests/clipboard-keyboard-removed.sh`). This is verified on
sway (wlroots) only: a compositor that also requires keyboard focus for `set_selection` may ignore a copy that
was handled after the window lost the focus. Transfers are
limited to 16 MiB and five seconds, a reader that stalls or an oversized transfer yields nil rather than truncated
data.

Incoming drops use AppKit's drag hit testing and the same enter, update, exit and perform sequence as the
other backends; copy and move are negotiated, the drag pasteboard is separate from the clipboard, and
callbacks run after native dispatch. Outgoing drags start from a mouse press and show a drag icon at the
output scale. A drag whose source and target are the same process stays in the process and keeps the
original Cocoa data. File lists are converted by `CoreGraphics/DarlingFileURIList.m`, shared with the X11 backend:
only paths below `/Volumes/SystemRoot` (host paths) are offered to other processes.

## OpenGL, layers and scale

OpenGL views and layer-backed content are EGL child surfaces (`wl_subsurface`, `wl_egl_window`,
[viewporter](https://gitlab.freedesktop.org/wayland/wayland-protocols/-/blob/main/stable/viewporter/viewporter.xml))
of the window surface, clipped and committed together with it. The EGL display is handed to OpenGL through
`CGLRegisterNativeDisplayForPlatform`. A context can be made current and swapped on any thread, as on the X11 backend; the parts of a swap that
touch window state (crop, position, stacking, the parent's commit) are done by the main thread, which a swap
on another thread asks through the main run loop. The drawable size in pixels and the scale are reported by the subwindow
(`drawablePixelSize`, `backingScaleFactor`), and `NSOpenGLView` reshapes when the allocation changes.

Scale follows the output a surface is on: the integer `wl_surface.set_buffer_scale`, or, when the compositor offers
[wp-fractional-scale-v1](https://gitlab.freedesktop.org/wayland/wayland-protocols/-/blob/main/staging/fractional-scale/fractional-scale-v1.xml)
together with viewporter, the preferred scale in 120ths with the buffer cropped and scaled through a viewport. The cursor
surface (CoreGraphics') and drag icons use the same scale; a compositor without viewporter gets an integer scale only. Swaps are paced to the
refresh rate of the window's output (`refreshMillihertz`).

EDR color descriptions and HDR metadata are applied per surface: the toplevel, the OpenGL
subwindow and each Metal layer's own surface get their own color-management objects and follow
their own preferred-description changes. The dma-buf path can negotiate either 8-bit ARGB8888
buffers for CPU-rendered content or half-float ARGB/XRGB16161616F buffers for producers whose
IOSurface pixels are actually half floats. It never converts an 8-bit surface into a floating-point
one, so an ordinary window buffer keeps the shm/8-bit fallback. A Metal layer with a float drawable
uses its Vulkan swapchain format and relies on the compositor's color description for HDR; the
render manager's float-format negotiation is available to native IOSurface producers.

## Fullscreen and pointer lock

A window is fullscreen when it has the fullscreen style bit, or is an untitled window that can become key and has
the size of one output (`DarlingFullscreenPolicy.h`, the rule the X11 backend uses too); it then sends
`xdg_toplevel.set_fullscreen` (made by the CoreGraphics window, which holds the drawing back until the compositor has
answered), naming the output it is on when that is unambiguous. The size to return to is kept
across leaving fullscreen, hiding and showing, and a `setFrame:` made while fullscreen wins over what the compositor
remembers. The decision is re-made when the outputs change.

`CGAssociateMouseAndMouseCursorPosition(false)` (relative mouse mode) locks the pointer with
[pointer-constraints](https://gitlab.freedesktop.org/wayland/wayland-protocols/-/blob/main/unstable/pointer-constraints/pointer-constraints-unstable-v1.xml)
and reads motion from
[relative-pointer](https://gitlab.freedesktop.org/wayland/wayland-protocols/-/blob/main/unstable/relative-pointer/relative-pointer-unstable-v1.xml),
with `deltaY` growing downward. While locked, `CGWarpMouseCursorPosition` moves only the cursor position the application
sees (it takes CoreGraphics global coordinates) and the pointer reappears there on unlock; without a lock a warp does
nothing, because a Wayland client cannot move the pointer. A compositor without the protocols logs that once.

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
needs a compositor and checks screens, scale and window frames through the API.
`../../tests/appkit-wayland-window-chrome.sh` checks which windows get a frame, on headless sway. The programs in `tests/` here
are manual fixtures that exercise one feature each against a real or private test compositor; their file
names say what they cover. `tests/wayland-surface-color.sh` needs no guest: it checks that a compositor
preference change reaches three independent surfaces (a toplevel, an OpenGL surface and a Metal layer
surface), each sending its own color description and HDR metadata. `tests/wayland-render-formats.sh`
also needs no guest: it checks that dma-buf feedback can advertise 8-bit and half-float formats with
the 16-byte table entries required by the protocol.
