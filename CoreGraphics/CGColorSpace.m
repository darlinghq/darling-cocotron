/* Copyright (c) 2007 Christopher J. W. Lloyd

   Permission is hereby granted, free of charge, to any person obtaining a copy
   of this software and associated documentation files (the "Software"), to
   deal in the Software without restriction, including without limitation the
   rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
   sell copies of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:

   The above copyright notice and this permission notice shall be included in
   all copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
   IN THE SOFTWARE. */

#import <CoreGraphics/CGColorSpace.h>
#import <Onyx2D/O2ColorSpace.h>

const CFStringRef kCGColorSpaceDisplayP3 = CFSTR("kCGColorSpaceDisplayP3");
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

CGColorSpaceRef CGColorSpaceRetain(CGColorSpaceRef colorSpace) {
    return O2ColorSpaceRetain(colorSpace);
}

void CGColorSpaceRelease(CGColorSpaceRef colorSpace) {
    O2ColorSpaceRelease(colorSpace);
}

CGColorSpaceRef CGColorSpaceCreateDeviceRGB() {
    return O2ColorSpaceCreateDeviceRGB();
}

CGColorSpaceRef CGColorSpaceCreateDeviceGray() {
    return O2ColorSpaceCreateDeviceGray();
}

CGColorSpaceRef CGColorSpaceCreateDeviceCMYK() {
    return O2ColorSpaceCreateDeviceCMYK();
}

CGColorSpaceRef CGColorSpaceCreatePattern(CGColorSpaceRef baseSpace) {
    return O2ColorSpaceCreatePattern(baseSpace);
}

CGColorSpaceModel CGColorSpaceGetModel(CGColorSpaceRef self) {
    return O2ColorSpaceGetModel(self);
}

size_t CGColorSpaceGetNumberOfComponents(CGColorSpaceRef self) {
    return O2ColorSpaceGetNumberOfComponents(self);
}

CGColorSpaceRef CGColorSpaceCreateWithName(CFStringRef name) {
    return (CGColorSpaceRef) O2ColorSpaceCreateWithName(name);
}
