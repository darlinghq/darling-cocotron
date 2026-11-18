/* Copyright (C) 2026 Lubos Dolezel */
#import <CoreText/CTFont.h>
#import <CoreText/CTFontDescriptor.h>

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

// Whether the descriptor describes one of the system UI fonts: a font made by
// CTFontCreateUIFontForLanguage() for any UI font type except the user and the
// user fixed-pitch types, or a copy of the descriptor of such a font. A
// descriptor made from a font name or from attributes is not one, whatever the
// name. NULL gives false.
CORETEXT_EXPORT bool CTFontDescriptorIsSystemUIFont(CTFontDescriptorRef descriptor);
