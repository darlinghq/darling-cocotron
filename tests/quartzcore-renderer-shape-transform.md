# Shape layer with a displayLayer: delegate

`quartzcore-renderer-shape-transform.m` renders a red 20x10 CAShapeLayer, centred at
(32, 32) and rotated 90 degrees about its anchor, whose delegate implements
`-displayLayer:` without setting contents. Rotated, it covers x 27-37, y 22-42, so
(32, 40) is red and (24, 32) is black.

Exit 5: nothing drawn (the delegate replaced the path drawing); exit 6: transform not
applied; exit 0: correct.

Build it like any AppKit/QuartzCore client (link AppKit, QuartzCore, CoreGraphics, OpenGL)
and run it with the Wayland backend on a headless compositor.

## Verified on 2026-10-08

QuartzCore built from `origin/master` (673716eec) with and without the change, swapped
into a private Darling prefix between runs, native Wayland on a headless Sway:

- without the change: exit 5, "shape layer drew nothing"
- with the change: exit 0
