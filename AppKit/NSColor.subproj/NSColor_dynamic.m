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

// A color from +colorWithName:dynamicProvider:, resolved against the current appearance each time it is used.
@interface NSColor_dynamic : NSColor {
    NSColor *(^_provider)(NSAppearance *);
}
@end

@implementation NSColor_dynamic

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
