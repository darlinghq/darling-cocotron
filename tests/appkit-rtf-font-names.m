/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// RTF keeps the name of a font: writing an attributed string and reading it
// back gives the same font name and size, the font table names the font, and
// the bold and italic switches in effect apply to the font named by \f.
// Expectations come from observing macOS 26.7.3 (writing Helvetica,
// Helvetica-Bold, Times-Roman and Courier-Oblique puts the name of the font in
// the font table, adds \b and \i for the traits, and reading gives the same
// names back).
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

static NSFont *roundTrip(NSFont *font, NSString **rtf) {
    NSAttributedString *string = [[[NSAttributedString alloc]
            initWithString: @"abc"
                attributes: [NSDictionary dictionaryWithObject: font forKey: NSFontAttributeName]] autorelease];
    NSData *data = [string RTFFromRange: NSMakeRange(0, 3) documentAttributes: [NSDictionary dictionary]];
    if (rtf != NULL)
        *rtf = [[[NSString alloc] initWithData: data encoding: NSISOLatin1StringEncoding] autorelease];
    NSAttributedString *back = [[[NSAttributedString alloc] initWithRTF: data documentAttributes: NULL] autorelease];
    return [back attribute: NSFontAttributeName atIndex: 0 effectiveRange: NULL];
}

static NSAttributedString *readRTF(NSString *rtf) {
    return [[[NSAttributedString alloc] initWithRTF: [rtf dataUsingEncoding: NSASCIIStringEncoding]
                                 documentAttributes: NULL] autorelease];
}

static void testPlainFonts(void) {
    NSArray *names = [NSArray arrayWithObjects: @"Helvetica", @"Times-Roman", @"Courier", nil];
    for (NSString *name in names) {
        NSFont *font = [NSFont fontWithName: name size: 13];
        NSString *rtf = nil;
        NSFont *back = roundTrip(font, &rtf);
        char what[128];

        snprintf(what, sizeof what, "%s round trips with the same name", [name UTF8String]);
        expect([[back fontName] isEqualToString: [font fontName]], what);
        snprintf(what, sizeof what, "%s round trips with the same size", [name UTF8String]);
        expect([back pointSize] == 13, what);
        snprintf(what, sizeof what, "the font table names %s", [name UTF8String]);
        expect([rtf rangeOfString: [NSString stringWithFormat: @"%@;", [font fontName]]].location != NSNotFound, what);
    }
}

static void testTraits(void) {
    NSFontManager *manager = [NSFontManager sharedFontManager];
    NSFont *plain = [NSFont fontWithName: @"Helvetica" size: 12];
    NSFont *bold = [manager convertFont: plain toHaveTrait: NSBoldFontMask];
    NSString *rtf = nil;
    NSFont *back = roundTrip(bold, &rtf);

    expect([manager traitsOfFont: bold] & NSBoldFontMask, "the converted font is bold");
    expect([rtf rangeOfString: @"\\b"].location != NSNotFound, "bold is written as \\b");
    expect([[back fontName] isEqualToString: [bold fontName]], "a bold font round trips with the same name");
    expect([manager traitsOfFont: back] & NSBoldFontMask, "and is still bold");

    NSFont *italic = [manager convertFont: plain toHaveTrait: NSItalicFontMask];
    back = roundTrip(italic, &rtf);
    expect([rtf rangeOfString: @"\\i"].location != NSNotFound, "italic is written as \\i");
    expect([[back fontName] isEqualToString: [italic fontName]], "an italic font round trips with the same name");
}

static void testSwitchesApplyToTheNamedFont(void) {
    NSFontManager *manager = [NSFontManager sharedFontManager];
    NSAttributedString *string = readRTF(@"{\\rtf1\\ansi{\\fonttbl\\f0\\fswiss\\fcharset0 Helvetica;}\\b\\f0\\fs24 abc}");
    NSFont *font = [string attribute: NSFontAttributeName atIndex: 0 effectiveRange: NULL];

    expect(([manager traitsOfFont: font] & NSBoldFontMask) != 0, "\\b before \\f still gives a bold font");
    expect([font pointSize] == 12, "\\fs gives the size");
    NSFont *expected = [manager convertFont: [NSFont fontWithName: @"Helvetica" size: 12] toHaveTrait: NSBoldFontMask];
    expect([[font fontName] isEqualToString: [expected fontName]], "the bold font is the bold face of the named font");

    string = readRTF(@"{\\rtf1\\ansi{\\fonttbl\\f0\\fswiss\\fcharset0 Helvetica;}\\f0\\b\\fs24 abc\\b0 def}");
    font = [string attribute: NSFontAttributeName atIndex: 4 effectiveRange: NULL];
    expect(([manager traitsOfFont: font] & NSBoldFontMask) == 0, "\\b0 turns bold off");
    expect([[font fontName] isEqualToString: @"Helvetica"] || [[font familyName] isEqualToString: [[NSFont fontWithName: @"Helvetica" size: 12] familyName]],
           "and stays in the family of the named font");
}

static void testFontManagerConversionsKeepTheFont(void) {
    NSFontManager *manager = [NSFontManager sharedFontManager];
    NSFont *plain = [NSFont fontWithName: @"Helvetica" size: 12];
    NSFont *bold = [manager convertFont: plain toHaveTrait: NSBoldFontMask];

    expect([[[manager convertFont: plain toNotHaveTrait: NSBoldFontMask] fontName] isEqualToString: [plain fontName]],
           "a font without the trait is unchanged by toNotHaveTrait:");
    expect([[manager convertFont: bold toHaveTrait: NSBoldFontMask] isEqual: bold],
           "a font that has the trait is unchanged by toHaveTrait:");
    expect([[[manager convertFont: plain toHaveTrait: NSUnboldFontMask] fontName] isEqualToString: [plain fontName]],
           "unbold of a regular font is unchanged");
}

int main(void) {
    @autoreleasepool {
        testPlainFonts();
        testTraits();
        testSwitchesApplyToTheNamedFont();
        testFontManagerConversionsKeepTheFont();
    }
    if (failures != 0)
        return 1;
    puts("rtf font names: PASS");
    return 0;
}
