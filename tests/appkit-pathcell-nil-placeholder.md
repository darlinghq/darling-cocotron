Build `appkit-pathcell-nil-placeholder.m` against the matching AppKit headers and
framework; run it inside a Darling prefix (`PASS` and exit 0 on success). It needs a Darling
guest but does not start an `NSApplication`.

The documentation (macOS 10.5) declares `placeholderString` as an optional string (Swift
`String?`) and `placeholderAttributedString` as an optional, copied attributed string, and
says the attributed string is drawn in place of the path components when there are none and
it is not `nil`, else the plain string is drawn with default attributes when it is not `nil`.
So `nil` is a valid value of both properties and means no placeholder, and it is the value of
a cell decoded from an archive that has no placeholder. The test checks, on a cell made with
`init`, an instance of an application subclass whose setter wraps the superclass one, and a
cell decoded from a keyed archive: no placeholder string by default, `nil` accepted by both
setters without raising, a string reading back from its own setter, the empty string being a
placeholder and not its absence, `nil` clearing a set placeholder string (and a cleared cell
taking a new one), the attributed string being copied, set and cleared through its own
setter, decoding an archive with and without the placeholder key, cells not sharing the
placeholder string, and `respondsToSelector:` for the four accessors.

How the two properties relate beyond the drawing precedence (whether setting one changes
what the other returns) is not specified by the pages and is not tested.

On master the `nil` cases do not survive: `-setPlaceholderString:` hands `nil` to
`-[NSAttributedString initWithString:]`, which crashes, and decoding an archive without the
placeholder key crashes the same way inside `-initWithCoder:`; so the run dies at the first
check. The non-nil checks pass on master and pin the behaviour that must not change. Drawing
of the placeholder is not tested (nothing draws it yet).
