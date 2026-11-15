// The system font is named "San Francisco", which no installed family lists. Its family name used to come out as "San": looking
// the name up word by word asked for a family called "San", and fontFamilyWithName: invents any family it is asked for, so the
// first word won and also became a family in the font manager. Its display name was nil. The family of a name no installed family
// matches is the name itself (the fallback NSFont.m documents) unless the font system resolves the name to an installed family, the display name is never nil, and -familyName itself invents no family.
// Other callers (-[NSFont fontDescriptor], NSFontManager, NSFontPanel) still pass the family name to fontFamilyWithName:, which
// invents a family; it is now named after the font ("San Francisco"), not its first word, and is left as it is.
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
        NSFont *font = [NSFont systemFontOfSize:13];
        expect(font != nil, @"there is a system font");
        NSString *name = [font fontName];
        expect([name length] > 0, @"the system font has a name");
        NSArray *before = [[NSFontManager sharedFontManager] availableFontFamilies];
        NSString *family = [font familyName];
        expect([family length] > 0, @"the family name is never nil or empty");
        // The family is an installed family the name resolves to, else the name itself, never the first word of the name.
        NSArray *families = [[NSFontManager sharedFontManager] availableFontFamilies];
        expect([family isEqualToString:name] || [families containsObject:family],
               [NSString stringWithFormat:@"family of an unlisted name is the name or an installed family (got %@, name %@)", family, name]);
        expect([name rangeOfString:@" "].location == NSNotFound || ![family isEqualToString:[[name componentsSeparatedByString:@" "] firstObject]] || [families containsObject:family],
               @"the family is not invented from the first word of the name");
        NSString *display = [font displayName];
        expect([display length] > 0, @"display name is not nil or empty");
        NSArray *after = [[NSFontManager sharedFontManager] availableFontFamilies];
        expect([after count] == [before count], @"-familyName does not invent a family");
        expect(![after containsObject:@"San"], @"no family called San");
        NSFont *helvetica = [NSFont fontWithName:@"Helvetica" size:12];
        expect(helvetica == nil || [[helvetica familyName] length] > 0, @"a listed font still has a family name");
        NSLog(@"appkit-font-unknown-family: ok");
    }
    return 0;
}
