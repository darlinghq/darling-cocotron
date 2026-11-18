// NSUserInterfaceCompressionOptions behaves like a set of options: empty by default,
// standard options are distinct and their union, and the set operations compose.
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

int main(void)
{
    @autoreleasepool
    {
        Class cls = NSClassFromString(@"NSUserInterfaceCompressionOptions");
        expect(cls != Nil, @"the class exists");

        NSUserInterfaceCompressionOptions *empty = [[[cls alloc] init] autorelease];
        expect([empty isEmpty], @"init gives an empty set");

        NSUserInterfaceCompressionOptions *images = [cls hideImagesOption];
        NSUserInterfaceCompressionOptions *text = [cls hideTextOption];
        NSUserInterfaceCompressionOptions *metrics = [cls reduceMetricsOption];
        NSUserInterfaceCompressionOptions *widths = [cls breakEqualWidthsOption];
        NSUserInterfaceCompressionOptions *all = [cls standardOptions];
        expect(![images isEmpty], @"a standard option is not empty");
        expect(![images isEqual: text] && ![text isEqual: metrics] && ![metrics isEqual: widths],
               @"the four standard options are distinct");
        expect([images isEqual: [cls hideImagesOption]], @"a standard option equals itself across calls");

        expect([all containsOptions: images] && [all containsOptions: text] &&
               [all containsOptions: metrics] && [all containsOptions: widths],
               @"standardOptions contains all four");
        expect(![images containsOptions: all], @"one option does not contain the union");
        expect([images containsOptions: empty], @"every set contains the empty set");

        NSUserInterfaceCompressionOptions *pair = [images optionsByAddingOptions: text];
        expect([pair containsOptions: images] && [pair containsOptions: text], @"union holds both");
        expect(![pair containsOptions: metrics], @"union holds nothing else");
        expect([pair intersectsOptions: text], @"intersects on a shared option");
        expect(![pair intersectsOptions: metrics], @"does not intersect on disjoint options");
        expect([[pair optionsByRemovingOptions: text] isEqual: images], @"subtraction removes one");
        expect([[pair optionsByRemovingOptions: pair] isEmpty], @"subtracting itself empties");

        NSUserInterfaceCompressionOptions *viaSet = [[[cls alloc]
            initWithCompressionOptions: [NSSet setWithObjects: images, text, nil]] autorelease];
        expect([viaSet isEqual: pair], @"init from a set is the union");

        NSUserInterfaceCompressionOptions *custom = [[[cls alloc] initWithIdentifier: @"custom"] autorelease];
        expect(![custom isEmpty] && ![custom intersectsOptions: all], @"a custom option is its own element");

        NSData *data = [NSKeyedArchiver archivedDataWithRootObject: pair];
        NSUserInterfaceCompressionOptions *back = [NSKeyedUnarchiver unarchiveObjectWithData: data];
        expect([back isEqual: pair], @"archiving round-trips");

        // The class properties are usable with dot syntax, as the public header declares them.
        expect([NSUserInterfaceCompressionOptions.hideTextOption isEqual: text], @"class property equals the factory");

        // Archive layout as written by macOS 26.7.3: the key and the identifier strings
        // (black-box observation of NSKeyedArchiver output); archives interchange with macOS.
        NSData *archived = [NSKeyedArchiver archivedDataWithRootObject: text];
        NSDictionary *plist = [NSPropertyListSerialization propertyListWithData: archived options: 0
                                                                          format: NULL error: NULL];
        NSArray *objects = plist[@"$objects"];
        BOOL foundKey = NO, foundIdentifier = NO;
        for (id object in objects) {
            if ([object isKindOfClass: [NSDictionary class]] &&
                object[@"NSUserInterfaceCompressionOptionIdentifiers"] != nil)
                foundKey = YES;
            if ([object isEqual: @"NSUserInterfaceCompressionOptionHideText"])
                foundIdentifier = YES;
        }
        expect(foundKey, @"the archive stores the identifier set under the NSUserInterfaceCompressionOptionIdentifiers key");
        expect(foundIdentifier, @"the hide-text option archives the identifier NSUserInterfaceCompressionOptionHideText");

        NSLog(@"PASS: NSUserInterfaceCompressionOptions");
    }
    return 0;
}
