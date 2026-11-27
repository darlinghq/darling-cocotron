/* Copyright (c) 2006-2007 Christopher J. W. Lloyd <cjwl@objc.net>

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

#import <AppKit/NSBezierPath.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSDisplay.h>
#import <AppKit/NSColor_CGColor.h>
#import <AppKit/NSColor_catalog.h>
#import <AppKit/NSColorSpace.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSRaise.h>

#import <AppKit/NSGraphics.h>
#import <AppKit/NSGraphicsContext.h>

#import <AppKit/NSPasteboard.h>
#import "NSPasteboardAliases.h"
#import <Foundation/NSKeyedArchiver.h>

#import <objc/runtime.h>

static int NSColor_ignoresAlpha = -1;

NSNotificationName const NSSystemColorsDidChangeNotification = @"NSSystemColorsDidChangeNotification";

// NSColor_dynamic.m
@interface NSColor_dynamic : NSColor
- initWithName: (NSColorName) name provider: (NSColor * (^)(NSAppearance *)) provider;
@end

// NSColor_assetCatalog.m
@interface NSColor (NSAssetCatalog)
+ (NSColor *) _colorNamedInAssetCatalog: (NSString *) name bundle: (NSBundle *) bundle;
@end

@interface NSColor (private)
- (NSColorListName) catalogName;
- (NSColorName) colorName;
@end

// The constant colors (+redColor, +grayColor, the system colors' fallbacks ...) are sRGB (and Generic Gray
// Gamma 2.2) colors on macOS, not the Generic RGB / Generic Gray of +colorWithCalibratedRed:... They keep
// the calibrated family name here but their CGColor is in the device space, which Onyx2D treats as sRGB.
static NSColor *constantRGB(CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    NSColor *result = [NSColor_CGColor colorWithRed: red
                                              green: green
                                               blue: blue
                                              alpha: alpha
                                          spaceName: NSCalibratedRGBColorSpace
                                         colorSpace: space];
    CGColorSpaceRelease(space);
    return result;
}

static NSColor *constantWhite(CGFloat white, CGFloat alpha) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceGray();
    NSColor *result = [NSColor_CGColor colorWithGray: white
                                               alpha: alpha
                                           spaceName: NSCalibratedWhiteColorSpace
                                          colorSpace: space];
    CGColorSpaceRelease(space);
    return result;
}

void NSColorInitializeDynamicSystemColors(void);

@implementation NSColor

- (NSColorType) type {
    return NSColorTypeComponentBased;
}

+ (NSColor *) colorWithCGColor: (CGColorRef) color {
    if (color == NULL)
        return nil;

    CGColorSpaceRef colorSpace = CGColorGetColorSpace(color);
    NSColorSpaceName spaceName;
    switch (CGColorSpaceGetModel(colorSpace)) {
        case kCGColorSpaceModelMonochrome:
            spaceName = NSDeviceWhiteColorSpace;
            break;
        case kCGColorSpaceModelRGB:
            spaceName = NSCalibratedRGBColorSpace;
            break;
        case kCGColorSpaceModelCMYK:
            spaceName = NSDeviceCMYKColorSpace;
            break;
        case kCGColorSpaceModelPattern:
            spaceName = NSPatternColorSpace;
            break;
        default:
            spaceName = NSCustomColorSpace;
            break;
    }
    return [NSColor_CGColor colorWithColorRef: color spaceName: spaceName];
}

+ (NSColor *) colorWithColorSpace: (NSColorSpace *) space
                       components: (const CGFloat *) components
                            count: (NSInteger) count
{
    CGColorSpaceRef cgSpace = [space CGColorSpace];
    if (cgSpace == NULL || components == NULL) {
        [NSException raise: NSInvalidArgumentException
                    format: @"A component-based color space and components are required"];
    }
    CGColorSpaceModel model = CGColorSpaceGetModel(cgSpace);
    if (model == kCGColorSpaceModelPattern || model == kCGColorSpaceModelIndexed ||
        count != (NSInteger)CGColorSpaceGetNumberOfComponents(cgSpace) + 1) {
        [NSException raise: NSInvalidArgumentException
                    format: @"Color component count does not match its color space"];
    }

    CGColorRef cgColor = CGColorCreate(cgSpace, components);
    NSColor *result = [self colorWithCGColor: cgColor];
    CGColorRelease(cgColor);
    return result;
}

+ (BOOL) supportsSecureCoding {
    return YES;
}

- (void) encodeWithCoder: (NSCoder *) coder {

    if ([coder allowsKeyedCoding]) {
        NSColorSpaceName spaceName = [self colorSpaceName];
        // An sRGB color is tagged with the named color space but has no catalog entry: it is
        // archived by its RGB components
        if ([spaceName isEqualToString: NSNamedColorSpace] && [self type] != NSColorTypeCatalog)
            spaceName = NSCalibratedRGBColorSpace;

        if ([spaceName isEqualToString: NSCalibratedRGBColorSpace]) {
            CGFloat r, g, b, a;

            [self getRed: &r green: &g blue: &b alpha: &a];
            [coder encodeInt: 1 forKey: @"NSColorSpace"];
            NSString *string =
                    [NSString stringWithFormat: @"%f %f %f %f", r, g, b, a];
            NSData *data = [string dataUsingEncoding: NSASCIIStringEncoding];
            [coder encodeBytes: [data bytes]
                        length: [data length]
                        forKey: @"NSRGB"];
        } else if ([spaceName isEqualToString: NSDeviceRGBColorSpace]) {
            CGFloat r, g, b, a;

            [self getRed: &r green: &g blue: &b alpha: &a];
            [coder encodeInt: 2 forKey: @"NSColorSpace"];
            NSString *string =
                    [NSString stringWithFormat: @"%f %f %f %f", r, g, b, a];
            NSData *data = [string dataUsingEncoding: NSASCIIStringEncoding];
            [coder encodeBytes: [data bytes]
                        length: [data length]
                        forKey: @"NSRGB"];
        } else if ([spaceName isEqualToString: NSCalibratedWhiteColorSpace]) {
            CGFloat g, a;

            [self getWhite: &g alpha: &a];
            [coder encodeInt: 3 forKey: @"NSColorSpace"];
            NSString *string = [NSString stringWithFormat: @"%f %f", g, a];
            NSData *data = [string dataUsingEncoding: NSASCIIStringEncoding];
            [coder encodeBytes: [data bytes]
                        length: [data length]
                        forKey: @"NSWhite"];
        } else if ([spaceName isEqualToString: NSDeviceWhiteColorSpace]) {
            CGFloat g, a;

            [self getWhite: &g alpha: &a];
            [coder encodeInt: 4 forKey: @"NSColorSpace"];
            NSString *string = [NSString stringWithFormat: @"%f %f", g, a];
            NSData *data = [string dataUsingEncoding: NSASCIIStringEncoding];
            [coder encodeBytes: [data bytes]
                        length: [data length]
                        forKey: @"NSWhite"];
        } else if ([spaceName isEqualToString: NSDeviceCMYKColorSpace]) {
            CGFloat c, m, y, k, a;

            [self getCyan: &c magenta: &m yellow: &y black: &k alpha: &a];
            [coder encodeInt: 5 forKey: @"NSColorSpace"];
            NSString *string = [NSString
                    stringWithFormat: @"%f %f %f %f %f", c, m, y, k, a];
            NSData *data = [string dataUsingEncoding: NSASCIIStringEncoding];
            [coder encodeBytes: [data bytes]
                        length: [data length]
                        forKey: @"NSCMYK"];
        } else if ([spaceName isEqualToString: NSNamedColorSpace]) {
            [coder encodeInt: 6 forKey: @"NSColorSpace"];
            [coder encodeObject: [self catalogNameComponent]
                         forKey: @"NSCatalogName"];
            [coder encodeObject: [self colorNameComponent]
                         forKey: @"NSColorName"];
            // What the color stands for, for a reader that does not know the catalog
            NSColor *fallback = [self colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
            if (fallback != nil && fallback != self)
                [coder encodeObject: fallback forKey: @"NSColor"];
        }

    } else {
        // The layout -initWithCoder: reads: a color space byte followed by
        // the components as floats (or the names, for a catalog color).
        NSColorSpaceName spaceName = [self colorSpaceName];
        if ([spaceName isEqualToString: NSNamedColorSpace] && [self type] != NSColorTypeCatalog)
            spaceName = NSCalibratedRGBColorSpace;

        if ([spaceName isEqualToString: NSCalibratedRGBColorSpace] ||
            [spaceName isEqualToString: NSDeviceRGBColorSpace]) {
            uint8_t space =
                    [spaceName isEqualToString: NSCalibratedRGBColorSpace] ? 1
                                                                           : 2;
            CGFloat r, g, b, a;

            [self getRed: &r green: &g blue: &b alpha: &a];
            float values[4] = {r, g, b, a};
            [coder encodeValueOfObjCType: "c" at: &space];
            [coder encodeValuesOfObjCTypes: "ffff", &values[0], &values[1],
                                            &values[2], &values[3]];
        } else if ([spaceName isEqualToString: NSCalibratedWhiteColorSpace] ||
                   [spaceName isEqualToString: NSDeviceWhiteColorSpace]) {
            uint8_t space =
                    [spaceName isEqualToString: NSCalibratedWhiteColorSpace] ? 3
                                                                             : 4;
            CGFloat w, a;

            [self getWhite: &w alpha: &a];
            float values[2] = {w, a};
            [coder encodeValueOfObjCType: "c" at: &space];
            [coder encodeValuesOfObjCTypes: "ff", &values[0], &values[1]];
        } else if ([spaceName isEqualToString: NSDeviceCMYKColorSpace]) {
            uint8_t space = 5;
            CGFloat c, m, y, k, a;

            [self getCyan: &c magenta: &m yellow: &y black: &k alpha: &a];
            float values[5] = {c, m, y, k, a};
            [coder encodeValueOfObjCType: "c" at: &space];
            [coder encodeValuesOfObjCTypes: "fffff", &values[0], &values[1],
                                            &values[2], &values[3],
                                            &values[4]];
        } else if ([spaceName isEqualToString: NSNamedColorSpace]) {
            uint8_t space = 6;
            NSColorListName catalogName = [self catalogNameComponent];
            NSColorName colorName = [self colorNameComponent];
            NSColor *color =
                    [self colorUsingColorSpaceName: NSCalibratedRGBColorSpace];

            [coder encodeValueOfObjCType: "c" at: &space];
            [coder encodeValuesOfObjCTypes: "@@@", &catalogName, &colorName,
                                            &color];
        } else {
            // Other kinds of colors are archived as the RGB color they stand for.
            NSColor *rgb =
                    [self colorUsingColorSpaceName: NSCalibratedRGBColorSpace];

            if (rgb == nil || [[rgb colorSpaceName] isEqualToString: spaceName])
                [NSException raise: NSInvalidArgumentException
                            format: @"%@ can not encodeWithCoder:%@",
                                    [self class], [coder class]];
            [rgb encodeWithCoder: coder];
        }
    }
}

- (Class) classForCoder {
    return objc_lookUpClass("NSColor");
}

- initWithCoder: (NSCoder *) coder {
    NSColor *result = nil;
    NSKeyedUnarchiver *keyed = nil;
    int colorSpace;

    if ([coder allowsKeyedCoding]) {
        keyed = (NSKeyedUnarchiver *) coder;
        colorSpace = [keyed decodeIntForKey: @"NSColorSpace"];
    } else {
        uint8_t space;
        [coder decodeValuesOfObjCTypes: "c", &space];
        colorSpace = space;
    }

    switch (colorSpace) {
    case 1: // NSCalibratedRGBColor
    case 2: // NSDeviceRGBColor
    {
        CGFloat values[4] = {0, 0, 0, 1};

        if (keyed != nil) {
            NSUInteger length;
            const uint8_t *rgb = [keyed decodeBytesForKey: @"NSRGB"
                                           returnedLength: &length];
            NSString *string = [[[NSString alloc]
                    initWithBytes: rgb
                           length: length
                         encoding: NSUTF8StringEncoding] autorelease];
            NSArray *components = [string componentsSeparatedByString: @" "];
            int count = [components count];

            for (int i = 0; i < count && i < 4; i++)
                values[i] = [[components objectAtIndex: i] doubleValue];
        } else {
            float fvalues[4];
            [coder decodeValuesOfObjCTypes: "ffff", &fvalues[0], &fvalues[1],
                                            &fvalues[2], &fvalues[3]];

            for (int i = 0; i < 4; i++)
                values[i] = fvalues[i];
        }

        if (colorSpace == 1)
            result = [NSColor colorWithCalibratedRed: values[0]
                                               green: values[1]
                                                blue: values[2]
                                               alpha: values[3]];
        else
            result = [NSColor colorWithDeviceRed: values[0]
                                           green: values[1]
                                            blue: values[2]
                                           alpha: values[3]];
    } break;

    case 3: // NSCalibratedWhiteColor
    case 4: // NSDeviceWhiteColor
    {
        CGFloat values[2] = {0, 1};

        if (keyed != nil) {
            NSUInteger length;
            const uint8_t *white = [keyed decodeBytesForKey: @"NSWhite"
                                             returnedLength: &length];
            NSString *string = [[[NSString alloc]
                    initWithBytes: white
                           length: length
                         encoding: NSUTF8StringEncoding] autorelease];
            NSArray *components = [string componentsSeparatedByString: @" "];
            int count = [components count];

            for (int i = 0; i < count && i < 2; i++)
                values[i] = [[components objectAtIndex: i] doubleValue];
        } else {
            float fvalues[2];
            [coder decodeValuesOfObjCTypes: "ff", &fvalues[0], &fvalues[1]];

            for (int i = 0; i < 2; i++)
                values[i] = fvalues[i];
        }

        if (colorSpace == 3)
            result = [NSColor colorWithCalibratedWhite: values[0]
                                                 alpha: values[1]];
        else
            result = [NSColor colorWithDeviceWhite: values[0] alpha: values[1]];
    } break;

    case 5: // NSDeviceCMYKColor
    {
        // NSComponents data
        // NSCustomColorSpace NSColorSpace
        CGFloat values[5] = {0, 0, 0, 0, 1};

        if (keyed != nil) {
            NSUInteger length;
            const uint8_t *cmyk = [keyed decodeBytesForKey: @"NSCMYK"
                                            returnedLength: &length];
            NSString *string = [[[NSString alloc]
                    initWithBytes: cmyk
                           length: length - 1
                         encoding: NSUTF8StringEncoding] autorelease];
            NSArray *components = [string componentsSeparatedByString: @" "];
            int count = [components count];

            for (int i = 0; i < count && i < 5; i++)
                values[i] = [[components objectAtIndex: i] doubleValue];
        } else {
            float fvalues[5];
            [coder decodeValuesOfObjCTypes: "fffff", &fvalues[0], &fvalues[1],
                                            &fvalues[2], &fvalues[3],
                                            &fvalues[4]];

            for (int i = 0; i < 5; i++)
                values[i] = fvalues[i];
        }

        result = [NSColor colorWithDeviceCyan: values[0]
                                      magenta: values[1]
                                       yellow: values[2]
                                        black: values[3]
                                        alpha: values[4]];
    } break;

    case 6: // NSCatalogColor
    {
        NSColorListName catalogName;
        NSColorName colorName;
        NSColor *color;

        if (keyed != nil) {
            catalogName = [keyed decodeObjectOfClass: [NSString class] forKey: @"NSCatalogName"];
            colorName = [keyed decodeObjectOfClass: [NSString class] forKey: @"NSColorName"];
            color = [keyed decodeObjectOfClass: [NSColor class] forKey: @"NSColor"];
        } else {
            [coder decodeValuesOfObjCTypes: "@@@", &catalogName, &colorName,
                                            &color];
        }

        result = [NSColor_catalog colorWithArchivedCatalogName: catalogName
                                                     colorName: colorName
                                                 fallbackColor: color];
    } break;
    case 9: // oldSystemColor
    {
    }
    case 10: // NSPatternColor
    {
    }
    case 11: // NSColorSpaceColor
    {
    }

    default:
        NSLog(@"-[%@ %s] unknown color space %d", [self class],
              sel_getName(_cmd), colorSpace);
        result = [NSColor blackColor];
        break;
    }

    return [result retain];
}

- copyWithZone: (NSZone *) zone {
    return [self retain];
}

+ (NSColor *) alternateSelectedControlColor {
    return [NSColor colorWithCatalogName: @"System"
                               colorName: @"alternateSelectedControlColor"];
}

+ (NSColor *) alternateSelectedControlTextColor {
    return [NSColor colorWithCatalogName: @"System"
                               colorName: @"alternateSelectedControlTextColor"];
}

+ (NSColor *) keyboardFocusIndicatorColor {
    return [NSColor colorWithCatalogName: @"System"
                               colorName: @"keyboardFocusIndicatorColor"];
}

+ (NSColor *) highlightColor {
    return [NSColor colorWithCatalogName: @"System"
                               colorName: @"highlightColor"];
}

+ (NSColor *) shadowColor {
    return [NSColor colorWithCatalogName: @"System" colorName: @"shadowColor"];
}

+ (NSColor *) gridColor {
    return [NSColor colorWithCatalogName: @"System" colorName: @"gridColor"];
}

+ (NSColor *) separatorColor {
    return [NSColor colorWithCatalogName: @"System" colorName: @"separatorColor"];
}

+ (NSColor *) textInsertionPointColor {
    return [NSColor blackColor];
}

+ (NSColor *) controlColor {
    return [NSColor colorWithCatalogName: @"System" colorName: @"controlColor"];
}

// QUIRK: AppleAccentColor is an integer from -1 (Graphite) to 6 (Pink), default 4 (Blue), and +controlAccentColor
// is the matching colour, which differs between the appearances for Graphite, Red and Purple.
// (the value numbers are listed in https://alexwlchan.net/2022/changing-the-macos-accent-colour/)
// Evidence: black-box reads of +controlAccentColor converted to sRGB with each AppleAccentColor value, in the Aqua
// and DarkAqua appearances, on macOS 10.14.4 and 26.7.3 (tier 2). Both gave identical values except Yellow
// (26.7.3 is 1.000, 0.780, 0.149; the Mojave value is used).
// Test: tests/appkit-appearance-theme.m
+ (NSColor *) _accentColorForCode: (NSInteger) code dark: (BOOL) dark {
    switch (code) {
    case -1: // Graphite
        return dark ? [NSColor colorWithSRGBRed: 0.549f green: 0.549f blue: 0.549f alpha: 1.0f]
                    : [NSColor colorWithSRGBRed: 0.596f green: 0.596f blue: 0.596f alpha: 1.0f];
    case 0: // Red
        return dark ? [NSColor colorWithSRGBRed: 1.0f green: 0.322f blue: 0.341f alpha: 1.0f]
                    : [NSColor colorWithSRGBRed: 0.878f green: 0.220f blue: 0.243f alpha: 1.0f];
    case 1: // Orange
        return [NSColor colorWithSRGBRed: 0.969f green: 0.510f blue: 0.106f alpha: 1.0f];
    case 2: // Yellow
        return [NSColor colorWithSRGBRed: 0.988f green: 0.722f blue: 0.153f alpha: 1.0f];
    case 3: // Green
        return [NSColor colorWithSRGBRed: 0.384f green: 0.729f blue: 0.275f alpha: 1.0f];
    case 4: // Blue
    default:
        return [NSColor colorWithSRGBRed: 0.0f green: 0.478f blue: 1.0f alpha: 1.0f];
    case 5: // Purple
        return dark ? [NSColor colorWithSRGBRed: 0.647f green: 0.314f blue: 0.655f alpha: 1.0f]
                    : [NSColor colorWithSRGBRed: 0.584f green: 0.239f blue: 0.588f alpha: 1.0f];
    case 6: // Pink
        return [NSColor colorWithSRGBRed: 0.969f green: 0.310f blue: 0.620f alpha: 1.0f];
    }
}

+ (NSColor *) _accentColorForCode: (NSInteger) code {
    return [self _accentColorForCode: code dark: NO];
}

// The user's accent colour. Follows AppleAccentColor preference as a System catalog color.
+ (NSColor *) controlAccentColor {
    return [NSColor colorWithCatalogName: @"System" colorName: @"controlAccentColor"];
}

bool NSUserAccentHasHardwareColor(void) {
    return false;
}

NSString *NSUserAccentColorGetHardwareAccentColorName(void) {
    return nil;
}

// QUIRK: AppleAquaColorVariant == 6 corresponds to Graphite control tint (or AppleAccentColor == -1).
// Any other variant or default is NSBlueControlTint (value 1, not NSDefaultControlTint which is 0).
// Evidence: black-box reads of +currentControlTint on macOS 10.14.4 and 26.7.3 (tier 2): AppleAccentColor -1 and
// AppleAquaColorVariant 6 give 6 (graphite), every other accent gives 1 (blue).
// Test: tests/appkit-appearance-theme.m
+ (NSControlTint) currentControlTint {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    id variant = [defaults objectForKey: @"AppleAquaColorVariant"];
    if (variant != nil && [variant integerValue] == 6) {
        return NSGraphiteControlTint;
    }
    id accent = [defaults objectForKey: @"AppleAccentColor"];
    if (accent != nil && [accent integerValue] == -1) {
        return NSGraphiteControlTint;
    }
    return NSBlueControlTint;
}

// The colours are the ones macOS returns for the tints; they are not the
// current selection colours. Any other tint value gets the clear tint's grey.
+ (NSColor *) colorForControlTint: (NSControlTint) controlTint {
    switch (controlTint) {
    case NSDefaultControlTint:
    case NSBlueControlTint:
        return [NSColor colorWithSRGBRed: 0.608
                                   green: 0.757
                                    blue: 0.910
                                   alpha: 1.0];
    case NSGraphiteControlTint:
        return [NSColor colorWithSRGBRed: 0.729
                                   green: 0.757
                                    blue: 0.800
                                   alpha: 1.0];
    default:
        return [NSColor colorWithSRGBRed: 0.82 green: 0.82 blue: 0.82 alpha: 1.0];
    }
}

+ (NSColor *) selectedControlColor {
    return [NSColor colorWithCatalogName: @"System"
                               colorName: @"selectedControlColor"];
}

+ (NSColor *) secondarySelectedControlColor {
    return [NSColor colorWithCatalogName: @"System"
                               colorName: @"secondarySelectedControlColor"];
}

+ (NSColor *) controlTextColor {
    return [NSColor colorWithCatalogName: @"System"
                               colorName: @"controlTextColor"];
}

+ (NSColor *) selectedControlTextColor {
    return [NSColor colorWithCatalogName: @"System"
                               colorName: @"selectedControlTextColor"];
}

+ (NSColor *) disabledControlTextColor {
    return [NSColor colorWithCatalogName: @"System"
                               colorName: @"disabledControlTextColor"];
}

+ (NSColor *) controlBackgroundColor {
    return [NSColor colorWithCatalogName: @"System"
                               colorName: @"controlBackgroundColor"];
}

+ (NSColor *) controlDarkShadowColor {
    return [NSColor colorWithCatalogName: @"System"
                               colorName: @"controlDarkShadowColor"];
}

+ (NSColor *) controlHighlightColor {
    return [NSColor colorWithCatalogName: @"System"
                               colorName: @"controlHighlightColor"];
}

+ (NSColor *) controlLightHighlightColor {
    return [NSColor colorWithCatalogName: @"System"
                               colorName: @"controlLightHighlightColor"];
}

+ (NSColor *) controlShadowColor {
    return [NSColor colorWithCatalogName: @"System"
                               colorName: @"controlShadowColor"];
}

// The row backgrounds of tables, as in the light appearance of macOS 10.14: white and light grey.
// NOTE: the list may contain more than two colors
+ (NSArray *) controlAlternatingRowBackgroundColors {
    return [self alternatingContentBackgroundColors];
}

+ (NSColor *) textColor {
    return [NSColor colorWithCatalogName: @"System" colorName: @"textColor"];
}

+ (NSColor *) textBackgroundColor {
    return [NSColor colorWithCatalogName: @"System"
                               colorName: @"textBackgroundColor"];
}

+ (NSColor *) selectedTextColor {
    return [NSColor colorWithCatalogName: @"System"
                               colorName: @"selectedTextColor"];
}

+ (NSColor *) selectedTextBackgroundColor {
    return [NSColor colorWithCatalogName: @"System"
                               colorName: @"selectedTextBackgroundColor"];
}

+ (NSColor *) headerColor {
    return [NSColor colorWithCatalogName: @"System" colorName: @"headerColor"];
}

+ (NSColor *) headerTextColor {
    return [NSColor colorWithCatalogName: @"System"
                               colorName: @"headerTextColor"];
}

+ (NSColor *) scrollBarColor {
    return [NSColor colorWithCatalogName: @"System"
                               colorName: @"scrollBarColor"];
}

+ (NSColor *) knobColor {
    return [NSColor colorWithCatalogName: @"System" colorName: @"knobColor"];
}

+ (NSColor *) selectedKnobColor {
    return [NSColor colorWithCatalogName: @"System"
                               colorName: @"selectedKnobColor"];
}

+ (NSColor *) windowBackgroundColor {
    return [NSColor colorWithCatalogName: @"System"
                               colorName: @"windowBackgroundColor"];
}

+ (NSColor *) windowFrameColor {
    return [NSColor colorWithCatalogName: @"System"
                               colorName: @"windowFrameColor"];
}

+ (NSColor *) windowFrameTextColor {
    return [NSColor colorWithCatalogName: @"System" colorName: @"windowFrameTextColor"];
}

+ (NSColor *) selectedMenuItemColor {
    return [NSColor colorWithCatalogName: @"System"
                               colorName: @"selectedMenuItemColor"];
}

+ (NSColor *) selectedMenuItemTextColor {
    return [NSColor colorWithCatalogName: @"System"
                               colorName: @"selectedMenuItemTextColor"];
}

+ (NSColor *) menuBackgroundColor {
    return [NSColor colorWithCatalogName: @"System"
                               colorName: @"menuBackgroundColor"];
}

+ (NSColor *) mainMenuBarColor {
    return [NSColor colorWithCatalogName: @"System"
                               colorName: @"mainMenuBarColor"];
}

+ (NSColor *) menuItemTextColor {
    return [NSColor colorWithCatalogName: @"System"
                               colorName: @"menuItemTextColor"];
}

+ (NSColor *) labelColor {
    return [NSColor colorWithCatalogName: @"System" colorName: @"labelColor"];
}

// NSDisplay.m
void NSColorSetCatalogColor(NSColorListName catalogName, NSColorName colorName,
                            NSColor *color);
NSColor *NSColorGetCatalogColor(NSColorListName catalogName,
                                NSColorName colorName);

static BOOL isDarkAppearance(NSAppearance *appearance) {
    if (appearance == nil)
        appearance = [NSAppearance currentAppearance];
    NSAppearanceName match = [appearance bestMatchFromAppearancesWithNames: @[
        NSAppearanceNameAqua,
        NSAppearanceNameDarkAqua
    ]];
    return [match isEqualToString: NSAppearanceNameDarkAqua];
}

static void registerDynamicSystemColor(NSColorName name, NSColor *light, NSColor *dark) {
    NSColor *dynamic = [NSColor colorWithName: name dynamicProvider: ^NSColor *(NSAppearance *appearance) {
        return isDarkAppearance(appearance) ? dark : light;
    }];
    NSColorSetCatalogColor(@"System", name, dynamic);
}

// The selection colours follow the highlight colour the General preference pane writes together with the
// accent, so they are a table of the presets, Graphite (index 0) to Pink (7), each as {light, dark}. The
// selection colours are chosen by AppleHighlightColor's preset name and the focus indicator by AppleAccentColor.
// QUIRK: selectedControlColor (= selectedTextBackgroundColor), selectedContentBackgroundColor and
// keyboardFocusIndicatorColor depend on the accent/highlight setting, and differ between the appearances.
// Evidence: black-box reads of the three colours converted to sRGB on macOS 10.14.4 (tier 2), run with each
// AppleAccentColor value together with its AppleHighlightColor string (the preset names are the ones listed in
// https://alexwlchan.net/2022/changing-the-macos-accent-colour/ and the highlight strings in
// https://pypi.org/project/osx-colors/); the Blue light values are the ones pinned by the focus ring and
// system colour tests.
// Test: tests/appkit-appearance-theme.m
typedef struct {
    CGFloat control[2][4];
    CGFloat content[2][4];
    CGFloat focus[2][4];
} AccentSelectionColors;

static const AccentSelectionColors *accentSelectionTable(void) {
    static const AccentSelectionColors table[8] = {
    { /* -1 */ { { 0.878f, 0.878f, 0.878f, 1.000f }, { 1.000f, 1.000f, 1.000f, 0.247f } }, { { 0.502f, 0.502f, 0.502f, 1.000f }, { 0.408f, 0.408f, 0.408f, 1.000f } }, { { 0.600f, 0.600f, 0.620f, 1.000f }, { 0.765f, 0.765f, 0.765f, 0.498f } } },
    { /* 0 */ { { 0.961f, 0.765f, 0.773f, 1.000f }, { 0.545f, 0.341f, 0.345f, 1.000f } }, { { 0.765f, 0.145f, 0.169f, 1.000f }, { 0.816f, 0.204f, 0.224f, 1.000f } }, { { 0.827f, 0.125f, 0.153f, 0.247f }, { 1.000f, 0.478f, 0.502f, 0.298f } } },
    { /* 1 */ { { 0.988f, 0.851f, 0.733f, 1.000f }, { 0.533f, 0.396f, 0.278f, 1.000f } }, { { 0.851f, 0.420f, 0.039f, 1.000f }, { 0.784f, 0.376f, 0.012f, 1.000f } }, { { 0.922f, 0.435f, 0.008f, 0.247f }, { 1.000f, 0.698f, 0.224f, 0.298f } } },
    { /* 2 */ { { 0.996f, 0.914f, 0.745f, 1.000f }, { 0.541f, 0.459f, 0.290f, 1.000f } }, { { 0.871f, 0.620f, 0.082f, 1.000f }, { 0.804f, 0.561f, 0.055f, 1.000f } }, { { 0.945f, 0.659f, 0.055f, 0.247f }, { 1.000f, 0.949f, 0.278f, 0.298f } } },
    { /* 3 */ { { 0.816f, 0.918f, 0.780f, 1.000f }, { 0.361f, 0.463f, 0.325f, 1.000f } }, { { 0.302f, 0.627f, 0.196f, 1.000f }, { 0.259f, 0.569f, 0.165f, 1.000f } }, { { 0.302f, 0.671f, 0.184f, 0.247f }, { 0.553f, 0.957f, 0.424f, 0.298f } } },
    { /* 4 */ { { 0.701961f, 0.843137f, 1.000000f, 1.000f }, { 0.247f, 0.388f, 0.545f, 1.000f } }, { { 0.000000f, 0.388235f, 0.882353f, 1.000f }, { 0.000000f, 0.345098f, 0.815686f, 1.000f } }, { { 0.000000f, 0.403922f, 0.956863f, 0.247059f }, { 0.102f, 0.663f, 1.000f, 0.298f } } },
    { /* 5 */ { { 0.875f, 0.773f, 0.875f, 1.000f }, { 0.439f, 0.337f, 0.439f, 1.000f } }, { { 0.490f, 0.165f, 0.494f, 1.000f }, { 0.498f, 0.196f, 0.502f, 1.000f } }, { { 0.514f, 0.149f, 0.518f, 0.247f }, { 0.859f, 0.471f, 0.871f, 0.298f } } },
    { /* 6 */ { { 0.988f, 0.792f, 0.886f, 1.000f }, { 0.533f, 0.337f, 0.431f, 1.000f } }, { { 0.851f, 0.231f, 0.522f, 1.000f }, { 0.784f, 0.192f, 0.475f, 1.000f } }, { { 0.922f, 0.224f, 0.553f, 0.247f }, { 1.000f, 0.463f, 0.827f, 0.298f } } },
    };
    return table;
}

// The row the AppleAccentColor setting selects (keyboard focus indicator).
static const AccentSelectionColors *accentSelectionColors(void) {
    id val = [[NSUserDefaults standardUserDefaults] objectForKey: @"AppleAccentColor"];
    NSInteger code = (val != nil) ? [val integerValue] : 4;
    if (code < -1 || code > 6)
        code = 4;
    return &accentSelectionTable()[code + 1];
}

// The row the AppleHighlightColor setting selects (selection colours): the preset name the General pane appends to
// the RGB string, Blue when there is none. Returns -1 in *custom when the string has RGB but no preset name.
static const AccentSelectionColors *highlightSelectionColors(BOOL *custom) {
    static NSString *const names[8] = { @"Graphite", @"Red", @"Orange", @"Yellow", @"Green", @"Blue", @"Purple", @"Pink" };
    NSString *val = [[NSUserDefaults standardUserDefaults] stringForKey: @"AppleHighlightColor"];
    if (custom != NULL)
        *custom = NO;
    if (val != nil && [val length] > 0) {
        NSString *last = [[val componentsSeparatedByString: @" "] lastObject];
        for (int i = 0; i < 8; i++) {
            if ([last isEqualToString: names[i]])
                return &accentSelectionTable()[i];
        }
        if (custom != NULL)
            *custom = YES;
    }
    return &accentSelectionTable()[5];
}

static NSColor *selectionColor(const CGFloat c[4]) {
    return [NSColor colorWithSRGBRed: c[0] green: c[1] blue: c[2] alpha: c[3]];
}

// QUIRK: AppleHighlightColor in NSGlobalDomain stores RGB components as a space-separated float string,
// and selectedTextBackgroundColor and selectedControlColor follow it in the light appearance.
// Evidence: black-box reads on macOS 10.14.4 (tier 2) with AppleHighlightColor set to each preset; the string
// format is described in https://pypi.org/project/osx-colors/ (for example "0.752941 0.964706 0.678431 Green").
// Test: tests/appkit-appearance-theme.m
static NSColor *highlightColorFromDefaults(NSAppearance *appearance) {
    BOOL dark = isDarkAppearance(appearance);
    BOOL custom = NO;
    const AccentSelectionColors *row = highlightSelectionColors(&custom);
    if (!dark && custom) {
        NSString *val = [[NSUserDefaults standardUserDefaults] stringForKey: @"AppleHighlightColor"];
        if (val != nil && [val length] > 0) {
            float r = 0, g = 0, b = 0, a = 1.0;
            int count = sscanf([val UTF8String], "%f %f %f %f", &r, &g, &b, &a);
            if (count >= 3)
                return [NSColor colorWithSRGBRed: r green: g blue: b alpha: (count >= 4) ? a : 1.0f];
        }
    }
    return selectionColor(row->control[dark ? 1 : 0]);
}

// Registers the system colours that follow the appearance and the accent preferences in the System
// catalog. Done on the first catalog lookup rather than when the class initializes, so that merely using
// NSColor does not need a display.
void NSColorInitializeDynamicSystemColors(void) {
    static BOOL initialized = NO;
    if (initialized)
        return;
    initialized = YES;

    registerDynamicSystemColor(@"textColor", constantWhite(0.0, 1.0), constantWhite(1.0, 1.0));
    registerDynamicSystemColor(@"textBackgroundColor", constantWhite(1.0, 1.0), constantRGB(0.118, 0.118, 0.118, 1.0));
    registerDynamicSystemColor(@"controlColor", [NSColor colorWithCalibratedWhite: 0.93 alpha: 1.0], constantWhite(1.0, 0.247));
    registerDynamicSystemColor(@"controlTextColor", [NSColor colorWithSRGBRed: 0.0f green: 0.0f blue: 0.0f alpha: 0.847059f], constantWhite(1.0, 0.847059));
    registerDynamicSystemColor(@"selectedControlTextColor", [NSColor colorWithSRGBRed: 0.0f green: 0.0f blue: 0.0f alpha: 0.847059f], constantWhite(1.0, 0.847059));
    registerDynamicSystemColor(@"controlBackgroundColor", constantWhite(1.0, 1.0), constantRGB(0.118, 0.118, 0.118, 1.0));
    registerDynamicSystemColor(@"labelColor", [NSColor colorWithSRGBRed: 0.0f green: 0.0f blue: 0.0f alpha: 0.847059f],
                                            [NSColor colorWithSRGBRed: 1.0f green: 1.0f blue: 1.0f alpha: 0.847059f]);
    registerDynamicSystemColor(@"secondaryLabelColor", [NSColor colorWithSRGBRed: 0.0f green: 0.0f blue: 0.0f alpha: 0.498f],
                                                     [NSColor colorWithSRGBRed: 1.0f green: 1.0f blue: 1.0f alpha: 0.549f]);
    registerDynamicSystemColor(@"tertiaryLabelColor", [NSColor colorWithSRGBRed: 0.0f green: 0.0f blue: 0.0f alpha: 0.247f],
                                                    [NSColor colorWithSRGBRed: 1.0f green: 1.0f blue: 1.0f alpha: 0.25f]);
    registerDynamicSystemColor(@"quaternaryLabelColor", [NSColor colorWithSRGBRed: 0.0f green: 0.0f blue: 0.0f alpha: 0.098f],
                                                     [NSColor colorWithSRGBRed: 1.0f green: 1.0f blue: 1.0f alpha: 0.10f]);
    registerDynamicSystemColor(@"placeholderTextColor", [NSColor colorWithSRGBRed: 0.0f green: 0.0f blue: 0.0f alpha: 0.247f],
                                                      [NSColor colorWithSRGBRed: 1.0f green: 1.0f blue: 1.0f alpha: 0.25f]);
    registerDynamicSystemColor(@"windowFrameTextColor", [NSColor colorWithSRGBRed: 0.0f green: 0.0f blue: 0.0f alpha: 0.847f],
                                                       [NSColor colorWithSRGBRed: 1.0f green: 1.0f blue: 1.0f alpha: 0.847f]);
    registerDynamicSystemColor(@"separatorColor", [NSColor colorWithSRGBRed: 0.0f green: 0.0f blue: 0.0f alpha: 0.098f],
                                                [NSColor colorWithSRGBRed: 1.0f green: 1.0f blue: 1.0f alpha: 0.10f]);
    registerDynamicSystemColor(@"linkColor", [NSColor colorWithSRGBRed: 0.0f green: 0.411765f blue: 0.850980f alpha: 1.0f],
                                           [NSColor colorWithSRGBRed: 0.254902f green: 0.611765f blue: 1.0f alpha: 1.0f]);
    registerDynamicSystemColor(@"windowBackgroundColor", [NSColor colorWithSRGBRed: 0.925f green: 0.925f blue: 0.925f alpha: 1.0f],
                                                       constantRGB(0.196, 0.196, 0.196, 1.0));
    registerDynamicSystemColor(@"unemphasizedSelectedContentBackgroundColor", [NSColor colorWithSRGBRed: 0.862745f green: 0.862745f blue: 0.862745f alpha: 1.0f],
                                                                             [NSColor colorWithSRGBRed: 0.274510f green: 0.274510f blue: 0.274510f alpha: 1.0f]);
    registerDynamicSystemColor(@"unemphasizedSelectedTextColor", constantWhite(0.0, 1.0), constantWhite(1.0, 1.0));
    registerDynamicSystemColor(@"unemphasizedSelectedTextBackgroundColor", [NSColor colorWithSRGBRed: 0.863f green: 0.863f blue: 0.863f alpha: 1.0f],
                                                                          [NSColor colorWithSRGBRed: 0.275f green: 0.275f blue: 0.275f alpha: 1.0f]);

    // Dark values read on macOS 10.14.4 (tier 2, black-box reads of the colours in the DarkAqua appearance);
    // the light values are those DarlingDisplay returns.
    registerDynamicSystemColor(@"gridColor", [NSColor colorWithGenericGamma22White: 0.80f alpha: 1.0f], constantWhite(1.0, 0.098));
    registerDynamicSystemColor(@"headerTextColor", [NSColor colorWithSRGBRed: 0.0f green: 0.0f blue: 0.0f alpha: 0.847059f], constantWhite(1.0, 1.0));
    registerDynamicSystemColor(@"alternatingContentBackgroundColor", [NSColor colorWithSRGBRed: 0.956863f green: 0.960784f blue: 0.960784f alpha: 1.0f],
                                                                    constantWhite(1.0, 0.047));
    registerDynamicSystemColor(@"disabledControlTextColor", [NSColor colorWithSRGBRed: 0.0f green: 0.0f blue: 0.0f alpha: 0.247f], constantWhite(1.0, 0.247));
    registerDynamicSystemColor(@"highlightColor", [NSColor colorWithGenericGamma22White: 1.0f alpha: 1.0f], constantWhite(0.706, 1.0));
    NSColor *dynamicAccent = [NSColor colorWithName: @"controlAccentColor" dynamicProvider: ^NSColor *(NSAppearance *appearance) {
        id val = [[NSUserDefaults standardUserDefaults] objectForKey: @"AppleAccentColor"];
        NSInteger code = (val != nil) ? [val integerValue] : 4;
        return [NSColor _accentColorForCode: code dark: isDarkAppearance(appearance)];
    }];
    NSColorSetCatalogColor(@"System", @"controlAccentColor", dynamicAccent);

    NSColor *dynamicHighlight = [NSColor colorWithName: @"selectedTextBackgroundColor" dynamicProvider: ^NSColor *(NSAppearance *appearance) {
        return highlightColorFromDefaults(appearance);
    }];
    NSColorSetCatalogColor(@"System", @"selectedTextBackgroundColor", dynamicHighlight);
    NSColor *dynamicSelectedControl = [NSColor colorWithName: @"selectedControlColor" dynamicProvider: ^NSColor *(NSAppearance *appearance) {
        return highlightColorFromDefaults(appearance);
    }];
    NSColorSetCatalogColor(@"System", @"selectedControlColor", dynamicSelectedControl);
    NSColor *dynamicContent = [NSColor colorWithName: @"selectedContentBackgroundColor" dynamicProvider: ^NSColor *(NSAppearance *appearance) {
        return selectionColor(highlightSelectionColors(NULL)->content[isDarkAppearance(appearance) ? 1 : 0]);
    }];
    NSColorSetCatalogColor(@"System", @"selectedContentBackgroundColor", dynamicContent);
    // QUIRK: the indicator colour is a translucent tint of the accent, not an opaque one (see the table above).
    // Test: appkit-focus-ring.m (test_quirk_keyboard_focus_indicator_color) pins the Blue light value.
    NSColor *dynamicFocus = [NSColor colorWithName: @"keyboardFocusIndicatorColor" dynamicProvider: ^NSColor *(NSAppearance *appearance) {
        return selectionColor(accentSelectionColors()->focus[isDarkAppearance(appearance) ? 1 : 0]);
    }];
    NSColorSetCatalogColor(@"System", @"keyboardFocusIndicatorColor", dynamicFocus);
}

// A System catalog color that display backends may not know: the value a
// backend registered in the catalog, else the given default.
static NSColor *systemCatalogColor(NSColorName name, NSColor *fallback) {
    NSColorInitializeDynamicSystemColors();
    NSColor *color = [[NSDisplay currentDisplay] colorWithName: name];

    if (color == nil)
        color = NSColorGetCatalogColor(@"System", name);
    return [NSColor_catalog colorWithCatalogName: @"System"
                                       colorName: name
                                           color: color ? color : fallback];
}

// Label text at decreasing emphasis: black with less alpha than labelColor.
+ (NSColor *) secondaryLabelColor {
    return [NSColor colorWithCatalogName: @"System" colorName: @"secondaryLabelColor"];
}

+ (NSColor *) tertiaryLabelColor {
    return [NSColor colorWithCatalogName: @"System" colorName: @"tertiaryLabelColor"];
}

+ (NSColor *) quaternaryLabelColor {
    return [NSColor colorWithCatalogName: @"System" colorName: @"quaternaryLabelColor"];
}

// The Aqua values (the appearance of this implementation) of colors that macOS's System catalog
// has; a display backend may register another value.
+ (NSColor *) quinaryLabelColor {
    return systemCatalogColor(@"quinaryLabelColor", constantWhite(0.0, 0.047));
}

+ (NSColor *) placeholderTextColor {
    return [NSColor colorWithCatalogName: @"System" colorName: @"placeholderTextColor"];
}

+ (NSColor *) underPageBackgroundColor {
    return systemCatalogColor(@"underPageBackgroundColor", constantWhite(0.588, 0.898));
}

+ (NSColor *) findHighlightColor {
    return systemCatalogColor(@"findHighlightColor", constantRGB(1.0, 1.0, 0.0, 1.0));
}

// Fills for controls: black at decreasing alpha (macOS 11 and later; the Aqua values of 26.7.3).
+ (NSColor *) systemFillColor {
    return systemCatalogColor(@"systemFillColor", constantWhite(0.0, 0.098));
}

+ (NSColor *) secondarySystemFillColor {
    return systemCatalogColor(@"secondarySystemFillColor", constantWhite(0.0, 0.078));
}

+ (NSColor *) tertiarySystemFillColor {
    return systemCatalogColor(@"tertiarySystemFillColor", constantWhite(0.0, 0.047));
}

+ (NSColor *) quaternarySystemFillColor {
    return systemCatalogColor(@"quaternarySystemFillColor", constantWhite(0.0, 0.027));
}

+ (NSColor *) quinarySystemFillColor {
    return systemCatalogColor(@"quinarySystemFillColor", constantWhite(0.0, 0.008));
}

+ (NSColor *) systemRedColor {
    return systemCatalogColor(@"systemRedColor",
                              constantRGB(1.0, 0.23, 0.19, 1.0));
}

+ (NSColor *) systemGreenColor {
    return systemCatalogColor(@"systemGreenColor",
                              constantRGB(0.20, 0.78, 0.35, 1.0));
}

+ (NSColor *) systemBlueColor {
    return systemCatalogColor(@"systemBlueColor",
                              constantRGB(0.0, 0.48, 1.0, 1.0));
}

+ (NSColor *) systemOrangeColor {
    return systemCatalogColor(@"systemOrangeColor",
                              constantRGB(1.0, 0.58, 0.0, 1.0));
}

+ (NSColor *) systemYellowColor {
    return systemCatalogColor(@"systemYellowColor",
                              constantRGB(1.0, 0.80, 0.0, 1.0));
}

+ (NSColor *) systemBrownColor {
    return systemCatalogColor(@"systemBrownColor",
                              constantRGB(0.64, 0.52, 0.37, 1.0));
}

+ (NSColor *) systemPinkColor {
    return systemCatalogColor(@"systemPinkColor",
                              constantRGB(1.0, 0.18, 0.57, 1.0));
}

+ (NSColor *) systemPurpleColor {
    return systemCatalogColor(@"systemPurpleColor",
                              constantRGB(0.69, 0.32, 0.87, 1.0));
}

+ (NSColor *) systemGrayColor {
    return systemCatalogColor(@"systemGrayColor",
                              constantRGB(0.56, 0.56, 0.58, 1.0));
}

+ (NSColor *) systemTealColor {
    return systemCatalogColor(@"systemTealColor",
                              constantRGB(0.35, 0.78, 0.98, 1.0));
}

+ (NSColor *) systemIndigoColor {
    return systemCatalogColor(@"systemIndigoColor",
                              constantRGB(0.35, 0.34, 0.84, 1.0));
}

+ (NSColor *) systemMintColor {
    return systemCatalogColor(@"systemMintColor",
                              constantRGB(0.0, 0.78, 0.75, 1.0));
}

+ (NSColor *) systemCyanColor {
    return systemCatalogColor(@"systemCyanColor",
                              constantRGB(0.33, 0.75, 0.95, 1.0));
}

+ (NSColor *) unemphasizedSelectedTextColor {
    return [NSColor colorWithCatalogName: @"System"
                               colorName: @"unemphasizedSelectedTextColor"];
}

+ (NSColor *) unemphasizedSelectedTextBackgroundColor {
    return [NSColor colorWithCatalogName: @"System"
                               colorName: @"unemphasizedSelectedTextBackgroundColor"];
}

+ (NSColor *) linkColor {
    return [NSColor colorWithCatalogName: @"System" colorName: @"linkColor"];
}

+ (NSColor *) selectedContentBackgroundColor {
    return [NSColor colorWithCatalogName: @"System"
                               colorName: @"selectedContentBackgroundColor"];
}

+ (NSColor *) unemphasizedSelectedContentBackgroundColor {
    return [NSColor colorWithCatalogName: @"System"
                               colorName: @"unemphasizedSelectedContentBackgroundColor"];
}

+ (NSColor *) alternatingContentBackgroundColor {
    return [NSColor colorWithCatalogName: @"System"
                               colorName: @"alternatingContentBackgroundColor"];
}

+ (NSArray<NSColor *> *) alternatingContentBackgroundColors {
    return [NSArray arrayWithObjects: [self controlBackgroundColor],
                                      [self alternatingContentBackgroundColor],
                                      nil];
}

+ (NSColor *) clearColor {
    return constantRGB(0, 0, 0, 0);
}

+ (NSColor *) blackColor {
    return constantWhite(0, 1.0);
}

+ (NSColor *) blueColor {
    return constantRGB(0.0, 0.0, 1.0, 1.0);
}

+ (NSColor *) brownColor {
    return constantRGB(0.6, 0.4, 0.2, 1.0);
}

+ (NSColor *) cyanColor {
    return constantRGB(0.0, 1.0, 1.0, 1.0);
}

+ (NSColor *) darkGrayColor {
    return constantWhite(1.0 / 3.0, 1.0);
}

+ (NSColor *) grayColor {
    return constantWhite(0.5, 1.0);
}

+ (NSColor *) greenColor {
    return constantRGB(0.0, 1.0, 0.0, 1.0);
}

+ (NSColor *) lightGrayColor {
    return constantWhite(2.0 / 3.0, 1.0);
}

+ (NSColor *) magentaColor {
    return constantRGB(1.0, 0.0, 1.0, 1.0);
}

+ (NSColor *) orangeColor {
    return constantRGB(1.0, 0.5, 0.0, 1.0);
}

+ (NSColor *) purpleColor {
    return constantRGB(0.5, 0.0, 0.5, 1.0);
}

+ (NSColor *) redColor {
    return constantRGB(1.0, 0.0, 0.0, 1.0);
}

+ (NSColor *) whiteColor {
    return constantWhite(1, 1.0);
}

+ (NSColor *) yellowColor {
    return constantRGB(1.0, 1.0, 0.0, 1.0);
}

+ (NSColor *) colorWithDeviceWhite: (CGFloat) white alpha: (CGFloat) alpha {
    return [NSColor_CGColor colorWithGray: white
                                    alpha: alpha
                                spaceName: NSDeviceWhiteColorSpace];
}

+ (NSColor *) colorWithWhite: (CGFloat) white alpha: (CGFloat) alpha {
    return [self colorWithDeviceWhite: white alpha: alpha];
}

+ (NSColor *) colorWithDeviceRed: (CGFloat) red
                           green: (CGFloat) green
                            blue: (CGFloat) blue
                           alpha: (CGFloat) alpha
{
    return [NSColor_CGColor colorWithRed: red
                                   green: green
                                    blue: blue
                                   alpha: alpha
                               spaceName: NSDeviceRGBColorSpace];
}

+ (NSColor *) colorWithRed: (CGFloat) red
                     green: (CGFloat) green
                      blue: (CGFloat) blue
                     alpha: (CGFloat) alpha
{
    return [NSColor colorWithDeviceRed: red
                                 green: green
                                  blue: blue
                                 alpha: alpha];
}

+ (NSColor *) colorWithSRGBRed: (CGFloat) red
                         green: (CGFloat) green
                          blue: (CGFloat) blue
                         alpha: (CGFloat) alpha
{
    return [NSColor_CGColor colorWithRed: red
                                   green: green
                                    blue: blue
                                   alpha: alpha
                               spaceName: NSNamedColorSpace];
}

+ (NSColor *) colorWithDisplayP3Red: (CGFloat) red
                              green: (CGFloat) green
                               blue: (CGFloat) blue
                              alpha: (CGFloat) alpha
{
    CGFloat components[] = {red, green, blue, alpha};
    return [NSColor colorWithColorSpace: [NSColorSpace displayP3ColorSpace]
                             components: components
                                  count: 4];
}

+ (NSColor *) colorWithDeviceHue: (CGFloat) hue
                      saturation: (CGFloat) saturation
                      brightness: (CGFloat) brightness
                           alpha: (CGFloat) alpha
{
    return [NSColor_CGColor colorWithHue: hue
                              saturation: saturation
                              brightness: brightness
                                   alpha: alpha
                               spaceName: NSDeviceRGBColorSpace];
}

+ (NSColor *) colorWithDeviceCyan: (CGFloat) cyan
                          magenta: (CGFloat) magenta
                           yellow: (CGFloat) yellow
                            black: (CGFloat) black
                            alpha: (CGFloat) alpha
{
    return [NSColor_CGColor colorWithCyan: cyan
                                  magenta: magenta
                                   yellow: yellow
                                    black: black
                                    alpha: alpha
                                spaceName: NSDeviceCMYKColorSpace];
}

+ (NSColor *) colorWithCalibratedWhite: (CGFloat) white alpha: (CGFloat) alpha {
    return [NSColor_CGColor colorWithGray: white
                                    alpha: alpha
                                spaceName: NSCalibratedWhiteColorSpace];
}

+ (NSColor *) colorWithCalibratedRed: (CGFloat) red
                               green: (CGFloat) green
                                blue: (CGFloat) blue
                               alpha: (CGFloat) alpha
{
    return [NSColor_CGColor colorWithRed: red
                                   green: green
                                    blue: blue
                                   alpha: alpha
                               spaceName: NSCalibratedRGBColorSpace];
}

+ (NSColor *) colorWithCalibratedHue: (CGFloat) hue
                          saturation: (CGFloat) saturation
                          brightness: (CGFloat) brightness
                               alpha: (CGFloat) alpha
{
    return [NSColor_CGColor colorWithHue: hue
                              saturation: saturation
                              brightness: brightness
                                   alpha: alpha
                               spaceName: NSCalibratedRGBColorSpace];
}

+ (NSColor *) colorWithHue: (CGFloat) hue
                saturation: (CGFloat) saturation
                brightness: (CGFloat) brightness
                     alpha: (CGFloat) alpha
{
    // Not a calibrated color: macOS gives sRGB numbers here (see constantRGB).
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    NSColor *result = [NSColor_CGColor colorWithHue: hue
                                         saturation: saturation
                                         brightness: brightness
                                              alpha: alpha
                                          spaceName: NSCalibratedRGBColorSpace
                                         colorSpace: space];
    CGColorSpaceRelease(space);
    return result;
}

+ (NSColor *) colorWithCatalogName: (NSColorListName) catalogName
                         colorName: (NSColorName) colorName
{
    if ([catalogName isEqualToString: @"System"]) {
        NSColorInitializeDynamicSystemColors();
    }
    return [NSColor_catalog colorWithCatalogName: catalogName
                                       colorName: colorName];
}

+ (NSColor *) colorNamed: (NSColorName) name {
    return [self colorNamed: name bundle: nil];
}

// Looks a color up by name in the bundle's asset catalog (the main bundle if nil). A name that is
// not in the catalog gives nil, including the names of NSColor's own class methods such as labelColor.
+ (NSColor *) colorNamed: (NSColorName) name bundle: (NSBundle *) bundle {
    return [self _colorNamedInAssetCatalog: name bundle: bundle];
}

+ (NSColor *) colorWithGenericGamma22White: (CGFloat) white
                                     alpha: (CGFloat) alpha
{
    return [NSColor_CGColor colorWithGray: white
                                    alpha: alpha
                                spaceName: NSCustomColorSpace];
}

+ (NSColor *) colorWithColorSpace: (NSColorSpace *) space
                              hue: (CGFloat) hue
                       saturation: (CGFloat) saturation
                       brightness: (CGFloat) brightness
                            alpha: (CGFloat) alpha
{
    CGColorSpaceRef cgSpace = [space CGColorSpace];
    if (cgSpace == NULL || CGColorSpaceGetModel(cgSpace) != kCGColorSpaceModelRGB) {
        [NSException raise: NSInvalidArgumentException
                    format: @"+[NSColor colorWithColorSpace:hue:saturation:brightness:alpha:]: an RGB color space is required"];
    }

    hue = MIN(1.0, MAX(0.0, hue));
    saturation = MIN(1.0, MAX(0.0, saturation));
    brightness = MIN(1.0, MAX(0.0, brightness));

    // The standard hexcone conversion of the hue, in sixths.
    CGFloat sector = hue >= 1.0 ? 0.0 : hue * 6.0;
    int index = (int) sector;
    CGFloat fraction = sector - index;
    CGFloat p = brightness * (1.0 - saturation);
    CGFloat q = brightness * (1.0 - saturation * fraction);
    CGFloat t = brightness * (1.0 - saturation * (1.0 - fraction));
    CGFloat r, g, b;
    switch (index) {
    case 0: r = brightness; g = t; b = p; break;
    case 1: r = q; g = brightness; b = p; break;
    case 2: r = p; g = brightness; b = t; break;
    case 3: r = p; g = q; b = brightness; break;
    case 4: r = t; g = p; b = brightness; break;
    default: r = brightness; g = p; b = q; break;
    }

    CGFloat components[4] = { r, g, b, MIN(1.0, MAX(0.0, alpha)) };
    return [NSColor colorWithColorSpace: space components: components count: 4];
}

+ (NSColor *) colorWithName: (NSColorName) colorName dynamicProvider: (NSColor * (^)(NSAppearance *)) dynamicProvider {
    if (dynamicProvider == nil)
        [NSException raise: NSInvalidArgumentException format: @"+[NSColor colorWithName:dynamicProvider:]: nil provider"];
    return [[[NSColor_dynamic alloc] initWithName: colorName provider: dynamicProvider] autorelease];
}

+ (NSColor *) colorFromPasteboard: (NSPasteboard *) pasteboard {
    NSData *data = [pasteboard dataForType: NSColorPboardType];

    return [NSKeyedUnarchiver unarchiveObjectWithData: data];
}

static void drawPattern(void *info, CGContextRef cgContext) {
    NSImage *image = (NSImage *) info;
    NSSize size = [image size];
    NSGraphicsContext *context =
            [NSGraphicsContext graphicsContextWithGraphicsPort: cgContext
                                                       flipped: NO];

    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: context];
    [image drawInRect: NSMakeRect(0, 0, size.width, size.height)
             fromRect: NSZeroRect
            operation: NSCompositeCopy
             fraction: 1.0];
    [NSGraphicsContext restoreGraphicsState];
}

static void releasePatternInfo(void *info) {
    [(NSImage *) info release];
}

+ (NSColor *) colorWithPatternImage: (NSImage *) image {
    NSSize size = [image size];
    CGPatternCallbacks callbacks = {0, drawPattern, releasePatternInfo};
    [image retain];
    CGPatternRef pattern =
            CGPatternCreate(image, CGRectMake(0, 0, size.width, size.height),
                            CGAffineTransformIdentity, size.width, size.height,
                            kCGPatternTilingNoDistortion, YES, &callbacks);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGFloat components[4] = {1, 1, 1, 1};
    CGColorRef cgColor =
            CGColorCreateWithPattern(colorSpace, pattern, components);

    NSColor *result = [[[NSColor_CGColor alloc]
            initWithColorRef: cgColor
                   spaceName: NSPatternColorSpace] autorelease];

    CGColorRelease(cgColor);
    CGColorSpaceRelease(colorSpace);
    CGPatternRelease(pattern);

    return result;
}

- (NSImage *) patternImage {
    NSInvalidAbstractInvocation();
    return nil;
}

- (NSColorSpaceName) colorSpaceName {
    NSInvalidAbstractInvocation();
    return nil;
}

- (NSColorSpace *) colorSpace {
    CGColorRef cg = [self CGColor];
    if (cg != NULL) {
        CGColorSpaceRef cs = CGColorGetColorSpace(cg);
        if (cs != NULL) {
            return [[[NSColorSpace alloc] initWithCGColorSpace: cs] autorelease];
        }
    }
    return [NSColorSpace sRGBColorSpace];
}

- (NSInteger) numberOfComponents {
    NSInvalidAbstractInvocation();
    return 0;
}

- (void) getComponents: (CGFloat *) components {
    NSInvalidAbstractInvocation();
}

- (void) getWhite: (CGFloat *) white alpha: (CGFloat *) alpha {
    NSInvalidAbstractInvocation();
}

- (void) getRed: (CGFloat *) red
          green: (CGFloat *) green
           blue: (CGFloat *) blue
          alpha: (CGFloat *) alpha
{
    NSInvalidAbstractInvocation();
}

- (void) getHue: (CGFloat *) hue
        saturation: (CGFloat *) saturation
        brightness: (CGFloat *) brightness
             alpha: (CGFloat *) alpha
{
    NSInvalidAbstractInvocation();
}

- (void) getCyan: (CGFloat *) cyan
         magenta: (CGFloat *) magenta
          yellow: (CGFloat *) yellow
           black: (CGFloat *) black
           alpha: (CGFloat *) alpha
{
    NSInvalidAbstractInvocation();
}

- (CGFloat) whiteComponent {
    CGFloat white;

    [self getWhite: &white alpha: NULL];
    return white;
}

- (CGFloat) redComponent {
    CGFloat red;

    [self getRed: &red green: NULL blue: NULL alpha: NULL];

    return red;
}

- (CGFloat) greenComponent {
    CGFloat green;

    [self getRed: NULL green: &green blue: NULL alpha: NULL];

    return green;
}

- (CGFloat) blueComponent {
    CGFloat blue;

    [self getRed: NULL green: NULL blue: &blue alpha: NULL];

    return blue;
}

- (CGFloat) hueComponent {
    CGFloat hue;

    [self getHue: &hue saturation: NULL brightness: NULL alpha: NULL];

    return hue;
}

- (CGFloat) saturationComponent {
    CGFloat saturation;

    [self getHue: NULL saturation: &saturation brightness: NULL alpha: NULL];

    return saturation;
}

- (CGFloat) brightnessComponent {
    CGFloat brightness;

    [self getHue: NULL saturation: NULL brightness: &brightness alpha: NULL];

    return brightness;
}

- (CGFloat) cyanComponent {
    CGFloat cyan;

    [self getCyan: &cyan magenta: NULL yellow: NULL black: NULL alpha: NULL];
    return cyan;
}

- (CGFloat) magentaComponent {
    CGFloat magenta;

    [self getCyan: NULL magenta: &magenta yellow: NULL black: NULL alpha: NULL];
    return magenta;
}

- (CGFloat) yellowComponent {
    CGFloat yellow;

    [self getCyan: NULL magenta: NULL yellow: &yellow black: NULL alpha: NULL];
    return yellow;
}

- (CGFloat) blackComponent {
    CGFloat black;

    [self getCyan: NULL magenta: NULL yellow: NULL black: &black alpha: NULL];
    return black;
}

- (CGFloat) alphaComponent {
    return 1.0;
}

- (NSColorListName) catalogNameComponent {
    NSInvalidAbstractInvocation();
    return nil;
}

- (NSColorName) colorNameComponent {
    NSInvalidAbstractInvocation();
    return nil;
}

- (CGColorRef) CGColor {
    NSInvalidAbstractInvocation();
    return nil;
}

- (NSColor *) colorWithAlphaComponent: (CGFloat) alpha {
    if (alpha >= 1.0)
        return self;
    return nil;
}

// The same as passing a nil device description.
- (NSColor *) colorUsingColorSpaceName: (NSColorSpaceName) colorSpace {
    return [self colorUsingColorSpaceName: colorSpace device: nil];
}

- (NSColor *) colorUsingColorSpaceName: (NSColorSpaceName) colorSpace
                                device: (NSDictionary<NSString *,id> *) device
{
    NSInvalidAbstractInvocation();
    return nil;
}

// NSColorSpace wraps a CGColorSpace; the conversion goes to the device space
// of the same colour model, the closest the named-space conversions offer.
// nil when the colour cannot be converted.
- (NSColor *) colorUsingColorSpace: (NSColorSpace *) space {
    CGColorSpaceRef cgSpace = [space CGColorSpace];
    if (cgSpace == NULL)
        return nil;

    switch (CGColorSpaceGetModel(cgSpace)) {
    case kCGColorSpaceModelRGB:
        return [self colorUsingColorSpaceName: NSDeviceRGBColorSpace];
    case kCGColorSpaceModelMonochrome:
        return [self colorUsingColorSpaceName: NSDeviceWhiteColorSpace];
    case kCGColorSpaceModelCMYK:
        return [self colorUsingColorSpaceName: NSDeviceCMYKColorSpace];
    default:
        return nil;
    }
}

- (NSColor *) blendedColorWithFraction: (CGFloat) fraction
                               ofColor: (NSColor *) color
{
    NSColor *primary =
            [color colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
    NSColor *secondary =
            [self colorUsingColorSpaceName: NSCalibratedRGBColorSpace];

    if (primary == nil || secondary == nil)
        return nil;
    else {
        CGFloat pr, pg, pb, pa;
        CGFloat sr, sg, sb, sa;
        CGFloat rr, rg, rb, ra;

        [primary getRed: &pr green: &pg blue: &pb alpha: &pa];
        [secondary getRed: &sr green: &sg blue: &sb alpha: &sa];

        rr = pr * fraction + sr * (1 - fraction);
        rg = pg * fraction + sg * (1 - fraction);
        rb = pb * fraction + sb * (1 - fraction);
        ra = pa * fraction + sa * (1 - fraction);

        // The components are the colors' own numbers, kept as they were (see constantRGB).
        return constantRGB(rr, rg, rb, ra);
    }
}

// The color this color stands for right now: a catalog or dynamic color gives the color it resolves
// to for the current appearance, any other color itself.
- (NSColor *) _resolvedColor {
    return self;
}

// A color moved toward the highlight color (white) or the shadow color (black); levels outside 0...1
// are limited to it. The blend is that of -blendedColorWithFraction:ofColor:, alpha included. nil
// where the color has no RGB form (a pattern).
- (NSColor *) highlightWithLevel: (CGFloat) level {
    return [self blendedColorWithFraction: MIN(1.0, MAX(0.0, level)) ofColor: [NSColor highlightColor]];
}

- (NSColor *) shadowWithLevel: (CGFloat) level {
    return [self blendedColorWithFraction: MIN(1.0, MAX(0.0, level)) ofColor: [NSColor shadowColor]];
}

// QUIRK: the effects change a color the way a control's pressed, rolled-over and disabled states
// do, by numbers macOS does not document. Pressed is about c * 0.92 - 0.08 per RGB channel with the
// alpha moved 59% of the way to opaque, deep pressed and rollover about c * 0.86 - 0.14 with an
// opaque alpha, disabled 0.35 of the alpha; fitted to the results of macOS 10.14.4 and 26.7.3 for
// sRGB and system colors in the Aqua appearance, within 0.01. The result is a dynamic (catalog)
// color, as on macOS, so it follows the appearance of what it is applied to.
// Evidence: black-box observation (tier 2, MAC-EVIDENCE V615, probe v615_color_values.m).
// Test: tests/appkit-color-api.m (testSystemEffects)
static NSColor *colorWithEffect(NSColor *color, NSColorSystemEffect effect) {
    NSColor *rgb = [color colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
    if (rgb == nil)
        return color;
    CGFloat r, g, b, a;
    [rgb getRed: &r green: &g blue: &b alpha: &a];

    CGFloat slope = 1.0, offset = 0.0, alpha = a;
    switch (effect) {
    case NSColorSystemEffectPressed:
        slope = 0.9226;
        offset = -0.0795;
        alpha = a + (1.0 - a) * 0.59;
        break;
    case NSColorSystemEffectDeepPressed:
    case NSColorSystemEffectRollover:
        slope = 0.8598;
        offset = -0.1422;
        alpha = 1.0;
        break;
    case NSColorSystemEffectDisabled:
        alpha = a * 0.35;
        break;
    case NSColorSystemEffectNone:
    default:
        break;
    }
    return constantRGB(MAX(0.0, r * slope + offset), MAX(0.0, g * slope + offset),
                       MAX(0.0, b * slope + offset), alpha);
}

- (NSColor *) colorWithSystemEffect: (NSColorSystemEffect) effect {
    NSColor *base = self;
    return [NSColor colorWithName: nil
                  dynamicProvider: ^NSColor *(NSAppearance *appearance) {
                      return colorWithEffect([base _resolvedColor], effect);
                  }];
}

// A color is component based (RGB, white, CMYK), a catalog color (a named color, or one that
// depends on the appearance) or a pattern. A catalog color converts to what it stands for when that
// is component based; every other conversion between the kinds fails.
- (NSColor *) colorUsingType: (NSColorType) type {
    if ([self type] == type)
        return self;
    if (type == NSColorTypeComponentBased && [self type] == NSColorTypeCatalog) {
        NSColor *resolved = [self _resolvedColor];
        return [resolved type] == NSColorTypeComponentBased ? resolved : nil;
    }
    return nil;
}

// QUIRK: macOS answers "Developer" for the localized name of the System catalog and the color name
// itself for the localized name of a color (no localization tables are consulted). Not documented.
// Evidence: black-box observation on macOS 10.14.4 and 26.7.3 (tier 2, MAC-EVIDENCE V615).
// Test: tests/appkit-color-api.m (testCatalogNames)
- (NSString *) localizedCatalogNameComponent {
    // The localized names are only for catalog colors; any other color raises (macOS 26.7.3 and
    // 10.14.4, test appkit-color-api.m testCatalogNames)
    if ([self type] != NSColorTypeCatalog)
        [NSException raise: NSInvalidArgumentException format: @"-[NSColor localizedCatalogNameComponent]: not a catalog color"];
    NSString *name = [self catalogNameComponent];
    return [name isEqual: @"System"] ? @"Developer" : name;
}

- (NSString *) localizedColorNameComponent {
    if ([self type] != NSColorTypeCatalog)
        [NSException raise: NSInvalidArgumentException format: @"-[NSColor localizedColorNameComponent]: not a catalog color"];
    return [self colorNameComponent];
}

// There is no extended dynamic range here: every color is standard dynamic range, which is exposure 1.
- (CGFloat) linearExposure {
    return 1.0;
}

- (NSColor *) standardDynamicRangeColor {
    return [[self copy] autorelease];
}

- (NSColor *) colorByApplyingContentHeadroom: (CGFloat) contentHeadroom {
    return self;
}

- (void) set {
    [self setStroke];
    [self setFill];
}

- (void) setFill {
    NSInvalidAbstractInvocation();
}

- (void) setStroke {
    NSInvalidAbstractInvocation();
}

- (void) drawSwatchInRect: (NSRect) rect {
    // Draw some B&W triangle background so we can see the color alpha component
    [[NSColor whiteColor] setFill];
    NSRectFill(rect);
    [[NSColor blackColor] setFill];
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint: NSMakePoint(NSMinX(rect), NSMaxY(rect))];
    [path lineToPoint: NSMakePoint(NSMaxX(rect), NSMaxY(rect))];
    [path lineToPoint: NSMakePoint(NSMinX(rect), NSMinY(rect))];
    [path closePath];
    [path fill];

    [self setFill];
    NSRectFillUsingOperation(rect, NSCompositeSourceOver);
}

- (void) writeToPasteboard: (NSPasteboard *) pasteboard {
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject: self];

    [pasteboard setData: data forType: NSColorPboardType];
}

#pragma mark NSPasteboardWriting, NSPasteboardReading

- (NSArray<NSPasteboardType> *) writableTypesForPasteboard: (NSPasteboard *) pasteboard {
    return [NSArray arrayWithObject: NSPasteboardTypeColor];
}

- (id) pasteboardPropertyListForType: (NSPasteboardType) type {
    if (!NSPasteboardTypeConformsTo(type, NSPasteboardTypeColor))
        return nil;
    return [NSKeyedArchiver archivedDataWithRootObject: self];
}

+ (NSArray<NSPasteboardType> *) readableTypesForPasteboard: (NSPasteboard *) pasteboard {
    return [NSArray arrayWithObject: NSPasteboardTypeColor];
}

// The data of the type is an archive of the color: the object that comes out of it is the result.
+ (NSPasteboardReadingOptions) readingOptionsForType: (NSPasteboardType) type pasteboard: (NSPasteboard *) pasteboard {
    return NSPasteboardReadingAsKeyedArchive;
}

+ (void) setIgnoresAlpha: (BOOL) ignores {
    NSColor_ignoresAlpha = ignores;
}

// TODO: Affects NSColorPanel, NSColorSwatch and NSColorPickerTouchBarItem
+ (BOOL) ignoresAlpha {
    if (NSColor_ignoresAlpha == -1) {
        @synchronized(self) {
            if (NSColor_ignoresAlpha == -1)
                NSColor_ignoresAlpha =
                        [[[NSUserDefaults standardUserDefaults]
                                objectForKey: @"NSIgnoreAlpha"]
                                compare: @"NO"
                                options: NSCaseInsensitiveSearch] !=
                        NSOrderedSame;
        }
    }

    return NSColor_ignoresAlpha;
}

@end
