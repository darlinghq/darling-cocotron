/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

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

// Original - Christopher Lloyd <cjwl@objc.net>
#import <AppKit/NSDisplay.h>
#import <AppKit/NSFontFamily.h>
#import <AppKit/NSFontTypeface.h>
#import <AppKit/NSGraphicsContext.h>
#import <CoreText/CoreText.h>

@interface NSFontFamily ()
+ (NSMutableArray *) fontFamilies;
+ (void) buildFontFamilies;
+ (NSArray *) _familyAndStyleForFontName: (NSString *) name;
- (NSFontTypeface *) _typefaceWithExactName: (NSString *) name;
@end

@implementation NSFontFamily

static NSMutableArray *sharedList = nil;
static NSMutableDictionary *sharedByName = nil;

+ (NSMutableArray *) fontFamilies {
    @synchronized([NSFontFamily class]) {
        if (sharedList == nil) {
            sharedList = [NSMutableArray new];
            sharedByName = [NSMutableDictionary new];
            [self buildFontFamilies];
        }

        return sharedList;
    }
}

+ (NSArray *) allFontFamilyNames {
    NSMutableArray *result = [NSMutableArray new];
    NSArray *families = [self fontFamilies];
    int i, count = [families count];

    for (i = 0; i < count; i++)
        [result addObject: [[families objectAtIndex: i] name]];

    [result sortUsingSelector: @selector(compare:)];

    return result;
}

+ (void) addFontFamily: (NSFontFamily *) family {
    if (family == nil)
        return;
    @synchronized([NSFontFamily class]) {
        [[self fontFamilies] addObject: family];
        NSString *name = [family name];
        if (name != nil)
            [sharedByName setObject: family forKey: name];
    }
}

+ (NSFontFamily *) addFontFamilyWithName: (NSString *) familyName {
    if (familyName == nil)
        return nil;
    // The typefaces are looked up when they are first needed (see
    // -_ensureTypefacesLoaded): asking the font system about every installed
    // family up front takes seconds on a system with many fonts.
    NSFontFamily *family = [[self alloc] initWithName: familyName];
    [self addFontFamily: family];
    return [family autorelease];
}

+ (void) buildFontFamilies {
    NSSet *initialFamilyNames = [[NSDisplay currentDisplay] allFontFamilyNames];
    for (NSString *familyName in initialFamilyNames) {
        [self addFontFamilyWithName: familyName];
    }
}

+ (NSFontFamily *) fontFamilyWithName: (NSString *) name {
    if (name == nil)
        return nil;
    @synchronized([NSFontFamily class]) {
        [self fontFamilies]; // Ensure buildFontFamilies has run
        NSFontFamily *family = [sharedByName objectForKey: name];
        if (family != nil)
            return family;

        // Pretend to have this family.
        return [self addFontFamilyWithName: name];
    }
}

// A font can be named by something other than one of the typeface names
// listed for its family, such as a display name or a name that the font
// system substitutes. Ask the font system which face the name resolves to,
// and return that face's family and style names, or nil.
+ (NSArray *) _familyAndStyleForFontName: (NSString *) name {
    static NSMutableDictionary *resolved = nil;
    NSArray *result;

    if (name == nil)
        return nil;

    @synchronized(self) {
        if (resolved == nil)
            resolved = [NSMutableDictionary new];
        result = [[[resolved objectForKey: name] retain] autorelease];
    }

    if (result == nil) {
        CTFontRef font = CTFontCreateWithName((CFStringRef) name, 12, NULL);
        NSString *family = nil, *style = nil;

        if (font != NULL) {
            family = (NSString *) CTFontCopyFamilyName(font);
            style = (NSString *) CTFontCopyName(font, kCTFontStyleNameKey);
            CFRelease(font);
        }

        if (family != nil && style != nil)
            result = [NSArray arrayWithObjects: family, style, nil];
        else
            result = (NSArray *) [NSNull null];
        [family release];
        [style release];

        @synchronized(self) {
            [resolved setObject: result forKey: name];
        }
    }

    return (result == (NSArray *) [NSNull null]) ? nil : result;
}

+ (NSFontFamily *) fontFamilyWithTypefaceName: (NSString *) name {
    if (name == nil)
        return nil;

    NSArray *familyAndStyle = [self _familyAndStyleForFontName: name];

    // The family the font system resolves the name to is almost always the
    // answer; looking there first avoids loading the typefaces of every
    // family just to find a name.
    if (familyAndStyle != nil) {
        NSFontFamily *resolvedFamily;

        @synchronized([NSFontFamily class]) {
            [self fontFamilies];
            resolvedFamily = [[[sharedByName objectForKey:
                    [familyAndStyle objectAtIndex: 0]] retain] autorelease];
        }
        if ([resolvedFamily _typefaceWithExactName: name] != nil)
            return resolvedFamily;
    }

    NSArray *families = [self fontFamilies];
    int i, count = [families count];

    for (i = 0; i < count; i++) {
        NSFontFamily *check = [families objectAtIndex: i];

        if ([check _typefaceWithExactName: name] != nil)
            return check;
    }

    if (familyAndStyle == nil)
        return nil;

    NSFontFamily *family =
            [self fontFamilyWithName: [familyAndStyle objectAtIndex: 0]];

    if ([family typefaceWithName: name] == nil)
        return nil;

    return family;
}

+ (NSFontTypeface *) fontTypefaceWithName: (NSString *) name {
    return [[self fontFamilyWithTypefaceName: name] typefaceWithName: name];
}

- initWithName: (NSString *) name {
    _name = [name copy];
    _typefaces = [NSMutableArray new];
    _typefacesLoaded = NO;
    return self;
}

- (void) dealloc {
    [_name release];
    [_typefaces release];
    [super dealloc];
}

- (NSString *) name {
    return _name;
}

// Asks the font system for the family's typefaces the first time they are
// needed.
- (void) _ensureTypefacesLoaded {
    if (!_typefacesLoaded) {
        @synchronized(self) {
            if (!_typefacesLoaded) {
                NSArray *typefaces = [[NSDisplay currentDisplay]
                        fontTypefacesForFamilyName: _name];
                if (typefaces != nil)
                    [_typefaces addObjectsFromArray: typefaces];
                _typefacesLoaded = YES;
            }
        }
    }
}

- (NSFontTypeface *) _typefaceWithExactName: (NSString *) name {
    [self _ensureTypefacesLoaded];
    int i, count = [_typefaces count];

    for (i = 0; i < count; i++) {
        NSFontTypeface *typeface = [_typefaces objectAtIndex: i];

        if ([[typeface name] isEqualToString: name])
            return typeface;
    }

    return nil;
}

- (NSFontTypeface *) typefaceWithName: (NSString *) name {
    NSFontTypeface *typeface = [self _typefaceWithExactName: name];

    if (typeface != nil)
        return typeface;

    // Otherwise, take the face the name resolves to, if it is in this family.
    NSArray *familyAndStyle = [[self class] _familyAndStyleForFontName: name];

    if (![[familyAndStyle objectAtIndex: 0] isEqualToString: _name])
        return nil;

    NSString *style = [familyAndStyle objectAtIndex: 1];
    [self _ensureTypefacesLoaded];
    int i, count = [_typefaces count];

    for (i = 0; i < count; i++) {
        typeface = [_typefaces objectAtIndex: i];

        if ([[typeface traitName] isEqualToString: style])
            return typeface;
    }

    return nil;
}

- (NSFontTypeface *) typefaceWithTraits: (NSFontTraitMask) traits {
    [self _ensureTypefacesLoaded];
    int i, count = [_typefaces count];

    for (i = 0; i < count; i++) {
        NSFontTypeface *typeface = [_typefaces objectAtIndex: i];

        if ([typeface traits] == traits)
            return typeface;
    }

    return nil;
}

- (void) addTypeface: (NSFontTypeface *) typeface {
    if (typeface != nil) {
        _typefacesLoaded = YES;
        [_typefaces addObject: typeface];
    }
}

- (void) addTypefaces: (NSArray *) typefaces {
    if (typefaces != nil) {
        _typefacesLoaded = YES;
        [_typefaces addObjectsFromArray: typefaces];
    }
}

- (NSArray *) typefaces {
    [self _ensureTypefacesLoaded];
    return _typefaces;
}

- (NSString *) description {
    return [NSString stringWithFormat: @"<%@ 0x%x %@ %@>", [self class], self,
                                       _name, _typefaces];
}
@end
