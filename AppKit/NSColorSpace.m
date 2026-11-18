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

#import <AppKit/NSColorSpace.h>
#import <Foundation/NSRaise.h>
#import <dispatch/dispatch.h>

// not sure where these belong
NSString *const _NSColorCoreUICatalogMainBundleID =
        @"_NSColorCoreUICatalogMainBundleID";
NSString *const _NSColorCoreUICatalogNamePrefix =
        @"_NSColorCoreUICatalogNamePrefix";

@implementation NSColorSpace

+ (NSColorSpace *) displayP3ColorSpace {
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);
    if (space == NULL)
        return nil;
    NSColorSpace *result =
            [[[self alloc] initWithCGColorSpace: space] autorelease];
    CGColorSpaceRelease(space);
    return result;
}

+ (NSColorSpace *) sRGBColorSpace {
    CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    NSColorSpace *colorSpace =
            [[[self alloc] initWithCGColorSpace: srgb] autorelease];
    CGColorSpaceRelease(srgb);
    return colorSpace;
}

+ (NSColorSpace *) extendedSRGBColorSpace {
    static NSColorSpace *shared = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      CGColorSpaceRef space =
              CGColorSpaceCreateWithName(kCGColorSpaceExtendedSRGB);
      if (space != NULL) {
          shared = [[self alloc] initWithCGColorSpace: space];
          CGColorSpaceRelease(space);
      }
    });
    return shared;
}

// The generic spaces fall back to sRGB / device gray if the named space cannot be created.
+ (NSColorSpace *) genericRGBColorSpace {
    CGColorSpaceRef rgb = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
    if (rgb == NULL)
        return [self sRGBColorSpace];

    NSColorSpace *result =
            [[[self alloc] initWithCGColorSpace: rgb] autorelease];
    CGColorSpaceRelease(rgb);
    return result;
}

+ (NSColorSpace *) genericGrayColorSpace {
    CGColorSpaceRef gray = CGColorSpaceCreateWithName(kCGColorSpaceGenericGray);
    if (gray == NULL)
        gray = CGColorSpaceCreateDeviceGray();
    NSColorSpace *result =
            [[[self alloc] initWithCGColorSpace: gray] autorelease];
    CGColorSpaceRelease(gray);
    return result;
}

+ (NSColorSpace *) genericGamma22GrayColorSpace {
    CGColorSpaceRef gray =
            CGColorSpaceCreateWithName(kCGColorSpaceGenericGrayGamma2_2);
    if (gray == NULL)
        return [self genericGrayColorSpace];

    NSColorSpace *result =
            [[[self alloc] initWithCGColorSpace: gray] autorelease];
    CGColorSpaceRelease(gray);
    return result;
}

+ (NSColorSpace *) deviceRGBColorSpace {
    CGColorSpaceRef device = CGColorSpaceCreateDeviceRGB();
    NSColorSpace *result =
            [[[self alloc] initWithCGColorSpace: device] autorelease];

    CGColorSpaceRelease(device);

    return result;
}

+ (NSColorSpace *) deviceGrayColorSpace {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceGray();
    NSColorSpace *result =
            [[[self alloc] initWithCGColorSpace: space] autorelease];
    CGColorSpaceRelease(space);
    return result;
}

+ (NSColorSpace *) deviceCMYKColorSpace {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceCMYK();
    NSColorSpace *result =
            [[[self alloc] initWithCGColorSpace: space] autorelease];
    CGColorSpaceRelease(space);
    return result;
}

+ (NSColorSpace *) _colorSpaceWithCGName: (CFStringRef) name {
    CGColorSpaceRef space = CGColorSpaceCreateWithName(name);
    if (space == NULL)
        return nil;
    NSColorSpace *result =
            [[[self alloc] initWithCGColorSpace: space] autorelease];
    CGColorSpaceRelease(space);
    return result;
}

+ (NSColorSpace *) genericCMYKColorSpace {
    return [self _colorSpaceWithCGName: kCGColorSpaceGenericCMYK];
}

+ (NSColorSpace *) adobeRGB1998ColorSpace {
    return [self _colorSpaceWithCGName: kCGColorSpaceAdobeRGB1998];
}

- initWithCGColorSpace: (CGColorSpaceRef) cgColorSpace {
    _cgColorSpace = CGColorSpaceRetain(cgColorSpace);
    return self;
}

- (void) dealloc {
    CGColorSpaceRelease(_cgColorSpace);
    [super dealloc];
}

- (CGColorSpaceRef) CGColorSpace {
    return _cgColorSpace;
}

- (NSColorSpaceModel) colorSpaceModel {
    switch (CGColorSpaceGetModel(_cgColorSpace)) {
    case kCGColorSpaceModelMonochrome:
        return NSColorSpaceModelGray;
    case kCGColorSpaceModelRGB:
        return NSColorSpaceModelRGB;
    case kCGColorSpaceModelCMYK:
        return NSColorSpaceModelCMYK;
    case kCGColorSpaceModelLab:
        return NSColorSpaceModelLAB;
    case kCGColorSpaceModelDeviceN:
        return NSColorSpaceModelDeviceN;
    case kCGColorSpaceModelIndexed:
        return NSColorSpaceModelIndexed;
    case kCGColorSpaceModelPattern:
        return NSColorSpaceModelPatterned;
    default:
        return NSColorSpaceModelUnknown;
    }
}

// An indexed space reports the components of its base space, as CGColorSpaceGetNumberOfComponents does.
- (NSInteger) numberOfColorComponents {
    return (NSInteger) CGColorSpaceGetNumberOfComponents(_cgColorSpace);
}

- (nullable instancetype) initWithICCProfileData: (NSData *) iccData {
    CGColorSpaceRef space = iccData != nil ? CGColorSpaceCreateWithICCProfile((CFDataRef) iccData) : NULL;
    if (space == NULL) {
        [self release];
        return nil;
    }
    self = [self initWithCGColorSpace: space];
    CGColorSpaceRelease(space);
    return self;
}

- (NSData *) ICCProfileData {
    return [(NSData *) CGColorSpaceCopyICCData(_cgColorSpace) autorelease];
}

// Equality and hash are those of the CoreGraphics space, so the same space reached through NSColorSpace or through
// a bitmap's CGImage compares equal.
- (BOOL) isEqual: (id) other {
    if (other == self)
        return YES;
    if (![other isKindOfClass: [NSColorSpace class]])
        return NO;
    CGColorSpaceRef otherSpace = [(NSColorSpace *) other CGColorSpace];
    if (otherSpace == _cgColorSpace)
        return YES;
    return otherSpace != NULL && _cgColorSpace != NULL && CFEqual(_cgColorSpace, otherSpace);
}

- (NSUInteger) hash {
    return _cgColorSpace != NULL ? (NSUInteger) CFHash(_cgColorSpace) : 0;
}

// The name macOS shows for the space (its profile description). Only the named spaces of this class
// are told apart; any other space gets the name of its model.
- (NSString *) localizedName {
    struct {
        CFStringRef creator;
        NSString *name;
    } named[] = {
        { kCGColorSpaceSRGB, @"sRGB IEC61966-2.1" },
        { kCGColorSpaceDisplayP3, @"Display P3" },
        { kCGColorSpaceGenericRGB, @"Generic RGB Profile" },
        { kCGColorSpaceGenericGray, @"Generic Gray Profile" },
        { kCGColorSpaceGenericGrayGamma2_2, @"Generic Gray Gamma 2.2 Profile" },
    };
    for (size_t i = 0; i < sizeof(named) / sizeof(named[0]); i++) {
        CGColorSpaceRef space = CGColorSpaceCreateWithName(named[i].creator);
        BOOL same = space != NULL && CFEqual(space, _cgColorSpace);
        CGColorSpaceRelease(space);
        if (same)
            return named[i].name;
    }
    switch (CGColorSpaceGetModel(_cgColorSpace)) {
    case kCGColorSpaceModelMonochrome:
        return @"Gray";
    case kCGColorSpaceModelRGB:
        return @"RGB";
    case kCGColorSpaceModelCMYK:
        return @"CMYK";
    default:
        return @"Color Space";
    }
}

@end

NSString* _NSColorSpaceNameFromNum(void) {
    NSUnimplementedFunction();
    return nil;
};
