// https://developer.apple.com/documentation/appkit/nsclipview/documentrect
// documentRect is the document view's frame, enlarged to the size of the clip view in a direction where the
// document view is smaller than the clip view.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int g_failures;
#define CHECK(cond) do { \
        if (!(cond)) { printf("FAIL %d: %s\n", __LINE__, #cond); g_failures++; } \
    } while (0)

static NSRect rectFor(NSRect clipFrame, NSRect docFrame) {
    NSClipView *clip = [[[NSClipView alloc] initWithFrame: clipFrame] autorelease];
    NSView *doc = [[[NSView alloc] initWithFrame: docFrame] autorelease];
    [clip setDocumentView: doc];
    return [clip documentRect];
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSRect clip = NSMakeRect(0, 0, 100, 80);

        CHECK(NSEqualRects(rectFor(clip, NSMakeRect(0, 0, 300, 200)), NSMakeRect(0, 0, 300, 200)));  // larger: its frame
        CHECK(NSEqualRects(rectFor(clip, NSMakeRect(10, 20, 50, 40)), NSMakeRect(10, 20, 100, 80))); // smaller: the clip view's size
        CHECK(NSEqualRects(rectFor(clip, NSMakeRect(0, 0, 300, 40)), NSMakeRect(0, 0, 300, 80)));    // wider only
        CHECK(NSEqualRects(rectFor(clip, NSMakeRect(0, 0, 50, 200)), NSMakeRect(0, 0, 100, 200)));   // taller only

        // GUESS: no document view, no rectangle.
        CHECK(NSIsEmptyRect([[[[NSClipView alloc] initWithFrame: clip] autorelease] documentRect]));

        // Scrolling moves the bounds origin, not the size, so the document rect does not change.
        NSClipView *scrolled = [[[NSClipView alloc] initWithFrame: clip] autorelease];
        NSView *doc = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, 300, 200)] autorelease];
        [scrolled setDocumentView: doc];
        [scrolled scrollToPoint: NSMakePoint(40, 30)];
        CHECK(NSEqualRects([scrolled documentRect], NSMakeRect(0, 0, 300, 200)));
    }
    if (g_failures) { printf("%d failure(s)\n", g_failures); return 1; }
    printf("ok\n");
    return 0;
}
