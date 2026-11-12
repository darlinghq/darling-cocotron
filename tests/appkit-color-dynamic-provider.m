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
        __block int calls = 0;
        NSColor *color = [NSColor colorWithName:@"testColor"
                                dynamicProvider:^NSColor *(NSAppearance *appearance) {
                                    calls++;
                                    if ([[appearance name] isEqual:NSAppearanceNameDarkAqua])
                                        return [NSColor colorWithCalibratedRed:0 green:0 blue:1 alpha:1];
                                    return [NSColor colorWithCalibratedRed:1 green:0 blue:0 alpha:1];
                                }];
        expect(color != nil && [[color colorNameComponent] isEqual:@"testColor"], @"name");

        [NSAppearance setCurrentAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];
        expect([color redComponent] == 1 && [color blueComponent] == 0, @"resolves for Aqua");
        NSColor *rgb = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
        expect(rgb != nil && [rgb redComponent] == 1, @"colorUsingColorSpaceName: resolves");
        const CGFloat *components = CGColorGetComponents([color CGColor]);
        expect(components != NULL && components[0] == 1 && components[2] == 0, @"CGColor for Aqua");

        [NSAppearance setCurrentAppearance:[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua]];
        expect([color redComponent] == 0 && [color blueComponent] == 1, @"resolves again for Dark Aqua");
        components = CGColorGetComponents([color CGColor]);
        expect(components != NULL && components[2] == 1, @"CGColor for Dark Aqua");

        NSColor *faded = [color colorWithAlphaComponent:0.5];
        expect([faded alphaComponent] == 0.5 && [faded blueComponent] == 1, @"alpha variant resolves");
        [NSAppearance setCurrentAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];
        expect([faded alphaComponent] == 0.5 && [faded redComponent] == 1, @"alpha variant stays dynamic");
        expect(calls > 0, @"provider called");

        BOOL raised = NO;
        @try
        {
            [[NSColor colorWithName:nil dynamicProvider:^NSColor *(NSAppearance *a) { return nil; }] redComponent];
        }
        @catch (NSException *exception)
        {
            raised = [[exception name] isEqual:NSInternalInconsistencyException];
        }
        expect(raised, @"a nil result raises");

        NSLog(@"PASS appkit-color-dynamic-provider");
    }
    return 0;
}
