Build `appkit-toolbaritemgroup-control-representation.m` against the matching AppKit
headers and framework; run it inside a Darling prefix (`PASS` and exit 0 on success). It
needs no window server.

The documentation declares `controlRepresentation` (macOS 10.15) as a read-write property of
`NSToolbarItemGroup` that says how a toolbar displays a grouped toolbar item, of the enum
`NSToolbarItemGroup.ControlRepresentation` with the cases `automatic`, `expanded` and
`collapsed`; it states no default. The test checks, on a group made with
`initWithItemIdentifier:`, one made by the images factory, an instance of an application
subclass whose setter wraps the superclass one (the failing receiver in a real application
was a subclass) and a group decoded from a keyed archive: the default, set/get round trips
of every case, the value and the group's other state (`selectionMode`, `label`, `tag`,
`subitems`) not overwriting one another, two groups not sharing the value, a copy keeping
it and being independent afterwards, and `respondsToSelector:` for both accessors.

Observed on macOS 26.7.3 (probe tig.m): the default is `automatic`, and a copy has the default value. On master the selectors do not
exist: with ARC the test does not compile against master's header, without ARC the first
call raises an unrecognized-selector exception. The value is only stored, so no effect on
how the group is displayed is tested.
