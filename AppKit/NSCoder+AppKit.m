// Copyright (C) 2020 Lubos Dolezel

// Support for decoding legacy NXColors

#import "NSCoder+AppKit.h"
#import <Foundation/NSArchiver.h>
#import <Foundation/NSCoder.h>

enum {
    kColorSingleChannel = 0x1,
    kColorHasNamedColor = 0x4,
    kColorTypeFlags = 0x1f,
    kColorIsRGB = 0x40,
    kColorOpaque = 0x80,
};

@implementation NSCoder (AppKit)

- (NSColor *) decodeNXColor {
    uint8_t type;

    [self decodeValuesOfObjCTypes: "c", &type];
    if ((type & kColorTypeFlags) == 2 || (type & 0x10)) {
        return nil;
    }

    // RGB or CMY components
    uint16_t component1, component2, component3;
    if ((type & kColorTypeFlags) == kColorSingleChannel) {
        [self decodeValuesOfObjCTypes: "s", &component1];
        component3 = component2 = component1;
    } else {
        [self decodeValuesOfObjCTypes: "sss", &component1, &component2,
                                       &component3];
    }

    uint16_t componentK = 0, componentAlpha;
    if (!(type & kColorIsRGB)) {
        [self decodeValuesOfObjCTypes: "s", &componentK];
    }

    if (!(type & kColorOpaque)) {
        [self decodeValuesOfObjCTypes: "s", &componentAlpha];
    } else {
        componentAlpha = 65534; // opaque
    }
    if (type & kColorHasNamedColor) {
        NSString *colorName = nil;

        const char *atom;
        [self decodeValuesOfObjCTypes: "%", &atom];

        const char *name = atom;
        while (*name) {
            name++;
            if (*name == '\x1B') {
                break;
            }
        }

        if (*name) {
            colorName =
                [NSString stringWithCString: name
                                   encoding: NSMacOSRomanStringEncoding];
        }

        NSString *catalogs[2] = {@"PANTONE", nil};
        NSString *palette = nil;

        if (atom) {
            int i;
            char bufPalette[112];
            for (i = 0; i < 100; i++) {
                if (atom[i] == '\0' || atom[i] == '\x1B') {
                    break;
                }
                bufPalette[i] = atom[i];
            }
            bufPalette[i] = '\0';

            if (i != 0) {
                if (i == 2 && bufPalette[0] == 0x7F) {
                    // FIXME: This works differently in practice, but I don't
                    // know how
                    palette = catalogs[0];
                } else {
                    palette = [NSString
                        stringWithCString: bufPalette
                                 encoding: NSMacOSRomanStringEncoding];
                }
            }
        }

        if (colorName && palette) {
            NSColor *color = [NSColor colorWithCatalogName: palette
                                                 colorName: colorName];
            if (color != nil) {
                if (componentAlpha != 0) {
                    // TODO: Unless completely transparent, apply alpha
                }
                return color;
            }
        }
    }

    if (type & kColorIsRGB) {
        return [NSColor colorWithCalibratedRed: (component1 / 65534.0f)
                                         green: (component2 / 65534.0f)
                                          blue: (component3 / 65534.0f)
                                         alpha: (componentAlpha / 65534.0f)];
    } else {
        return [NSColor colorWithDeviceCyan: (component1 / 65534.0f)
                                    magenta: (component2 / 65534.0f)
                                     yellow: (component3 / 65534.0f)
                                      black: (componentK / 65534.0f)
                                      alpha: (componentAlpha / 65534.0f)];
    }
}

@end
