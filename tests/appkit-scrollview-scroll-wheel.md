Build `appkit-scrollview-scroll-wheel.m` against the matching AppKit headers and framework; run
it inside a Darling prefix (`PASS` and exit 0 on success). It needs a Darling guest with a window
system: it starts an `NSApplication` and puts the scroll view in a window.

The documentation says `scrollingDeltaX` and `scrollingDeltaY` are the preferred deltas of a scroll
wheel event, and that when `hasPreciseScrollingDeltas` is false they count lines, to be multiplied
by the height of a line or row, while otherwise the view scrolls by the amount itself. The test drives
`-[NSScrollView scrollWheel:]` on a 200x100 scroll view over a 1000x800 document, scrolled to
(100, 200), with line scroll amounts 7 (vertical) and 5 (horizontal), and reads the content view's
bounds origin:

- wheel events (not precise): a notch scrolls the axis' line scroll amount times the number of lines
  per notch, in the direction the document's flippedness gives, for flipped and unflipped documents,
  horizontally, with both axes in one event and through the document view's own `scrollWheel:`;
  clamping at both ends of both axes
- precise events, vertical: the scroll view moves by exactly the scrolling delta in points, whatever
  the line scroll amounts are, for flipped and unflipped documents, clamped at both ends

The documentation gives no number of lines for a notch: the test uses 3, the amount `NSScrollView` has
always used (GUESS). It does not say that the line scroll amounts are the height of a line or row of a wheel
(GUESS), nor which unit the precise amount is in (the page says to scroll by it; points is a GUESS).

Not tested: the sign of the horizontal axis of a precise event (not documented, and the X11 and Wayland
backends disagree), `usesPredominantAxisScrolling` (the scroll view does not use it) and the default line
scroll amount of a scroll view (not documented).

On master the precise cases fail (the scroll view takes the legacy deltas, a tenth of the scrolling
ones, times the line scroll amount and 3); the wheel cases pass and pin the behaviour that must not
change. Precise events are made with the private method the window system backends use to mark one, as
`appkit-precise-scroll-events.m` does.
