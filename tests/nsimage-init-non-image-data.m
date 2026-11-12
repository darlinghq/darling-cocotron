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
        NSData *text = [@"attachment payload" dataUsingEncoding:NSASCIIStringEncoding];
        expect(![NSBitmapImageRep canInitWithData:text], @"NSBitmapImageRep rejects non-image data");
        expect([NSImageRep imageRepClassForData:text] == Nil, @"no image rep class for non-image data");
        expect([[NSImage alloc] initWithData:text] == nil, @"initWithData: returns nil for non-image data");
        expect([[NSImage alloc] initWithData:[NSData data]] == nil, @"initWithData: returns nil for empty data");

        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:2 pixelsHigh:3
            bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
            bytesPerRow:0 bitsPerPixel:0];
        NSData *tiff = [rep TIFFRepresentation];
        expect([NSBitmapImageRep canInitWithData:tiff], @"NSBitmapImageRep accepts TIFF data");
        NSImage *image = [[NSImage alloc] initWithData:tiff];
        expect(image != nil && NSEqualSizes([image size], NSMakeSize(2, 3)), @"initWithData: decodes TIFF data");
        [image release];
        [rep release];
        NSLog(@"PASS: NSImage initWithData: returns nil for data that is not an image");
    }
    return 0;
}
