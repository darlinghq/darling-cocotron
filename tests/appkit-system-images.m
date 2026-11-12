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
        NSArray *names = @[ NSImageNameFolder, NSImageNameComputer, NSImageNameNetwork, NSImageNameTrashEmpty,
                            NSImageNameTrashFull, NSImageNameUser ];
        for (NSImageName name in names)
        {
            NSImage *image = [NSImage imageNamed:name];
            expect(image != nil, [NSString stringWithFormat:@"%@ is available", name]);
            expect(NSEqualSizes(image.size, NSMakeSize(32, 32)), [NSString stringWithFormat:@"%@ is 32x32", name]);

            NSBitmapImageRep *rep = (NSBitmapImageRep *)image.representations.firstObject;
            expect([rep isKindOfClass:[NSBitmapImageRep class]] && rep.samplesPerPixel == 4 && rep.bitsPerSample == 8,
                   [NSString stringWithFormat:@"%@ is an RGBA bitmap", name]);
            const unsigned char *center = rep.bitmapData + 16 * rep.bytesPerRow + 16 * 4;
            expect(center[3] > 128, [NSString stringWithFormat:@"%@ has artwork", name]);
        }
        expect([NSImage imageNamed:@"NSNoSuchSystemImage"] == nil, @"unknown names stay nil");
        NSLog(@"PASS: system named images");
    }
    return 0;
}
