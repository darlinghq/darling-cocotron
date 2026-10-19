`coregraphics-gradient.c` is a pixel probe for `CGGradient` and the linear and radial draw calls. Build it
inside a Darling guest against this branch's CoreGraphics, with `-framework CoreGraphics
-framework CoreFoundation`, and run it. It prints `PASS` and exits 0, or prints each failing pixel and
exits 1.

It reads one row of an 8-bit RGBA bitmap and allows 8 units per channel, because Onyx2D samples the
stops about once per axis pixel. Cases: 2 and 5 stops, a hard stop, alpha, extend flags, radial,
`CGGradientCreateWithColors`, invalid input, a first stop above 0, unordered locations, out-of-range
locations, and the later-colour-wins rule at coincident stops (the 101-wide axis puts a sample exactly
on the stops).

Status: syntax-checked against the SDK headers only. It has not been run in a guest. The expected
values were computed with a host model of the stop evaluator and the Onyx2D axial sampling, and each
new case fails when its rule in `CGGradient.m` is removed in a scratch copy of that model.
