Build `appkit-menuitemcell-draw-border-background.m` against the matching AppKit headers and
framework; run it inside a Darling prefix with a display (`PASS` and exit 0 on success). It
calls `[NSApplication sharedApplication]` and draws cells into bitmaps through a window, like
the other drawing tests.

The documentation lists `drawBorderAndBackground(withFrame:in:)`
(`drawBorderAndBackgroundWithFrame:inView:`) on `NSMenuItemCell`, not on `NSButtonCell`. It is
the step that covers whatever frames or backs a menu item, which runs ahead of the cell's other
drawing steps; the page for `-drawWithFrame:inView:` describes whole-cell drawing as the border
first and then the interior. The docs also say `NSMenuItemCell` no longer draws menus, and
`NSPopUpButtonCell` inherits from it. The test checks, for a bordered pop-up cell and a bordered
menu item cell:

- the selector exists on both classes;
- the method draws the same pixels as `-drawBezelWithFrame:inView:` (the pop-up cell's arrows
  included), and for the pop-up cell something other than nothing;
- `-drawWithFrame:inView:` still draws what a bezel followed by the interior draws, and a
  transparent cell draws nothing (unchanged behaviour);
- subclasses whose overrides call `super` (the failing receiver in a real application was a
  pop-up cell subclass) are found and no longer raise, reach the bezel once, are called once by
  whole-cell drawing, and draw the same pixels as the plain cell.

Marked GUESS in the source: for a button-based cell the border and background is its bezel; a
menu item's own background is not drawn. On master the selector does not exist: with ARC the
test does not compile against master's header, without ARC the first super call raises an
unrecognized-selector exception.
