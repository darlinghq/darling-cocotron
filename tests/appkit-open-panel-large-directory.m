// Copyright (C) 2026 Lubos Dolezel
//
// An open panel listing a folder with thousands of entries uses little memory per entry: the panel is
// pointed at a folder of 8000 files and folders (half of them folders), shows all of them as rows, and the
// process stays under a resident-size limit that allows for the application itself, the panel and a
// small cost per entry. Listing the folder with URLs that carry properties cost several kilobytes per entry.
// Usage: appkit-open-panel-large-directory [files] [limit in MB] [existing folder]. Needs a display.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <mach/mach.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

static int failures;
#define CHECK(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

static void collect(NSView *view, Class cls, NSMutableArray *out) {
    if ([view isKindOfClass: cls])
        [out addObject: view];
    for (NSView *sub in [view subviews])
        collect(sub, cls, out);
}

static long residentMegabytes(void) {
    mach_task_basic_info_data_t info;
    mach_msg_type_number_t size = MACH_TASK_BASIC_INFO_COUNT;
    if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t) &info, &size) != KERN_SUCCESS)
        return -1;
    return (long) (info.resident_size / (1024 * 1024));
}

int main(int argc, char **argv) {
    @autoreleasepool {
        int count = argc > 1 ? atoi(argv[1]) : 8000;
        long limit = argc > 2 ? atol(argv[2]) : 400;
        [NSApplication sharedApplication];

        NSFileManager *fm = [NSFileManager defaultManager];
        // an existing folder of "count" visible entries may be given instead of one being generated
        BOOL given = argc > 3;
        NSString *root = given ? [NSString stringWithUTF8String: argv[3]]
                               : [NSTemporaryDirectory() stringByAppendingPathComponent:
                                         [NSString stringWithFormat: @"open-panel-large-%d", getpid()]];
        [fm createDirectoryAtPath: root withIntermediateDirectories: YES attributes: nil error: nil];
        for (int i = 0; i < count && !given; i++) {
            // half of the entries are folders, as in a folder of build or session directories
            NSString *name = [NSString stringWithFormat: @"entry-%06d.%s", i, i % 3 ? "txt" : "png"];
            const char *path = [[root stringByAppendingPathComponent: name] fileSystemRepresentation];
            if (i % 2) {
                mkdir(path, 0755);
            } else {
                int fd = open(path, O_WRONLY | O_CREAT, 0644);
                if (fd >= 0)
                    close(fd);
            }
        }

        NSOpenPanel *panel = [NSOpenPanel openPanel];
        [panel setDirectoryURL: [NSURL fileURLWithPath: root isDirectory: YES]];
        [panel beginWithCompletionHandler: ^(NSModalResponse r) {}];
        [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 3]];

        NSMutableArray *lists = [NSMutableArray array];
        collect([panel contentView], [NSOutlineView class], lists);
        NSOutlineView *list = [lists firstObject];
        CHECK(list != nil);
        CHECK([list numberOfRows] == count);
        // scroll through the whole list so that every row is drawn once
        for (NSInteger row = 0; row < [list numberOfRows]; row += 200) {
            [list scrollRowToVisible: row];
            [list displayIfNeeded];
        }
        long mb = residentMegabytes();
        printf("resident size: %ld MB for %d files (limit %ld MB)\n", mb, count, limit);
        CHECK(mb < limit);

        [panel cancel: nil];
        if (!given)
            [fm removeItemAtPath: root error: nil];
    }
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
