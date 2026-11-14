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
#import <AppKit/NSColor_CGColor.h>
#import <AppKit/NSColor_catalog.h>
#import <AppKit/NSColorSpace.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSRaise.h>

#import <AppKit/NSGraphics.h>
#import <AppKit/NSGraphicsContext.h>

#import <AppKit/NSPasteboard.h>
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

- (void) encodeWithCoder: (NSCoder *) coder {

    if ([coder allowsKeyedCoding]) {
        NSColorSpaceName spaceName = [self colorSpaceName];

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
            // FIXME: encode @"NSColor"
        }

    } else {
        // The layout -initWithCoder: reads: a color space byte followed by
        // the components as floats (or the names, for a catalog color).
        NSColorSpaceName spaceName = [self colorSpaceName];

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
            catalogName = [keyed decodeObjectForKey: @"NSCatalogName"];
            colorName = [keyed decodeObjectForKey: @"NSColorName"];
            color = [keyed decodeObjectForKey: @"NSColor"];
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

// macOS 10.14+; approximation: opaque gray instead of semitransparent
+ (NSColor *) separatorColor {
    return constantWhite(0.85, 1.0);
}

+ (NSColor *) textInsertionPointColor {
    return [NSColor blackColor];
}

+ (NSColor *) controlColor {
    return [NSColor colorWithCatalogName: @"System" colorName: @"controlColor"];
}

// The user's accent colour. There is no accent setting to follow here, so it
// is the default one, the system blue (sRGB 0, 122, 255).
+ (NSColor *) controlAccentColor {
    return [NSColor colorWithSRGBRed: 0.0
                               green: 122.0 / 255.0
                                blue: 1.0
                               alpha: 1.0];
}

// The blue tint is the default appearance.
+ (NSControlTint) currentControlTint {
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

// overwrite this, if you need a different set of alternating background colors
// NOTE: the list may contain more then two colors
+ (NSArray *) controlAlternatingRowBackgroundColors {
    return [NSArray arrayWithObjects: [NSColor whiteColor],
                                      constantRGB(0.90, 0.95, 1.0, 1.0),
                                      nil];
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
    return [NSColor controlColor];
}

+ (NSColor *) windowFrameColor {
    return [NSColor colorWithCatalogName: @"System"
                               colorName: @"windowFrameColor"];
}

+ (NSColor *) windowFrameTextColor {
    return [NSColor textColor];
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
NSColor *NSColorGetCatalogColor(NSColorListName catalogName,
                                NSColorName colorName);

// A System catalog color that display backends may not know: the value a
// backend registered in the catalog, else the given default.
static NSColor *systemCatalogColor(NSColorName name, NSColor *fallback) {
    NSColor *color = NSColorGetCatalogColor(@"System", name);
    return [NSColor_catalog colorWithCatalogName: @"System"
                                       colorName: name
                                           color: color ? color : fallback];
}

// Label text at decreasing emphasis: black with less alpha than labelColor.
+ (NSColor *) secondaryLabelColor {
    return systemCatalogColor(@"secondaryLabelColor",
                              constantWhite(0.0, 0.5));
}

+ (NSColor *) tertiaryLabelColor {
    return systemCatalogColor(@"tertiaryLabelColor",
                              constantWhite(0.0, 0.26));
}

+ (NSColor *) quaternaryLabelColor {
    return systemCatalogColor(@"quaternaryLabelColor",
                              constantWhite(0.0, 0.1));
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
