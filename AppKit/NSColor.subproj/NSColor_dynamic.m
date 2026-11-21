/*
 This file is part of Darling.

 Copyright (C) 2026 Darling Developers

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
#import <AppKit/NSColor.h>
#import <Foundation/NSUUID.h>

// A color from +colorWithName:dynamicProvider:, resolved against the current appearance each time it is used.
@interface NSColor_dynamic : NSColor {
#if !__OBJC2__ // NSColor's ivars, see NSColor.h
    NSColorName _colorName;
#endif
    NSColor *(^_provider)(NSAppearance *);
}
@end

@implementation NSColor_dynamic

- (NSColorType) type {
    // Classify the dynamic object without resolving its current representation.
    return NSColorTypeCatalog;
}

- initWithName: (NSColorName) name provider: (NSColor * (^)(NSAppearance *)) provider {
    _colorName = [name copy];
    _provider = [provider copy];
    return self;
}

- (void) dealloc {
    [_colorName release];
    [_provider release];
    [super dealloc];
}

- (NSColor *) _resolvedColor {
    NSColor *color = _provider([NSAppearance currentAppearance]);
    if (color == nil)
        [NSException raise: NSInternalInconsistencyException
                    format: @"dynamic color %@: the provider returned nil", _colorName];
    if ([color isKindOfClass: [NSColor_dynamic class]])
        return [(NSColor_dynamic *) color _resolvedColor];
    return color;
}

- (NSString *) description {
    return [NSString stringWithFormat: @"<%@ name: %@ resolved: %@>", [self class], _colorName, [self _resolvedColor]];
}

- (NSColorName) colorNameComponent {
    return _colorName;
}

// QUIRK: a dynamic color archives as a catalog color of the list "#$customDynamic", named after the
// color (a unique name when it has none), with the color it resolves to now as the fallback; that is
// what a reader gets back. Not documented. Evidence: black-box observation of the archive and of
// unarchiving on macOS 26.7.3 (tier 2). Test: tests/appkit-color-secure-coding.m
- (void) encodeWithCoder: (NSCoder *) coder {
    NSColorName name = _colorName ? _colorName : [[NSUUID UUID] UUIDString];
    NSColorListName catalog = @"#$customDynamic";
    NSColor *resolved = [[self _resolvedColor] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];

    if (resolved == nil)
        [NSException raise: NSInvalidArgumentException
                    format: @"%@ can not encodeWithCoder:%@: it does not resolve to an RGB color",
                            [self class], [coder class]];

    if ([coder allowsKeyedCoding]) {
        [coder encodeInt: 6 forKey: @"NSColorSpace"];
        [coder encodeObject: catalog forKey: @"NSCatalogName"];
        [coder encodeObject: name forKey: @"NSColorName"];
        [coder encodeObject: resolved forKey: @"NSColor"];
    } else {
        uint8_t space = 6;
        [coder encodeValueOfObjCType: "c" at: &space];
        [coder encodeValuesOfObjCTypes: "@@@", &catalog, &name, &resolved];
    }
}

- (NSColorSpaceName) colorSpaceName {
    return [[self _resolvedColor] colorSpaceName];
}

- (NSInteger) numberOfComponents {
    return [[self _resolvedColor] numberOfComponents];
}

- (void) getComponents: (CGFloat *) components {
    [[self _resolvedColor] getComponents: components];
}

- (void) getWhite: (CGFloat *) white alpha: (CGFloat *) alpha {
    [[self _resolvedColor] getWhite: white alpha: alpha];
}

- (void) getRed: (CGFloat *) red green: (CGFloat *) green blue: (CGFloat *) blue alpha: (CGFloat *) alpha {
    [[self _resolvedColor] getRed: red green: green blue: blue alpha: alpha];
}

- (void) getHue: (CGFloat *) hue
        saturation: (CGFloat *) saturation
        brightness: (CGFloat *) brightness
             alpha: (CGFloat *) alpha
{
    [[self _resolvedColor] getHue: hue saturation: saturation brightness: brightness alpha: alpha];
}

- (void) getCyan: (CGFloat *) cyan
         magenta: (CGFloat *) magenta
          yellow: (CGFloat *) yellow
           black: (CGFloat *) black
           alpha: (CGFloat *) alpha
{
    [[self _resolvedColor] getCyan: cyan magenta: magenta yellow: yellow black: black alpha: alpha];
}

- (CGFloat) alphaComponent {
    return [[self _resolvedColor] alphaComponent];
}

- (NSImage *) patternImage {
    return [[self _resolvedColor] patternImage];
}

- (CGColorRef) CGColor {
    return [[self _resolvedColor] CGColor];
}

- (NSColor *) colorUsingColorSpace: (NSColorSpace *) space {
    return [[self _resolvedColor] colorUsingColorSpace: space];
}

- (NSColor *) colorUsingColorSpaceName: (NSColorSpaceName) colorSpace {
    return [self colorUsingColorSpaceName: colorSpace device: nil];
}

- (NSColor *) colorUsingColorSpaceName: (NSColorSpaceName) colorSpace device: (NSDictionary<NSString *, id> *) device {
    return [[self _resolvedColor] colorUsingColorSpaceName: colorSpace device: device];
}

// Stays dynamic: the alpha applies to whatever the provider resolves to.
- (NSColor *) colorWithAlphaComponent: (CGFloat) alpha {
    NSColor *(^provider)(NSAppearance *) = _provider;
    return [NSColor colorWithName: _colorName
                  dynamicProvider: ^NSColor *(NSAppearance *appearance) {
                      return [provider(appearance) colorWithAlphaComponent: alpha];
                  }];
}

- (void) setFill {
    [[self _resolvedColor] setFill];
}

- (void) setStroke {
    [[self _resolvedColor] setStroke];
}

@end
