/*
 This file is part of Darling.

 Copyright (C) 2019 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

#import <AppKit/NSAppearance.h>
#import <AppKit/NSApplication.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSException.h>
#import <Foundation/NSThread.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSColorSpace.h>
#import <CoreGraphics/CoreGraphics.h>

NSString *const NSAppearanceNameAqua = @"NSAppearanceNameAqua";
NSString *const NSAppearanceNameDarkAqua = @"NSAppearanceNameDarkAqua";
NSString *const NSAppearanceNameSystem = @"NSAppearanceNameSystem";
NSString *const NSAppearanceNameTouchBar = @"NSAppearanceNameTouchBar";
NSString *const NSAppearanceNameLightContent = @"NSAppearanceNameLightContent";
NSString *const NSAppearanceNameVibrantDark = @"NSAppearanceNameVibrantDark";
NSString *const NSAppearanceNameVibrantLight = @"NSAppearanceNameVibrantLight";
NSString *const NSAppearanceNameAccessibilityHighContrastAqua =
        @"NSAppearanceNameAccessibilityAqua";
NSString *const NSAppearanceNameAccessibilityHighContrastDarkAqua =
        @"NSAppearanceNameAccessibilityDarkAqua";
NSString *const NSAppearanceNameAccessibilityHighContrastSystem =
        @"NSAppearanceNameAccessibilityHighContrastSystem";
NSString *const NSAppearanceNameAccessibilityHighContrastVibrantLight =
        @"NSAppearanceNameAccessibilityVibrantLight";
NSString *const NSAppearanceNameAccessibilityHighContrastVibrantDark =
        @"NSAppearanceNameAccessibilityVibrantDark";

NSString *const NSAppearanceNameControlStrip =
        @"NSAppearanceNameControlStrip"; // Undocumented

BOOL NSSolariumEnabled(void) {
    return NO;
}

@implementation NSAppearance

static NSString *const NSAppearanceThreadKey = @"NSAppearanceCurrentDrawingAppearance";

+ (NSAppearance *) appearanceNamed: (NSAppearanceName) name {
    static NSMutableDictionary *appearances;
    @synchronized(self) {
        if (appearances == nil) {
            NSAppearanceName names[] = {
                NSAppearanceNameAqua,
                NSAppearanceNameDarkAqua,
                NSAppearanceNameVibrantDark,
                NSAppearanceNameVibrantLight,
                NSAppearanceNameAccessibilityHighContrastAqua,
                NSAppearanceNameAccessibilityHighContrastDarkAqua,
                NSAppearanceNameAccessibilityHighContrastVibrantLight,
                NSAppearanceNameAccessibilityHighContrastVibrantDark,
                NSAppearanceNameLightContent,
            };
            appearances = [NSMutableDictionary new];
            for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
                NSAppearance *appearance = [[NSAppearance alloc] init];
                appearance->_name = [names[i] copy];
                [appearances setObject: appearance forKey: names[i]];
                [appearance release];
            }
        }
        return name == nil ? nil : [appearances objectForKey: name];
    }
}

- (void) dealloc {
    [_name release];
    if (NS_EXTRA_ALLOCATED(NSAppearance, self))
        [NS_EXTRA(NSAppearance, self)->_tintColor release];
    NS_EXTRA_FREE(NSAppearance, self);
    [super dealloc];
}

// SPI. The color controls drawn in this appearance are tinted with: the
// accent color, or the one given to -appearanceByApplyingTintColor:. Observed
// on macOS 26.7.3 (test tests/appkit-appearance-private.m): every named
// appearance reports the accent color in sRGB.
- (NSColor *) tintColor {
    if (NS_EXTRA_ALLOCATED(NSAppearance, self) && NS_EXTRA(NSAppearance, self)->_hasTintColor)
        return NS_EXTRA(NSAppearance, self)->_tintColor;
    NSColor *accent = [NSColor controlAccentColor];
    NSColor *srgb = [accent colorUsingColorSpace: [NSColorSpace sRGBColorSpace]];
    return srgb != nil ? srgb : accent;
}

// SPI. A new appearance of the same name whose tint color is the given one,
// also when that is nil. Two such appearances with equal names and tint colors
// are equal. Observed on macOS 26.7.3 (test tests/appkit-appearance-private.m).
- (NSAppearance *) appearanceByApplyingTintColor: (NSColor *) tintColor {
    NSAppearance *tinted = [[NSAppearance alloc] init];
    tinted->_name = [_name copy];
    NS_EXTRA(NSAppearance, tinted)->_hasTintColor = YES;
    NS_EXTRA(NSAppearance, tinted)->_tintColor = [tintColor retain];
    return [tinted autorelease];
}

- (BOOL) isEqual: (id) other {
    if (other == self)
        return YES;
    if (![other isKindOfClass: [NSAppearance class]])
        return NO;
    NSAppearance *appearance = other;
    if (!(_name == appearance->_name || [_name isEqualToString: appearance->_name]))
        return NO;
    BOOL tinted = NS_EXTRA_ALLOCATED(NSAppearance, self) && NS_EXTRA(NSAppearance, self)->_hasTintColor;
    BOOL otherTinted = NS_EXTRA_ALLOCATED(NSAppearance, appearance) && NS_EXTRA(NSAppearance, appearance)->_hasTintColor;
    if (tinted != otherTinted)
        return NO;
    if (!tinted)
        return YES;
    NSColor *tint = NS_EXTRA(NSAppearance, self)->_tintColor;
    NSColor *otherTint = NS_EXTRA(NSAppearance, appearance)->_tintColor;
    return tint == otherTint || [tint isEqual: otherTint];
}

- (NSUInteger) hash {
    return [_name hash];
}

- (NSAppearanceName) name {
    return _name;
}

// SPI. Whether controls are laid out with the current (macOS 26) metrics. Observed on macOS
// 26.7.3: YES for every named appearance, light, dark, vibrant and high contrast alike; the
// controls Darling draws follow the same metrics as its other appearances, so the answer is
// the same. Test: tests/appkit-scroll-view-separator-tracking.m.
- (BOOL) _usesMetricsAppearance {
    return YES;
}

BOOL NSAccessibilityDisplayShouldIncreaseContrast(void);

static BOOL isDarkAppearanceName(NSAppearanceName name) {
    return [name isEqualToString: NSAppearanceNameDarkAqua] ||
           [name isEqualToString: NSAppearanceNameVibrantDark] ||
           [name isEqualToString:
                         NSAppearanceNameAccessibilityHighContrastDarkAqua] ||
           [name isEqualToString:
                         NSAppearanceNameAccessibilityHighContrastVibrantDark];
}

// The receiver's own name if listed, else the basic appearance of its
// family (Aqua or Dark Aqua), so that asking with Aqua and Dark Aqua tells
// light from dark appearances, as Apple's Dark Mode documentation does.
- (NSAppearanceName) bestMatchFromAppearancesWithNames:
        (NSArray<NSAppearanceName> *) appearances
{
    if (_name == nil)
        return nil;
    // QUIRK: with Increase Contrast on, the Aqua and Dark Aqua appearances match the high contrast variant of
    // the same family when it is offered, while their own name stays Aqua / Dark Aqua.
    // Evidence: black-box reads on macOS 10.14.4 and 26.7.3 (tier 2): with increaseContrast set in
    // com.apple.universalaccess, asking Aqua for a best match among {Aqua, high contrast Aqua, Dark Aqua, high
    // contrast Dark Aqua} gives high contrast Aqua (Dark Aqua gives high contrast Dark Aqua), asking among
    // {Aqua, Dark Aqua} gives its own name, and the name itself is unchanged. Without the setting the own name wins.
    // Test: tests/appkit-appearance-increase-contrast.m
    BOOL isAqua = [_name isEqualToString: NSAppearanceNameAqua];
    BOOL isDarkAqua = [_name isEqualToString: NSAppearanceNameDarkAqua];
    if ((isAqua || isDarkAqua) && NSAccessibilityDisplayShouldIncreaseContrast()) {
        NSAppearanceName highContrast = isAqua ? NSAppearanceNameAccessibilityHighContrastAqua
                                               : NSAppearanceNameAccessibilityHighContrastDarkAqua;
        if ([appearances containsObject: highContrast])
            return highContrast;
    }
    if ([appearances containsObject: _name])
        return _name;
    NSAppearanceName family = isDarkAppearanceName(_name)
                                      ? NSAppearanceNameDarkAqua
                                      : NSAppearanceNameAqua;
    if ([appearances containsObject: family])
        return family;
    return nil;
}

+ (NSAppearance *) currentDrawingAppearance {
    NSAppearance *appearance = [[[NSThread currentThread] threadDictionary]
            objectForKey: NSAppearanceThreadKey];
    if (appearance == nil)
        appearance = [NSApp effectiveAppearance];
    if (appearance == nil)
        appearance = [self appearanceNamed: NSAppearanceNameAqua];
    return appearance;
}

+ (NSAppearance *) currentAppearance {
    return [self currentDrawingAppearance];
}

+ (void) setCurrentAppearance: (NSAppearance *) appearance {
    NSMutableDictionary *thread = [[NSThread currentThread] threadDictionary];
    if (appearance != nil)
        [thread setObject: appearance forKey: NSAppearanceThreadKey];
    else
        [thread removeObjectForKey: NSAppearanceThreadKey];
}

// Blocks nest, and the previous appearance comes back also when the block
// raises.
- (void) performAsCurrentDrawingAppearance: (void (^)(void)) block {
    NSMutableDictionary *thread = [[NSThread currentThread] threadDictionary];
    NSAppearance *previous =
            [[thread objectForKey: NSAppearanceThreadKey] retain];
    [thread setObject: self forKey: NSAppearanceThreadKey];
    @try {
        block();
    } @finally {
        if (previous != nil)
            [thread setObject: previous forKey: NSAppearanceThreadKey];
        else
            [thread removeObjectForKey: NSAppearanceThreadKey];
        [previous release];
    }
}

// How far colorByAdjustingLightnessOfColor:darker: blends towards black or white.
static const CGFloat NSAppearanceLightnessAdjustment = 0.1;

+ (NSColor *) colorByAdjustingLightnessOfColor: (NSColor *) color darker: (BOOL) darker {
    NSColor *target = darker ? [NSColor blackColor] : [NSColor whiteColor];
    NSColor *result = [color blendedColorWithFraction: NSAppearanceLightnessAdjustment
                                              ofColor: target];
    return result ? result : color;
}

// The CoreUI option strings _drawInRect:context:options: understands (the
// values of kCUIWidgetKey, kCUIWidgetScrollBarTrackCorner and kCUIIsFlippedKey).
static NSString *const NSAppearanceWidgetKey = @"widget";
static NSString *const NSAppearanceWidgetScrollBarTrackCorner = @"kCUIWidgetScrollBarTrackCorner";
static NSString *const NSAppearanceIsFlippedKey = @"is.flipped";

// The square of scroll bar track corner artwork, in points.
static const CGFloat NSAppearanceTrackCornerSize = 15;

// SPI. Draws the system artwork for the widget the options name (CoreUI option
// keys) into the context. Darling has artwork for the scroll bar track corner;
// other widgets draw nothing, as on macOS for a widget it does not know.
// QUIRK: the track corner is a fixed 15 x 15 square centered in the rect, not
// scaled to it: light gray (250/255) in light appearances, light gray at about
// 7% opacity in dark ones. A half-point offset rounds down, except vertically
// when the options say the context is flipped, where it rounds up. Not
// documented. Evidence: black-box observation on macOS 26.7.3 x86_64 of the
// pixels drawn into bitmap contexts (tier 2).
// Test: tests/appkit-appearance-private.m.
- (void) _drawInRect: (NSRect) rect context: (CGContextRef) context options: (NSDictionary *) options {
    if (context == NULL)
        return;
    id widget = [options objectForKey: NSAppearanceWidgetKey];
    if (![widget isKindOfClass: [NSString class]] ||
        ![widget isEqualToString: NSAppearanceWidgetScrollBarTrackCorner])
        return;

    BOOL flipped = [[options objectForKey: NSAppearanceIsFlippedKey] boolValue];
    CGFloat y = NSMidY(rect) - NSAppearanceTrackCornerSize / 2;
    CGRect square = CGRectMake(
            floor(NSMidX(rect) - NSAppearanceTrackCornerSize / 2),
            flipped ? ceil(y) : floor(y),
            NSAppearanceTrackCornerSize, NSAppearanceTrackCornerSize);
    CGContextSaveGState(context);
    if (isDarkAppearanceName(_name))
        CGContextSetRGBFillColor(context, 0.79, 0.79, 0.79, 0.075);
    else
        CGContextSetRGBFillColor(context, 250.0 / 255, 250.0 / 255, 250.0 / 255, 1);
    CGContextFillRect(context, square);
    CGContextRestoreGState(context);
}

- (void) encodeWithCoder: (NSCoder *) aCoder {
}

- (id) initWithCoder: (NSCoder *) aDecoder {
    return self;
}

+ (BOOL) supportsSecureCoding
{
    return YES;
}

@end
