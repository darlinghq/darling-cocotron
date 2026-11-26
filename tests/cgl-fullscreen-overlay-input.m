// CFLAGS: -framework Foundation -framework AppKit -framework ApplicationServices -framework OpenGL
// Copyright (C) 2026 Lubos Dolezel
//
// The input of a fullscreen CGL context (CGLSetFullScreenOnDisplay), whose display is covered by a window that
// belongs to none of the application's windows: the keys, the pointer's motion and buttons and the wheel reach
// the application as events with no window, located on the screen, the way the events of a captured display
// do. They are CGEvents first, so an event tap of the process sees them, with no window number; the NSEvents
// are made from those; the motion is in CGGetLastMouseDelta().
//
// Driven by cgl-fullscreen-overlay-input-x11.sh (XTest) or cgl-fullscreen-overlay-input-wayland.sh (a virtual
// pointer and keyboard): the program prints READY and the display's bounds,
// then PHASE2 and PHASE3 when it has seen what the harness did before, and reports at the end. Skipped
// (SKIP, exit 0) without a fullscreen-capable pixel format.
//
// Usage: cgl-fullscreen-overlay-input (waits at most 40 seconds in all)
// Prints PASS or FAIL lines, then ALL PASSED or FAILED n.
#import <AppKit/AppKit.h>
#include <ApplicationServices/ApplicationServices.h>
#include <OpenGL/OpenGL.h>
#include <OpenGL/gl.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

extern CGLError CGLSetFullScreenOnDisplay(CGLContextObj ctx, GLuint display_mask);
extern CGOpenGLDisplayMask CGDisplayIDToOpenGLDisplayMask(CGDirectDisplayID display);

static int failures;
static void expect(BOOL ok, NSString *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", [what UTF8String]);
    if (!ok)
        failures++;
}

// What the event tap of the process sees, before AppKit gets the events.
static int tapMoved, tapDowns, tapUps, tapScrolls, tapKeyDowns;
static int tapWithWindow;          // pointer events that name a window
static CGPoint tapLastMoved;
static int64_t tapKeyCode = -1;

static CGEventRef tapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *info) {
    switch (type) {
    case kCGEventMouseMoved:
    case kCGEventLeftMouseDown:
    case kCGEventLeftMouseUp:
    case kCGEventScrollWheel:
        if (CGEventGetIntegerValueField(event, kCGMouseEventWindowUnderMousePointer) != 0 ||
            CGEventGetIntegerValueField(event, kCGMouseEventWindowUnderMousePointerThatCanHandleThisEvent) != 0)
            tapWithWindow++;
        if (type == kCGEventMouseMoved) {
            tapMoved++;
            tapLastMoved = CGEventGetLocation(event);
        } else if (type == kCGEventLeftMouseDown) {
            tapDowns++;
        } else if (type == kCGEventLeftMouseUp) {
            tapUps++;
        } else {
            tapScrolls++;
        }
        break;
    case kCGEventKeyDown:
        tapKeyDowns++;
        tapKeyCode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
        break;
    default:
        break;
    }
    return event;
}

// What AppKit delivers.
static NSMutableArray *moves, *downs, *ups, *scrolls, *keys;

static void collect(NSTimeInterval seconds, BOOL (^done)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while ([deadline timeIntervalSinceNow] > 0 && !done()) {
        NSEvent *event = [NSApp nextEventMatchingMask: NSEventMaskAny
                                            untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]
                                               inMode: NSDefaultRunLoopMode
                                              dequeue: YES];
        if (event == nil)
            continue;
        switch ([event type]) {
        case NSEventTypeMouseMoved: [moves addObject: event]; break;
        case NSEventTypeLeftMouseDown: [downs addObject: event]; break;
        case NSEventTypeLeftMouseUp: [ups addObject: event]; break;
        case NSEventTypeScrollWheel: [scrolls addObject: event]; break;
        case NSEventTypeKeyDown: [keys addObject: event]; break;
        default: break;
        }
    }
}

static BOOL near(NSPoint p, CGFloat x, CGFloat y) {
    return fabs(p.x - x) <= 1.0 && fabs(p.y - y) <= 1.0;
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    @autoreleasepool {
        moves = [NSMutableArray new];
        downs = [NSMutableArray new];
        ups = [NSMutableArray new];
        scrolls = [NSMutableArray new];
        keys = [NSMutableArray new];
        [NSApplication sharedApplication];
        [NSApp finishLaunching];

        CGEventMask mask = CGEventMaskBit(kCGEventMouseMoved) | CGEventMaskBit(kCGEventLeftMouseDown) |
                           CGEventMaskBit(kCGEventLeftMouseUp) | CGEventMaskBit(kCGEventScrollWheel) |
                           CGEventMaskBit(kCGEventKeyDown);
        CFMachPortRef tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly,
                                             mask, tapCallback, NULL);
        if (tap == NULL) {
            printf("FAIL no event tap\n");
            return 1;
        }
        CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(NULL, tap, 0);
        CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
        CGEventTapEnable(tap, true);

        CGDirectDisplayID display = CGMainDisplayID();
        CGOpenGLDisplayMask displayMask = CGDisplayIDToOpenGLDisplayMask(display);
        CGLPixelFormatAttribute attrs[] = {kCGLPFAFullScreen, kCGLPFADoubleBuffer, kCGLPFADisplayMask,
                                           (CGLPixelFormatAttribute) displayMask, 0};
        CGLPixelFormatObj format = NULL;
        GLint count = 0;
        CGLContextObj context = NULL;
        if (CGLChoosePixelFormat(attrs, &format, &count) != kCGLNoError || format == NULL ||
            CGLCreateContext(format, NULL, &context) != kCGLNoError ||
            CGLSetFullScreenOnDisplay(context, displayMask) != kCGLNoError) {
            printf("SKIP: no fullscreen context\n");
            return 0;
        }

        // The program draws, as one that fills a display does (a Wayland toplevel is mapped by its first buffer).
        CGLSetCurrentContext(context);
        glClearColor(0, 0, 0, 1);
        glClear(GL_COLOR_BUFFER_BIT);
        CGLFlushDrawable(context);

        CGRect bounds = CGDisplayBounds(display);
        CGFloat height = bounds.size.height;
        printf("READY %d %d %d %d\n", (int) bounds.origin.x, (int) bounds.origin.y, (int) bounds.size.width,
               (int) bounds.size.height);

        // The pointer is moved to (200, 150) of the display; the motion before it is not counted.
        collect(15, ^BOOL { return [moves count] > 0 && near([[moves lastObject] locationInWindow],
                                  bounds.origin.x + 200, bounds.origin.y + height - 150); });
        NSEvent *first = [moves lastObject];
        expect(first != nil && near([first locationInWindow], bounds.origin.x + 200, bounds.origin.y + height - 150),
               @"the pointer's motion arrives, located on the screen");
        expect([first window] == nil && [first windowNumber] == 0, @"  it has no window");
        int32_t dx, dy;
        CGGetLastMouseDelta(&dx, &dy);
        printf("PHASE2\n");

        // Moved by (+30, -20) in the display's y-down space.
        [moves removeAllObjects];
        collect(15, ^BOOL { return [moves count] > 0 && near([[moves lastObject] locationInWindow],
                                  bounds.origin.x + 230, bounds.origin.y + height - 130); });
        NSEvent *second = [moves lastObject];
        expect(second != nil && near([second locationInWindow], bounds.origin.x + 230, bounds.origin.y + height - 130),
               @"the second motion is where the pointer went");
        if (second != nil) {
            expect([second window] == nil, @"  it has no window");
            NSPoint mouse = [NSEvent mouseLocation];
            expect(near(mouse, [second locationInWindow].x, [second locationInWindow].y),
                   @"  +[NSEvent mouseLocation] agrees");
        }
        CGGetLastMouseDelta(&dx, &dy);
        expect(abs(dx - 30) <= 1 && abs(dy + 20) <= 1,
               [NSString stringWithFormat: @"CGGetLastMouseDelta() reports the motion (%d, %d)", dx, dy]);
        CGGetLastMouseDelta(&dx, &dy);
        expect(dx == 0 && dy == 0, @"  and a call takes what was reported");
        expect(tapMoved > 0 && fabs(tapLastMoved.x - (bounds.origin.x + 230)) <= 1 &&
               fabs(tapLastMoved.y - (bounds.origin.y + 130)) <= 1,
               @"the event tap saw the motion at the pointer's position");
        printf("PHASE3\n");

        // A double click, a click after the double-click interval, the key "a" and a notch of the wheel.
        collect(15, ^BOOL { return [keys count] > 0 && [scrolls count] > 0 && [ups count] >= 3; });
        expect([downs count] >= 3, [NSString stringWithFormat: @"the buttons arrive (%d downs, %d ups)",
                                    (int) [downs count], (int) [ups count]]);
        if ([downs count] >= 3) {
            expect([[downs objectAtIndex: 0] clickCount] == 1 && [[downs objectAtIndex: 1] clickCount] == 2 &&
                   [[downs objectAtIndex: 2] clickCount] == 1,
                   [NSString stringWithFormat: @"  with the click counts of a double click and a later click (%d %d %d)",
                    (int) [[downs objectAtIndex: 0] clickCount], (int) [[downs objectAtIndex: 1] clickCount],
                    (int) [[downs objectAtIndex: 2] clickCount]]);
            expect([[downs objectAtIndex: 0] window] == nil, @"  and no window");
            expect(near([[downs objectAtIndex: 0] locationInWindow], bounds.origin.x + 230,
                        bounds.origin.y + height - 130), @"  located where the pointer is");
        }
        if ([ups count] >= 3)
            expect([[ups objectAtIndex: 1] clickCount] == 2 && [[ups objectAtIndex: 1] window] == nil,
                   @"the release of the second click reports its count");
        expect([scrolls count] > 0 && [[scrolls objectAtIndex: 0] window] == nil &&
               [[scrolls objectAtIndex: 0] deltaY] > 0, @"the wheel scrolls up, with no window");
        NSEvent *key = [keys firstObject];
        expect(key != nil && [[key characters] isEqual: @"a"] && [key window] == nil && [key windowNumber] == 0,
               @"the key arrives with no window");

        // The tap's callbacks run from the run loop, which may not have caught up with the last event yet.
        collect(0.3, ^BOOL { return NO; });
        expect(tapDowns >= 3 && tapUps >= 3 && tapScrolls > 0 && tapKeyDowns > 0 &&
               (key == nil || tapKeyCode == (int64_t) [key keyCode]),
               [NSString stringWithFormat: @"the event tap saw the buttons, the wheel and the key, which agrees with the NSEvent (%d %d %d %d)",
                tapDowns, tapUps, tapScrolls, tapKeyDowns]);
        expect(tapWithWindow == 0, [NSString stringWithFormat:
                                    @"no pointer CGEvent of the overlay names a window (%d do)", tapWithWindow]);

        // With the mouse disassociated from the cursor the pointer is grabbed on the overlay: the cursor stays
        // where it is, and the motion arrives as deltas, with no window.
        NSPoint frozen = [NSEvent mouseLocation];
        expect(CGAssociateMouseAndMouseCursorPosition(false) == kCGErrorSuccess, @"the mouse is disassociated");
        [moves removeAllObjects];
        (void) CGGetLastMouseDelta(&dx, &dy);
        printf("PHASE4\n");
        collect(15, ^BOOL { return [moves count] > 0; });
        double sumX = 0, sumY = 0;
        for (NSEvent *move in moves) {
            sumX += [move deltaX];
            sumY += [move deltaY];
            if ([move window] != nil)
                expect(NO, @"  a motion names a window");
        }
        expect([moves count] > 0 && fabs(sumX - 12) <= 1.5 && fabs(sumY - 5) <= 1.5,
               [NSString stringWithFormat: @"the relative motion arrives as deltas (%.1f, %.1f)", sumX, sumY]);
        CGGetLastMouseDelta(&dx, &dy);
        expect(abs(dx - 12) <= 1 && abs(dy - 5) <= 1,
               [NSString stringWithFormat: @"  and in CGGetLastMouseDelta() (%d, %d)", dx, dy]);
        expect(near([NSEvent mouseLocation], frozen.x, frozen.y), @"  while the cursor stays where it was");
        CGAssociateMouseAndMouseCursorPosition(true);

        CGLClearDrawable(context);
        CGLDestroyContext(context);
        CGLDestroyPixelFormat(format);
    }
    if (failures == 0)
        printf("ALL PASSED\n");
    else
        printf("FAILED %d\n", failures);
    return failures != 0;
}
