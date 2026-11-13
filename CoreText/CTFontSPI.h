/* Copyright (C) 2026 Lubos Dolezel */
#import <CoreText/CTFont.h>

// Exported by CoreText on macOS but not declared in the SDK headers. Not
// installed; for callers inside the tree and tests that declare it themselves.

// Draws glyphs starting at the context's text position, using the font and
// size of the CTFont (which stay set in the context), and advances the text
// position by the advances.
CORETEXT_EXPORT void CTFontDrawGlyphsWithAdvances(CTFontRef font, const CGGlyph *glyphs,
                                                  const CGSize *advances, size_t count,
                                                  CGContextRef context);

// Whether text in this font is antialiased.
CORETEXT_EXPORT bool CTFontShouldAntiAlias(CTFontRef font);
