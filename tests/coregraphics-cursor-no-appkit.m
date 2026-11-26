// CFLAGS: -framework Foundation -framework CoreGraphics -framework CoreFoundation
// Copyright (C) 2026 Lubos Dolezel
//
// A process without AppKit with a window of its own (a CGS window) sets the cursor the pointer shows over it with the
// cursor SPI of CoreGraphics (CGSCursor.h), hides it, selects another one while it is hidden and shows it again. What
// the window system shows is the driver's to check (coregraphics-cursor-no-appkit-x11.sh: XFixes, the cursor image under
// the pointer; coregraphics-cursor-no-appkit-wayland.sh: the cursor requests of the client's WAYLAND_DEBUG output):
//   1 hide                      nothing is shown
//   2 show, no cursor selected  the default cursor again (a process that never selected one has no image of its own)
//   3 a shape (the I-beam)
//   4 an image, 16x16 points, hot spot 3,5, red
//   5 hide                      nothing is shown
//   6 another image (32x32 pixels for 16x16 points, hot spot 4,6, green) selected while hidden: still nothing shown
//   7 show                      the green image
//   8 no cursor selected        the default cursor
// Each step is announced with "STEP n name" after its calls were made and the window system had time to apply them.
// The program waits for the pointer to move over its window first (the driver moves it), then goes through the steps by
// itself ("MOVED" when it saw the pointer move). Prints "READY" (and "WINDOW <native window>") when the window is up and "DONE" at the end; the verdict is the
// driver's. Usage: coregraphics-cursor-no-appkit (no arguments)
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreGraphics/CGSServerSPI.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>

typedef CFTypeRef RegionRef;
extern CGError CGSNewRegionWithRect(const CGRect *rect, RegionRef *newRegion);
extern CGError CGSNewWindow(CGSConnectionID cid, CFIndex flags, float x, float y, const RegionRef region, CGSWindowID *windowID);
extern OSStatus CGSOrderWindow(CGSConnectionID cid, CGSWindowID wid, int place, CGSWindowID relativeTo);
extern void *_CGSNativeWindowForID(CGSConnectionID cid, CGSWindowID wid);
extern CGError _CGSWindowDrawImage(CGSConnectionID cid, CGSWindowID wid, CGImageRef image, CGPoint origin);

typedef void *(*CreateShape)(int shape);
typedef void *(*CreateImage)(CGImageRef image, CGSize size, CGPoint hotSpot);
typedef int (*SetCurrent)(void *cursor);
typedef void (*Release)(void *cursor);

static BOOL moved;

static CGEventRef tapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *info) {
    moved = YES;
    return event;
}

static CGImageRef solidImage(size_t size, double red, double green, double blue) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, size, size, 8, 0, space, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
    CGColorSpaceRelease(space);
    CGContextSetRGBFillColor(context, red, green, blue, 1);
    CGContextFillRect(context, CGRectMake(0, 0, size, size));
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return image;
}

static void pauseFor(double seconds) {
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, seconds, false);
}

static int stepNumber;
static void step(const char *name) {
    pauseFor(0.8);
    stepNumber++;
    // On the stream the driver reads the window system's requests from too.
    fprintf(stderr, "STEP %d %s\n", stepNumber, name);
    pauseFor(1.4);
}

int main(void) {
    @autoreleasepool {
        CreateShape createShape = (CreateShape) dlsym(RTLD_DEFAULT, "CGSCursorCreateWithShape");
        CreateImage createImage = (CreateImage) dlsym(RTLD_DEFAULT, "CGSCursorCreateWithImage");
        SetCurrent setCurrent = (SetCurrent) dlsym(RTLD_DEFAULT, "CGSCursorSetCurrent");
        Release release = (Release) dlsym(RTLD_DEFAULT, "CGSCursorRelease");
        CGSConnectionID cid = CGSMainConnectionID();
        // In the middle of the main display, where the drivers move the pointer on a compositor that places windows itself.
        CGRect display = CGDisplayBounds(CGMainDisplayID());
        CGRect frame = CGRectMake(CGRectGetMidX(display) - 200, CGRectGetMidY(display) - 150, 400, 300);
        RegionRef region = NULL;
        CGSWindowID wid = 0;
        if (cid == 0 || CGSNewRegionWithRect(&frame, &region) != kCGErrorSuccess ||
            CGSNewWindow(cid, 0, 0, 0, region, &wid) != kCGErrorSuccess || CGSOrderWindow(cid, wid, 1, 0) != kCGErrorSuccess) {
            printf("FAIL no window\n");
            return 1;
        }
        // A window with contents of its own is mapped by Wayland compositors.
        CGImageRef contents = solidImage(400, 0.8, 0.8, 0.8);
        _CGSWindowDrawImage(cid, wid, contents, CGPointZero);
        CGImageRelease(contents);
        if (createShape == NULL || createImage == NULL || setCurrent == NULL || release == NULL)
            printf("NOSPI the cursor SPI is missing\n");

        CGEventMask mask = CGEventMaskBit(kCGEventMouseMoved);
        CFMachPortRef tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly, mask, tapCallback, NULL);
        if (tap == NULL) {
            printf("FAIL no event tap\n");
            return 1;
        }
        CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(NULL, tap, 0);
        CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
        CGEventTapEnable(tap, true);

        printf("WINDOW %lu\nREADY\n", (unsigned long) (uintptr_t) _CGSNativeWindowForID(cid, wid));
        fflush(stdout);
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: 60];
        while (!moved && [deadline timeIntervalSinceNow] > 0)
            pauseFor(0.1);
        printf("MOVED\n");
        fflush(stdout);
        pauseFor(1.5);

        CGDisplayHideCursor(kCGDirectMainDisplay);
        step("hide");
        CGDisplayShowCursor(kCGDirectMainDisplay);
        step("show-default");
        if (createShape != NULL) {
            void *shape = createShape(1 /* kCGSCursorShapeIBeam */);
            setCurrent(shape);
            release(shape);
        }
        step("ibeam");
        CGImageRef red = solidImage(16, 1, 0, 0), green = solidImage(32, 0, 1, 0);
        void *redCursor = createImage != NULL ? createImage(red, CGSizeMake(16, 16), CGPointMake(3, 5)) : NULL;
        void *greenCursor = createImage != NULL ? createImage(green, CGSizeMake(16, 16), CGPointMake(4, 6)) : NULL;
        if (setCurrent != NULL)
            setCurrent(redCursor);
        step("image");
        CGDisplayHideCursor(kCGDirectMainDisplay);
        step("hide-image");
        if (setCurrent != NULL)
            setCurrent(greenCursor);
        step("image-while-hidden");
        CGDisplayShowCursor(kCGDirectMainDisplay);
        step("show-image");
        if (setCurrent != NULL)
            setCurrent(NULL);
        step("default");
        if (release != NULL) {
            release(redCursor);
            release(greenCursor);
        }
        CGImageRelease(red);
        CGImageRelease(green);
        printf("DONE\n");
    }
    return 0;
}
