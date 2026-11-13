`coregraphics-gradient.c` is a pixel probe for `CGGradient` and the linear and radial draw calls. Build it
inside a Darling guest against this branch's CoreGraphics, with `-framework CoreGraphics
-framework CoreFoundation`, and run it. It prints `PASS` and exits 0, or prints each failing pixel and
exits 1.

It reads one row of an 8-bit RGBA bitmap and allows 8 units per channel, because Onyx2D samples the
stops about once per axis pixel. Cases: 2 and 5 stops, a hard stop, alpha, extend flags, radial,
`CGGradientCreateWithColors`, invalid input, a first stop above 0, unordered locations (sorted with their colours),
out-of-range locations (the gradient is not created), and the earlier-colour-shows rule at coincident
stops (pixel 50 of an axis from 0.5 to 100.5 sits exactly on the stops).

The stop rules (first and last stop, ordering, range of locations, coincident stops) follow
observations of CGGradient on macOS 10.14.4 and macOS 26.7.3 with the same pixel probe; both versions
agreed. The test itself has not been run in a Darling guest yet.
