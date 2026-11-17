// Copyright (C) 2026 Lubos Dolezel
//
// NSApplication's applicationIconImage and the NSApplicationIcon named image are the icon of the
// application bundle (CFBundleIconFile), not nothing / a generic stand-in, and -setApplicationIconImage:
// replaces the former. The test builds a bundle holding a copy of its own executable and a one-icon .icns file,
// runs that copy as the child, and reports the child's result.
//
// Build: clang -fobjc-arc -framework AppKit appkit-application-icon-image.m
#import <AppKit/AppKit.h>
#include <spawn.h>
#include <stdio.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;
static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static NSData *pngOfSide(int side, uint8_t gray) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, side, side, 8, 0, space, kCGImageAlphaPremultipliedLast);
    CGContextSetRGBFillColor(ctx, gray / 255.0, gray / 255.0, gray / 255.0, 1);
    CGContextFillRect(ctx, CGRectMake(0, 0, side, side));
    CGImageRef image = CGBitmapContextCreateImage(ctx);
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:image];
    NSData *png = [rep representationUsingType:NSPNGFileType properties:@{}];
    CGImageRelease(image);
    CGContextRelease(ctx);
    CGColorSpaceRelease(space);
    return png;
}

// An .icns file holding one 128 x 128 PNG icon ("ic07").
static NSData *icns128(void) {
    NSData *png = pngOfSide(128, 0x40);
    NSMutableData *d = [NSMutableData data];
    uint32_t chunk = (uint32_t)([png length] + 8), total = chunk + 8;
    unsigned char h[16] = {'i','c','n','s', total >> 24, total >> 16, total >> 8, total,
                           'i','c','0','7', chunk >> 24, chunk >> 16, chunk >> 8, chunk};
    [d appendBytes:h length:16];
    [d appendData:png];
    return d;
}

static int child(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSImage *icon = [NSApp applicationIconImage];
        CHECK(icon != nil);
        CHECK([icon size].width >= 128);  // the one icon in the file
        NSImage *named = [NSImage imageNamed:NSImageNameApplicationIcon];
        CHECK(named != nil);
        CHECK(named != nil && [named size].width == [icon size].width);
        // The icon file is also reachable by its name, with or without the extension.
        CHECK([NSImage imageNamed:@"testicon"] != nil);

        NSImage *custom = [[NSImage alloc] initWithSize:NSMakeSize(48, 48)];
        [NSApp setApplicationIconImage:custom];
        CHECK([[NSApp applicationIconImage] size].width == 48);
    }
    return failures ? 1 : 0;
}

int main(int argc, char **argv) {
    if (argc > 1 && strcmp(argv[1], "child") == 0) return child();
    int status = 1;
    @autoreleasepool {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"appicon-%d", getpid()]];
        NSString *app = [root stringByAppendingPathComponent:@"Probe.app/Contents"];
        [fm createDirectoryAtPath:[app stringByAppendingPathComponent:@"MacOS"] withIntermediateDirectories:YES attributes:nil error:NULL];
        [fm createDirectoryAtPath:[app stringByAppendingPathComponent:@"Resources"] withIntermediateDirectories:YES attributes:nil error:NULL];
        [@{@"CFBundleName": @"Probe", @"CFBundleIdentifier": @"test.appicon.probe", @"CFBundleExecutable": @"probe",
           @"CFBundlePackageType": @"APPL", @"CFBundleIconFile": @"testicon"}
            writeToFile:[app stringByAppendingPathComponent:@"Info.plist"] atomically:YES];
        [icns128() writeToFile:[app stringByAppendingPathComponent:@"Resources/testicon.icns"] atomically:YES];
        NSString *exe = [app stringByAppendingPathComponent:@"MacOS/probe"];
        [fm copyItemAtPath:[NSString stringWithUTF8String:argv[0]] toPath:exe error:NULL];
        chmod([exe fileSystemRepresentation], 0755);
        char *args[] = {(char *)[exe fileSystemRepresentation], "child", NULL};
        pid_t pid;
        if (posix_spawn(&pid, args[0], NULL, NULL, args, environ) == 0) {
            waitpid(pid, &status, 0);
            status = WIFEXITED(status) ? WEXITSTATUS(status) : 1;
        }
        [fm removeItemAtPath:root error:NULL];
    }
    if (status == 0) printf("PASS\n");
    return status;
}
