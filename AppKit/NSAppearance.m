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
    [super dealloc];
}

- (NSAppearanceName) name {
    return _name;
}

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
