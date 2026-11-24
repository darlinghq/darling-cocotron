Build `appkit-tablecolumn-sizetofit.m` against the matching AppKit headers and framework;
run it inside a Darling prefix (`PASS` and exit 0 on success). It needs no window server.

The documentation says `sizeToFit()` resizes the column to fit the width of its header
cell, that a maximum width smaller than the header's width is raised to it and a minimum
width larger than it is lowered to it, and that a change of the column's width marks its
table view as needing display. The test therefore checks, with a header cell of a chosen
width: the width becoming the header's width (growing and shrinking), the raised maximum,
the lowered minimum, limits equal to the header's width staying, a second call changing
nothing, the width of a real header cell following its title, the table view being marked
only when the width changes, and a subclass that overrides the width and limit setters
seeing exactly the changes (width and maximum, not the minimum), and a subclass that
overrides `-headerCell`, whose override is not used (macOS measures the stored cell).
It also checks `respondsToSelector:`.

Observed on macOS 26.7.3 and Mac OS X 10.14.4, not documented: the header cell's width is that of
`-cellSize` (unrounded), the limits and the width are changed through the setters, the stored
header cell is measured, and only the table view, not its header view, is marked as needing display. On master the
method does not exist: with ARC the test does not compile against master's header, without
ARC every call raises an unrecognized-selector exception. Only the stored values are
tested, not the drawing. The helper classes use plain instance variables because the
legacy (i386) Objective-C runtime does not synthesize properties.
