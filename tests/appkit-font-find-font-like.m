// CFLAGS: -framework AppKit -framework CoreText -framework CoreFoundation
// Copyright (C) 2026 Lubos Dolezel
//
// +[NSFont findFontLike:forString:withRange:inLanguage:] and +findFontLike:forCharacter:inLanguage: (used by
// browser engines for font fallback, not declared in the SDK headers): a font that shows the text in
// place of the given font (which one is for the system to say: for a character the given font covers,
// macOS 10.14.4 can answer another font), nil when no font has the text. Observed on macOS 10.14.4 and 26.7.3.
#import <AppKit/AppKit.h>
#include <stdio.h>

@interface NSFont (FindFontLikeSPI)
+ (NSFont *) findFontLike: (NSFont *) font forString: (NSString *) string withRange: (NSRange) range inLanguage: (id) language;
+ (NSFont *) findFontLike: (NSFont *) font forCharacter: (unichar) character inLanguage: (id) language;
@end

static int failures;
#define CHECK(c) do { if (!(c)) { printf("FAIL: %s (line %d)\n", #c, __LINE__); failures++; } } while (0)

static BOOL covers(NSFont *font, UniChar *chars, CFIndex count) {
	CGGlyph glyphs[2];
	return CTFontGetGlyphsForCharacters((CTFontRef) font, chars, glyphs, count);
}

int main(void)
{
	@autoreleasepool {
		NSFont *base = [NSFont fontWithName: @"Helvetica" size: 16];
		CHECK(base != nil);

		// Covered by the font itself: a font that covers it, of the same size.
		UniChar a = 'a';
		NSString *latin = @"a";
		NSFont *same = [NSFont findFontLike: base forString: latin withRange: NSMakeRange(0, 1) inLanguage: nil];
		CHECK(same != nil && covers(same, &a, 1) && [same pointSize] == 16);
		same = [NSFont findFontLike: base forCharacter: 'a' inLanguage: nil];
		CHECK(same != nil && covers(same, &a, 1));

		// Not covered: another font that covers it, of the same size.
		UniChar han = 0x4E2D;
		NSString *hanString = [NSString stringWithCharacters: &han length: 1];
		NSFont *cjk = [NSFont findFontLike: base forString: hanString withRange: NSMakeRange(0, 1) inLanguage: nil];
		CHECK(cjk != nil);
		CHECK(cjk != nil && ![[cjk fontName] isEqualToString: [base fontName]]);
		CHECK(cjk != nil && covers(cjk, &han, 1));
		CHECK(cjk != nil && [cjk pointSize] == 16);
		NSFont *cjk2 = [NSFont findFontLike: base forCharacter: han inLanguage: nil];
		CHECK(cjk2 != nil && covers(cjk2, &han, 1));

		// A surrogate pair: U+1F600.
		UniChar pair[2] = { 0xD83D, 0xDE00 };
		NSString *emoji = [NSString stringWithCharacters: pair length: 2];
		NSFont *emojiFont = [NSFont findFontLike: base forString: emoji withRange: NSMakeRange(0, 2) inLanguage: nil];
		CHECK(emojiFont != nil);
		CHECK(emojiFont != nil && covers(emojiFont, pair, 2));

		// Only the range is looked at.
		NSString *mixed = [NSString stringWithFormat: @"a%C", han];
		NSFont *first = [NSFont findFontLike: base forString: mixed withRange: NSMakeRange(0, 1) inLanguage: nil];
		CHECK(first != nil && covers(first, &a, 1));
	}
	printf(failures ? "FAILED\n" : "PASS\n");
	return failures != 0;
}
