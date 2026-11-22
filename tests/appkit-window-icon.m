/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// A window that shows the application icon: the guest side of appkit-window-icon-x11.sh (the window
// manager's _NET_WM_ICON) and appkit-window-icon-wayland.sh (the xdg-toplevel-icon buffers a compositor
// receives). Usage: appkit-window-icon <mode> <seconds>
//   bundle   the application icon comes from the application bundle: the program makes a bundle holding a
//            copy of itself and a 128 x 128 green icns file, and runs the copy
//   runtime  -setApplicationIconImage: gives a red image before the window is shown
//   change   as runtime, then a blue image replaces it after the window is shown
// A window is shown for <seconds>; the lines READY (the window is up) and CHANGED (the new image is set)
// say how far it got. Run with DARLING_APPKIT_BACKEND=x11 or wayland and the matching DISPLAY or
// WAYLAND_DISPLAY set.
#import <AppKit/AppKit.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static NSData *pngOfSide(int side, double red, double green, double blue) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, side, side, 8, 0, space, kCGImageAlphaPremultipliedLast);
    CGContextSetRGBFillColor(ctx, red, green, blue, 1);
    CGContextFillRect(ctx, CGRectMake(0, 0, side, side));
    CGImageRef image = CGBitmapContextCreateImage(ctx);
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage: image];
    NSData *png = [rep representationUsingType: NSPNGFileType properties: @{}];
    CGImageRelease(image);
    CGContextRelease(ctx);
    CGColorSpaceRelease(space);
    return png;
}

// An .icns file holding one 128 x 128 PNG icon ("ic07").
static NSData *icns128(void) {
    NSData *png = pngOfSide(128, 0, 1, 0);
    NSMutableData *d = [NSMutableData data];
    uint32_t chunk = (uint32_t) ([png length] + 8), total = chunk + 8;
    unsigned char h[16] = {'i', 'c', 'n', 's', total >> 24, total >> 16, total >> 8, total,
                           'i', 'c', '0', '7', chunk >> 24, chunk >> 16, chunk >> 8, chunk};
    [d appendBytes: h length: 16];
    [d appendData: png];
    return d;
}

static NSImage *solidImage(double red, double green, double blue) {
    NSImage *image = [[NSImage alloc] initWithData: pngOfSide(64, red, green, blue)];
    [image setSize: NSMakeSize(64, 64)];
    return image;
}

static int showWindow(const char *mode, double seconds) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
        if (strcmp(mode, "runtime") == 0 || strcmp(mode, "change") == 0)
            [NSApp setApplicationIconImage: solidImage(1, 0, 0)];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 240, 120)
                                                       styleMask: NSTitledWindowMask | NSClosableWindowMask
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        [window setTitle: @"icon-test"];
        [window makeKeyAndOrderFront: nil];
        [NSApp finishLaunching];

        NSDate *end = [NSDate dateWithTimeIntervalSinceNow: seconds];
        NSDate *change = [NSDate dateWithTimeIntervalSinceNow: 4];
        BOOL ready = NO, changed = NO;
        while ([end timeIntervalSinceNow] > 0) {
            NSEvent *event = [NSApp nextEventMatchingMask: NSAnyEventMask
                                                untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]
                                                   inMode: NSDefaultRunLoopMode
                                                  dequeue: YES];
            if (event != nil)
                [NSApp sendEvent: event];
            if (!ready && [window isVisible]) {
                ready = YES;
                printf("READY\n");
                fflush(stdout);
            }
            if (ready && !changed && strcmp(mode, "change") == 0 && [change timeIntervalSinceNow] < 0) {
                changed = YES;
                [NSApp setApplicationIconImage: solidImage(0, 0, 1)];
                printf("CHANGED\n");
                fflush(stdout);
            }
        }
    }
    return 0;
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: appkit-window-icon bundle|runtime|change <seconds>\n");
        return 2;
    }
    const char *mode = argv[1];
    double seconds = atof(argv[2]);
    NSBundle *main = [NSBundle mainBundle];
    if (strcmp(mode, "bundle") != 0 || [main objectForInfoDictionaryKey: @"CFBundleIconFile"] != nil)
        return showWindow(mode, seconds);

    // Not in a bundle yet: make one around a copy of this program and run that.
    @autoreleasepool {
        NSString *app = [NSTemporaryDirectory() stringByAppendingPathComponent:
                [NSString stringWithFormat: @"window-icon-%d.app", getpid()]];
        NSString *macos = [app stringByAppendingPathComponent: @"Contents/MacOS"];
        NSString *resources = [app stringByAppendingPathComponent: @"Contents/Resources"];
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath: macos withIntermediateDirectories: YES attributes: nil error: NULL];
        [fm createDirectoryAtPath: resources withIntermediateDirectories: YES attributes: nil error: NULL];
        NSString *copy = [macos stringByAppendingPathComponent: @"window-icon"];
        [fm copyItemAtPath: [main executablePath] toPath: copy error: NULL];
        [icns128() writeToFile: [resources stringByAppendingPathComponent: @"icon.icns"] atomically: NO];
        NSDictionary *info = @{@"CFBundleExecutable": @"window-icon", @"CFBundleIdentifier": @"test.window-icon",
                               @"CFBundleName": @"window-icon", @"CFBundlePackageType": @"APPL",
                               @"CFBundleIconFile": @"icon"};
        [info writeToFile: [app stringByAppendingPathComponent: @"Contents/Info.plist"] atomically: NO];

        char *args[] = {(char *) [copy fileSystemRepresentation], argv[1], argv[2], NULL};
        pid_t pid;
        if (posix_spawn(&pid, args[0], NULL, NULL, args, environ) != 0) {
            fprintf(stderr, "cannot run the bundled copy\n");
            return 1;
        }
        int status = 0;
        waitpid(pid, &status, 0);
        [fm removeItemAtPath: app error: NULL];
        return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
    }
}
