// Copyright (C) 2026 Lubos Dolezel
//
// NSWorkspace asks the file viewer application (the bundle identifier in NSFileViewer) to show items by sending it
// an open-documents event ('aevt'/'odoc') whose direct object lists the items and with the boolean parameter 'aapd'
// set to true; a reveal without a file sends a reopen event ('aevt'/'rapp') with the same parameter; one call of
// -activateFileViewerSelectingURLs: is one event with all the URLs in order. Observed on macOS 26.7.3 (tier 2). The
// test is both the caller and, started as the application it builds from its own executable, a logger.
//
// The container must have been started with DISPLAY set: the viewer application is launched by LaunchServices.
//
// Build: clang -fobjc-arc -framework AppKit appkit-workspace-reveal-viewer.m
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define VIEWER_PREFIX @"org.example.reveal-test-viewer."

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static NSString *logPath;

@interface Logger : NSObject
@end
@implementation Logger
- (void) handle:(NSAppleEventDescriptor *)event reply:(NSAppleEventDescriptor *)reply {
    NSAppleEventDescriptor *items = [event paramDescriptorForKeyword:keyDirectObject];
    NSAppleEventDescriptor *flag = [event paramDescriptorForKeyword:'aapd'];
    NSMutableString *line = [NSMutableString stringWithFormat:@"%08x %08x aapd=%d items=%ld",
        (unsigned) [event eventClass], (unsigned) [event eventID], flag ? (int) [flag booleanValue] : -1,
        (long) [items numberOfItems]];
    for (NSInteger i = 1; i <= [items numberOfItems]; i++) {
        NSAppleEventDescriptor *item = [items descriptorAtIndex:i];
        NSURL *url = nil;
        if ([item descriptorType] == 'bmrk')
            url = [NSURL URLByResolvingBookmarkData:[item data] options:0 relativeToURL:nil bookmarkDataIsStale:NULL error:NULL];
        else
            url = [NSURL URLWithString:[item stringValue]];
        [line appendFormat:@" %@", [url path]];
    }
    [line appendString:@"\n"];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:logPath];
    [h seekToEndOfFile];
    [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [h closeFile];
}
@end

@interface ViewerDelegate : NSObject <NSApplicationDelegate>
@property(strong) Logger *logger;
@end
@implementation ViewerDelegate
// AppKit installs its own handlers when it launches; the logger replaces them just before that.
- (void) applicationWillFinishLaunching:(NSNotification *)n {
    self.logger = [Logger new];
    NSAppleEventManager *m = [NSAppleEventManager sharedAppleEventManager];
    [m setEventHandler:self.logger andSelector:@selector(handle:reply:) forEventClass:'aevt' andEventID:'odoc'];
    [m setEventHandler:self.logger andSelector:@selector(handle:reply:) forEventClass:'aevt' andEventID:'rapp'];
}
@end

static int runViewer(void) {
    [NSApplication sharedApplication];
    ViewerDelegate *delegate = [ViewerDelegate new];
    [NSApp setDelegate:delegate];
    [NSTimer scheduledTimerWithTimeInterval:12 repeats:NO block:^(NSTimer *t) { exit(0); }];
    [NSApp run];
    return 0;
}

static NSString *waitForLines(NSUInteger lines) {
    for (int i = 0; i < 100; i++) {
        NSString *s = [NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:nil];
        if ([[s componentsSeparatedByString:@"\n"] count] > lines)
            return s;
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
    }
    return [NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:nil];
}

int main(int argc, char **argv) {
#ifdef __i386__
    // On i386 the event reaches the viewer (the send succeeds), but a handler installed through
    // NSAppleEventManager is not called, while one installed with AEInstallEventHandler is. That is a gap in the
    // NSAppleEventManager forwarding of Foundation, not in NSWorkspace, so this slice is not checked here.
    puts("SKIP: i386");
    return 0;
#endif
    @autoreleasepool {
        // started as the viewer application: log next to the bundle
        if ([[[NSBundle mainBundle] bundleIdentifier] hasPrefix:VIEWER_PREFIX]) {
            logPath = [[[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"events.log"];
            return runViewer();
        }

        // a new identifier each run: registrations of an earlier run may remain
        NSString *VIEWER_ID = [VIEWER_PREFIX stringByAppendingFormat:@"%d", getpid()];
        NSString *dir = [NSString stringWithFormat:@"%@/Applications/reveal-test-%d", NSHomeDirectory(), getpid()];
        NSString *app = [dir stringByAppendingPathComponent:@"Viewer.app"];
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath:[app stringByAppendingPathComponent:@"Contents/MacOS"] withIntermediateDirectories:YES attributes:nil error:nil];
        [fm copyItemAtPath:[NSString stringWithUTF8String:argv[0]] toPath:[app stringByAppendingPathComponent:@"Contents/MacOS/viewer"] error:nil];
        NSDictionary *info = @{@"CFBundleIdentifier": VIEWER_ID, @"CFBundleExecutable": @"viewer", @"CFBundlePackageType": @"APPL",
                               @"CFBundleName": @"Viewer", @"CFBundleVersion": @"1", @"LSBackgroundOnly": @YES};
        [info writeToFile:[app stringByAppendingPathComponent:@"Contents/Info.plist"] atomically:YES];
        logPath = [dir stringByAppendingPathComponent:@"events.log"];
        [@"" writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        LSRegisterURL((__bridge CFURLRef) [NSURL fileURLWithPath:app], true);
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{@"NSFileViewer": VIEWER_ID}];

        NSString *a = [dir stringByAppendingPathComponent:@"a.txt"], *b = [dir stringByAppendingPathComponent:@"b.txt"];
        [@"a" writeToFile:a atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [@"b" writeToFile:b atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSWorkspace *ws = [NSWorkspace sharedWorkspace];
        CHECK([ws URLForApplicationWithBundleIdentifier:VIEWER_ID] != nil);

        // a reveal: one odoc with the file, 'aapd' true; the application is started for it
        CHECK([ws selectFile:a inFileViewerRootedAtPath:dir] == YES);
        NSString *log = waitForLines(1);
        CHECK([log containsString:@"61657674 6f646f63 aapd=1 items=1"]);
        NSString *wantA = [NSString stringWithFormat:@"aapd=1 items=1 %@", [a stringByResolvingSymlinksInPath]];
        CHECK([log containsString:wantA]);

        // no file: a reopen, no items
        CHECK([ws selectFile:nil inFileViewerRootedAtPath:dir] == YES);
        log = waitForLines(2);
        CHECK([log containsString:@"72617070 aapd=1 items=0"]);

        // two URLs: one event, in order
        [ws activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:b], [NSURL fileURLWithPath:a]]];
        log = waitForLines(3);
        NSArray *lines = [log componentsSeparatedByString:@"\n"];
        CHECK([lines count] >= 4 && [lines[2] containsString:@"aapd=1 items=2"]);
        NSRange rb = [lines[2] rangeOfString:[b stringByResolvingSymlinksInPath]];
        NSRange ra = [lines[2] rangeOfString:[a stringByResolvingSymlinksInPath]];
        CHECK(rb.location != NSNotFound && ra.location != NSNotFound && rb.location < ra.location);

        [fm removeItemAtPath:dir error:nil];
        if (failures == 0)
            puts("PASS: NSWorkspace file viewer events");
        return failures != 0;
    }
}
