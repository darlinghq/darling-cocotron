// Copyright (C) 2026 Lubos Dolezel
//
// An NSImageCell's image is its object value. Expected values are from
// black-box runs of this test on macOS 26.7.3 (x86_64) and Mac OS X 10.14.4
// (i386):
//  - setting the object value to an image sets the image, and setting the image
//    sets the object value, both to the same object (not a copy); a nil image
//    clears both;
//  - -initImageCell: gives the image as the object value;
//  - an image view's -setObjectValue: and -setImage: do the same through its
//    cell;
//  - a keyed archive of an image cell with a bitmap image, as in a nib, unarchives with the image
//    as both the image and the object value;
//  - a button cell's object value is not its image.
// Build: clang -framework AppKit appkit-image-cell-object-value.m (no ARC)
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

int main(void) {
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [NSApplication sharedApplication];
    NSImage *a = [[NSImage alloc] initWithSize: NSMakeSize(4, 4)];
    NSImage *b = [[NSImage alloc] initWithSize: NSMakeSize(8, 8)];

    NSImageCell *cell = [[NSImageCell alloc] init];
    CHECK([cell image] == nil && [cell objectValue] == nil);
    [cell setObjectValue: a];
    CHECK([cell image] == a);
    CHECK([cell objectValue] == a);
    [cell setImage: b];
    CHECK([cell image] == b);
    CHECK([cell objectValue] == b);
    [cell setImage: nil];
    CHECK([cell image] == nil && [cell objectValue] == nil);

    NSImageCell *initialised = [[NSImageCell alloc] initImageCell: a];
    CHECK([initialised image] == a);
    CHECK([initialised objectValue] == a);

    NSImageView *view = [[NSImageView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
    [view setObjectValue: a];
    CHECK([view image] == a);
    [view setImage: b];
    CHECK([view objectValue] == b);
    CHECK([[view cell] objectValue] == b);

    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL pixelsWide: 4 pixelsHigh: 4
            bitsPerSample: 8 samplesPerPixel: 4 hasAlpha: YES isPlanar: NO colorSpaceName: NSDeviceRGBColorSpace
            bytesPerRow: 0 bitsPerPixel: 0];
    NSImage *bitmap = [[NSImage alloc] initWithSize: NSMakeSize(4, 4)];
    [bitmap addRepresentation: rep];
    NSImageCell *unarchived = [NSKeyedUnarchiver unarchiveObjectWithData:
            [NSKeyedArchiver archivedDataWithRootObject: [[NSImageCell alloc] initImageCell: bitmap]]];
    CHECK([unarchived image] != nil);
    CHECK([unarchived image] == [unarchived objectValue]);
    CHECK(NSEqualSizes([[unarchived image] size], NSMakeSize(4, 4)));

    NSButtonCell *button = [[NSButtonCell alloc] init];
    [button setObjectValue: a];
    CHECK([button image] == nil);

    if (failures == 0)
        printf("PASS appkit-image-cell-object-value\n");
    [pool release];
    return failures != 0;
}
