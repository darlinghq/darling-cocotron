Build `appkit-toolbaritemgroup-selected-index.m` against the matching AppKit headers and
framework; run it inside a Darling prefix (`PASS` and exit 0 on success). It needs no window
server.

The documentation declares `selectedIndex` (macOS 10.15) as a read-write `NSInteger`
property of `NSToolbarItemGroup`: the index of the most recently selected subitem, which with
the `selectAny` or `momentary` selection mode must not be taken to be the selected subitem.
It states no default and nothing about an index outside the subitems. The test checks, on a
group made with `initWithItemIdentifier:`, one made by the images factory, an instance of an
application subclass whose setter wraps the superclass one (the failing receiver in a real
application was a subclass) and a group decoded from a keyed archive: the default, set/get
round trips (including values outside the subitems), the value and the group's other state
(`selectionMode`, `controlRepresentation`, `label`, `tag`, `subitems`) not overwriting one
another, two groups not sharing the value, a copy keeping it and being independent
afterwards, and `respondsToSelector:` for both accessors.

Marked GUESS in the source: the default is 0; the setter stores any value, negative or past
the last subitem included; neither the setter nor `setSubitems:` checks the value against the
subitems. On master the selectors do not exist: with ARC the test does not compile against
master's header, without ARC the first call raises an unrecognized-selector exception. The
value is only stored: no subitem is selected or drawn as selected, and
`isSelectedAtIndex:` and `setSelected:atIndex:` are not implemented and not tested.
