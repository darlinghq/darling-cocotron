#import <AppKit/AppKit.h>
#include <stdlib.h>

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

static BOOL closeEnough(CGFloat a, CGFloat b)
{
    CGFloat difference = a - b;
    return difference < 0.00001 && difference > -0.00001;
}

int main(void)
{
    @autoreleasepool
    {
        expect([NSColor colorWithCGColor:NULL] == nil, @"null input");

        CGColorSpaceRef rgbSpace = CGColorSpaceCreateWithName(kCGColorSpaceExtendedSRGB);
        expect(rgbSpace != NULL, @"extended sRGB space");
        CGFloat rgbComponents[] = {0.2, 0.4, 0.6, 0.5};
        CGColorRef rgb = CGColorCreate(rgbSpace, rgbComponents);
        expect(rgb != NULL, @"RGB fixture");
        NSColor *rgbColor = [[NSColor colorWithCGColor:rgb] retain];
        expect(rgbColor != nil, @"RGB conversion");
        expect([rgbColor.colorSpaceName isEqualToString:NSCalibratedRGBColorSpace], @"RGB color-space family");
        CGColorRelease(rgb);
        CGColorSpaceRelease(rgbSpace);

        CGColorRef roundTrip = rgbColor.CGColor;
        const CGFloat *actual = CGColorGetComponents(roundTrip);
        expect(CGColorSpaceGetModel(CGColorGetColorSpace(roundTrip)) == kCGColorSpaceModelRGB,
               @"RGB model survives after original release");
        for (unsigned i = 0; i < 4; ++i)
            expect(closeEnough(actual[i], rgbComponents[i]), @"RGB component or alpha changed");
        CGColorRelease(roundTrip);
        [rgbColor release];

        CGColorSpaceRef graySpace = CGColorSpaceCreateDeviceGray();
        CGFloat grayComponents[] = {0.3, 0.8};
        CGColorRef gray = CGColorCreate(graySpace, grayComponents);
        NSColor *grayColor = [[NSColor colorWithCGColor:gray] retain];
        expect(grayColor != nil, @"grayscale conversion");
        expect([grayColor.colorSpaceName isEqualToString:NSDeviceWhiteColorSpace], @"grayscale family");
        CGColorRelease(gray);
        CGColorSpaceRelease(graySpace);
        roundTrip = grayColor.CGColor;
        actual = CGColorGetComponents(roundTrip);
        expect(CGColorSpaceGetModel(CGColorGetColorSpace(roundTrip)) == kCGColorSpaceModelMonochrome,
               @"grayscale model survives after original release");
        expect(closeEnough(actual[0], grayComponents[0]) && closeEnough(actual[1], grayComponents[1]),
               @"grayscale component or alpha changed");
        CGColorRelease(roundTrip);
        [grayColor release];

        NSLog(@"PASS: NSColor retains CGColor space, components, and alpha");
    }
    return 0;
}
