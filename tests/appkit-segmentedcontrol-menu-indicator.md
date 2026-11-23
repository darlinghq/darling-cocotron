Build `appkit-segmentedcontrol-menu-indicator.m` against the matching AppKit headers and
framework; run it inside a Darling prefix (`PASS` and exit 0 on success). It needs no window
server.

The documentation gives `setShowsMenuIndicator(_:forSegment:)` and
`showsMenuIndicator(forSegment:)` (macOS 10.13) on `NSSegmentedControl` a signature and nothing
else: no abstract, default, effect on drawing, or behavior for an index out of range. The test
checks both selectors, on a plain control and on an application subclass whose setter wraps the
superclass one (the failing receiver in a real application was a subclass): set/get per
segment, segments not affecting one another, the value and the segment's menu, tag, label,
enabled and selected state not overwriting one another, a segment added later, two controls not
sharing it.

Observed on macOS 26.7.3 and 10.14.4 (probe `p769.m` of batch 12a): the default is `NO`; an index out
of range raises `NSRangeException`; the other segment properties are independent of the value; an
archive carries it in the segment item under `NSSegmentItemShowMenuIndicator`, which the test decodes. On master the selectors do not exist: with ARC the test does not
compile against master's header, without ARC the first call raises an unrecognized-selector
exception. The value is only stored: no indicator is drawn.
