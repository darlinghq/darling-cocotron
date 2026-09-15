# Wayland AppKit backend

Select with `DARLING_APPKIT_BACKEND=wayland`. Without it, AppKit uses X11. If the
compositor or required native libraries cannot be reached, the backend logs the
reason and falls back to X11. `WAYLAND_DISPLAY` must be a **host filesystem path**
when passed through Darling; native libwayland resolves it outside the container.

Supported: xdg-shell toplevels, CPU drawing via wl_shm, pointer and keyboard input,
compositor keymaps, repeat, resize, hide/re-show, compositor close, themed cursors
and NSImage cursors. Images use immutable premultiplied ARGB storage and retain
their hotspot. Invalid image dimensions or nonfinite hotspots fall back to the arrow; finite
hotspots are clamped to the image bounds.
Native cursor buffers belong to the display, so an AppKit cursor can outlive its
Wayland connection. Image cursors do not require libwayland-cursor or a theme.

## Manual regression application

Build `tests/waylandtest.m` as a plain arm64 executable linked against AppKit with
your Darling SDK/toolchain. It does not need pointer authentication disabled.
Run it in a dedicated test prefix and compositor; set `DARLING_APPKIT_BACKEND` to
`wayland` and `WAYLAND_DISPLAY` to the compositor's host socket path.

The application draws red/green/blue views, a text view, and a second yellow window.
It logs input events, text, geometry, activation, and close delivery. Right-click
the red view to hide/re-show the second window. `EXIT_AFTER` controls its exit
timer (seconds); keep the second window visible while testing close on the first.

Set `IMAGE_CURSOR=1` to register a 32x24 image cursor over the red view, with
hotspot (5,7). With the pointer held over that view, capture using `grim -c`:

- Left 16 columns: magenta upper half, cyan lower half.
- Next 8 columns: transparent, preserving the red background.
- Right 8 columns: half-alpha magenta/cyan, blending over red.
- The image starts five pixels left and seven pixels above the pointer.

Move into the text view to restore the themed I-beam. Leave/re-enter the window,
resize it, and hide/re-show the second window. Test Romanian text `Hello ăîșț`,
key repeat and modifiers, then compositor close (`windowWillClose` in the log).

Also run without the selector variable on an isolated X server to verify
`backend X11Display` and typing, then with Wayland selected and an invalid socket:
one fallback message and an X11 window should result.

`UNPREMULT_CURSOR=1` selects an additional shared-renderer diagnostic: it uses
an unpremultiplied NSBitmapImageRep. Onyx2D's current 8-bit image reader does not
correctly premultiply this input, so transparent/partial-alpha pixels can render
incorrectly. The normal fixture supplies premultiplied data to test the backend
independently of that shared drawing issue.

## Remaining milestones

M2: xdg_popup menus, output-aware HiDPI rendering/cursors, and client-side title
bars where server decorations are absent. Current buffers use scale 1, menus are
separate toplevels, and the compositor controls window placement.
M3: clipboard and drag/drop. M4: EGL/OpenGL subwindows.

All native calls use fixed-arity functions; requests use
`wl_proxy_marshal_array_flags`, and events use a dispatcher to avoid the
Darwin/Linux arm64 variadic and listener ABI differences.
