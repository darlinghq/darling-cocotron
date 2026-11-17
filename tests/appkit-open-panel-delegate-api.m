// Copyright (C) 2026 Lubos Dolezel
//
// The public NSOpenPanel API around navigation: directoryURL, the delegate's panel:shouldEnableURL: and
// panel:didChangeToDirectoryURL:, canChooseDirectories, allowedFileTypes and URLs. It runs unchanged on macOS;
// run with an argument of "log" to print the delegate traffic instead of checking it (that is how the expected
// values were observed on Mac OS X 10.14.4; black-box observation: no delegate calls before the panel is shown;
// once shown, panel:didChangeToDirectoryURL: for the starting directory and panel:shouldEnableURL: for its entries;
// setting directoryURL while shown reports the new directory, and setting the current one again reports nothing;
// directoryURL answers with the symlink-resolved path, and before the panel is shown with the default folder).
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
static BOOL logOnly;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

@interface Delegate : NSObject <NSOpenSavePanelDelegate> {
@public
    NSMutableArray *events;
}
@end

@implementation Delegate
- (instancetype) init {
    if ((self = [super init]))
        events = [NSMutableArray new];
    return self;
}
- (BOOL) panel: (id) sender shouldEnableURL: (NSURL *) url {
    [events addObject: [@"enable " stringByAppendingString: [url lastPathComponent]]];
    return ![[url lastPathComponent] isEqual: @"b.txt"];
}
- (void) panel: (id) sender didChangeToDirectoryURL: (NSURL *) url {
    [events addObject: [@"changed " stringByAppendingString: [url lastPathComponent]]];
}
- (void) panelSelectionDidChange: (id) sender {
    [events addObject: @"selection"];
}
@end

static void spin(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

static NSUInteger count(NSArray *events, NSString *event) {
    NSUInteger n = 0;
    for (NSString *e in events)
        if ([e isEqual: event])
            n++;
    return n;
}

static void dump(const char *phase, Delegate *d) {
    printf("%s: %s\n", phase, [[d->events componentsJoinedByString: @", "] UTF8String]);
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        logOnly = argc > 1;
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];

        NSString *root = [[NSTemporaryDirectory() stringByResolvingSymlinksInPath] stringByAppendingPathComponent:
                [NSString stringWithFormat: @"openpanel-api-%d", getpid()]];
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm createDirectoryAtPath: [root stringByAppendingPathComponent: @"sub"]
                withIntermediateDirectories: YES attributes: nil error: nil];
        for (NSString *name in @[ @"a.txt", @"b.txt", @"c.png", @"sub/d.txt" ])
            [@"x" writeToFile: [root stringByAppendingPathComponent: name] atomically: NO
                      encoding: NSUTF8StringEncoding error: nil];
        NSURL *rootURL = [NSURL fileURLWithPath: root isDirectory: YES];
        NSURL *subURL = [NSURL fileURLWithPath: [root stringByAppendingPathComponent: @"sub"] isDirectory: YES];

        // Folders such as applications are packages, which the panel treats as files.
        NSString *bundlePath = [root stringByAppendingPathComponent: @"tool.app"];
        [fm createDirectoryAtPath: bundlePath withIntermediateDirectories: YES attributes: nil error: nil];
        CHECK([[NSWorkspace sharedWorkspace] isFilePackageAtPath: bundlePath]);
        CHECK(![[NSWorkspace sharedWorkspace] isFilePackageAtPath: [root stringByAppendingPathComponent: @"sub"]]);
        CHECK(![[NSWorkspace sharedWorkspace] isFilePackageAtPath: [root stringByAppendingPathComponent: @"a.txt"]]);

        NSOpenPanel *panel = [NSOpenPanel openPanel];
        Delegate *d = [Delegate new];
        [panel performSelector: @selector(setDelegate:) withObject: d];

        // The defaults.
        CHECK([panel canChooseFiles] && ![panel canChooseDirectories] && ![panel allowsMultipleSelection]);
        CHECK([[panel URLs] count] == 0);
        [panel setAllowsMultipleSelection: YES];
        CHECK([panel allowsMultipleSelection]);
        [panel setAllowsMultipleSelection: NO];

        [panel setDirectoryURL: rootURL];
        // (macOS 10.14.4 answers with its default folder here, until the panel is shown; not asserted.)
        if (logOnly) { dump("setDirectoryURL before showing", d); printf("directoryURL right after set: %s (set %s)\n", [[[panel directoryURL] path] UTF8String], [root UTF8String]); }
        CHECK([d->events count] == 0);
        [d->events removeAllObjects];

        [panel setCanChooseDirectories: YES];
        CHECK([panel canChooseDirectories]);
        [panel setAllowedFileTypes: @[ @"txt" ]];
        CHECK([[panel allowedFileTypes] isEqual: @[ @"txt" ]]);

        __block NSInteger result = -1;
        [panel beginWithCompletionHandler: ^(NSModalResponse r) { result = r; }];
        spin(1.5);
        if (logOnly) dump("after beginWithCompletionHandler", d);
        CHECK([[[[panel directoryURL] path] stringByResolvingSymlinksInPath] isEqual: [root stringByResolvingSymlinksInPath]]);
        // The delegate is asked about the entries of the directory the panel shows.
        CHECK(count(d->events, @"enable a.txt") >= 1);
        CHECK(count(d->events, @"enable sub") >= 1);
        [d->events removeAllObjects];

        [panel setDirectoryURL: subURL];
        spin(1.0);
        if (logOnly) dump("setDirectoryURL while showing", d);
        CHECK(count(d->events, @"changed sub") >= 1);
        CHECK(count(d->events, @"enable d.txt") >= 1);
        CHECK([[[[panel directoryURL] path] stringByResolvingSymlinksInPath] isEqual: [[subURL path] stringByResolvingSymlinksInPath]]);
        [d->events removeAllObjects];

        [panel setDirectoryURL: rootURL];
        spin(1.0);
        CHECK(count(d->events, [@"changed " stringByAppendingString: [root lastPathComponent]]) >= 1);
        [d->events removeAllObjects];

        [panel setDirectoryURL: rootURL];
        spin(0.5);
        if (logOnly) dump("setDirectoryURL to the same directory", d);
        CHECK(count(d->events, [@"changed " stringByAppendingString: [root lastPathComponent]]) == 0);

        [panel performSelector: @selector(cancel:) withObject: nil];
        spin(0.5);
        if (logOnly) printf("result %ld, URLs %lu, directoryURL %s\n", (long)result, (unsigned long)[[panel URLs] count],
                            [[[panel directoryURL] path] UTF8String]);
        CHECK(result == NSModalResponseCancel);
        [fm removeItemAtPath: root error: nil];
    }
    if (failures == 0)
        puts("PASS");
    return failures != 0;
}
