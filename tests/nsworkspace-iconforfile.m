// Copyright (C) 2026 Lubos Dolezel
//
// -[NSWorkspace iconForFile:] for application bundles, built in a temporary
// directory:
//  - an icon named by CFBundleIconFile that is a PNG file;
//  - an icon named without an extension that is an .icns file holding PNG
//    chunks (the largest chunk is used);
//  - CFBundleIconFiles listing candidates, the first that exists wins;
//  - repeated lookups return the same image object (cached);
//  - a truncated .icns file is not an icon and does not crash.
// With the argument "strict" it also checks that a bundle without any icon
// and a plain file give no image (Darling's behaviour; macOS hands out generic
// icons for both, so this is not part of the portable run).
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

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

static NSData *pngOfSize(int side) {
    NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL
                                                                     pixelsWide: side
                                                                     pixelsHigh: side
                                                                  bitsPerSample: 8
                                                                samplesPerPixel: 4
                                                                       hasAlpha: YES
                                                                       isPlanar: NO
                                                                 colorSpaceName: NSDeviceRGBColorSpace
                                                                    bytesPerRow: side * 4
                                                                   bitsPerPixel: 32] autorelease];
    memset([rep bitmapData], 0xff, (size_t) side * side * 4);
    return [rep representationUsingType: NSPNGFileType properties: @{}];
}

static void appendChunk(NSMutableData *icns, const char *type, NSData *payload) {
    uint32_t length = (uint32_t) ([payload length] + 8);
    unsigned char header[8] = {type[0], type[1], type[2], type[3], length >> 24, length >> 16, length >> 8, length};
    [icns appendBytes: header length: 8];
    [icns appendData: payload];
}

static NSData *icnsWithPNGs(NSArray *chunks /* of @[type, data] */) {
    NSMutableData *body = [NSMutableData data];
    for (NSArray *chunk in chunks)
        appendChunk(body, [chunk[0] UTF8String], chunk[1]);
    NSMutableData *icns = [NSMutableData data];
    uint32_t total = (uint32_t) ([body length] + 8);
    unsigned char header[8] = {'i', 'c', 'n', 's', total >> 24, total >> 16, total >> 8, total};
    [icns appendBytes: header length: 8];
    [icns appendData: body];
    return icns;
}

static NSString *makeApp(NSString *root, NSString *name, NSDictionary *info, NSDictionary *resources) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *app = [root stringByAppendingPathComponent: [name stringByAppendingString: @".app"]];
    NSString *res = [app stringByAppendingPathComponent: @"Contents/Resources"];
    [fm createDirectoryAtPath: res withIntermediateDirectories: YES attributes: nil error: NULL];
    [info writeToFile: [app stringByAppendingPathComponent: @"Contents/Info.plist"] atomically: YES];
    for (NSString *file in resources)
        [resources[file] writeToFile: [res stringByAppendingPathComponent: file] atomically: YES];
    return app;
}

int main(int argc, char **argv) {
    BOOL strict = argc > 1 && strcmp(argv[1], "strict") == 0;
    @autoreleasepool {
        NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent: [NSString stringWithFormat: @"iconforfile-%d", getpid()]];

        NSString *pngApp = makeApp(root, @"PNGIcon", @{@"CFBundleName" : @"PNGIcon", @"CFBundleIconFile" : @"icon.png"},
                                   @{@"icon.png" : pngOfSize(48)});
        NSImage *icon = [workspace iconForFile: pngApp];
        CHECK(icon != nil, "PNG icon file found");
        if (icon != nil) {
            CHECK([icon size].width == 48 && [icon size].height == 48, "PNG icon is 48x48 (%g x %g)", [icon size].width,
                  [icon size].height);
            CHECK([workspace iconForFile: pngApp] == icon, "second lookup returns the cached image");
        }

        NSData *icns = icnsWithPNGs(@[@[@"ic07", pngOfSize(128)], @[@"ic08", pngOfSize(256)], @[@"ic09", pngOfSize(512)]]);
        NSString *icnsApp = makeApp(root, @"ICNSIcon", @{@"CFBundleName" : @"ICNSIcon", @"CFBundleIconFile" : @"AppIcon"},
                                    @{@"AppIcon.icns" : icns});
        icon = [workspace iconForFile: icnsApp];
        CHECK(icon != nil, "icns icon (name without extension) found");
        if (icon != nil)
            CHECK([icon size].width == 512 && [icon size].height == 512, "the largest chunk wins (%g x %g)", [icon size].width,
                  [icon size].height);

        NSString *listApp = makeApp(root, @"ListIcon",
                                    @{@"CFBundleName" : @"ListIcon", @"CFBundleIconFiles" : @[@"missing.png", @"second.png"]},
                                    @{@"second.png" : pngOfSize(32)});
        icon = [workspace iconForFile: listApp];
        CHECK(icon != nil && [icon size].width == 32, "CFBundleIconFiles: the first candidate that exists is used");

        NSData *truncated = [icns subdataWithRange: NSMakeRange(0, [icns length] / 2)];
        NSString *brokenApp = makeApp(root, @"BrokenIcon", @{@"CFBundleName" : @"BrokenIcon", @"CFBundleIconFile" : @"Broken"},
                                      @{@"Broken.icns" : truncated});
        icon = [workspace iconForFile: brokenApp];
        (void) icon; // must not crash; a truncated container may or may not yield its first chunks

        if (strict) {
            NSString *bare = makeApp(root, @"NoIcon", @{@"CFBundleName" : @"NoIcon"}, @{});
            CHECK([workspace iconForFile: bare] == nil, "a bundle without an icon gives no image");
            NSString *plain = [root stringByAppendingPathComponent: @"plain.txt"];
            [@"x" writeToFile: plain atomically: YES encoding: NSUTF8StringEncoding error: NULL];
            CHECK([workspace iconForFile: plain] == nil, "a plain file gives no image");
        }

        [[NSFileManager defaultManager] removeItemAtPath: root error: NULL];
    }
    if (failures) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    puts("PASS: NSWorkspace iconForFile: for application bundles");
    return 0;
}
