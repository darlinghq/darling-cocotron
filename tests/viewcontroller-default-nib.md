# NSViewController default nib

`viewcontroller-default-nib.py DIR` writes `DIR/DefaultNibViewController.nib`, a keyed-archive nib
(written by `nibfixture.py`) whose File's Owner `view` outlet points at a 320x200 view. Build
`viewcontroller-default-nib.m` as a standalone Objective-C executable linked with AppKit and Foundation
using the Darling SDK, copy the nib into the prefix, and run `viewcontroller-default-nib DIR` in a
Darling guest. It needs no display connection.

A view controller created with a nil nib name loads the nib named after its class, as AppKit does since
OS X 10.10, and still raises `NSInvalidArgumentException` when that nib does not exist. The expected
result is `default nib checks=3 failures=0`. The pre-fix library raises "nibName is nil".
