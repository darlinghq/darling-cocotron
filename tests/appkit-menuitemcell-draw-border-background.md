Build `appkit-menuitemcell-draw-border-background.m` against the matching AppKit headers and
framework; run it inside a Darling prefix with a display (`PASS` and exit 0 on success). It
calls `[NSApplication sharedApplication]` and draws cells into bitmaps through a window, like
the other drawing tests.

The documentation lists `drawBorderAndBackground(withFrame:in:)`
(`drawBorderAndBackgroundWithFrame:inView:`) on `NSMenuItemCell`, not on `NSButtonCell`. It is
the step that covers whatever frames or backs a menu item, which runs ahead of the cell's other
drawing steps; the page for `-drawWithFrame:inView:` describes whole-cell drawing as the border
first and then the interior. The docs also say `NSMenuItemCell` no longer draws menus, and
`NSPopUpButtonCell` inherits from it.

What the Macs do (macOS 26.7.3 and 10.14.4, x86_64 and i386; probe `p767.m` of batch 12a): the
method is found on `NSMenuItemCell` and `NSPopUpButtonCell`, not on `NSButtonCell`, `NSCell` or
`NSActionCell`. A pop-up button cell draws the border and background and then the interior; its
border and background is its bezel (a subclass sees border, bezel, interior, and the step draws the
pixels of the bezel). A plain menu item cell draws nothing in the step and does not go through the
bezel (a subclass sees border, interior), bordered or not (marked `QUIRK` in the source). The test
checks:

- the selector exists on both classes;
- for a bordered pop-up cell the step draws the same pixels as `-drawBezelWithFrame:inView:` (the
  arrows included) and something other than nothing; `-drawWithFrame:inView:` draws what a bezel
  followed by the interior draws, and a transparent cell draws nothing;
- for a bordered menu item cell the step draws nothing, and whole-cell drawing does not call the
  bezel;
- subclasses whose overrides call `super` (the failing receiver in a real application was a
  pop-up cell subclass) are found and no longer raise, reach the bezel once, are called once by
  whole-cell drawing, and draw the same pixels as the plain cell.

On master the selector does not exist: with ARC the test does not compile against master's header,
without ARC the first super call raises an unrecognized-selector exception.
