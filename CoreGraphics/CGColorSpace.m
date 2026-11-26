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

#import <CoreGraphics/CGColorSpace.h>
#import <Onyx2D/O2ColorSpace.h>
#import <Onyx2D/O2ColorICC.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#import <Onyx2D/O2DataProvider.h>

const CFStringRef kCGColorSpaceDisplayP3 = CFSTR("kCGColorSpaceDisplayP3");
const CFStringRef kCGColorSpaceExtendedDisplayP3 =
        CFSTR("kCGColorSpaceExtendedDisplayP3");
const CFStringRef kCGColorSpaceLinearDisplayP3 =
        CFSTR("kCGColorSpaceLinearDisplayP3");
const CFStringRef kCGColorSpaceExtendedLinearDisplayP3 =
        CFSTR("kCGColorSpaceExtendedLinearDisplayP3");
const CFStringRef kCGColorSpaceGenericGray = CFSTR("kCGColorSpaceGenericGray");
const CFStringRef kCGColorSpaceGenericRGB = CFSTR("kCGColorSpaceGenericRGB");
const CFStringRef kCGColorSpaceGenericCMYK = CFSTR("kCGColorSpaceGenericCMYK");
const CFStringRef kCGColorSpaceGenericRGBLinear =
        CFSTR("kCGColorSpaceGenericRGBLinear");
const CFStringRef kCGColorSpaceAdobeRGB1998 =
        CFSTR("kCGColorSpaceAdobeRGB1998");
const CFStringRef kCGColorSpaceSRGB = CFSTR("kCGColorSpaceSRGB");
const CFStringRef kCGColorSpaceGenericGrayGamma2_2 =
        CFSTR("kCGColorSpaceGenericGrayGamma2_2");
const CFStringRef kCGColorSpaceGenericXYZ = CFSTR("kCGColorSpaceGenericXYZ");
const CFStringRef kCGColorSpaceGenericLab = CFSTR("kCGColorSpaceGenericLab");
const CFStringRef kCGColorSpaceACESCGLinear =
        CFSTR("kCGColorSpaceACESCGLinear");
const CFStringRef kCGColorSpaceITUR_709 = CFSTR("kCGColorSpaceITUR_709");
const CFStringRef kCGColorSpaceITUR_2020 = CFSTR("kCGColorSpaceITUR_2020");
const CFStringRef kCGColorSpaceITUR_2100_PQ = CFSTR("kCGColorSpaceITUR_2100_PQ");
const CFStringRef kCGColorSpaceITUR_2100_HLG = CFSTR("kCGColorSpaceITUR_2100_HLG");
const CFStringRef kCGColorSpaceROMMRGB = CFSTR("kCGColorSpaceROMMRGB");
const CFStringRef kCGColorSpaceDCIP3 = CFSTR("kCGColorSpaceDCIP3");
const CFStringRef kCGColorSpaceExtendedSRGB =
        CFSTR("kCGColorSpaceExtendedSRGB");
const CFStringRef kCGColorSpaceLinearSRGB = CFSTR("kCGColorSpaceLinearSRGB");
const CFStringRef kCGColorSpaceExtendedLinearSRGB =
        CFSTR("kCGColorSpaceExtendedLinearSRGB");
const CFStringRef kCGColorSpaceExtendedGray =
        CFSTR("kCGColorSpaceExtendedGray");
const CFStringRef kCGColorSpaceLinearGray = CFSTR("kCGColorSpaceLinearGray");
const CFStringRef kCGColorSpaceExtendedLinearGray =
        CFSTR("kCGColorSpaceExtendedLinearGray");
const CFStringRef kCGColorSpaceExtendedLinearITUR_2020 =
        CFSTR("kCGColorSpaceExtendedLinearITUR_2020");
const CFStringRef kCGColorSpaceExtendedITUR_2020 =
        CFSTR("kCGColorSpaceExtendedITUR_2020");
const CFStringRef kCGColorSpaceLinearITUR_2020 =
        CFSTR("kCGColorSpaceLinearITUR_2020");

// The key, in the options of color-space creation, that asks for an extended-range space.
const CFStringRef kCGColorSpaceExtendedRange = CFSTR("kCGColorSpaceExtendedRange");

// CGColorSpaceRef is an O2ColorSpace; give it CGColorSpace's type ID for
// CFGetTypeID.
@implementation O2ColorSpace (CGColorSpaceTypeID)

- (CFTypeID) _cfTypeID {
    return CGColorSpaceGetTypeID();
}

@end

CFTypeID CGColorSpaceGetTypeID(void) {
    return (CFTypeID) [O2ColorSpace self];
}

CGColorSpaceRef CGColorSpaceRetain(CGColorSpaceRef colorSpace) {
    return (CGColorSpaceRef)O2ColorSpaceRetain((O2ColorSpaceRef)colorSpace);
}

void CGColorSpaceRelease(CGColorSpaceRef colorSpace) {
    O2ColorSpaceRelease((O2ColorSpaceRef)colorSpace);
}

CGColorSpaceRef CGColorSpaceCreateDeviceRGB() {
    return (CGColorSpaceRef)O2ColorSpaceCreateDeviceRGB();
}

CGColorSpaceRef CGColorSpaceCreateDeviceGray() {
    return (CGColorSpaceRef)O2ColorSpaceCreateDeviceGray();
}

CGColorSpaceRef CGColorSpaceCreateDeviceCMYK() {
    return (CGColorSpaceRef)O2ColorSpaceCreateDeviceCMYK();
}

CGColorSpaceRef CGColorSpaceCreatePattern(CGColorSpaceRef baseSpace) {
    return (CGColorSpaceRef)O2ColorSpaceCreatePattern((O2ColorSpaceRef)baseSpace);
}

CGColorSpaceRef CGColorSpaceCreateIndexed(CGColorSpaceRef baseSpace, size_t lastIndex, const unsigned char *colorTable) {
    return (CGColorSpaceRef)O2ColorSpaceCreateIndexed((O2ColorSpaceRef)baseSpace, lastIndex, colorTable);
}

CGColorSpaceRef CGColorSpaceGetBaseColorSpace(CGColorSpaceRef self) {
    return (CGColorSpaceRef)O2ColorSpaceGetBaseColorSpace((O2ColorSpaceRef)self);
}

size_t CGColorSpaceGetColorTableCount(CGColorSpaceRef self) {
    return O2ColorSpaceGetColorTableCount((O2ColorSpaceRef)self);
}

void CGColorSpaceGetColorTable(CGColorSpaceRef self, uint8_t *table) {
    O2ColorSpaceGetColorTable((O2ColorSpaceRef)self, table);
}

CGColorSpaceModel CGColorSpaceGetModel(CGColorSpaceRef self) {
    return (CGColorSpaceModel)O2ColorSpaceGetModel((O2ColorSpaceRef)self);
}

size_t CGColorSpaceGetNumberOfComponents(CGColorSpaceRef self) {
    return O2ColorSpaceGetNumberOfComponents((O2ColorSpaceRef)self);
}

CGColorSpaceRef CGColorSpaceCreateWithName(CFStringRef name) {
    return (CGColorSpaceRef) O2ColorSpaceCreateWithName(name);
}

CFStringRef CGColorSpaceGetName(CGColorSpaceRef colorSpace) {
    return O2ColorSpaceGetName((O2ColorSpaceRef)colorSpace);
}

CFStringRef CGColorSpaceCopyName(CGColorSpaceRef colorSpace) {
    CFStringRef name = CGColorSpaceGetName(colorSpace);
    if (name != NULL)
        CFRetain(name);
    return name;
}

CFDataRef CGColorSpaceCopyICCData(CGColorSpaceRef colorSpace) {
    // Only the named spaces with a colorimetric profile have ICC data
    // (synthesized from that profile); device and other spaces report NULL.
    return O2ColorSpaceCopyICCData((O2ColorSpaceRef)colorSpace);
}

// A property list that CGColorSpaceCreateWithPropertyList makes the space again
// from. Apple does not document what the list holds, so this is Darling's own:
// the name of a named space, or else the ICC data; a space that has neither has
// no property list. A list written on macOS may not be read back here.
CFPropertyListRef CGColorSpaceCopyPropertyList(CGColorSpaceRef space) {
    if (space == NULL)
        return NULL;
    CFStringRef name = CGColorSpaceCopyName(space);
    if (name != NULL)
        return name;
    return CGColorSpaceCopyICCData(space);
}

CGColorSpaceRef CGColorSpaceCreateWithPropertyList(CFPropertyListRef plist) {
    if (plist == NULL)
        return NULL;
    if (CFGetTypeID(plist) == CFStringGetTypeID())
        return CGColorSpaceCreateWithName((CFStringRef) plist);
    if (CFGetTypeID(plist) == CFDataGetTypeID())
        return CGColorSpaceCreateWithICCData(plist);
    return NULL;
}

CFDataRef CGColorSpaceCopyICCProfile(CGColorSpaceRef colorSpace) {
    return CGColorSpaceCopyICCData(colorSpace);
}

// The platform colour space of macOS is a ColorSync profile: the legacy profile reference of ColorSync
// (CMProfileRef) is one. The profile is turned into a colour space through its ICC data.
extern CFTypeID ColorSyncProfileGetTypeID(void);
extern CFDataRef ColorSyncProfileCopyData(CFTypeRef profile, CFErrorRef *error);

CGColorSpaceRef CGColorSpaceCreateWithPlatformColorSpace(const void *ref) {
    if (ref == NULL || CFGetTypeID(ref) != ColorSyncProfileGetTypeID())
        return NULL;

    CFDataRef data = ColorSyncProfileCopyData((CFTypeRef) ref, NULL);
    CGColorSpaceRef space = data != NULL ? CGColorSpaceCreateWithICCProfile(data) : NULL;

    if (data != NULL)
        CFRelease(data);
    return space;
}

CGColorSpaceRef CGColorSpaceCreateWithICCProfile(CFDataRef data) {
    return (CGColorSpaceRef) O2ColorSpaceCreateWithICCData(data);
}

// QUIRK: the documentation types the parameter CFTypeRef without saying which
// types it takes. Black-box observation of macOS 26.7.3 (tier 2): a CFData
// holding an ICC profile and a CGDataProvider over the same data both give a
// colour space; NULL, an object of another type (a CFString) and data that is no
// profile give NULL.
// Test: the provider case of tests/coregraphics-colorspace-create-with-icc-data.c
CGColorSpaceRef CGColorSpaceCreateWithICCData(CFTypeRef data) {
    if (data == NULL)
        return NULL;
    if (CFGetTypeID(data) == CFDataGetTypeID())
        return CGColorSpaceCreateWithICCProfile((CFDataRef) data);
    if ([(id) data isKindOfClass: [O2DataProvider class]]) {
        CFDataRef copied = CGDataProviderCopyData((CGDataProviderRef) data);
        CGColorSpaceRef space = copied != NULL ? CGColorSpaceCreateWithICCProfile(copied) : NULL;

        if (copied != NULL)
            CFRelease(copied);
        return space;
    }
    return NULL;
}

CGColorSpaceRef CGColorSpaceCreateICCBased(size_t nComponents, const CGFloat *range,
                                           CGDataProviderRef profile,
                                           CGColorSpaceRef alternate)
{
    // ICC profiles are not interpreted, so the profile is treated as an
    // unsupported one: the alternate space is used, or the device space with
    // the same number of components when there is no usable alternate.
    if (profile == NULL)
        return NULL;
    if (nComponents != 1 && nComponents != 3 && nComponents != 4)
        return NULL;

    if (alternate != NULL &&
        CGColorSpaceGetNumberOfComponents(alternate) == nComponents)
        return CGColorSpaceRetain(alternate);

    switch (nComponents) {
    case 1:
        return CGColorSpaceCreateDeviceGray();
    case 3:
        return CGColorSpaceCreateDeviceRGB();
    default:
        return CGColorSpaceCreateDeviceCMYK();
    }
}

typedef struct {
    const CFStringRef *name;
    const CFStringRef *standard;
    const CFStringRef *extended;
    const CFStringRef *extendedLinear;
} CGColorSpaceRangeForms;

// each named space with the forms of it that use the standard range, the
// extended range, and the extended range with a linear transfer function
static const CGColorSpaceRangeForms rangeForms[] = {
    {&kCGColorSpaceSRGB, &kCGColorSpaceSRGB, &kCGColorSpaceExtendedSRGB, &kCGColorSpaceExtendedLinearSRGB},
    {&kCGColorSpaceExtendedSRGB, &kCGColorSpaceSRGB, &kCGColorSpaceExtendedSRGB, &kCGColorSpaceExtendedLinearSRGB},
    {&kCGColorSpaceLinearSRGB, &kCGColorSpaceLinearSRGB, &kCGColorSpaceExtendedLinearSRGB, &kCGColorSpaceExtendedLinearSRGB},
    {&kCGColorSpaceExtendedLinearSRGB, &kCGColorSpaceLinearSRGB, &kCGColorSpaceExtendedLinearSRGB, &kCGColorSpaceExtendedLinearSRGB},
    {&kCGColorSpaceDisplayP3, &kCGColorSpaceDisplayP3, &kCGColorSpaceExtendedDisplayP3, &kCGColorSpaceExtendedLinearDisplayP3},
    {&kCGColorSpaceExtendedDisplayP3, &kCGColorSpaceDisplayP3, &kCGColorSpaceExtendedDisplayP3, &kCGColorSpaceExtendedLinearDisplayP3},
    {&kCGColorSpaceLinearDisplayP3, &kCGColorSpaceLinearDisplayP3, &kCGColorSpaceExtendedLinearDisplayP3, &kCGColorSpaceExtendedLinearDisplayP3},
    {&kCGColorSpaceExtendedLinearDisplayP3, &kCGColorSpaceLinearDisplayP3, &kCGColorSpaceExtendedLinearDisplayP3, &kCGColorSpaceExtendedLinearDisplayP3},
    {&kCGColorSpaceITUR_2020, &kCGColorSpaceITUR_2020, &kCGColorSpaceExtendedITUR_2020, &kCGColorSpaceExtendedLinearITUR_2020},
    {&kCGColorSpaceExtendedITUR_2020, &kCGColorSpaceITUR_2020, &kCGColorSpaceExtendedITUR_2020, &kCGColorSpaceExtendedLinearITUR_2020},
    {&kCGColorSpaceLinearITUR_2020, &kCGColorSpaceLinearITUR_2020, &kCGColorSpaceExtendedLinearITUR_2020, &kCGColorSpaceExtendedLinearITUR_2020},
    {&kCGColorSpaceExtendedLinearITUR_2020, &kCGColorSpaceLinearITUR_2020, &kCGColorSpaceExtendedLinearITUR_2020, &kCGColorSpaceExtendedLinearITUR_2020},
};

static const CGColorSpaceRangeForms *rangeFormsForSpace(CGColorSpaceRef space) {
    CFStringRef name = CGColorSpaceGetName(space);
    if (name == NULL)
        return NULL;
    for (size_t i = 0; i < sizeof(rangeForms) / sizeof(rangeForms[0]); i++) {
        if (CFEqual(name, *rangeForms[i].name))
            return &rangeForms[i];
    }
    return NULL;
}

CGColorSpaceRef CGColorSpaceCreateExtended(CGColorSpaceRef space) {
    const CGColorSpaceRangeForms *forms = rangeFormsForSpace(space);
    return forms ? CGColorSpaceCreateWithName(*forms->extended) : NULL;
}

CGColorSpaceRef CGColorSpaceCreateExtendedLinearized(CGColorSpaceRef space) {
    const CGColorSpaceRangeForms *forms = rangeFormsForSpace(space);
    return forms ? CGColorSpaceCreateWithName(*forms->extendedLinear) : NULL;
}

// a space that already uses the standard range, or that has no other form,
// is returned as it is
CGColorSpaceRef CGColorSpaceCreateCopyWithStandardRange(CGColorSpaceRef space) {
    if (space == NULL)
        return NULL;
    const CGColorSpaceRangeForms *forms = rangeFormsForSpace(space);
    if (forms == NULL || forms->name == forms->standard)
        return CGColorSpaceRetain(space);
    return CGColorSpaceCreateWithName(*forms->standard);
}

bool CGColorSpaceUsesExtendedRange(CGColorSpaceRef space) {
    const CGColorSpaceRangeForms *forms = rangeFormsForSpace(space);
    return forms != NULL && forms->name == forms->extended;
}

bool CGColorSpaceUsesITUR_2100TF(CGColorSpaceRef space) {
    CFStringRef name = space != NULL ? CGColorSpaceGetName(space) : NULL;
    if (name == NULL)
        return false;
    return CFEqual(name, kCGColorSpaceITUR_2100_PQ) ||
           CFEqual(name, kCGColorSpaceITUR_2100_HLG);
}

bool CGColorSpaceIsHLGBased(CGColorSpaceRef space) {
    CFStringRef name = space != NULL ? CGColorSpaceGetName(space) : NULL;
    return name != NULL && CFEqual(name, kCGColorSpaceITUR_2100_HLG);
}

// QUIRK: which spaces count as HDR is not documented. Observed on macOS 26.7.3
// (tier 2, one query per named space): true for kCGColorSpaceITUR_2100_PQ,
// kCGColorSpaceITUR_2100_HLG and kCGColorSpaceDisplayP3_PQ, false for sRGB,
// linear and extended sRGB, Display P3, ITU-R 709 and 2020, DCI-P3, ROMM, ACEScg,
// the generic gray, RGB, CMYK, Lab and XYZ spaces and a device RGB space. That is
// the BT.2100 transfer function test. A NULL space is not observed and gives false.
// Test: tests/coregraphics-colorspace-hdr-output.c
bool CGColorSpaceIsHDR(CGColorSpaceRef space) {
    return space != NULL && CGColorSpaceUsesITUR_2100TF(space);
}

// QUIRK: observed on macOS 26.7.3 (tier 2): true for every RGB, gray, CMYK, Lab
// and XYZ space queried, false for an indexed space (and a pattern space, which
// cannot be created here). A NULL space is not observed and gives false.
// Test: tests/coregraphics-colorspace-hdr-output.c
bool CGColorSpaceSupportsOutput(CGColorSpaceRef space) {
    if (space == NULL)
        return false;
    CGColorSpaceModel model = CGColorSpaceGetModel(space);
    return model != kCGColorSpaceModelIndexed && model != kCGColorSpaceModelPattern;
}

bool CGColorSpaceEqualToColorSpace(CGColorSpaceRef space1, CGColorSpaceRef space2) {
    if (space1 == space2)
        return true;
    if (space1 == NULL || space2 == NULL)
        return false;
    if (CFEqual(space1, space2))
        return true;
    if (CGColorSpaceGetModel(space1) != CGColorSpaceGetModel(space2))
        return false;

    // Spaces made in different ways (by name, from ICC data) are the same
    // space when their profiles are the same.
    CFDataRef data1 = CGColorSpaceCopyICCData(space1);
    CFDataRef data2 = data1 != NULL ? CGColorSpaceCopyICCData(space2) : NULL;
    bool equal = data1 != NULL && data2 != NULL && CFEqual(data1, data2);
    if (data1 != NULL)
        CFRelease(data1);
    if (data2 != NULL)
        CFRelease(data2);
    return equal;
}

CFStringRef CGColorSpaceCopyICCProfileDescription(CGColorSpaceRef space) {
    if (space == NULL)
        return NULL;
    CFDataRef data = CGColorSpaceCopyICCData(space);
    if (data == NULL)
        return NULL;
    CFStringRef description = O2ICCProfileCopyDescription(data);
    CFRelease(data);
    return description;
}

