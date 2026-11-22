// The window system limits user resizing to the sizes NSWindow derives from minSize, maxSize,
// contentMinSize and contentMaxSize. minSize and maxSize are frame sizes
// (https://developer.apple.com/documentation/appkit/nswindow/minsize), while contentMinSize and
// contentMaxSize are sizes of the content view
// (https://developer.apple.com/documentation/appkit/nswindow/contentminsize), so the frame size
// is the content size plus what the frame adds around the content.
// The documentation lists them as separate properties. Observed on macOS 26.7.3 (black-box probe,
// QUIRK), they are two views of one limit, and the last one set wins:
//   a titled window has minSize {0, 32} and contentMinSize {0, 0} by default (32 = the title bar);
//   setMinSize 300x200 gives contentMinSize 300x168, then setContentMinSize 100x100 gives minSize 100x132;
//   setMinSize 50x50 gives contentMinSize 50x18, setMinSize -5x-5 gives contentMinSize {0, 0};
//   setMaxSize 800x600 gives contentMaxSize 800x568, setContentMaxSize 1000x900 gives maxSize 1000x932,
//   setMaxSize 0x0 gives contentMaxSize 0x-32 (a maximum is not clamped), FLT_MAX stays FLT_MAX;
//   the content limit is what is kept: with contentMinSize 300x200, a borderless style reports minSize
//   300x200 and the titled style again 300x232.
// Checks marked quirk_ pin these; the others pin the frame sizes handed to the window system.
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
#define SIZE(s) NSStringFromSize(s).UTF8String

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 400, 300)
                                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                                    backing:NSBackingStoreBuffered defer:YES];
        NSSize c = [w frameRectForContentRect:NSZeroRect].size;

        // Defaults.
        CHECK(NSEqualSizes([w contentMinSize], NSZeroSize), "quirk_default_content_min, got %s", SIZE([w contentMinSize]));
        CHECK(NSEqualSizes([w minSize], c), "quirk_default_min_is_the_frame_chrome, got %s", SIZE([w minSize]));
        CHECK([w contentMaxSize].width == FLT_MAX && [w contentMaxSize].height == FLT_MAX, "quirk_default_content_max_is_FLT_MAX, got %s", SIZE([w contentMaxSize]));
        CHECK([w maxSize].width == FLT_MAX && [w maxSize].height == FLT_MAX, "default_max_is_FLT_MAX, got %s", SIZE([w maxSize]));
        CHECK(NSEqualSizes([w _minFrameSize], NSZeroSize), "no minimum is handed to the window system by default, got %s", SIZE([w _minFrameSize]));
        CHECK([w _maxFrameSize].width >= FLT_MAX && [w _maxFrameSize].height >= FLT_MAX, "no maximum is handed to the window system by default, got %s", SIZE([w _maxFrameSize]));

        // Minimum: one limit seen from the frame and from the content.
        [w setMinSize:NSMakeSize(300, 200)];
        CHECK(NSEqualSizes([w minSize], NSMakeSize(300, 200)), "setMinSize is returned by minSize, got %s", SIZE([w minSize]));
        CHECK(NSEqualSizes([w contentMinSize], NSMakeSize(300 - c.width, 200 - c.height)), "quirk_setMinSize_sets_contentMinSize, got %s", SIZE([w contentMinSize]));
        CHECK(NSEqualSizes([w _minFrameSize], NSMakeSize(300, 200)), "the minimum handed to the window system, got %s", SIZE([w _minFrameSize]));
        [w setContentMinSize:NSMakeSize(100, 100)];
        CHECK(NSEqualSizes([w minSize], NSMakeSize(100 + c.width, 100 + c.height)), "quirk_setContentMinSize_sets_minSize_last_call_wins, got %s", SIZE([w minSize]));
        CHECK(NSEqualSizes([w _minFrameSize], NSMakeSize(100 + c.width, 100 + c.height)), "the content minimum wins at the window system, got %s", SIZE([w _minFrameSize]));
        [w setMinSize:NSMakeSize(50, 50)];
        CHECK(NSEqualSizes([w contentMinSize], NSMakeSize(MAX(0, 50 - c.width), MAX(0, 50 - c.height))), "quirk_min_below_the_chrome_is_zero_content, got %s", SIZE([w contentMinSize]));
        [w setMinSize:NSMakeSize(-5, -5)];
        CHECK(NSEqualSizes([w contentMinSize], NSZeroSize), "quirk_negative_min_is_zero_content, got %s", SIZE([w contentMinSize]));
        CHECK(NSEqualSizes([w _minFrameSize], NSZeroSize), "no minimum handed on, got %s", SIZE([w _minFrameSize]));
        [w setContentMinSize:NSMakeSize(250, 0)];
        CHECK([w _minFrameSize].width == 250 + c.width && [w _minFrameSize].height == 0, "each dimension decides on its own, got %s", SIZE([w _minFrameSize]));

        // Maximum.
        [w setContentMinSize:NSZeroSize];
        [w setMaxSize:NSMakeSize(800, 600)];
        CHECK(NSEqualSizes([w contentMaxSize], NSMakeSize(800 - c.width, 600 - c.height)), "quirk_setMaxSize_sets_contentMaxSize, got %s", SIZE([w contentMaxSize]));
        [w setContentMaxSize:NSMakeSize(1000, 900)];
        CHECK(NSEqualSizes([w maxSize], NSMakeSize(1000 + c.width, 900 + c.height)), "quirk_setContentMaxSize_sets_maxSize_last_call_wins, got %s", SIZE([w maxSize]));
        CHECK(NSEqualSizes([w _maxFrameSize], NSMakeSize(1000 + c.width, 900 + c.height)), "the maximum handed to the window system, got %s", SIZE([w _maxFrameSize]));
        [w setMaxSize:NSMakeSize(0, 0)];
        CHECK(NSEqualSizes([w maxSize], NSZeroSize) && NSEqualSizes([w contentMaxSize], NSMakeSize(-c.width, -c.height)), "quirk_zero_max_is_not_clamped, got %s %s", SIZE([w maxSize]), SIZE([w contentMaxSize]));
        CHECK([w _maxFrameSize].width >= FLT_MAX && [w _maxFrameSize].height >= FLT_MAX, "a zero maximum is no limit at the window system, got %s", SIZE([w _maxFrameSize]));
        [w setMaxSize:NSMakeSize(FLT_MAX, FLT_MAX)];
        CHECK([w contentMaxSize].width == FLT_MAX && [w maxSize].width == FLT_MAX, "FLT_MAX stays FLT_MAX, got %s", SIZE([w contentMaxSize]));

        // The content limit is what is kept, so a style that adds another frame changes the frame limit.
        [w setContentMinSize:NSMakeSize(300, 200)];
        [w setStyleMask:NSWindowStyleMaskBorderless];
        NSSize borderless = [w frameRectForContentRect:NSZeroRect].size;
        CHECK(NSEqualSizes([w minSize], NSMakeSize(300 + borderless.width, 200 + borderless.height)) && NSEqualSizes([w contentMinSize], NSMakeSize(300, 200)),
              "quirk_content_limit_is_kept_over_a_style_change, got %s %s", SIZE([w minSize]), SIZE([w contentMinSize]));
        [w setStyleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable];
        CHECK(NSEqualSizes([w minSize], NSMakeSize(300 + c.width, 200 + c.height)), "quirk_titled_style_again, got %s", SIZE([w minSize]));

        // The window system's frame changes are limited when they resize the window, not when they only move it.
        NSWindow *m = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 400, 300)
                                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                                    backing:NSBackingStoreBuffered defer:YES];
        NSSize before = [m frame].size;
        [m setContentMinSize:NSMakeSize(before.width + 100, before.height + 100)];
        NSRect moved = [m frame];
        moved.origin.x += 40;
        [m platformWindow:nil frameChanged:moved didSize:NO];
        CHECK(NSEqualSizes([m frame].size, before), "a move leaves the size alone, got %s", SIZE([m frame].size));
        CHECK([m frame].origin.x == moved.origin.x, "a move moves the window");
        [m platformWindow:nil frameChanged:[m frame] didSize:YES];
        CHECK([m frame].size.width >= [m _minFrameSize].width && [m frame].size.height >= [m _minFrameSize].height, "a resize is limited, got %s", SIZE([m frame].size));
    }
    printf(failures ? "FAILED\n" : "PASSED\n");
    return failures != 0;
}
