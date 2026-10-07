# PDF document inspection regression

Compile `coregraphics-pdf-document-inspection.m` as an arm64 Objective-C guest
executable using the Darling SDK, linking Foundation and CoreGraphics. The test
uses Onyx2D headers to inspect the returned dictionary because CoreGraphics does
not yet implement the public PDF dictionary/string readers.

Run the executable under Darling and require `parsed PDF document inspection
passed` and guest exit 0. The same test exits 10 against a runtime without either
inspection export. The installed launcher can return 0 for a guest failure, so
capture the guest status explicitly:

```sh
DPREFIX="$PREFIX" darling shell /bin/bash -c "$GUEST_TEST; result=\$?; printf 'regression exit=%s\n' \"\$result\""
```

The fixture generator produces four PDFs with accurate object offsets and xref
entries: each combination of an Info dictionary and an Encrypt dictionary. The
test verifies parsed metadata text, absent metadata, stable borrowed dictionary
identity, and encryption detection. Its synthetic standard-security dictionary
is for detecting an Encrypt entry; this does not test passwords or decryption.

A focused implementation test can link the source tree's compiled
`CoreGraphics/CGPDFDocument.m` object into the executable, with `-export_dynamic`
and Onyx2D linked from the runtime's PrivateFrameworks directory. This exercises
the actual wrapper code and existing parser, but does not replace full framework
or ColorSync Utility runtime verification. ColorSync's private bitmap-context
imports remain a separate launch barrier.
