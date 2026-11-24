/* Copyright (C) 2026 Lubos Dolezel

   Licensed under the MIT license, the same as the rest of this project. */

// The text container of NSTextView made with -initWithFrame:, and what the resizable setters leave alone.
// On macOS 26.7.3 and 10.14.4 (x86_64, i386; black-box observation) the container is as wide as the view and
// 10000000 points tall, follows the width of the view and not its height, the view is vertically
// resizable and not horizontally, and -setVerticallyResizable: and -setHorizontallyResizable: do not change
// the tracking flags of the container; a container made by the NSTextContainer initializers tracks neither (and -init makes it 10000000 by
// 10000000), and the window's field editor tracks neither.
// Build without ARC.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(...) do { if (!(__VA_ARGS__)) { printf("FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSTextContainer *plain = [[[NSTextContainer alloc] init] autorelease];
        CHECK(![plain widthTracksTextView] && ![plain heightTracksTextView]);
        CHECK([plain containerSize].width == 10000000 && [plain containerSize].height == 10000000);
        plain = [[[NSTextContainer alloc] initWithContainerSize:NSMakeSize(100, 100)] autorelease];
        CHECK(![plain widthTracksTextView] && ![plain heightTracksTextView]);
        CHECK([plain containerSize].width == 100 && [plain containerSize].height == 100);

        NSTextView *view = [[[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)] autorelease];
        NSTextContainer *container = [view textContainer];
        CHECK([container containerSize].width == 200);
        CHECK([container containerSize].height == 10000000);
        CHECK([container widthTracksTextView]);
        CHECK(![container heightTracksTextView]);
        CHECK([view isVerticallyResizable] && ![view isHorizontallyResizable]);

        [view setVerticallyResizable:YES];
        [view setHorizontallyResizable:YES];
        CHECK([container widthTracksTextView] && ![container heightTracksTextView]);
        [view setHorizontallyResizable:NO];
        [view setVerticallyResizable:NO];
        CHECK([container widthTracksTextView] && ![container heightTracksTextView]);
        [container setHeightTracksTextView:YES];
        [view setVerticallyResizable:YES];
        CHECK([container heightTracksTextView]);

        // The window's field editor follows neither the width nor the height.
        NSWindow *window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 100, 100) styleMask:NSWindowStyleMaskTitled
                                                          backing:NSBackingStoreBuffered defer:YES] autorelease];
        NSTextView *editor = (NSTextView *)[window fieldEditor:YES forObject:nil];
        CHECK(![[editor textContainer] widthTracksTextView] && ![[editor textContainer] heightTracksTextView]);

        NSTextView *given = [[[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)
                                                 textContainer:[[[NSTextContainer alloc] initWithContainerSize:NSMakeSize(200, 10000000)] autorelease]] autorelease];
        CHECK(![[given textContainer] widthTracksTextView] && ![[given textContainer] heightTracksTextView]);
    }
    if (failures)
        return 1;
    printf("PASS\n");
    return 0;
}
