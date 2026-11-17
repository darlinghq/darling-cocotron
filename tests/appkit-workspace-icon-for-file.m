// Copyright (C) 2026 Lubos Dolezel
//
// -[NSWorkspace iconForFile:] returns an icon for any path: an existing file, a directory, a path that does
// not exist (the icon of its filename extension) and even an empty path (a generic icon). It is never nil.
// -[NSWorkspace iconForFiles:] returns one icon for a single file and for a group. Icons are 32 x 32 points.
// Checked on macOS 10.14.4 and 26.7.3.
//
// Build: clang -fobjc-arc -framework AppKit appkit-workspace-icon-for-file.m
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static void checkIcon(NSImage *icon, const char *what) {
    if (icon == nil) {
        fprintf(stderr, "FAIL %s: nil icon\n", what);
        failures++;
        return;
    }
    if (!NSEqualSizes([icon size], NSMakeSize(32, 32))) {
        fprintf(stderr, "FAIL %s: size %s\n", what, [NSStringFromSize([icon size]) UTF8String]);
        failures++;
    }
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                [NSString stringWithFormat: @"icon-for-file-%d", getpid()]];
        NSString *file = [dir stringByAppendingPathComponent: @"archive.zip"];
        [[NSFileManager defaultManager] createDirectoryAtPath: dir withIntermediateDirectories: YES
                                                   attributes: nil error: nil];
        CHECK([@"x" writeToFile: file atomically: YES encoding: NSUTF8StringEncoding error: nil]);

        checkIcon([workspace iconForFile: file], "existing file");
        checkIcon([workspace iconForFile: dir], "directory");
        checkIcon([workspace iconForFile: [dir stringByAppendingPathComponent: @"missing.7z"]], "missing file");
        checkIcon([workspace iconForFile: @"/nonexistent-directory/missing"], "missing file without extension");
        checkIcon([workspace iconForFile: @""], "empty path");
        checkIcon([workspace iconForFiles: @[ file ]], "one file");
        checkIcon([workspace iconForFiles: @[ file, dir ]], "two files");

        [[NSFileManager defaultManager] removeItemAtPath: dir error: nil];
    }
    if (failures == 0)
        puts("PASS");
    return failures != 0;
}
