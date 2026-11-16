// Copyright (C) 2026 Lubos Dolezel
//
// Pins QUIRK: for a program built against an SDK older than 10.6, the bitmap of an image without
// alpha after -lockFocus / drawing / -unlockFocus has no alpha channel (3 samples per pixel, 24 bits
// per pixel); for programs built for 10.6 and later it has 4 samples and 32 bits, as macOS 10.14.4
// gives (black-box). An image with alpha keeps 4 samples in both. See the QUIRK comment in
// AppKit/NSImage.m for the evidence.
//
// One source, two builds. The run mode is the argument; the program checks that the SDK version
// dyld reports for it matches:
//   new: an ordinary build, e.g. guest-cc.sh -a i386 -t 10.13 -o t-new t.m -framework AppKit
//   old: the same with the linker told the program was built against the 10.5 SDK, which is what
//        dyld_get_program_sdk_version() reports for a 10.5 or earlier program:
//        guest-cc.sh -a i386 -t 10.13 -o t-old t.m -framework AppKit -Wl,-sdk_version,10.5
//        run as: t-old old        t-new new
// (A 10.4/10.5 era binary has no version load command at all, and dyld then reports no SDK version
// either; the quirk treats that the same way as an SDK older than 10.6.)
#import <AppKit/AppKit.h>
#include <mach-o/dyld_priv.h>
#import <objc/message.h>
#include <stdio.h>
#include <string.h>

static int failures;

#define CHECK(cond, ...) \
    do { \
        if (!(cond)) { \
            fprintf(stderr, "FAIL line %d: ", __LINE__); \
            fprintf(stderr, __VA_ARGS__); \
            fputc('\n', stderr); \
            failures++; \
        } \
    } while (0)

enum { W = 16, H = 8 };

// Creates a bitmap of the given layout. The BOOL arguments of the initializer are passed as full
// words through a cast message send: a 1 byte BOOL stored in a stack argument slot is not
// widened by the compiler this test is cross-built with, and macOS 10.14.4's initializer
// sometimes read garbage from the rest of the slot and refused the call ("Inconsistent set of
// values"), which made results depend on the stack contents.
static NSBitmapImageRep *newBitmap(long width, long height, long samples, long alpha, NSString *space) {
    typedef id (*InitFunction)(id, SEL, unsigned char **, long, long, long, long, long, long, NSString *, long, long);
    return ((InitFunction) objc_msgSend)([NSBitmapImageRep alloc],
                                         @selector(initWithBitmapDataPlanes:pixelsWide:pixelsHigh:bitsPerSample:samplesPerPixel:hasAlpha:isPlanar:colorSpaceName:bytesPerRow:bitsPerPixel:),
                                         NULL, width, height, 8, samples, alpha, 0, space, 0, samples * 8);
}


static BOOL near(int a, int b) {
    return a - b <= 6 && b - a <= 6;
}

static void checkBitmap(const char *name, NSBitmapImageRep *rep, BOOL expectOpaque) {
    CHECK(rep != nil, "%s: no bitmap", name);
    if (rep == nil)
        return;
    NSInteger samples = expectOpaque ? 3 : 4;
    CHECK([rep samplesPerPixel] == samples, "%s: samples per pixel %ld, expected %ld", name, (long) [rep samplesPerPixel], (long) samples);
    CHECK([rep bitsPerSample] == 8, "%s: bits per sample %ld", name, (long) [rep bitsPerSample]);
    CHECK([rep bitsPerPixel] == samples * 8, "%s: bits per pixel %ld", name, (long) [rep bitsPerPixel]);
    CHECK([rep bytesPerRow] == W * samples, "%s: bytes per row %ld", name, (long) [rep bytesPerRow]);
    CHECK([rep hasAlpha] == !expectOpaque, "%s: hasAlpha %d", name, (int) [rep hasAlpha]);
    CHECK([rep pixelsWide] == W && [rep pixelsHigh] == H, "%s: size %ldx%ld", name, (long) [rep pixelsWide], (long) [rep pixelsHigh]);
    unsigned char *d = [rep bitmapData];
    if (d == NULL || [rep samplesPerPixel] < 3)
        return;
    NSInteger n = [rep samplesPerPixel];
    unsigned char *left = d + 3 * [rep bytesPerRow] + 2 * n, *right = d + 3 * [rep bytesPerRow] + (W - 3) * n;
    CHECK(near(left[0], 255) && near(left[1], 0) && near(left[2], 0), "%s: left pixel %d %d %d", name, left[0], left[1], left[2]);
    CHECK(near(right[0], 0) && near(right[1], 0) && near(right[2], 255), "%s: right pixel %d %d %d", name, right[0], right[1], right[2]);
}

// The flow a program of the 10.5 era uses: focus the image, draw, unfocus, then read the bitmap of its TIFF data.
static void run(const char *name, NSBitmapImageRep *source, BOOL expectOpaque) {
    NSImage *image = [[NSImage alloc] initWithSize: NSMakeSize(W, H)];
    [image addRepresentation: source];

    [image lockFocus];
    [image unlockFocus];

    char label[64];
    snprintf(label, sizeof label, "%s TIFF round trip", name);
    checkBitmap(label, [NSBitmapImageRep imageRepWithData: [image TIFFRepresentation]], expectOpaque);

    // the focused image still draws what was drawn into it
    NSBitmapImageRep *target = newBitmap(W, H, 4, YES, NSDeviceRGBColorSpace);
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: [NSGraphicsContext graphicsContextWithBitmapImageRep: target]];
    [image drawInRect: NSMakeRect(0, 0, W, H)];
    [NSGraphicsContext restoreGraphicsState];
    NSColor *c = [[target colorAtX: 2 y: 3] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
    CHECK([c redComponent] > 0.9 && [c greenComponent] < 0.1 && [c blueComponent] < 0.1 && [c alphaComponent] > 0.99,
          "%s: drawn pixel %g %g %g %g", name, [c redComponent], [c greenComponent], [c blueComponent], [c alphaComponent]);
    [target release];
    [image release];
}

int main(int argc, char **argv) {
    if (argc != 2 || (strcmp(argv[1], "old") != 0 && strcmp(argv[1], "new") != 0)) {
        fprintf(stderr, "usage: %s old|new\n", argv[0]);
        return 2;
    }
    BOOL old = strcmp(argv[1], "old") == 0;

    uint32_t sdk = dyld_get_program_sdk_version();
    if (old != (sdk < 0x000a0600)) {
        printf("SKIP: the program's SDK version is 0x%08x, not an %s program\n", sdk, old ? "old" : "new");
        return 2;
    }

    @autoreleasepool {
        [NSApplication sharedApplication];

        // opaque RGB representation: left half red, right half blue
        NSBitmapImageRep *opaque = newBitmap(W, H, 3, NO, NSDeviceRGBColorSpace);
        NSBitmapImageRep *withAlpha = newBitmap(W, H, 4, YES, NSDeviceRGBColorSpace);
        NSBitmapImageRep *reps[2] = {opaque, withAlpha};
        for (int r = 0; r < 2; r++) {
            NSInteger n = [reps[r] samplesPerPixel];
            unsigned char *p = [reps[r] bitmapData];
            for (int y = 0; y < H; y++)
                for (int x = 0; x < W; x++) {
                    unsigned char *px = p + y * [reps[r] bytesPerRow] + x * n;
                    px[0] = x < W / 2 ? 255 : 0;
                    px[1] = 0;
                    px[2] = x < W / 2 ? 0 : 255;
                    if (n == 4)
                        px[3] = 255;
                }
        }

        run("opaque image", opaque, old);
        run("image with alpha", withAlpha, NO);
        [opaque release];
        [withAlpha release];
    }
    if (failures == 0)
        printf("lockFocus bitmap format (%s program): PASS\n", argv[1]);
    return failures != 0;
}
