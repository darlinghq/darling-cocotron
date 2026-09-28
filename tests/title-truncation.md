# Attributed title truncation regression checklist

Exercise NSTextFieldCell and NSTableHeaderCell with the same attributed value.
Use a fixed-width font first, then a proportional font with kerning enabled.

- Head mode retains the end of the title and prefixes an ellipsis.
- Middle mode retains both ends and inserts one ellipsis between them.
- Tail mode retains the beginning and appends an ellipsis.
- Clipping mode draws without adding an ellipsis.
- Empty strings and zero-width rectangles do not throw range exceptions.
- A rectangle narrower than the ellipsis clips the ellipsis; it does not make
  an invalid substring range.
- Exactly fitting text is unchanged.
- For `A😀B`, `AéB` (decomposed e + accent), and emoji joined with ZWJ,
  sweep the rectangle width through each character boundary. No retained
  substring may start/end inside a Foundation composed-character sequence.
- With mixed attributes, retained characters keep their original attributes.
- Repeated drawing and measurement still use upstream NSStringDrawer caching.

The search uses bounded binary search over candidate lengths. Shaping can make
widths non-monotonic: verify that any accepted candidate fits, but do not infer
that binary search proves the globally longest possible candidate. The final
ellipsis-only fallback may exceed the rectangle and is clipped intentionally.

This checklist is not an executed test result. Build and graphical validation
remain required.
