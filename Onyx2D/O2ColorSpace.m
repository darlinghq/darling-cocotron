/* Copyright (c) 2007 Christopher J. W. Lloyd

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

#import <CoreFoundation/CFBase.h>
#import <Foundation/NSString.h>
#import <Onyx2D/O2ColorSpace.h>
#import <Onyx2D/O2ColorICC.h>
#include <string.h>

const CFStringRef kO2ColorSpaceDisplayP3 = CFSTR("kCGColorSpaceDisplayP3");
const CFStringRef kO2ColorSpaceGenericGray = CFSTR("kCGColorSpaceGenericGray");
const CFStringRef kO2ColorSpaceGenericRGB = CFSTR("kCGColorSpaceGenericRGB");
const CFStringRef kO2ColorSpaceGenericCMYK = CFSTR("kCGColorSpaceGenericCMYK");
const CFStringRef kO2ColorSpaceGenericRGBLinear =
        CFSTR("kCGColorSpaceGenericRGBLinear");
const CFStringRef kO2ColorSpaceAdobeRGB1998 =
        CFSTR("kCGColorSpaceAdobeRGB1998");
const CFStringRef kO2ColorSpaceSRGB = CFSTR("kCGColorSpaceSRGB");
const CFStringRef kO2ColorSpaceGenericGrayGamma2_2 =
        CFSTR("kCGColorSpaceGenericGrayGamma2_2");
const CFStringRef kO2ColorSpaceGenericXYZ = CFSTR("kCGColorSpaceGenericXYZ");
const CFStringRef kO2ColorSpaceGenericLab = CFSTR("kCGColorSpaceGenericLab");
const CFStringRef kO2ColorSpaceACESCGLinear =
        CFSTR("kCGColorSpaceACESCGLinear");
const CFStringRef kO2ColorSpaceITUR_709 = CFSTR("kCGColorSpaceITUR_709");
const CFStringRef kO2ColorSpaceITUR_2020 = CFSTR("kCGColorSpaceITUR_2020");
const CFStringRef kO2ColorSpaceROMMRGB = CFSTR("kCGColorSpaceROMMRGB");
const CFStringRef kO2ColorSpaceDCIP3 = CFSTR("kCGColorSpaceDCIP3");
const CFStringRef kO2ColorSpaceExtendedSRGB =
        CFSTR("kCGColorSpaceExtendedSRGB");
const CFStringRef kO2ColorSpaceLinearSRGB = CFSTR("kCGColorSpaceLinearSRGB");
const CFStringRef kO2ColorSpaceExtendedLinearSRGB =
        CFSTR("kCGColorSpaceExtendedLinearSRGB");
const CFStringRef kO2ColorSpaceExtendedGray =
        CFSTR("kCGColorSpaceExtendedGray");
const CFStringRef kO2ColorSpaceLinearGray = CFSTR("kCGColorSpaceLinearGray");
const CFStringRef kO2ColorSpaceExtendedLinearGray =
        CFSTR("kCGColorSpaceExtendedLinearGray");

@implementation O2ColorSpace

- initWithDeviceGray {
    _type = kO2ColorSpaceModelMonochrome;
    _isPlatformRGB = NO;
    return self;
}

- initWithDeviceRGB {
    _type = kO2ColorSpaceModelRGB;
    _isPlatformRGB = NO;
    return self;
}

- initWithDeviceCMYK {
    _type = kO2ColorSpaceModelCMYK;
    _isPlatformRGB = NO;
    return self;
}

- initWithPlatformRGB {
    _type = kO2ColorSpaceModelRGB;
    _isPlatformRGB = NO;
    return self;
}

- initWithPattern {
    _type = kO2ColorSpaceModelPattern;
    _isPlatformRGB = NO;
    return self;
}

- (void)dealloc {
    if (_name != NULL)
        CFRelease(_name);
    [_patternBase release];
    [super dealloc];
}

- copyWithZone: (NSZone *) zone {
    return [self retain];
}

- (O2ColorSpaceModel) type {
    return _type;
}

O2ColorSpaceRef O2ColorSpaceRetain(O2ColorSpaceRef self) {
    return (self != NULL) ? (O2ColorSpaceRef) CFRetain(self) : NULL;
}

void O2ColorSpaceRelease(O2ColorSpaceRef self) {
    if (self != NULL)
        CFRelease(self);
}

O2ColorSpaceRef O2ColorSpaceCreateDeviceGray(void) {
    return [[O2ColorSpace alloc] initWithDeviceGray];
}

O2ColorSpaceRef O2ColorSpaceCreateDeviceRGB(void) {
    O2ColorSpaceRef self = [O2ColorSpace allocWithZone: NULL];
    self->_type = kO2ColorSpaceModelRGB;
    self->_isPlatformRGB = NO;
    return self;
}

O2ColorSpaceRef O2ColorSpaceCreateDeviceCMYK(void) {
    return [[O2ColorSpace alloc] initWithDeviceCMYK];
}

O2ColorSpaceRef O2ColorSpaceCreatePlatformRGB(void) {
    return [[O2ColorSpace alloc] initWithPlatformRGB];
}

O2ColorSpaceRef O2ColorSpaceCreatePattern(O2ColorSpaceRef baseSpace) {
    O2ColorSpace *space = [[O2ColorSpace alloc] initWithPattern];
    space->_patternBase = [baseSpace retain];
    return space;
}

O2ColorSpaceRef O2ColorSpaceCreateIndexed(O2ColorSpaceRef baseSpace, size_t lastIndex, const unsigned char *colorTable) {
    if (baseSpace == NULL || colorTable == NULL)
        return NULL;
    return [[O2ColorSpace_indexed alloc] initWithColorSpace: baseSpace
                                                      hival: lastIndex
                                                      bytes: colorTable];
}

O2ColorSpaceRef O2ColorSpaceCreateDeviceN(const char **names,
                                          O2ColorSpaceRef alternateSpace,
                                          O2FunctionRef tintTransform)
{
    return [[O2ColorSpace_DeviceN alloc] initWithComponentNames: names
                                                 alternateSpace: alternateSpace
                                                  tintTransform: tintTransform];
}

O2ColorSpaceRef O2ColorSpaceCreateWithName(CFStringRef name) {
    if (name == NULL)
        return NULL;

    // Named spaces carry their name; the ones with a colorimetric profile
    // (O2ColorConversion.h) convert properly, the rest are still represented as
    // device RGB with the name kept for callers.
    const CFStringRef rgbNames[] = {
        kO2ColorSpaceSRGB,
        kO2ColorSpaceExtendedSRGB,
        kO2ColorSpaceLinearSRGB,
        kO2ColorSpaceExtendedLinearSRGB,
        kO2ColorSpaceDisplayP3,
        kO2ColorSpaceITUR_2020,
        CFSTR("kCGColorSpaceExtendedDisplayP3"),
        CFSTR("kCGColorSpaceLinearDisplayP3"),
        CFSTR("kCGColorSpaceExtendedLinearDisplayP3"),
        CFSTR("kCGColorSpaceITUR_2100_PQ"),
        CFSTR("kCGColorSpaceITUR_2100_HLG"),
        CFSTR("kCGColorSpaceExtendedLinearITUR_2020"),
        kO2ColorSpaceGenericRGB,
        kO2ColorSpaceGenericRGBLinear,
        kO2ColorSpaceAdobeRGB1998,
        kO2ColorSpaceITUR_709,
        kO2ColorSpaceITUR_2020,
    };
    for (size_t i = 0; i < sizeof(rgbNames) / sizeof(rgbNames[0]); i++) {
        if (CFEqual(name, rgbNames[i])) {
            O2ColorSpaceRef cs = [[O2ColorSpace alloc] initWithDeviceRGB];
            CFRetain(name);
            cs->_name = name;
            return cs;
        }
    }

    const CFStringRef grayNames[] = {
        kO2ColorSpaceGenericGray,
        kO2ColorSpaceGenericGrayGamma2_2,
        kO2ColorSpaceExtendedGray,
        kO2ColorSpaceLinearGray,
        kO2ColorSpaceExtendedLinearGray,
    };
    for (size_t i = 0; i < sizeof(grayNames) / sizeof(grayNames[0]); i++) {
        if (CFEqual(name, grayNames[i])) {
            O2ColorSpaceRef cs = [[O2ColorSpace alloc] initWithDeviceGray];
            CFRetain(name);
            cs->_name = name;
            return cs;
        }
    }
    return NULL;
}

CFStringRef O2ColorSpaceGetName(O2ColorSpaceRef colorSpace) {
    return colorSpace ? colorSpace->_name : NULL;
}

BOOL O2ColorSpaceGetColorProfile(O2ColorSpaceRef self, O2ColorProfile *profile) {
    if (self == NULL || self->_name == NULL)
        return NO;
    char name[64];
    if (!CFStringGetCString(self->_name, name, sizeof(name),
                            kCFStringEncodingASCII))
        return NO;
    if (!O2ColorProfileForName(name, profile))
        return NO;
    // The profile and the model must agree (a gray profile for a gray space).
    return profile->isGray == (self->_type == kO2ColorSpaceModelMonochrome);
}

// Profile description for the names O2ColorProfileForName understands, with
// the optional "Extended" prefix already removed.
static const char *profileDescription(const char *suffix) {
    static const struct {
        const char *suffix;
        const char *description;
    } names[] = {
        {"SRGB", "sRGB IEC61966-2.1"},
        {"LinearSRGB", "sRGB IEC61966-2.1 Linear"},
        {"DisplayP3", "Display P3"},
        {"LinearDisplayP3", "Display P3 Linear"},
        {"GenericRGB", "Generic RGB"},
        {"GenericRGBLinear", "Generic RGB Linear"},
        {"AdobeRGB1998", "Adobe RGB (1998)"},
        {"ITUR_709", "Rec. ITU-R BT.709"},
        {"ITUR_2020", "Rec. ITU-R BT.2020"},
        {"LinearITUR_2020", "Rec. ITU-R BT.2020 Linear"},
        {"GenericGray", "Generic Gray"},
        {"GenericGrayGamma2_2", "Generic Gray Gamma 2.2"},
        {"Gray", "Gray"},
        {"LinearGray", "Linear Gray"},
    };
    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++)
        if (strcmp(names[i].suffix, suffix) == 0)
            return names[i].description;
    return NULL;
}

CFDataRef O2ColorSpaceCopyICCData(O2ColorSpaceRef self) {
    O2ColorProfile profile;
    char name[64];

    if (self == NULL || self->_name == NULL ||
        !O2ColorSpaceGetColorProfile(self, &profile) ||
        !CFStringGetCString(self->_name, name, sizeof(name), kCFStringEncodingASCII))
        return NULL;

    const char *suffix = name + strlen("kCGColorSpace");
    if (strncmp(suffix, "Extended", 8) == 0)
        suffix += 8;
    const char *description = profileDescription(suffix);
    return description ? O2ColorProfileCopyICCData(&profile, description) : NULL;
}

BOOL O2ColorSpaceIsPlatformRGB(O2ColorSpaceRef self) {
    return self->_isPlatformRGB;
}

size_t O2ColorSpaceGetNumberOfComponents(O2ColorSpaceRef self) {
    switch (self->_type) {

    case kO2ColorSpaceModelMonochrome:
        return 1;

    case kO2ColorSpaceModelRGB:
        return 3;

    case kO2ColorSpaceModelCMYK:
        return 4;

    case kO2ColorSpaceModelIndexed:
        return 1;

    case kO2ColorSpaceModelDeviceN:
        return ((O2ColorSpace_DeviceN *) self)->_numberOfComponents;

    default:
        return 0;
    }
}

O2ColorSpaceRef O2ColorSpaceGetBaseColorSpace(O2ColorSpaceRef self) {
    if ([self isKindOfClass: [O2ColorSpace_indexed class]])
        return [(O2ColorSpace_indexed *) self baseColorSpace];
    if (self != nil && self->_type == kO2ColorSpaceModelPattern)
        return self->_patternBase;
    return NULL;
}

size_t O2ColorSpaceGetColorTableCount(O2ColorSpaceRef self) {
    if ([self isKindOfClass: [O2ColorSpace_indexed class]])
        return [(O2ColorSpace_indexed *) self hival] + 1;
    return 0;
}

void O2ColorSpaceGetColorTable(O2ColorSpaceRef self, unsigned char *table) {
    if (table == NULL || ![self isKindOfClass: [O2ColorSpace_indexed class]])
        return;
    O2ColorSpace_indexed *indexed = (O2ColorSpace_indexed *) self;
    memcpy(table, [indexed paletteBytes],
           O2ColorSpaceGetNumberOfComponents([indexed baseColorSpace]) * ([indexed hival] + 1));
}

O2ColorSpaceModel O2ColorSpaceGetModel(O2ColorSpaceRef self) {
    return self->_type;
}

- (BOOL) isEqualToColorSpace: (O2ColorSpaceRef) other {
    if (self->_type != other->_type)
        return NO;
    return YES;
}

- (NSString *) description {
    return [NSString
            stringWithFormat: @"<%@: %p, type=%d>", [self class], self, _type];
}

@end

@implementation O2ColorSpace_indexed

- initWithColorSpace: (O2ColorSpaceRef) baseColorSpace
               hival: (size_t) hival
               bytes: (const unsigned char *) bytes
{
    size_t i, max = O2ColorSpaceGetNumberOfComponents(baseColorSpace) *
                    (hival + 1);

    _type = kO2ColorSpaceModelIndexed;
    _base = [baseColorSpace retain];
    _hival = hival;
    _bytes = NSZoneMalloc(NSDefaultMallocZone(), max);
    for (i = 0; i < max; i++)
        _bytes[i] = bytes[i];
    return self;
}

- (void) dealloc {
    [_base release];
    NSZoneFree(NSDefaultMallocZone(), _bytes);
    [super dealloc];
}

- (BOOL) isEqualToColorSpace: (O2ColorSpaceRef) otherX {
    O2ColorSpace_indexed *other = (O2ColorSpace_indexed *) other;
    if (self->_type != other->_type)
        return NO;

    if (![self->_base isEqualToColorSpace: other->_base])
        return NO;
    if (self->_hival != other->_hival)
        return NO;

    size_t i, max = O2ColorSpaceGetNumberOfComponents(self->_base) *
                    (self->_hival + 1);
    for (i = 0; i < max; i++)
        if (self->_bytes[i] != other->_bytes[i])
            return NO;

    return YES;
}

- (O2ColorSpaceRef) baseColorSpace {
    return _base;
}

- (size_t) hival {
    return _hival;
}

- (const unsigned char *) paletteBytes {
    return _bytes;
}

@end

@implementation O2ColorSpace_DeviceN

- initWithComponentNames: (const char **) names
          alternateSpace: (O2ColorSpaceRef) altSpace
           tintTransform: (O2FunctionRef) tintTransform
{
    int i;

    for (i = 0; names[i] != NULL; i++)
        _numberOfComponents++;

    _names = malloc(sizeof(char *) * _numberOfComponents);

    for (i = 0; i < _numberOfComponents; i++) {
        size_t length = strlen(names[i]);
        _names[i] = malloc(length + 1);

        strcpy(_names[i], names[i]);
    }

    _type = kO2ColorSpaceModelDeviceN;
    _alternateSpace = O2ColorSpaceRetain(altSpace);
    _tintTransform = O2FunctionRetain(tintTransform);
    return self;
}

- (void) dealloc {
    size_t i;

    for (i = 0; i < _numberOfComponents; i++)
        free(_names[i]);
    free(_names);

    O2ColorSpaceRelease(_alternateSpace);
    O2FunctionRelease(_tintTransform);
    [super dealloc];
}

- (O2ColorSpaceRef) alternateSpace {
    return _alternateSpace;
}

- (O2FunctionRef) tintTransform {
    return _tintTransform;
}

@end
