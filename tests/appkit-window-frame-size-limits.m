// The window system limits user resizing to the sizes NSWindow derives from minSize, maxSize,
// contentMinSize and contentMaxSize. The frame sizes: minSize and maxSize are frame sizes
// (https://developer.apple.com/documentation/appkit/nswindow/minsize), while contentMinSize and
// contentMaxSize are sizes of the content view and take precedence over them
// (https://developer.apple.com/documentation/appkit/nswindow/contentminsize), so the frame size
// is the content size plus what the frame adds around the content.
// Build: guest-cc.sh -o t appkit-window-frame-size-limits.m -framework Cocoa
#import <Cocoa/Cocoa.h>
#include <float.h>

@interface NSWindow (FrameSizeLimitsFixture)
- (NSSize) _minFrameSize;
- (NSSize) _maxFrameSize;
- (void) platformWindow:(id)window frameChanged:(NSRect)frame didSize:(BOOL)didSize;
@end

static int failures;
#define CHECK(c, ...) do { if (!(c)) { failures++; printf("FAIL line %d: ", __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 400, 300)
                                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                                    backing:NSBackingStoreBuffered defer:YES];
        NSSize chrome = [w frameRectForContentRect:NSZeroRect].size;

        CHECK(NSEqualSizes([w _minFrameSize], NSZeroSize), "no minimum by default, got %s", NSStringFromSize([w _minFrameSize]).UTF8String);
        CHECK([w _maxFrameSize].width >= FLT_MAX && [w _maxFrameSize].height >= FLT_MAX, "no maximum by default, got %s", NSStringFromSize([w _maxFrameSize]).UTF8String);

        [w setMinSize:NSMakeSize(200, 150)];
        [w setMaxSize:NSMakeSize(800, 600)];
        CHECK(NSEqualSizes([w _minFrameSize], NSMakeSize(200, 150)), "minSize is a frame size, got %s", NSStringFromSize([w _minFrameSize]).UTF8String);
        CHECK(NSEqualSizes([w _maxFrameSize], NSMakeSize(800, 600)), "maxSize is a frame size, got %s", NSStringFromSize([w _maxFrameSize]).UTF8String);

        [w setContentMinSize:NSMakeSize(250, 180)];
        [w setContentMaxSize:NSMakeSize(700, 500)];
        NSSize min = [w _minFrameSize], max = [w _maxFrameSize];
        CHECK(NSEqualSizes(min, NSMakeSize(250 + chrome.width, 180 + chrome.height)), "contentMinSize takes precedence and includes the frame, got %s", NSStringFromSize(min).UTF8String);
        CHECK(NSEqualSizes(max, NSMakeSize(700 + chrome.width, 500 + chrome.height)), "contentMaxSize takes precedence and includes the frame, got %s", NSStringFromSize(max).UTF8String);

        [w setContentMinSize:NSMakeSize(250, 0)];
        CHECK([w _minFrameSize].width == 250 + chrome.width && [w _minFrameSize].height == 150, "each dimension decides on its own, got %s", NSStringFromSize([w _minFrameSize]).UTF8String);

        // The window system's frame changes are limited when they resize the window, not when they only move it.
        NSWindow *m = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 400, 300)
                                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                                    backing:NSBackingStoreBuffered defer:YES];
        NSSize before = [m frame].size;
        [m setContentMinSize:NSMakeSize(before.width + 100, before.height + 100)];
        NSRect moved = [m frame];
        moved.origin.x += 40;
        [m platformWindow:nil frameChanged:moved didSize:NO];
        CHECK(NSEqualSizes([m frame].size, before), "a move leaves the size alone, got %s", NSStringFromSize([m frame].size).UTF8String);
        CHECK([m frame].origin.x == moved.origin.x, "a move moves the window");
        [m platformWindow:nil frameChanged:[m frame] didSize:YES];
        CHECK([m frame].size.width >= [m _minFrameSize].width && [m frame].size.height >= [m _minFrameSize].height, "a resize is limited, got %s", NSStringFromSize([m frame].size).UTF8String);
    }
    printf(failures ? "FAILED\n" : "PASSED\n");
    return failures != 0;
}
