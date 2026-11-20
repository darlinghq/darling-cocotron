// Copyright (C) 2026 Lubos Dolezel
//
// Windows that the user moves by dragging a part of their content, for the harnesses
// appkit-window-drag-x11.sh and appkit-window-drag-wayland.sh, which press the left button at a
// point of each window, drag it by an offset and release it:
//   perform-drag     borderless; its view calls -performWindowDragWithEvent: from -mouseDown: (moves)
//   not-movable      the same with movable set to NO (stays)
//   titlebar         titled, transparent title bar with a hidden title and hidden buttons, its content
//                    covering the title bar; the content view's hit test finds nothing in the top 30
//                    points, so a press in the title bar area reaches the frame view (moves)
//   below-titlebar   the same window with a band of 100 points, pressed 60 points from the top: the
//                    press reaches the frame view below the title bar area, which does not move a
//                    window from there (stays)
//   frame-subclass   a window whose frame view class (+frameViewClassForStyleMask:) starts the drag
//                    itself from -mouseDown:, for a press where the content view finds nothing (moves)
//   background       movableByWindowBackground, pressed on a transparent view (moves)
// The program prints "READY" once the windows are shown, then "frame <name> <x> <y>" (Cocoa screen
// coordinates) whenever a window's origin changes, and "final <name> <x> <y>" before it exits after
// <seconds> (the first argument, default 20).
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <stdlib.h>

@interface NSThemeFrame : NSView
@end

// Starts a window drag from every press.
@interface DragView : NSView
@end
@implementation DragView
- (BOOL) isOpaque {
    return YES;
}
- (void) drawRect: (NSRect) rect {
    [[NSColor colorWithCalibratedRed: 0.3 green: 0.5 blue: 0.8 alpha: 1] setFill];
    NSRectFill(rect);
}
- (void) mouseDown: (NSEvent *) event {
    [[self window] performWindowDragWithEvent: event];
}
@end

// An opaque view that handles every press except in a band along its top edge, where its hit test
// finds nothing, as a view does for a part of the window it wants to be dragged by.
@interface BandView : NSView {
    CGFloat _band;
    int _presses;
}
@property CGFloat band;
@property int presses;
@end
@implementation BandView
// Synthesized explicitly: the i386 runtime does not synthesize properties.
@synthesize band = _band, presses = _presses;
- (BOOL) isOpaque {
    return YES;
}
- (void) drawRect: (NSRect) rect {
    [[NSColor colorWithCalibratedRed: 0.8 green: 0.6 blue: 0.3 alpha: 1] setFill];
    NSRectFill(rect);
}
- (NSView *) hitTest: (NSPoint) point {
    NSPoint local = [self convertPoint: point fromView: [self superview]];
    if (NSPointInRect(local, [self bounds]) && local.y >= NSHeight([self bounds]) - self.band)
        return nil;
    return [super hitTest: point];
}
- (void) mouseDown: (NSEvent *) event {
    self.presses++;
}
@end

// The frame view of DragFrameWindow: a press that reaches it starts a window drag.
@interface DragFrame : NSThemeFrame
@end
@implementation DragFrame
- (void) mouseDown: (NSEvent *) event {
    if ([[self window] isMovable])
        [[self window] performWindowDragWithEvent: event];
    else
        [super mouseDown: event];
}
@end

@interface DragFrameWindow : NSWindow
@end
@implementation DragFrameWindow
+ (Class) frameViewClassForStyleMask: (NSWindowStyleMask) style {
    return [DragFrame class];
}
@end

static NSMutableDictionary<NSString *, NSWindow *> *windows;

static NSWindow *make(Class cls, NSString *name, NSUInteger style, NSRect rect, NSView *content) {
    NSWindow *w = [[cls alloc] initWithContentRect: rect styleMask: style backing: NSBackingStoreBuffered
                                             defer: NO];
    [w setTitle: name];
    [w setReleasedWhenClosed: NO];
    [content setFrame: [[w contentView] frame]];
    [content setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
    [w setContentView: content];
    windows[name] = w;
    return w;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
        windows = [NSMutableDictionary dictionary];
        const NSUInteger titled = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                  NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;

        make([NSWindow class], @"perform-drag", NSWindowStyleMaskBorderless,
             NSMakeRect(100, 650, 300, 200), [[DragView alloc] init]);
        NSWindow *fixed = make([NSWindow class], @"not-movable", NSWindowStyleMaskBorderless,
                               NSMakeRect(500, 650, 300, 200), [[DragView alloc] init]);
        [fixed setMovable: NO];

        for (NSString *name in @[ @"titlebar", @"below-titlebar" ]) {
            BandView *band = [[BandView alloc] init];
            band.band = [name isEqual: @"titlebar"] ? 30 : 100;
            NSWindow *w = make([NSWindow class], name, titled,
                               NSMakeRect([name isEqual: @"titlebar"] ? 900 : 1300, 650, 300, 200), band);
            [w setTitlebarAppearsTransparent: YES];
            [w setTitleVisibility: NSWindowTitleHidden];
            for (NSWindowButton b = NSWindowCloseButton; b <= NSWindowZoomButton; b++)
                [[w standardWindowButton: b] setHidden: YES];
        }

        BandView *band = [[BandView alloc] init];
        band.band = 60;
        make([DragFrameWindow class], @"frame-subclass", titled, NSMakeRect(100, 250, 300, 200), band);

        NSView *clear = [[NSView alloc] init];
        NSWindow *bg = make([NSWindow class], @"background", NSWindowStyleMaskBorderless,
                            NSMakeRect(500, 250, 300, 200), clear);
        [bg setMovableByWindowBackground: YES];
        [bg setBackgroundColor: [NSColor colorWithCalibratedRed: 0.4 green: 0.7 blue: 0.4 alpha: 1]];

        for (NSWindow *w in [windows allValues])
            [w orderFront: nil];
        [NSApp activateIgnoringOtherApps: YES];
        printf("READY\n");
        fflush(stdout);

        NSMutableDictionary<NSString *, NSValue *> *last = [NSMutableDictionary dictionary];
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow: argc > 1 ? atof(argv[1]) : 20];
        while ([until timeIntervalSinceNow] > 0) {
            NSEvent *e = [NSApp nextEventMatchingMask: NSEventMaskAny
                                            untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]
                                               inMode: NSDefaultRunLoopMode
                                              dequeue: YES];
            if (e)
                [NSApp sendEvent: e];
            for (NSString *name in windows) {
                NSPoint o = [windows[name] frame].origin;
                NSValue *v = [NSValue valueWithPoint: o];
                if (![last[name] isEqual: v]) {
                    last[name] = v;
                    printf("frame %s %.0f %.0f\n", [name UTF8String], o.x, o.y);
                    fflush(stdout);
                }
            }
        }
        for (NSString *name in [[windows allKeys] sortedArrayUsingSelector: @selector(compare:)]) {
            NSPoint o = [windows[name] frame].origin;
            printf("final %s %.0f %.0f\n", [name UTF8String], o.x, o.y);
        }
    }
    return 0;
}
