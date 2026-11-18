// Copyright (C) 2026 Lubos Dolezel
//
// A panel that has only been created is not on screen and does not cost the memory of a displayed
// window, and a panel listing a large folder costs little per entry.
//  1. +[NSSavePanel savePanel] and +[NSOpenPanel openPanel] return windows that are not visible
//     (macOS only shows a panel when it is run or begun). Presenting the first window brings up the
//     software OpenGL renderer, which used to happen just by creating a panel, so creating both
//     panels must stay under 40 MB of extra resident memory.
//  2. An open panel on a folder of 10000 entries costs less than 12 MB more than an open panel on an
//     empty folder opened right before it. Each entry used to cost kilobytes of temporary names that
//     sorting the folder left behind (the growth varies by a few MB between runs).
// Usage: appkit-startup-memory [panel limit in MB] [entries limit in MB]. Needs a display.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <mach/mach.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

static int failures;
#define CHECK(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

static long residentKilobytes(void) {
    mach_task_basic_info_data_t info;
    mach_msg_type_number_t size = MACH_TASK_BASIC_INFO_COUNT;
    if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t) &info, &size) != KERN_SUCCESS)
        return -1;
    return (long) (info.resident_size / 1024);
}

static void listFolder(NSString *folder) {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setDirectoryURL: [NSURL fileURLWithPath: folder isDirectory: YES]];
    [panel beginWithCompletionHandler: ^(NSModalResponse r) {}];
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 3]];
    [panel cancel: nil];
}

int main(int argc, char **argv) {
    @autoreleasepool {
        long panelLimit = argc > 1 ? atol(argv[1]) : 40;
        long entriesLimit = argc > 2 ? atol(argv[2]) : 12;
        [NSApplication sharedApplication];

        long before = residentKilobytes();
        NSSavePanel *save = [NSSavePanel savePanel];
        NSOpenPanel *openP = [NSOpenPanel openPanel];
        long created = residentKilobytes() - before;
        printf("panels created: +%ld KB (limit %ld MB)\n", created, panelLimit);
        CHECK(![save isVisible]);
        CHECK(![openP isVisible]);
        CHECK(created < panelLimit * 1024);

        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *base = [NSTemporaryDirectory() stringByAppendingPathComponent:
                [NSString stringWithFormat: @"startup-memory-%d", getpid()]];
        NSString *empty = [base stringByAppendingPathComponent: @"empty"];
        NSString *empty2 = [base stringByAppendingPathComponent: @"empty2"];
        NSString *big = [base stringByAppendingPathComponent: @"big"];
        [fm createDirectoryAtPath: empty withIntermediateDirectories: YES attributes: nil error: nil];
        [fm createDirectoryAtPath: empty2 withIntermediateDirectories: YES attributes: nil error: nil];
        [fm createDirectoryAtPath: big withIntermediateDirectories: YES attributes: nil error: nil];
        for (int i = 0; i < 10000; i++) {
            NSString *name = [NSString stringWithFormat: @"entry-%06d.%s", i, i % 3 ? "txt" : "png"];
            const char *path = [[big stringByAppendingPathComponent: name] fileSystemRepresentation];
            if (i % 2) {
                mkdir(path, 0755);
            } else {
                int fd = open(path, O_WRONLY | O_CREAT, 0644);
                if (fd >= 0)
                    close(fd);
            }
        }

        listFolder(empty);
        long afterEmpty = residentKilobytes();
        listFolder(empty2);
        long afterEmpty2 = residentKilobytes();
        listFolder(big);
        long entries = (residentKilobytes() - afterEmpty2) - (afterEmpty2 - afterEmpty);
        printf("10000 entries: +%ld KB over an empty folder (limit %ld MB)\n", entries, entriesLimit);
        CHECK(entries < entriesLimit * 1024);
        [fm removeItemAtPath: base error: nil];
    }
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
