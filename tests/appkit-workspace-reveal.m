// Copyright (C) 2026 Lubos Dolezel
//
// -[NSWorkspace selectFile:inFileViewerRootedAtPath:] and -activateFileViewerSelectingURLs: ask the file viewer
// (the application named by NSFileViewer, else the Finder) to show items; where it is not installed they must not
// raise and the first returns YES, as documented and as observed on macOS 26.7.3 (an unknown NSFileViewer bundle
// identifier is logged and not an error). The test names a viewer that does not exist, so that nothing is shown on
// a Mac (do not run it against a real Finder: it would open windows). Nothing is returned for nil arguments.
//
// Build: clang -fobjc-arc -framework AppKit appkit-workspace-reveal.m
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{@"NSFileViewer": @"org.example.no-such-file-viewer"}];
        NSWorkspace *ws = [NSWorkspace sharedWorkspace];
        NSString *dir = NSTemporaryDirectory();
        NSString *file = [dir stringByAppendingPathComponent:@"reveal-test.txt"];
        [@"x" writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil];

        @try {
            CHECK([ws selectFile:file inFileViewerRootedAtPath:@""] == YES);
            CHECK([ws selectFile:file inFileViewerRootedAtPath:dir] == YES);
            CHECK([ws selectFile:nil inFileViewerRootedAtPath:dir] == YES);
            CHECK([ws selectFile:nil inFileViewerRootedAtPath:nil] == NO);
            [ws activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:file], [NSURL fileURLWithPath:dir]]];
            [ws activateFileViewerSelectingURLs:@[]];
        } @catch (NSException *e) {
            fprintf(stderr, "FAIL: raised %s\n", [[e description] UTF8String]);
            failures++;
        }
        [[NSFileManager defaultManager] removeItemAtPath:file error:nil];
        if (failures == 0)
            puts("PASS: NSWorkspace file viewer");
        return failures != 0;
    }
}
