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
    // Onyx2D color spaces are not built from ICC profiles and carry none;
    // a color space without a profile reports NULL.
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
    const CFStringRef *extended;
    const CFStringRef *extendedLinear;
} CGColorSpaceRangeForms;

static const CGColorSpaceRangeForms rangeForms[] = {
    {&kCGColorSpaceSRGB, &kCGColorSpaceExtendedSRGB, &kCGColorSpaceExtendedLinearSRGB},
    {&kCGColorSpaceExtendedSRGB, &kCGColorSpaceExtendedSRGB, &kCGColorSpaceExtendedLinearSRGB},
    {&kCGColorSpaceLinearSRGB, &kCGColorSpaceExtendedLinearSRGB, &kCGColorSpaceExtendedLinearSRGB},
    {&kCGColorSpaceExtendedLinearSRGB, &kCGColorSpaceExtendedLinearSRGB, &kCGColorSpaceExtendedLinearSRGB},
    {&kCGColorSpaceDisplayP3, &kCGColorSpaceExtendedDisplayP3, &kCGColorSpaceExtendedLinearDisplayP3},
    {&kCGColorSpaceExtendedDisplayP3, &kCGColorSpaceExtendedDisplayP3, &kCGColorSpaceExtendedLinearDisplayP3},
    {&kCGColorSpaceLinearDisplayP3, &kCGColorSpaceExtendedLinearDisplayP3, &kCGColorSpaceExtendedLinearDisplayP3},
    {&kCGColorSpaceExtendedLinearDisplayP3, &kCGColorSpaceExtendedLinearDisplayP3, &kCGColorSpaceExtendedLinearDisplayP3},
    {&kCGColorSpaceExtendedLinearITUR_2020, &kCGColorSpaceExtendedLinearITUR_2020, &kCGColorSpaceExtendedLinearITUR_2020},
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
