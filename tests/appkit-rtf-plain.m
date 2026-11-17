/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// The RTF control word \plain resets the character formatting. Expectations
// come from observing macOS 26.7.3 and macOS 10.14.4: after \plain the font
// is Helvetica at 12 points (the default font, not the font named by \f), bold
// and italic are gone, underline is gone, and the text color is gone. \b and
// \i stay in effect across \f when \plain is not used.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

static NSDictionary *attributesOfLast(NSString *body) {
    NSString *rtf = [NSString stringWithFormat:
            @"{\\rtf1\\ansi{\\fonttbl\\f0\\fswiss Helvetica;\\f1\\fswiss Times-Roman;}"
             @"{\\colortbl;\\red255\\green0\\blue0;}%@}", body];
    NSAttributedString *a = [[[NSAttributedString alloc]
            initWithRTF: [rtf dataUsingEncoding: NSASCIIStringEncoding]
     documentAttributes: NULL] autorelease];
    return [a attributesAtIndex: [a length] - 1 effectiveRange: NULL];
}

static NSFontTraitMask traits(NSFont *f) {
    return [[NSFontManager sharedFontManager] traitsOfFont: f];
}

int main(void) {
    @autoreleasepool {
        NSDictionary *d = attributesOfLast(@"\\f0\\fs30\\b B \\plain P");
        NSFont *f = [d objectForKey: NSFontAttributeName];
        expect(!(traits(f) & NSBoldFontMask), "\\plain removes bold");
        expect([f pointSize] == 12, "\\plain restores the default size");

        d = attributesOfLast(@"\\f0\\b\\i BI \\plain\\f1 P");
        f = [d objectForKey: NSFontAttributeName];
        expect(!(traits(f) & (NSBoldFontMask | NSItalicFontMask)), "a font selected after \\plain is not bold or italic");

        d = attributesOfLast(@"\\f1\\ul\\cf1 U \\plain P");
        expect([d objectForKey: NSUnderlineStyleAttributeName] == nil, "\\plain removes underline");
        expect([d objectForKey: NSForegroundColorAttributeName] == nil, "\\plain removes the text color");

        d = attributesOfLast(@"\\f0\\b B \\f1 T");
        expect(traits([d objectForKey: NSFontAttributeName]) & NSBoldFontMask, "\\f keeps bold when \\plain is not used");

        d = attributesOfLast(@"\\f0\\b B \\b0\\f1 T");
        expect(!(traits([d objectForKey: NSFontAttributeName]) & NSBoldFontMask), "\\b0 removes bold");
    }
    if (failures != 0)
        return 1;
    puts("rtf plain: PASS");
    return 0;
}
