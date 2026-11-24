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
the result is a group with the identifier, mode, target and
action; one subitem per image in order with the image and the label at its position; the
three modes; no labels, fewer labels and more labels than images; no images; two groups not
sharing subitems; the subitems being independent of the group; `selectionMode` as a property,
independent of the other state of the group and of other groups; a copy with its own copies of the
subitems; and `respondsToSelector:` for the factory and the accessors.

Observed on macOS 26.7.3 (probe tig.m, marked QUIRK in the source): the subitems get UUID identifiers of their own and a label is also the palette label, the target and action are the group's, the factory makes an `NSToolbarItemGroup` also when sent to a subclass, and a copy has copies of the subitems and the default selection mode. On master the factory and `selectionMode` do not exist: with
ARC the test does not compile against master's headers, without ARC the factory call raises
an unrecognized-selector exception. The mode is only stored, so no drawing or selection is
tested; `selectedIndex`, `isSelected(at:)`, `controlRepresentation` and the titles factory are
not implemented.
