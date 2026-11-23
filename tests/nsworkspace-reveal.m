// Copyright (C) 2026 Lubos Dolezel
// nsworkspace-reveal <dir>: -[NSWorkspace selectFile:inFileViewerRootedAtPath:] and activateFileViewerSelectingURLs:.
// <dir> holds two application bundles, not yet registered, whose executable is darling's tests/src/ae-receiver.m
// (it appends the events it gets to events.txt next to its bundle): finder/Finder.app (com.apple.finder) and
// viewer/Receiver.app (org.darlinghq.test.ae-receiver). The test:
//  - when no com.apple.finder is installed: registers finder/Finder.app, and checks
//    that selectFile: of a file gives "aevt odoc aapd bmrk:<file URL>" (the root path is not sent),
//    activateFileViewerSelectingURLs: of two files in different folders one event with both, in order, and
//    selectFile:nil "aevt rapp aapd"; where a Finder is installed (macOS) it prints SKIP for these;
//  - registers viewer/Receiver.app, sets NSFileViewer to its bundle ID and checks that a reveal goes to it.
// Prints "FAIL: ..." for each check that does not hold and exits 1 if any did. The receivers quit by themselves.
// Link with -framework AppKit -framework CoreServices. The macOS observations are in darling's tests/volumes.md.
#import <AppKit/AppKit.h>
#include <CoreServices/CoreServices.h>
#include <stdlib.h>

static int failures;

static void expect(BOOL ok, NSString *what)
{
    if (!ok)
    {
        printf("FAIL: %s\n", [what UTF8String]);
        failures++;
    }
}

// the lines of events.txt, once it has at least `count` of them (waiting up to 15 s)
static NSArray *waitForLines(NSString *path, NSUInteger count)
{
    NSArray *lines = @[];
    for (int i = 0; i < 150; i++)
    {
        NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
        lines = text.length ? [[text stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]] componentsSeparatedByString:@"\n"] : @[];
        if (lines.count >= count)
            break;
        usleep(100000);
    }
    return lines;
}

static NSString *item(NSString *path)
{
    return [@"bmrk:" stringByAppendingString:[[NSURL fileURLWithPath:path] absoluteString]];
}

int main(int argc, char **argv)
{
    if (argc != 2)
    {
        fprintf(stderr, "usage: nsworkspace-reveal <dir>\n");
        return 2;
    }
    @autoreleasepool
    {
        NSWorkspace *ws = [NSWorkspace sharedWorkspace];
        char real[PATH_MAX];
        if (realpath(argv[1], real) == NULL)
            return 2;
        NSString *dir = [NSString stringWithUTF8String:real];
        NSString *a = [dir stringByAppendingPathComponent:@"a.txt"];
        NSString *b = [dir stringByAppendingPathComponent:@"sub/b.txt"];
        [[NSFileManager defaultManager] createDirectoryAtPath:[dir stringByAppendingPathComponent:@"sub"] withIntermediateDirectories:YES attributes:nil error:NULL];
        [@"a" writeToFile:a atomically:NO encoding:NSUTF8StringEncoding error:NULL];
        [@"b" writeToFile:b atomically:NO encoding:NSUTF8StringEncoding error:NULL];

        if ([ws URLForApplicationWithBundleIdentifier:@"com.apple.finder"] == nil)
        {
            NSString *finder = [dir stringByAppendingPathComponent:@"finder/Finder.app"];
            NSString *events = [dir stringByAppendingPathComponent:@"finder/events.txt"];
            expect(LSRegisterURL((CFURLRef)[NSURL fileURLWithPath:finder], true) == noErr, @"Finder.app cannot be registered");

            expect([ws selectFile:a inFileViewerRootedAtPath:@"/"], @"selectFile: returns NO");
            NSArray *lines = waitForLines(events, 1);
            NSString *expected = [NSString stringWithFormat:@"aevt odoc aapd %@", item(a)];
            expect(lines.count == 1 && [lines[0] isEqual:expected], [NSString stringWithFormat:@"after selectFile: the events are %@", lines]);

            [ws activateFileViewerSelectingURLs:@[ [NSURL fileURLWithPath:a], [NSURL fileURLWithPath:b] ]];
            lines = waitForLines(events, 2);
            expected = [NSString stringWithFormat:@"aevt odoc aapd %@ %@", item(a), item(b)];
            expect(lines.count == 2 && [lines[1] isEqual:expected], [NSString stringWithFormat:@"after activateFileViewerSelectingURLs: the events are %@", lines]);

            expect([ws selectFile:nil inFileViewerRootedAtPath:dir], @"selectFile:nil returns NO");
            lines = waitForLines(events, 3);
            expect(lines.count == 3 && [lines[2] isEqual:@"aevt rapp aapd"], [NSString stringWithFormat:@"after selectFile:nil the events are %@", lines]);
        }
        else
            printf("SKIP: a Finder is installed; only NSFileViewer is checked\n");

        NSString *viewer = [dir stringByAppendingPathComponent:@"viewer/Receiver.app"];
        NSString *viewerEvents = [dir stringByAppendingPathComponent:@"viewer/events.txt"];
        expect(LSRegisterURL((CFURLRef)[NSURL fileURLWithPath:viewer], true) == noErr, @"Receiver.app cannot be registered");
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{ @"NSFileViewer": @"org.darlinghq.test.ae-receiver" }];
        expect([ws selectFile:a inFileViewerRootedAtPath:@""], @"selectFile: with NSFileViewer returns NO");
        NSArray *lines = waitForLines(viewerEvents, 1);
        NSString *expected = [NSString stringWithFormat:@"aevt odoc aapd %@", item(a)];
        expect(lines.count == 1 && [lines[0] isEqual:expected], [NSString stringWithFormat:@"with NSFileViewer the events are %@", lines]);
    }
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
