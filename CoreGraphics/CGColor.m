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

#import <CoreGraphics/CGColor.h>
#import <Onyx2D/O2Color.h>
#import <Onyx2D/O2ColorSpace.h>

// CGColorRef is an O2Color; give it CGColor's type ID for CFGetTypeID.
@implementation O2Color (CGColorTypeID)

- (CFTypeID) _cfTypeID {
    return CGColorGetTypeID();
}

@end

CFTypeID CGColorGetTypeID(void) {
    return (CFTypeID) [O2Color self];
}

CGColorRef CGColorRetain(CGColorRef self) {
    return (CGColorRef)O2ColorRetain((O2ColorRef)self);
}

void CGColorRelease(CGColorRef self) {
    O2ColorRelease((O2ColorRef)self);
}

CGColorRef CGColorCreate(CGColorSpaceRef colorSpace, const CGFloat *components)
{
    return (CGColorRef)O2ColorCreate((O2ColorSpaceRef)colorSpace, components);
}

CGColorRef CGColorCreateGenericGray(CGFloat gray, CGFloat a) {
    return (CGColorRef)O2ColorCreateGenericGray(gray, a);
}

CGColorRef CGColorCreateGenericRGB(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    return (CGColorRef)O2ColorCreateGenericRGB(r, g, b, a);
}

CGColorRef CGColorCreateGenericCMYK(CGFloat c, CGFloat m, CGFloat y, CGFloat k,
                                    CGFloat a)
{
    return (CGColorRef)O2ColorCreateGenericCMYK(c, m, y, k, a);
}

CGColorRef CGColorCreateWithPattern(CGColorSpaceRef colorSpace,
                                    CGPatternRef pattern,
                                    const CGFloat *components)
{
    return (CGColorRef)O2ColorCreateWithPattern((O2ColorSpaceRef)colorSpace, (O2PatternRef)pattern, components);
}

CGColorRef CGColorCreateCopyByMatchingToColorSpace(CGColorSpaceRef colorSpace,
                                                   CGColorRenderingIntent intent,
                                                   CGColorRef color,
                                                   CFDictionaryRef options)
{
    return (CGColorRef)O2ColorCreateCopyByMatchingToColorSpace(
            (O2ColorSpaceRef)colorSpace, (O2ColorRef)color);
}

CGColorRef CGColorCreateCopy(CGColorRef self) {
    return (CGColorRef)O2ColorCreateCopy((O2ColorRef)self);
}

CGColorRef CGColorCreateCopyWithAlpha(CGColorRef self, CGFloat a) {
    return (CGColorRef)O2ColorCreateCopyWithAlpha((O2ColorRef)self, a);
}

bool CGColorEqualToColor(CGColorRef self, CGColorRef other) {
    return O2ColorEqualToColor((O2ColorRef)self, (O2ColorRef)other);
}

CGColorSpaceRef CGColorGetColorSpace(CGColorRef self) {
    return (CGColorSpaceRef)O2ColorGetColorSpace((O2ColorRef)self);
}

size_t CGColorGetNumberOfComponents(CGColorRef self) {
    return O2ColorGetNumberOfComponents((O2ColorRef)self);
}

const CGFloat *CGColorGetComponents(CGColorRef self) {
    return O2ColorGetComponents((O2ColorRef)self);
}

CGFloat CGColorGetAlpha(CGColorRef self) {
    return O2ColorGetAlpha((O2ColorRef)self);
}

CGPatternRef CGColorGetPattern(CGColorRef self) {
    return (CGPatternRef)O2ColorGetPattern((O2ColorRef)self);
}

CGColorRef CGColorGetConstantColor(CFStringRef colorName) {
    CGColorRef res = NULL;
    if (CFStringCompare(colorName,kCGColorWhite,0) == kCFCompareEqualTo)
        res = CGColorCreateGenericGray(1.0, 1.0);
    if (CFStringCompare(colorName,kCGColorBlack,0) == kCFCompareEqualTo)
        res = CGColorCreateGenericGray(0.0, 1.0);
    if (CFStringCompare(colorName,kCGColorClear,0) == kCFCompareEqualTo)
        res = CGColorCreateGenericGray(0.0, 0.0);

    return CFAutorelease(res);
}

const CFStringRef kCGColorWhite = CFSTR("kCGColorWhite");
const CFStringRef kCGColorBlack = CFSTR("kCGColorBlack");
const CFStringRef kCGColorClear = CFSTR("kCGColorClear");
