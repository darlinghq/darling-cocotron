# NSPopover from a NIBArchive nib

`nibarchive-popover.py DIR` writes `DIR/NIBArchivePopover.nib`, a binary NIBArchive nib (the format
`AppKit/nib.subproj/NSNibArchive.m` converts), authored from that file's documented layout. Its
top-level object is an `NSPopover` with `NSBehavior` (int8 2), `NSAnimates` (false), `NSContentWidth` and
`NSContentHeight` (double 0.0) and `NSHasFullSizeContent` (true, ignored). `popover.py` covers the keyed-plist
path; this covers the NIBArchive path for the same class.

Build `nibarchive-popover.m` as an Objective-C executable linked with AppKit and Foundation using the Darling
SDK, copy the nib into the prefix, and run `nibarchive-popover DIR` in a Darling guest. It needs no display.

The test checks the fixture starts with `NIBArchive`, loads it with `NSNib`, and checks the popover's behavior
(`NSPopoverBehaviorSemitransient`), `animates`, content size, and that stderr holds no "stub" line while
loading (the forwarding stub that an unimplemented class hits). Expected result:
`nibarchive popover checks=7 failures=0`. A runtime without `NSPopover` fails the decode checks.
