# NSPopover

`popover.py DIR` writes `DIR/Popover.nib` (via `nibfixture.py`) with a top-level `NSPopover`: transient
behavior, no animation, a 200x100 content size and a content view controller. Build `popover.m` as an
Objective-C executable linked with AppKit and Foundation using the Darling SDK, copy the nib into the
prefix, and run `popover DIR` in a Darling guest with a display connection (it opens a window).

The test decodes the popover, checks the `-init` defaults, shows it above a view in a window with
`NSMaxYEdge` and checks its frame, then checks that `popoverShouldClose:` can veto `-performClose:` and
that the delegate sees will/did show and close in order. The expected result is
`popover checks=15 failures=0`. The pre-fix library's forwarding stub returns nil from `-initWithCoder:`,
so loading the nib raises "Failed to decode element 0 of 1 in array for key NS.objects".
