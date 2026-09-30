Build `view-zero-bounds.m` as an Objective-C executable linked against the rebuilt
AppKit and Foundation, then run it under Darling. It needs no window or event loop.

The test checks rectangle conversion and inverse conversion with zero width,
zero height, both dimensions zero, and nonzero bounds with independent 2x/3x
scaling. Empty axes retain unit scale; translation and nonempty-axis scaling
must remain intact. Expected final output: `zero bounds conversion PASS`.

Validation used an ARM64 integration AppKit carrying this coordinate-transform
change. All four cases pass; the same runtime without the change fails the first
case with four NaNs. The public candidate's complete NSView.m also compiles with
ARM64 staged dependency headers. These checks are not a clean full public AppKit
build or a complete iTerm2 rendering test.
