#import <AppKit/AppKit.h>
#include <stdlib.h>

@interface NSFont (DefaultGlyph)
- (NSGlyph) _defaultGlyphForChar: (unichar) character;
@end

static void expect(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

int main(void) {
    @autoreleasepool {
        NSFont *font = [NSFont systemFontOfSize: 12];
        expect(font != nil, @"system font");
        expect([font respondsToSelector: @selector(_defaultGlyphForChar:)],
               @"NSFont responds to _defaultGlyphForChar:");

        unichar characters[] = {'A', 'x', '7', '='};
        NSGlyph glyphs[4];
        [font getGlyphs: glyphs forCharacters: characters length: 4];
        for (int i = 0; i < 4; i++) {
            NSGlyph glyph = [font _defaultGlyphForChar: characters[i]];
            expect(glyph != 0, @"a mapped character has a glyph");
            expect(glyph == glyphs[i], @"same glyph as getGlyphs:forCharacters:length:");
        }
        expect([font _defaultGlyphForChar: 'A'] != [font _defaultGlyphForChar: 'B'],
               @"different characters map to different glyphs");

        NSLog(@"PASS: nsfont-default-glyph-for-char");
    }
    return 0;
}
