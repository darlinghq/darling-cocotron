// The system font is named "San Francisco", which no installed family lists. NSFontManager's trait conversion found the font's
// family through -[NSFontFamily fontFamilyWithTypefaceName:], which reached the family list only through the family "San" that
// -[NSFont familyName] used to invent (fontFamilyWithName: invents any family it is asked for). Once -familyName stopped
// inventing, the family was nil: convertFont:toHaveTrait: logged "failed" and returned the font unchanged, so +boldSystemFontOfSize:
// and every bold or italic conversion of the system font did nothing. The family is now the one the display draws the name with;
// the lookup adds no family. The family-count check below holds only because nothing else runs first: -fontDescriptor, NSFontPanel,
// convertFont:toNotHaveTrait: and toFamily: still invent a family named after the font, and a lookup after them returns that one.
#import <AppKit/AppKit.h>
#include <stdlib.h>

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

int main(void)
{
    @autoreleasepool
    {
        NSFontManager *fm = [NSFontManager sharedFontManager];
        NSFont *system = [NSFont systemFontOfSize:13];
        expect(system != nil, @"there is a system font");
        NSArray *before = [fm availableFontFamilies];

        NSFont *bold = [fm convertFont:system toHaveTrait:NSBoldFontMask];
        expect(bold != system, @"the system font converts to bold (still the same font)");
        expect(([fm traitsOfFont:bold] & NSBoldFontMask) != 0, @"the converted system font has the bold trait");
        expect([bold pointSize] == [system pointSize], @"conversion keeps the point size");

        NSFont *boldSystem = [NSFont boldSystemFontOfSize:13];
        expect(([fm traitsOfFont:boldSystem] & NSBoldFontMask) != 0, @"+boldSystemFontOfSize: has the bold trait");

        NSFont *italic = [fm convertFont:system toHaveTrait:NSItalicFontMask];
        expect(italic != system, @"the system font converts to italic (still the same font)");
        expect(([fm traitsOfFont:italic] & NSItalicFontMask) != 0, @"the converted system font has the italic trait");

        NSArray *after = [fm availableFontFamilies];
        expect([after count] == [before count], @"converting the system font adds no family");
        expect(![after containsObject:@"San"] && ![after containsObject:[system fontName]], @"no family is named after the system font");
        NSLog(@"appkit-font-manager-system-font: ok");
    }
    return 0;
}
