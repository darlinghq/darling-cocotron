// Copyright (C) 2026 Lubos Dolezel
//
// Darling only (it reaches into the view's native layer window): the native window that hosts the root
// layer of a layer-backed view whose superview has no layer is placed in window coordinates, not in the
// superview's. It follows the view when an ancestor moves, not only when the view's own frame changes.
// A view's frame is in its superview's coordinates, so the two differ for every view below the content view.
//
// Build (in the guest): clang -fobjc-arc -framework AppKit view-layer-context-frame.m
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)
#define CHECKRECT(sink, expected) do { NSRect e = (expected); if (!NSEqualRects((sink)->frame, e)) { fprintf(stderr, "FAIL line %d: context frame %s, expected %s\n", __LINE__, [NSStringFromRect((sink)->frame) UTF8String], [NSStringFromRect(e) UTF8String]); failures++; } } while (0)

@interface FrameSink : NSObject { @public NSRect frame; unsigned updates; }
- (void)setFrame:(NSRect)value;
- (void)setHidden:(BOOL)value;
- (void)invalidate;
@end
@implementation FrameSink
- (void)setHidden:(BOOL)value {}
- (void)invalidate {}
- (void)setFrame:(NSRect)value { frame = value; updates++; }
@end

@interface SinkView : NSView
- (void)attachContext:(id)context;
- (void)detachContext;
@end
@implementation SinkView
- (void)attachContext:(id)context { _layerContext = context; }
- (void)detachContext { _layerContext = nil; }
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 500, 500)
                                                       styleMask: NSWindowStyleMaskBorderless
                                                         backing: NSBackingStoreBuffered
                                                           defer: YES];
        NSView *root = [window contentView];
        NSView *parent = [[NSView alloc] initWithFrame: NSMakeRect(10, 20, 200, 200)];
        NSView *mid = [[NSView alloc] initWithFrame: NSMakeRect(1, 1, 100, 100)];
        SinkView *child = [[SinkView alloc] initWithFrame: NSMakeRect(5, 5, 50, 50)];
        [root addSubview: parent];
        [parent addSubview: mid];
        [mid addSubview: child];
        FrameSink *sink = [FrameSink new];
        [child attachContext: sink];

        // the view's own frame changes: the context frame is in window coordinates
        [child setFrameOrigin: NSMakePoint(6, 7)];
        CHECKRECT(sink, NSMakeRect(17, 28, 50, 50));

        // an ancestor moves: the context follows although the view's frame did not change
        unsigned before = sink->updates;
        [parent setFrameOrigin: NSMakePoint(30, 40)];
        CHECK(sink->updates > before);
        CHECKRECT(sink, NSMakeRect(37, 48, 50, 50));
        [mid setFrameOrigin: NSMakePoint(11, 12)];
        CHECKRECT(sink, NSMakeRect(47, 59, 50, 50));

        [child detachContext];
    }
    if (failures == 0)
        puts("PASS");
    return failures != 0;
}
