#import <QuartzCore/QuartzCore.h>

// Declared by the client, as OpenSwiftUI and WebKit do: CAFilter is not public.
@interface CAFilter : NSObject <NSCopying, NSSecureCoding>
+ (instancetype)filterWithType:(NSString *)type;
+ (instancetype)filterWithName:(NSString *)name;
- (instancetype)initWithName:(NSString *)name;
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

// A filter archived on macOS 26.7.3 (type gaussianBlur, name "renamed", disabled, inputRadius 5):
static NSString *const macFilterArchive =
    @"YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEI"
    "CVRyb290gAGrCwwXGBkdJSYnLjJVJG51bGzVDQ4PEBESExQVFlxDQUZpbHRlclR5cGVcQ0FGaWx0ZXJOYW1lXxAPQ0FGaWx0ZXJF"
    "bmFibGVkXkNBRmlsdGVySW5wdXRzViRjbGFzc4ACgAMIgASAClxnYXVzc2lhbkJsdXJXcmVuYW1lZNIRGhscVGRpY3SACYAF0x4f"
    "ESAiJFdOUy5rZXlzWk5TLm9iamVjdHOhIYAGoSOAB4AIW2lucHV0UmFkaXVzEAXSKCkqK1okY2xhc3NuYW1lWCRjbGFzc2VzXxAT"
    "TlNNdXRhYmxlRGljdGlvbmFyeaMqLC1cTlNEaWN0aW9uYXJ5WE5TT2JqZWN00igpLzBfEBlMS05TRGljdGlvbmFyeUNvZGluZ1By"
    "b3h5oy8xLV1DQUNvZGluZ1Byb3h50igpMzRYQ0FGaWx0ZXKiMy0ACAARABoAJAApADIANwBJAEwAUQBTAF8AZQBwAH0AigCcAKsA"
    "sgC0ALYAtwC5ALsAyADQANUA2gDcAN4A5QDtAPgA+gD8AP4BAAECAQ4BEAEVASABKQE/AUMBUAFZAV4BegF+AYwBkQGaAAAAAAAA"
    "AgEAAAAAAAAANQAAAAAAAAAAAAAAAAAAAZ0=";

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
        // quirk_nil_type_makes_an_object: no type still gives an object (see the QUIRK in CAFilter.m).
        CAFilter *untyped = [CAFilter filterWithType:nil];
        expect(untyped != nil && [untyped.type isEqualToString:@"<nil>"] && [untyped.name isEqualToString:@"<nil>"] && untyped.enabled,
               @"nil type makes an object");
        CAFilter *bare = [[[CAFilter alloc] init] autorelease];
        expect(bare != nil && [bare.type isEqualToString:@"<nil>"] && bare.name == nil && !bare.enabled,
               @"init gives a disabled filter without a name");
        CAFilter *named = [CAFilter filterWithName:@"gaussianBlur"];
        expect([named.type isEqualToString:@"gaussianBlur"] && [named.name isEqualToString:@"gaussianBlur"] && named.enabled,
               @"the name based initialiser takes the name as the type");

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

        // Archiving: secure coding, a round trip, and an archive written by macOS.
        expect([CAFilter supportsSecureCoding], @"supports secure coding");
        CAFilter *archived = [CAFilter filterWithType:kCAFilterGaussianBlur];
        [archived setName:@"renamed"];
        archived.enabled = NO;
        [archived setValue:@5 forKey:kCAFilterInputRadius];
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:archived requiringSecureCoding:YES error:NULL];
        CAFilter *decoded = [NSKeyedUnarchiver unarchivedObjectOfClass:[CAFilter class] fromData:data error:NULL];
        expect(decoded != nil && [decoded.type isEqualToString:@"gaussianBlur"] && [decoded.name isEqualToString:@"renamed"] &&
                   !decoded.enabled && [[decoded valueForKey:kCAFilterInputRadius] intValue] == 5, @"archive round trip");
        NSData *macData = [[[NSData alloc] initWithBase64EncodedString:macFilterArchive options:0] autorelease];
        CAFilter *fromMac = [NSKeyedUnarchiver unarchivedObjectOfClass:[CAFilter class] fromData:macData error:NULL];
        expect(fromMac != nil && [fromMac.type isEqualToString:@"gaussianBlur"] && [fromMac.name isEqualToString:@"renamed"] &&
                   !fromMac.enabled && [[fromMac valueForKey:kCAFilterInputRadius] intValue] == 5, @"archive written by macOS decodes");

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
