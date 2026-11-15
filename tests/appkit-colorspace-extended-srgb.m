#import <AppKit/AppKit.h>
#include <stdlib.h>

// Declared here so the test compiles, and fails at run time, without the
// extended sRGB addition.
@interface NSColorSpace (ExtendedSRGBProbe)
+ (NSColorSpace *) extendedSRGBColorSpace;
@end

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
        expect([NSColorSpace respondsToSelector:@selector(extendedSRGBColorSpace)],
               @"+extendedSRGBColorSpace is not implemented");
        NSColorSpace *space = [NSColorSpace extendedSRGBColorSpace];
        expect(space != nil, @"extended sRGB space is nil");
        expect([NSColorSpace extendedSRGBColorSpace] == space, @"not the same object on a second call");

        CGColorSpaceRef cg = [space CGColorSpace];
        expect(cg != NULL, @"no backing CGColorSpace");
        CFStringRef name = CGColorSpaceGetName(cg);
        expect(name != NULL && CFEqual(name, kCGColorSpaceExtendedSRGB), @"backing space is not extended sRGB");
        expect(CGColorSpaceUsesExtendedRange(cg), @"backing space does not use extended range");
        expect(CGColorSpaceGetModel(cg) == kCGColorSpaceModelRGB, @"backing space is not RGB");
        expect(CGColorSpaceGetNumberOfComponents(cg) == 3, @"backing space does not have three components");

        // Extended range: components outside 0..1 must survive the round trip.
        CGFloat in[] = {1.25, -0.1, 0.4, 0.5};
        NSColor *color = [NSColor colorWithColorSpace:space components:in count:4];
        expect(color != nil, @"color in extended sRGB");
        CGColorRef roundTrip = color.CGColor;
        expect(roundTrip != NULL, @"CGColor of extended color");
        const CGFloat *out = CGColorGetComponents(roundTrip);
        for (unsigned i = 0; i < 4; ++i)
            expect(closeEnough(out[i], in[i]), @"component or alpha changed in round trip");
        CGColorRelease(roundTrip);

        NSLog(@"PASS");
    }
    return 0;
}
