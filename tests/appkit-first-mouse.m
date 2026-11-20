/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// Contract: -[NSView acceptsFirstMouse:] decides whether the mouse-down that
// would make a window key is also delivered to the view under it. NSView
// answers NO; the AppKit controls that are meant to be operated at once (buttons,
// text fields, sliders, steppers, scrollers, tables, ...) answer YES. A window
// that is not key and can become key sends such a click only to a view that
// accepts it: the view gets neither the mouse-down nor the matching mouse-up
// when it answers NO, and only the view under the pointer is asked, with the
// event itself. Windows that cannot become key, and right-button clicks, are
// delivered as always. The per-class answers and the delivery were observed on
// macOS 26.7.3 and Mac OS X 10.14.4 (x86_64). Needs a display.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL ok, const char *label) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", label);
    failures += !ok;
}

static void spin(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

@interface ProbeView : NSView {
@public
    BOOL accepts;
    int downs, ups, rightDowns;
    NSEvent *askedWith;
}
@end
@implementation ProbeView
- (BOOL) acceptsFirstMouse: (NSEvent *) event {
    askedWith = event;
    return accepts;
}
- (void) mouseDown: (NSEvent *) event { downs++; }
- (void) mouseUp: (NSEvent *) event { ups++; }
- (void) rightMouseDown: (NSEvent *) event { rightDowns++; }
@end

@interface NoKeyWindow : NSWindow
@end
@implementation NoKeyWindow
- (BOOL) canBecomeKeyWindow { return NO; }
@end

static NSEvent *mouseEvent(NSEventType type, NSWindow *window) {
    return [NSEvent mouseEventWithType: type location: NSMakePoint(50, 50) modifierFlags: 0
                             timestamp: [NSDate timeIntervalSinceReferenceDate] windowNumber: [window windowNumber]
                               context: nil eventNumber: 1 clickCount: 1 pressure: 1];
}

static NSWindow *makeWindow(Class cls, NSWindowStyleMask style, NSRect frame) {
    return [[cls alloc] initWithContentRect: frame styleMask: style backing: NSBackingStoreBuffered defer: NO];
}

static ProbeView *addProbe(NSWindow *window, BOOL accepts) {
    ProbeView *view = [[ProbeView alloc] initWithFrame: NSMakeRect(0, 0, 200, 200)];
    view->accepts = accepts;
    [[window contentView] addSubview: view];
    return view;
}

// Makes `other` the key window. A window system that keeps the input focus where
// it was (Wayland compositors do not let a client move it) leaves `target` key; the
// public becomeKeyWindow then moves the application's key window.
static void makeOtherKey(NSWindow *other, NSWindow *target) {
    [other makeKeyAndOrderFront: nil];
    spin(0.3);
    if ([target isKeyWindow])
        [other becomeKeyWindow];
}

static void click(NSWindow *window) {
    [window sendEvent: mouseEvent(NSEventTypeLeftMouseDown, window)];
    [window sendEvent: mouseEvent(NSEventTypeLeftMouseUp, window)];
}

static void checkClass(NSString *name, BOOL expected, NSView *view) {
    if (!view) {
        printf("SKIP %s (class not available)\n", [name UTF8String]);
        return;
    }
    NSWindow *host = makeWindow([NSWindow class], NSWindowStyleMaskTitled, NSMakeRect(0, 0, 300, 200));
    NSString *label = [NSString stringWithFormat: @"%@ acceptsFirstMouse: is %s without a window, nil event", name, expected ? "YES" : "NO"];
    expect([view acceptsFirstMouse: nil] == expected, [label UTF8String]);
    [[host contentView] addSubview: view];
    NSEvent *event = mouseEvent(NSEventTypeLeftMouseDown, host);
    label = [NSString stringWithFormat: @"%@ acceptsFirstMouse: is %s in a window, nil event", name, expected ? "YES" : "NO"];
    expect([view acceptsFirstMouse: nil] == expected, [label UTF8String]);
    label = [NSString stringWithFormat: @"%@ acceptsFirstMouse: is %s in a window, real event", name, expected ? "YES" : "NO"];
    expect([view acceptsFirstMouse: event] == expected, [label UTF8String]);
    [view removeFromSuperview];
}

static NSButton *button(NSButtonType type, NSBezelStyle bezel) {
    NSButton *b = [[NSButton alloc] initWithFrame: NSMakeRect(10, 10, 120, 28)];
    [b setButtonType: type];
    [b setBezelStyle: bezel];
    [b setTitle: @"x"];
    return b;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSRect f = NSMakeRect(10, 10, 120, 28);

        // Per-class answers.
        checkClass(@"NSView", NO, [[NSView alloc] initWithFrame: f]);
        checkClass(@"NSControl", NO, [[NSControl alloc] initWithFrame: f]);
        checkClass(@"NSButton push", YES, button(NSButtonTypeMomentaryPushIn, NSBezelStyleRounded));
        checkClass(@"NSButton switch", YES, button(NSButtonTypeSwitch, NSBezelStyleRegularSquare));
        checkClass(@"NSButton radio", YES, button(NSButtonTypeRadio, NSBezelStyleRegularSquare));
        checkClass(@"NSButton toggle", YES, button(NSButtonTypeToggle, NSBezelStyleRounded));
        checkClass(@"NSButton recessed", YES, button(NSButtonTypePushOnPushOff, NSBezelStyleRecessed));
        NSButton *borderless = button(NSButtonTypeMomentaryPushIn, NSBezelStyleRounded);
        [borderless setBordered: NO];
        checkClass(@"NSButton borderless", YES, borderless);
        NSButton *disabled = button(NSButtonTypeMomentaryPushIn, NSBezelStyleRounded);
        [disabled setEnabled: NO];
        checkClass(@"NSButton disabled", YES, disabled);
        NSTextField *editable = [[NSTextField alloc] initWithFrame: f];
        [editable setEditable: YES];
        checkClass(@"NSTextField editable", YES, editable);
        NSTextField *label = [[NSTextField alloc] initWithFrame: f];
        [label setEditable: NO];
        [label setSelectable: NO];
        [label setBezeled: NO];
        [label setDrawsBackground: NO];
        checkClass(@"NSTextField label", YES, label);
        checkClass(@"NSSecureTextField", YES, [[NSSecureTextField alloc] initWithFrame: f]);
        checkClass(@"NSSearchField", YES, [[NSSearchField alloc] initWithFrame: f]);
        checkClass(@"NSComboBox", YES, [[NSComboBox alloc] initWithFrame: f]);
        checkClass(@"NSTokenField", YES, [[NSTokenField alloc] initWithFrame: f]);
        checkClass(@"NSSlider", YES, [[NSSlider alloc] initWithFrame: f]);
        NSPopUpButton *popUp = [[NSPopUpButton alloc] initWithFrame: f pullsDown: NO];
        [popUp addItemWithTitle: @"a"];
        checkClass(@"NSPopUpButton pop up", YES, popUp);
        NSPopUpButton *pullDown = [[NSPopUpButton alloc] initWithFrame: f pullsDown: YES];
        [pullDown addItemWithTitle: @"a"];
        checkClass(@"NSPopUpButton pull down", YES, pullDown);
        NSSegmentedControl *segmented = [[NSSegmentedControl alloc] initWithFrame: f];
        [segmented setSegmentCount: 2];
        checkClass(@"NSSegmentedControl", YES, segmented);
        checkClass(@"NSStepper", YES, [[NSStepper alloc] initWithFrame: NSMakeRect(0, 0, 19, 27)]);
        checkClass(@"NSColorWell", YES, [[NSColorWell alloc] initWithFrame: f]);
        checkClass(@"NSPathControl", YES, [[NSPathControl alloc] initWithFrame: f]);
        checkClass(@"NSMatrix", YES, [[NSMatrix alloc] initWithFrame: f]);
        checkClass(@"NSForm", YES, [[NSForm alloc] initWithFrame: f]);
        checkClass(@"NSScroller vertical", YES, [[NSScroller alloc] initWithFrame: NSMakeRect(0, 0, 15, 100)]);
        checkClass(@"NSScroller horizontal", YES, [[NSScroller alloc] initWithFrame: NSMakeRect(0, 0, 100, 15)]);
        checkClass(@"NSTableView", YES, [[NSTableView alloc] initWithFrame: f]);
        checkClass(@"NSOutlineView", YES, [[NSOutlineView alloc] initWithFrame: f]);
        checkClass(@"NSTabView", YES, [[NSTabView alloc] initWithFrame: f]);
        checkClass(@"NSSplitView", YES, [[NSSplitView alloc] initWithFrame: f]);
        checkClass(@"NSCollectionView", YES, [[NSCollectionView alloc] initWithFrame: f]);
        checkClass(@"NSScrollView", NO, [[NSScrollView alloc] initWithFrame: f]);
        checkClass(@"NSClipView", NO, [[NSClipView alloc] initWithFrame: f]);
        checkClass(@"NSTableHeaderView", NO, [[NSTableHeaderView alloc] initWithFrame: f]);
        checkClass(@"NSTableRowView", NO, [[NSTableRowView alloc] initWithFrame: f]);
        checkClass(@"NSTableCellView", NO, [[NSTableCellView alloc] initWithFrame: f]);
        checkClass(@"NSTextView", NO, [[NSTextView alloc] initWithFrame: f]);
        checkClass(@"NSImageView", NO, [[NSImageView alloc] initWithFrame: f]);
        checkClass(@"NSBox", NO, [[NSBox alloc] initWithFrame: f]);
        checkClass(@"NSStackView", NO, [[NSStackView alloc] initWithFrame: f]);
        checkClass(@"NSVisualEffectView", NO, [[NSVisualEffectView alloc] initWithFrame: f]);
        checkClass(@"NSProgressIndicator", NO, [[NSProgressIndicator alloc] initWithFrame: f]);
        checkClass(@"NSLevelIndicator", NO, [[NSLevelIndicator alloc] initWithFrame: f]);
        checkClass(@"NSDatePicker", NO, [[NSDatePicker alloc] initWithFrame: NSMakeRect(0, 0, 100, 28)]);
        checkClass(@"NSBrowser", NO, [[NSBrowser alloc] initWithFrame: f]);

        // Delivery of the click that would make a window key.
        NSWindow *other = makeWindow([NSWindow class], NSWindowStyleMaskTitled, NSMakeRect(100, 100, 200, 200));
        NSWindow *target = makeWindow([NSWindow class], NSWindowStyleMaskTitled, NSMakeRect(400, 100, 200, 200));
        ProbeView *probe = addProbe(target, NO);
        [other orderFront: nil];
        [target orderFront: nil];
        makeOtherKey(other, target);
        expect(![target isKeyWindow], "setup: the target window is not key");

        click(target);
        expect(probe->downs == 0 && probe->ups == 0, "NO: the first click is delivered neither as mouseDown nor as mouseUp");
        expect(probe->askedWith != nil, "NO: the view under the click is asked");
        probe->accepts = YES;
        probe->askedWith = nil;
        makeOtherKey(other, target);
        click(target);
        expect(probe->downs == 1 && probe->ups == 1, "YES: the first click is delivered as mouseDown and mouseUp");

        probe->accepts = NO;
        probe->askedWith = nil;
        makeOtherKey(other, target);
        NSEvent *down = mouseEvent(NSEventTypeLeftMouseDown, target);
        probe->downs = 0;
        [target sendEvent: down];
        expect(probe->askedWith == down, "the view is asked with the click event itself");
        [target sendEvent: mouseEvent(NSEventTypeLeftMouseUp, target)];

        probe->rightDowns = 0;
        makeOtherKey(other, target);
        [target sendEvent: mouseEvent(NSEventTypeRightMouseDown, target)];
        expect(probe->rightDowns == 1, "NO: a right-button click is delivered");

        // Only the view under the pointer is asked, not its ancestors.
        ProbeView *child = [[ProbeView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)];
        [probe addSubview: child];
        probe->accepts = YES;
        child->accepts = NO;
        probe->askedWith = nil;
        probe->downs = 0;
        makeOtherKey(other, target);
        click(target);
        expect(child->downs == 0 && probe->downs == 0, "child NO inside parent YES: not delivered");
        expect(child->askedWith != nil && probe->askedWith == nil, "child NO inside parent YES: only the child is asked");
        probe->accepts = NO;
        child->accepts = YES;
        makeOtherKey(other, target);
        click(target);
        expect(child->downs == 1 && probe->downs == 0, "child YES inside parent NO: delivered to the child");
        [child removeFromSuperview];

        // A window that cannot become key is not activated by the click, so it is delivered.
        NoKeyWindow *noKey = (NoKeyWindow *) makeWindow([NoKeyWindow class], NSWindowStyleMaskTitled, NSMakeRect(700, 100, 200, 200));
        ProbeView *noKeyProbe = addProbe(noKey, NO);
        [noKey orderFront: nil];
        click(noKey);
        expect(noKeyProbe->downs == 1 && noKeyProbe->ups == 1, "window that cannot become key: delivered although the view answers NO");

        // A non-activating panel that is not key drops the click for a NO view.
        NSPanel *panel = (NSPanel *) makeWindow([NSPanel class], NSWindowStyleMaskTitled | NSWindowStyleMaskNonactivatingPanel,
                                                NSMakeRect(700, 400, 200, 200));
        ProbeView *panelProbe = addProbe(panel, NO);
        [panel orderFront: nil];
        makeOtherKey(other, panel);
        click(panel);
        expect(panelProbe->downs == 0 && panelProbe->ups == 0, "non-activating panel, not key: not delivered when the view answers NO");
    }
    printf("%s\n", failures ? "FAILED" : "ALL PASSED");
    return failures != 0;
}
