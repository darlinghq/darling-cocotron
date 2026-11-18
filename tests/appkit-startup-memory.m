// Copyright (C) 2026 Lubos Dolezel
//
// A panel that has only been created is not on screen and does not cost the memory of a displayed
// window: +[NSSavePanel savePanel] and +[NSOpenPanel openPanel] return windows that are not visible
// (macOS only shows a panel when it is run or begun). Presenting the first window brings up the
// software OpenGL renderer, which used to happen just by creating a panel, so creating both panels
// must stay under 40 MB of extra resident memory.
// Usage: appkit-startup-memory [limit in MB]. Needs a display.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>
#include <mach/mach.h>

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
        [NSApplication sharedApplication];

        long before = residentKilobytes();
        NSSavePanel *save = [NSSavePanel savePanel];
        NSOpenPanel *openP = [NSOpenPanel openPanel];
        long created = residentKilobytes() - before;
        printf("panels created: +%ld KB (limit %ld MB)\n", created, panelLimit);
        CHECK(![save isVisible]);
        CHECK(![openP isVisible]);
        CHECK(created < panelLimit * 1024);
    }
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
