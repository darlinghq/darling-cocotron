#import <QuartzCore/QuartzCore.h>

// Declared by the client, as OpenSwiftUI and WebKit do: CAFilter is not public.
@interface CAFilter : NSObject <NSCopying>
+ (instancetype)filterWithType:(NSString *)type;
@property(readonly, copy) NSString *type;
@property(copy) NSString *name;
@property(getter=isEnabled) BOOL enabled;
@end

extern NSString *const kCAFilterAlphaThreshold, *const kCAFilterAverageColor,
    *const kCAFilterColorBrightness, *const kCAFilterColorContrast, *const kCAFilterColorHueRotate,
    *const kCAFilterColorInvert, *const kCAFilterColorMatrix, *const kCAFilterColorMonochrome,
    *const kCAFilterColorSaturate, *const kCAFilterCurves, *const kCAFilterGaussianBlur,
    *const kCAFilterLuminanceCurveMap, *const kCAFilterLuminanceToAlpha, *const kCAFilterMultiplyColor,
    *const kCAFilterVariableBlur, *const kCAFilterVibrantColorMatrix;
extern NSString *const kCAFilterInputRadius, *const kCAFilterInputNormalizeEdges,
    *const kCAFilterInputAmount, *const kCAFilterInputPremultipliedValues;
#include <stdlib.h>

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

int main(void)
{
    @autoreleasepool
    {
        expect([kCAFilterGaussianBlur isEqualToString:@"gaussianBlur"], @"gaussian blur type");
        expect([kCAFilterVibrantColorMatrix isEqualToString:@"vibrantColorMatrix"], @"vibrant color matrix type");
        expect([kCAFilterInputRadius isEqualToString:@"inputRadius"], @"radius input key");
        expect([kCAFilterInputPremultipliedValues isEqualToString:@"inputPremultipliedValues"],
               @"premultiplied values input key");
        expect([CAFilter filterWithType:nil] == nil, @"nil type");
        expect([[CAFilter alloc] init] == nil, @"a filter needs a type");

        CAFilter *blur = [[CAFilter filterWithType:kCAFilterGaussianBlur] retain];
        expect([blur.type isEqualToString:@"gaussianBlur"], @"type");
        expect([blur.name isEqualToString:@"gaussianBlur"], @"name defaults to type");
        expect(blur.enabled, @"enabled by default");

        [blur setValue:@12.5 forKey:kCAFilterInputRadius];
        [blur setValue:@YES forKey:kCAFilterInputNormalizeEdges];
        expect([[blur valueForKey:kCAFilterInputRadius] doubleValue] == 12.5, @"radius round trip");
        expect([[blur valueForKey:kCAFilterInputNormalizeEdges] boolValue], @"normalize edges round trip");
        expect([blur valueForKey:kCAFilterInputAmount] == nil, @"unset input is nil");
        [blur setValue:nil forKey:kCAFilterInputNormalizeEdges];
        expect([blur valueForKey:kCAFilterInputNormalizeEdges] == nil, @"nil removes an input");

        [blur setValue:@"blur" forKey:@"name"];
        [blur setValue:@NO forKey:@"enabled"];
        expect([blur.name isEqualToString:@"blur"] && !blur.enabled, @"properties through KVC");
        expect([blur valueForKey:@"type"] == blur.type, @"type through KVC");

        CAFilter *copy = [blur copy];
        expect(copy != blur && [copy.type isEqualToString:blur.type], @"copy keeps type");
        expect([copy.name isEqualToString:@"blur"] && !copy.enabled, @"copy keeps name and enabled");
        expect([[copy valueForKey:kCAFilterInputRadius] doubleValue] == 12.5, @"copy keeps inputs");
        [copy setValue:@3 forKey:kCAFilterInputRadius];
        expect([[blur valueForKey:kCAFilterInputRadius] doubleValue] == 12.5, @"copy inputs are independent");
        [copy release];

        NSArray *filters = [[NSArray alloc] initWithObjects:blur, nil];
        [blur release];
        expect([[[filters objectAtIndex:0] valueForKey:kCAFilterInputRadius] doubleValue] == 12.5,
               @"filter survives in a retaining array");
        [filters release];

        NSString *types[] = {
            kCAFilterAlphaThreshold, kCAFilterAverageColor, kCAFilterColorBrightness,
            kCAFilterColorContrast, kCAFilterColorHueRotate, kCAFilterColorInvert,
            kCAFilterColorMatrix, kCAFilterColorMonochrome, kCAFilterColorSaturate,
            kCAFilterCurves, kCAFilterLuminanceCurveMap, kCAFilterLuminanceToAlpha,
            kCAFilterMultiplyColor, kCAFilterVariableBlur,
        };
        for (unsigned i = 0; i < sizeof(types) / sizeof(types[0]); i++)
            expect([[CAFilter filterWithType:types[i]].type isEqualToString:types[i]], types[i]);
    }
    NSLog(@"PASS");
    return 0;
}
