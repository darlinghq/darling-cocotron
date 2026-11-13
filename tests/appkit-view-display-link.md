Build `appkit-view-display-link.m` against the matching AppKit, QuartzCore and
Foundation headers/frameworks. Run inside a graphical Darling prefix, with
`DARLING_APPKIT_BACKEND=wayland` and a native Wayland socket, or
`DARLING_APPKIT_BACKEND=x11` and an X server.

The test creates real windows and drives the run loop. It checks callback sender,
hidden ancestors, hide/show, pause, ordered-out windows, reparenting, detached
and deallocated views, and target release on invalidation. Before the factory
implementation it exits 1 with an unrecognized-selector exception; afterwards
it must finish with `RESULT failures=0`.

This verifies the public factory and lifecycle. Existing CADisplayLink cadence
is timer-backed; the test does not establish compositor-vsync synchronization.
Native Wayland currently cannot report minimized state through isMiniaturized,
so minimizing is not covered by this test.
