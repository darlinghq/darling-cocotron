# CGPath nullability

`coregraphics-path-nullability.swift` is a typecheck-only regression for VibeDarling/darling#1007. Run it against an SDK that provides the CoreGraphics Clang module built from this tree's headers:

    swiftc -typecheck coregraphics-path-nullability.swift

Without the audit in CGPath.h, `CGMutablePath()` imports as `CGMutablePath?` and both uses fail with "value of optional type 'CGMutablePath?' must be unwrapped". With it the file typechecks.

Measured with swift 6.3.3 (aarch64) on a module map that includes only CGPath.h with stand-in CF macros (the CoreGraphics module itself was not built): the pre-audit header gives those two errors, the audited header gives none.
