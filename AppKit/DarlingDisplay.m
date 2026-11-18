/* Copyright (C) 2026 Lubos Dolezel

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import "private-include/AppKit/DarlingDisplay.h"
#import <AppKit/NSColor.h>
#import <AppKit/NSFontManager.h>
#import <AppKit/NSFontTypeface.h>
#import <AppKit/NSPrintInfo.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSSavePanel.h>
#import <AppKit/NSOpenPanel.h>
#import <Onyx2D/O2Font_freetype.h>
#import <fontconfig/fontconfig.h>

void NSColorSetCatalogColor(NSColorListName catalogName, NSColorName colorName, NSColor *color);

@implementation DarlingDisplay

- (id) init {
    if ((self = [super init]) != nil)
        _buttonClickCounts = [NSMutableDictionary new];
    return self;
}

- (void) dealloc {
    [_buttonClickCounts release];
    [super dealloc];
}

- (NSColor *) colorWithName: (NSString *) colorName {
    if ([colorName isEqual: @"controlColor"])
        return [NSColor colorWithCalibratedWhite: 0.93 alpha: 1.0];
    // The disabled text colour and the menu highlight are the values macOS 10.14 returns in the light
    // appearance, converted to sRGB. There is no public menu background or menu text colour to read back; the
    // menu text takes the label colour's value and the background is an estimate of the light menu material.
    if ([colorName isEqual: @"disabledControlTextColor"])
        return [NSColor colorWithSRGBRed: 0.0f green: 0.0f blue: 0.0f alpha: 0.247f];
    if ([colorName isEqual: @"controlTextColor"])
        return [NSColor blackColor];
    if ([colorName isEqual: @"menuBackgroundColor"])
        return [NSColor colorWithSRGBRed: 0.945f green: 0.945f blue: 0.945f alpha: 1.0f];
    if ([colorName isEqual: @"mainMenuBarColor"])
        return [NSColor colorWithCalibratedWhite: 0.9 alpha: 1.0];
    if ([colorName isEqual: @"controlShadowColor"])
        return [NSColor darkGrayColor];
    if ([colorName isEqual: @"selectedControlColor"])
        return [NSColor colorWithSRGBRed: 0.701961f /* 179 */
                                   green: 0.843137f /* 215 */
                                    blue: 1.0f
                                   alpha: 1.0f];
    if ([colorName isEqual: @"controlBackgroundColor"])
        return [NSColor whiteColor];
    if ([colorName isEqual: @"controlLightHighlightColor"])
        return [NSColor lightGrayColor];
    if ([colorName isEqual: @"headerColor"])
        return [NSColor greenColor];
    if ([colorName isEqual: @"textBackgroundColor"])
        return [NSColor whiteColor];
    if ([colorName isEqual: @"textColor"])
        return [NSColor blackColor];
    if ([colorName isEqual: @"selectedTextColor"])
        return [NSColor whiteColor];
    if ([colorName isEqual: @"headerTextColor"])
        return [NSColor blackColor];
    if ([colorName isEqual: @"menuItemTextColor"])
        return [NSColor colorWithSRGBRed: 0.0f green: 0.0f blue: 0.0f alpha: 0.847f];
    if ([colorName isEqual: @"selectedMenuItemTextColor"])
        return [NSColor whiteColor];
    if ([colorName isEqual: @"selectedMenuItemColor"])
        return [NSColor colorWithSRGBRed: 0.259f green: 0.467f blue: 0.957f alpha: 1.0f];
    if ([colorName isEqual: @"selectedControlTextColor"])
        return [NSColor blackColor];
    if ([colorName isEqual: @"windowFrameColor"])
        return [NSColor lightGrayColor];
    if ([colorName isEqual: @"shadowColor"])
        return [NSColor colorWithGenericGamma22White: 0.0f alpha: 1.0f];
    if ([colorName isEqual: @"alternateSelectedControlTextColor"])
        return [NSColor colorWithGenericGamma22White: 1.0f alpha: 1.0f];
    if ([colorName isEqual: @"labelColor"])
        return [NSColor colorWithSRGBRed: 0.0f
                                   green: 0.0f
                                    blue: 0.0f
                                   alpha: 0.847059f];
    if ([colorName isEqual: @"linkColor"])
        return [NSColor colorWithSRGBRed: 0.0f
                                   green: 0.411765f
                                    blue: 0.850980f
                                   alpha: 1.0f];
    if ([colorName isEqual: @"unemphasizedSelectedTextColor"])
        return [NSColor
                colorWithGenericGamma22White: 0.0f /* 1.0f on dark mode */
                                               alpha: 1.0f];
    if ([colorName isEqual: @"selectedContentBackgroundColor"])
        return [NSColor colorWithSRGBRed: 0.0f
                                   green: 0.388235f /* 0.345098f on dark mode */
                                    blue: 0.882353f /* 0.815686f on dark mode */
                                   alpha: 1.0f];
    if ([colorName isEqual: @"unemphasizedSelectedContentBackgroundColor"])
        return [NSColor colorWithSRGBRed: 0.862745f /* 0.274510f on dark mode */
                                   green: 0.862745f /* 0.274510f on dark mode */
                                    blue: 0.862745f /* 0.274510f on dark mode */
                                   alpha: 1.0f];
    if ([colorName isEqual: @"alternatingContentBackgroundColor"])
        return [NSColor colorWithSRGBRed: 0.956863f
                                   green: 0.960784f
                                    blue: 0.960784f
                                   alpha: 1.0f];
    if ([colorName isEqual: @"selectedTextBackgroundColor"])
        return [NSColor colorWithCalibratedRed: 0.20f
                                         green: 0.55f
                                          blue: 1.00f
                                         alpha: 1.00f];
    if ([colorName isEqual: @"alternateSelectedControlColor"])
        return [NSColor colorWithSRGBRed: 0.0f
                                   green: 0.388235f
                                    blue: 0.882353f
                                    alpha: 1.0f];
    if ([colorName isEqual: @"controlDarkShadowColor"])
        return [NSColor colorWithCalibratedRed: 0.0f
                                         green: 0.0f
                                          blue: 0.0f
                                         alpha: 1.0f];
    if ([colorName isEqual: @"controlHighlightColor"])
        return [NSColor colorWithCalibratedRed: 0.890097f
                                         green: 0.890097f
                                          blue: 0.890097f
                                         alpha: 1.0f];
    if ([colorName isEqual: @"gridColor"])
        return [NSColor colorWithGenericGamma22White: 0.80f alpha: 1.0f];
    if ([colorName isEqual: @"highlightColor"])
        return [NSColor colorWithGenericGamma22White: 1.0f alpha: 1.0f];
    if ([colorName isEqual: @"keyboardFocusIndicatorColor"])
        // QUIRK: the indicator colour is a translucent blue, not an opaque one. Evidence: black-box read of
        // +[NSColor keyboardFocusIndicatorColor] converted to sRGB on macOS 10.14.4, Blue control tint (tier 2).
        // Test: appkit-focus-ring.m (test_quirk_keyboard_focus_indicator_color)
        return [NSColor colorWithSRGBRed: 0.0f
                                   green: 0.403922f
                                    blue: 0.956863f
                                    alpha: 0.247059f];
    if ([colorName isEqual: @"knobColor"])
        return [NSColor colorWithSRGBRed: 0.60f
                                   green: 0.60f
                                    blue: 0.733333f
                                    alpha: 1.0f];
    if ([colorName isEqual: @"scrollBarColor"])
        return [NSColor colorWithSRGBRed: 0.666667f
                                   green: 0.666667f
                                    blue: 0.666667f
                                    alpha: 1.0f];
    if ([colorName isEqual: @"secondarySelectedControlColor"])
        return [NSColor colorWithSRGBRed: 0.862745f
                                   green: 0.862745f
                                    blue: 0.862745f
                                    alpha: 1.0f];
    if ([colorName isEqual: @"selectedKnobColor"])
        return [NSColor colorWithSRGBRed: 0.40f
                                   green: 0.40f
                                    blue: 0.60f
                                    alpha: 1.0f];

    // The label, background, accent and system colors of the System catalog. The values are those
    // of macOS 10.14 in the light appearance, measured with black-box probes
    // (mac-probes/ua3-system-colors.m): later releases move some of them slightly.
    if ([colorName isEqual: @"secondaryLabelColor"])
        return [NSColor colorWithSRGBRed: 0.0f green: 0.0f blue: 0.0f alpha: 0.498f];
    if ([colorName isEqual: @"tertiaryLabelColor"])
        return [NSColor colorWithSRGBRed: 0.0f green: 0.0f blue: 0.0f alpha: 0.247f];
    if ([colorName isEqual: @"quaternaryLabelColor"])
        return [NSColor colorWithSRGBRed: 0.0f green: 0.0f blue: 0.0f alpha: 0.098f];
    if ([colorName isEqual: @"placeholderTextColor"])
        return [NSColor colorWithSRGBRed: 0.0f green: 0.0f blue: 0.0f alpha: 0.247f];
    if ([colorName isEqual: @"windowFrameTextColor"])
        return [NSColor colorWithSRGBRed: 0.0f green: 0.0f blue: 0.0f alpha: 0.847f];
    if ([colorName isEqual: @"separatorColor"])
        return [NSColor colorWithSRGBRed: 0.0f green: 0.0f blue: 0.0f alpha: 0.098f];
    if ([colorName isEqual: @"windowBackgroundColor"])
        return [NSColor colorWithSRGBRed: 0.925f green: 0.925f blue: 0.925f alpha: 1.0f];
    if ([colorName isEqual: @"underPageBackgroundColor"])
        return [NSColor colorWithSRGBRed: 0.588f green: 0.588f blue: 0.588f alpha: 0.898f];
    if ([colorName isEqual: @"findHighlightColor"])
        return [NSColor colorWithSRGBRed: 1.0f green: 1.0f blue: 0.0f alpha: 1.0f];
    if ([colorName isEqual: @"unemphasizedSelectedTextBackgroundColor"])
        return [NSColor colorWithSRGBRed: 0.863f green: 0.863f blue: 0.863f alpha: 1.0f];
    if ([colorName isEqual: @"controlAccentColor"])
        return [NSColor colorWithSRGBRed: 0.0f green: 0.478f blue: 1.0f alpha: 1.0f];
    if ([colorName isEqual: @"systemRedColor"])
        return [NSColor colorWithSRGBRed: 1.0f green: 0.231f blue: 0.188f alpha: 1.0f];
    if ([colorName isEqual: @"systemGreenColor"])
        return [NSColor colorWithSRGBRed: 0.157f green: 0.804f blue: 0.255f alpha: 1.0f];
    if ([colorName isEqual: @"systemBlueColor"])
        return [NSColor colorWithSRGBRed: 0.0f green: 0.478f blue: 1.0f alpha: 1.0f];
    if ([colorName isEqual: @"systemOrangeColor"])
        return [NSColor colorWithSRGBRed: 1.0f green: 0.584f blue: 0.0f alpha: 1.0f];
    if ([colorName isEqual: @"systemYellowColor"])
        return [NSColor colorWithSRGBRed: 1.0f green: 0.8f blue: 0.0f alpha: 1.0f];
    if ([colorName isEqual: @"systemBrownColor"])
        return [NSColor colorWithSRGBRed: 0.635f green: 0.518f blue: 0.369f alpha: 1.0f];
    if ([colorName isEqual: @"systemPinkColor"])
        return [NSColor colorWithSRGBRed: 1.0f green: 0.176f blue: 0.333f alpha: 1.0f];
    if ([colorName isEqual: @"systemPurpleColor"])
        return [NSColor colorWithSRGBRed: 0.686f green: 0.322f blue: 0.871f alpha: 1.0f];
    if ([colorName isEqual: @"systemGrayColor"])
        return [NSColor colorWithSRGBRed: 0.557f green: 0.557f blue: 0.576f alpha: 1.0f];

    // A name the catalog does not have has no color.
    return nil;
}

- (void) _addSystemColor: (NSColor *) result forName: (NSString *) colorName {
    NSColorSetCatalogColor(@"System", colorName, result);
}

- (NSTimeInterval) textCaretBlinkInterval {
    return 0.5;
}


- (NSSet *) allFontFamilyNames {
    FcPattern *pat = FcPatternCreate();
    // Avoid the variadic FcObjectSetBuild(): fontconfig is a native (Linux) library, and on
    // arm64 Darwin and Linux pass variadic arguments differently (stack vs. registers).
    FcObjectSet *props = FcObjectSetCreate();
    FcObjectSetAdd(props, FC_FAMILY);

    FcFontSet *set = FcFontList(O2FontSharedFontConfig(), pat, props);
    NSMutableSet *ret = [NSMutableSet set];

    for (int i = 0; i < set->nfont; i++) {
        FcChar8 *family;
        if (FcPatternGetString(set->fonts[i], FC_FAMILY, 0, &family) ==
            FcResultMatch && family != NULL) {
            NSString *familyStr = [NSString stringWithCString: (const char *) family
                                                     encoding: NSUTF8StringEncoding];
            if (familyStr == nil)
                familyStr = [NSString stringWithCString: (const char *) family
                                               encoding: NSISOLatin1StringEncoding];
            if (familyStr != nil)
                [ret addObject: familyStr];
        }
    }

    FcPatternDestroy(pat);
    FcObjectSetDestroy(props);
    FcFontSetDestroy(set);
    return ret;
}

static NSString *matchedFamily(FcConfig *config, NSString *family) {
    FcPattern *pat = FcPatternCreate();
    if (family != nil) {
        FcPatternAddString(pat, FC_FAMILY,
                           (const FcChar8 *) [family UTF8String]);
    }
    FcConfigSubstitute(config, pat, FcMatchPattern);
    FcDefaultSubstitute(pat);

    FcResult result;
    FcPattern *match = FcFontMatch(config, pat, &result);
    FcPatternDestroy(pat);
    if (match == NULL)
        return nil;

    FcChar8 *matched = NULL;
    NSString *res = nil;
    if (FcPatternGetString(match, FC_FAMILY, 0, &matched) == FcResultMatch)
        res = [NSString stringWithUTF8String: (const char *) matched];
    FcPatternDestroy(match);
    return res;
}

- (NSString *) substituteFamilyName: (NSString *) familyName {
    return matchedFamily(O2FontSharedFontConfig(), familyName);
}

// A generic family with no installed member matches the same default font as
// a pattern without any family.
- (NSString *) fontFamilyNameForGenericFamily: (NSString *) generic {
    FcConfig *config = O2FontSharedFontConfig();
    NSString *family = matchedFamily(config, generic);
    if (family == nil || [family isEqualToString: matchedFamily(config, nil)])
        return nil;
    return family;
}

// NSUnboldFontMask and NSUnitalicFontMask are conversion requests, not face
// traits.
static NSFontTraitMask fontTraitsOfPattern(FcPattern *p) {
    int slant = FC_SLANT_ROMAN, width = FC_WIDTH_NORMAL,
        weight = FC_WEIGHT_REGULAR;
    FcPatternGetInteger(p, FC_SLANT, 0, &slant);
    FcPatternGetInteger(p, FC_WIDTH, 0, &width);
    FcPatternGetInteger(p, FC_WEIGHT, 0, &weight);

    NSFontTraitMask traits = 0;
    if (slant == FC_SLANT_OBLIQUE || slant == FC_SLANT_ITALIC)
        traits |= NSItalicFontMask;
    if (weight >= FC_WEIGHT_SEMIBOLD)
        traits |= NSBoldFontMask;
    if (width <= FC_WIDTH_SEMICONDENSED)
        traits |= NSNarrowFontMask;
    else if (width >= FC_WIDTH_SEMIEXPANDED)
        traits |= NSExpandedFontMask;
    return traits;
}

// -[NSFontFamily typefaceWithTraits:] takes the first face with a trait mask,
// so list the faces nearest to regular (or bold) weight and normal width first,
// then regular, italic, bold, bold italic.
static int fontPatternDistance(FcPattern *p) {
    int slant = FC_SLANT_ROMAN, width = FC_WIDTH_NORMAL,
        weight = FC_WEIGHT_REGULAR;
    FcPatternGetInteger(p, FC_SLANT, 0, &slant);
    FcPatternGetInteger(p, FC_WIDTH, 0, &width);
    FcPatternGetInteger(p, FC_WEIGHT, 0, &weight);
    BOOL bold = weight >= FC_WEIGHT_SEMIBOLD;
    int target = bold ? FC_WEIGHT_BOLD : FC_WEIGHT_REGULAR;
    return (abs(weight - target) * 1000 + abs(width - FC_WIDTH_NORMAL)) * 4 +
           bold * 2 + (slant != FC_SLANT_ROMAN);
}

static int compareFontPatterns(const void *a, const void *b) {
    return fontPatternDistance(*(FcPattern *const *) a) -
           fontPatternDistance(*(FcPattern *const *) b);
}

- (NSArray<NSFontTypeface *> *) fontTypefacesForFamilyName:
        (NSString *) familyName
{
    familyName = [self substituteFamilyName: familyName];
    if (familyName == nil) {
        return @[];
    }
    FcPattern *pat = FcPatternCreate();
    FcPatternAddString(pat, FC_FAMILY,
                       (unsigned char *) [familyName UTF8String]);
    // Not FcObjectSetBuild(): see -allFontFamilyNames.
    FcObjectSet *props = FcObjectSetCreate();
    FcObjectSetAdd(props, FC_FAMILY);
    FcObjectSetAdd(props, FC_STYLE);
    FcObjectSetAdd(props, FC_SLANT);
    FcObjectSetAdd(props, FC_WIDTH);
    FcObjectSetAdd(props, FC_WEIGHT);

    FcFontSet *set = FcFontList(O2FontSharedFontConfig(), pat, props);
    NSMutableArray *ret = [NSMutableArray array];
    qsort(set->fonts, set->nfont, sizeof(FcPattern *), compareFontPatterns);

    for (int i = 0; i < set->nfont; i++) {
        FcChar8 *typeface;
        FcPattern *p = set->fonts[i];
        if (FcPatternGetString(p, FC_STYLE, 0, &typeface) == FcResultMatch && typeface != NULL) {
            NSString *traitName =
                    [NSString stringWithCString: (const char *) typeface
                                       encoding: NSUTF8StringEncoding];
            if (traitName == nil)
                traitName = [NSString stringWithCString: (const char *) typeface
                                               encoding: NSISOLatin1StringEncoding];
            if (traitName == nil)
                traitName = @"Regular";

            FcChar8 *pattern = FcNameUnparse(p);
            NSString *name = nil;
            if (pattern != NULL) {
                name = [NSString stringWithCString: (const char *) pattern
                                          encoding: NSUTF8StringEncoding];
                if (name == nil)
                    name = [NSString stringWithCString: (const char *) pattern
                                              encoding: NSISOLatin1StringEncoding];
                FcStrFree(pattern);
            }
            if (name == nil)
                name = traitName;

            NSFontTypeface *face = [[NSFontTypeface alloc]
                    initWithName: name
                       traitName: traitName
                          traits: fontTraitsOfPattern(p)];
            if (face != nil) {
                [ret addObject: face];
                [face release];
            }
        }
    }

    FcPatternDestroy(pat);
    FcObjectSetDestroy(props);
    FcFontSetDestroy(set);
    return ret;
}

- (CGFloat) scrollerWidth {
    return 15.0;
}

- (CGFloat) doubleClickInterval {
    return 1.0;
}

- (int) runModalPageLayoutWithPrintInfo: (NSPrintInfo *) printInfo {
    NSUnimplementedMethod();
    return 0;
}

- (int) runModalPrintPanelWithPrintInfoDictionary:
        (NSMutableDictionary *) attributes
{
    NSUnimplementedMethod();
    return 0;
}

- (O2Context *) graphicsPortForPrintOperationWithView: (NSView *) view
                                            printInfo: (NSPrintInfo *) printInfo
                                            pageRange: (NSRange) pageRange
{
    NSUnimplementedMethod();
    return nil;
}

- (int) savePanel: (NSSavePanel *) savePanel
        runModalForDirectory: (NSString *) directory
                        file: (NSString *) file
{
    NSUnimplementedMethod();
    return 0;
}

- (int) openPanel: (NSOpenPanel *) openPanel
        runModalForDirectory: (NSString *) directory
                        file: (NSString *) file
                       types: (NSArray *) types
{
    NSUnimplementedMethod();
    return 0;
}

@end

#import <AppKit/NSGraphicsStyle.h>

@implementation NSGraphicsStyle (Overrides)
- (void) drawMenuBranchArrowInRect: (NSRect) rect selected: (BOOL) selected {
    NSImage *arrow = [NSImage imageNamed: @"NSMenuArrow"];
    // ??? magic numbers
    rect.origin.y += 5;
    rect.origin.x -= 2;
    [arrow drawInRect: rect
             fromRect: NSZeroRect
            operation: NSCompositeSourceOver
             fraction: 1.0];
}

@end

