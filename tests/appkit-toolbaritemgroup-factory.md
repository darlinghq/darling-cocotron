Build `appkit-toolbaritemgroup-factory.m` against the matching AppKit headers and
framework; run it inside a Darling prefix (`PASS` and exit 0 on success). It needs no
window server.

The documentation describes `init(itemIdentifier:images:selectionMode:labels:target:action:)`
(Objective-C: `+groupWithItemIdentifier:images:selectionMode:labels:target:action:`, macOS
10.15) as creating a grouped toolbar item with the given identifier from images presented
as subitems, a selection mode, labels that correspond to the images and the target and
action the toolbar calls upon selection, and `selectionMode` as a read-write property of
three cases (`selectOne`, `selectAny`, `momentary`). A group's subitems are the toolbar items
of `subitems`, and the group's action applies to a subitem that has none. The test checks:
the result is a group (a subclass gets its own class) with the identifier, mode, target and
action; one subitem per image in order with the image and the label at its position; the
three modes; no labels, fewer labels and more labels than images; no images; two groups not
sharing subitems; the subitems being independent of the group; `selectionMode` as a property,
independent of the other state of the group and of other groups; a copy keeping the mode and
the subitems; and `respondsToSelector:` for the factory and the accessors.

Marked GUESS in the source, the choices the pages do not make: the identifier of a subitem
(the group's, a dot and its position), a missing label being the item's default, labels
beyond the images being ignored, the target and action being the group's own with none on
the subitems, a copy sharing its subitems' objects, and the default mode of a group made
another way being `selectOne`. On master the factory and `selectionMode` do not exist: with
ARC the test does not compile against master's headers, without ARC the factory call raises
an unrecognized-selector exception. The mode is only stored, so no drawing or selection is
tested; `selectedIndex`, `isSelected(at:)`, `controlRepresentation` and the titles factory are
not implemented.
