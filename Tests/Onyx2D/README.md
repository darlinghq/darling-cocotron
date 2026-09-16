# Straight-alpha image regression

Build `straight-alpha.m` as an Objective-C executable linked with AppKit and
CoreGraphics, using the same Darwin SDK and runtime as the framework build.
It needs no window or display server.

The test draws CGImages with explicit big/little byte order into a premultiplied
bitmap context. It checks alpha 0, 1, 128, 254, and 255, includes already
premultiplied controls, and verifies the source bytes remain unchanged.
Expected result: 20 PASS lines, failures=0, exit 0. The previous readers fail
six of these checks (intermediate straight-alpha values in both byte orders).
