// Copyright (C) 2026 Lubos Dolezel
//
// Licensed under the MIT license, the same as the rest of this project.
//
// The accessory view of NSSavePanel and NSOpenPanel with the built-in panel (the desktop file chooser is not asked
// for: DesktopFileChooser is unset). Needs a window server (X11 with a window manager, or the Wayland backend).
// Checks, for a save panel and an open panel:
//  - the accessory view is a subview of the panel's content view (its window is the panel) from the moment it is set,
//    visible and between the file list and the row of buttons, centred horizontally;
//  - the panel is taller by exactly the height of the view, the file list keeps its size, a view that changes its
//    height or is wider than the panel changes the panel, removing the view restores the panel's size, and setting a
//    view while the panel is up works;
//  - the view's controls are reachable (hit testing) and work, and what the user chose is there after OK;
//  - an open panel shows the view only while accessoryViewDisclosed is YES (NO by default), which its Options button
//    toggles.
// The layout follows black-box observation of NSSavePanel and NSOpenPanel on macOS 26.7.3 through the public API
// (probe in vd-upstream/mac-probes/panel-accessory/probe.m): the save panel grows by exactly the view's height (60 to
// 285 and 140 to 365 for a base of 225, the top fixed), the view is centred when narrower than the panel and a wider
// view widens the panel to the view's width, accessoryViewDisclosed is NO by default for an open panel.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

static int failures;
#define CHECK(...) do { if (!(__VA_ARGS__)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #__VA_ARGS__); failures++; } } while (0)

// accessoryViewDisclosed is declared by the newer AppKit headers only; reached through these so that the program
// builds against either, and fails (not crashes) where the panel lacks it.
@interface NSObject (AccessoryViewDisclosedTest)
- (BOOL) isAccessoryViewDisclosed;
- (void) setAccessoryViewDisclosed: (BOOL) disclosed;
@end

static void spin(NSTimeInterval s) {
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: s]];
}

@interface Counter : NSObject {
@public
    int checkActions, popUpActions;
}
- (void) check: (id) sender;
- (void) popUp: (id) sender;
@end
@implementation Counter
- (void) check: (id) sender { checkActions++; }
- (void) popUp: (id) sender { popUpActions++; }
@end

static Counter *counter;
static NSPopUpButton *popUp;
static NSButton *check;

// The accessory view: a check box and a pop-up button, as in a text editor's encoding choice.
static NSView *makeAccessory(CGFloat width, CGFloat height) {
    NSView *view = [[[NSView alloc] initWithFrame: NSMakeRect(0, 0, width, height)] autorelease];
    check = [[[NSButton alloc] initWithFrame: NSMakeRect(10, height - 22, 220, 20)] autorelease];
    [check setButtonType: NSSwitchButton];
    [check setTitle: @"Ignore rich text commands"];
    [check setTarget: counter];
    [check setAction: @selector(check:)];
    [view addSubview: check];
    popUp = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect(10, 2, 200, 24) pullsDown: NO] autorelease];
    [popUp addItemsWithTitles: @[ @"Automatic", @"Unicode (UTF-8)", @"Western (ISO Latin 1)" ]];
    [popUp setTarget: counter];
    [popUp setAction: @selector(popUp:)];
    [view addSubview: popUp];
    return view;
}

static NSScrollView *findList(NSView *view) {
    for (NSView *sub in [view subviews]) {
        if ([sub isKindOfClass: [NSScrollView class]] &&
            [[(NSScrollView *) sub documentView] isKindOfClass: [NSOutlineView class]])
            return (NSScrollView *) sub;
        NSScrollView *found = findList(sub);
        if (found != nil)
            return found;
    }
    return nil;
}

static NSButton *findButton(NSView *view, NSString *title) {
    for (NSView *sub in [view subviews]) {
        if ([sub isKindOfClass: [NSButton class]] && [[(NSButton *) sub title] isEqualToString: title])
            return (NSButton *) sub;
        NSButton *found = findButton(sub, title);
        if (found != nil)
            return found;
    }
    return nil;
}

static NSRect inContent(NSPanel *panel, NSView *view) {
    return [[panel contentView] convertRect: [view bounds] fromView: view];
}

static BOOL near(CGFloat a, CGFloat b) {
    return fabs(a - b) <= 1;
}

static NSSize contentSize(NSPanel *panel) {
    return [[panel contentView] frame].size;
}

static NSSavePanel *current;

// Waits until the panel's size has stopped changing: a window system may answer a resize some time after it was asked.
static void settle(void) {
    NSSize last = NSMakeSize(-1, -1);
    for (int i = 0; i < 20; i++) {
        spin(0.2);
        NSSize now = contentSize(current);
        if (NSEqualSizes(now, last))
            return;
        last = now;
    }
}

static void show(NSSavePanel *panel, BOOL *done, NSModalResponse *response) {
    current = panel;
    *done = NO;
    [panel beginWithCompletionHandler: ^(NSModalResponse r) {
        *response = r;
        *done = YES;
    }];
    settle();
}

static void dismiss(NSSavePanel *panel, BOOL *done) {
    [panel cancel: nil];
    for (int i = 0; i < 30 && !*done; i++)
        spin(0.1);
}

// What the layout of a panel without an accessory view is, to compare with.
typedef struct { NSSize content; NSSize list; } Base;

static Base measureBase(NSSavePanel *panel) {
    BOOL done;
    NSModalResponse response;
    show(panel, &done, &response);
    Base base = { contentSize(panel), [findList([panel contentView]) frame].size };
    dismiss(panel, &done);
    return base;
}

static void checkPlacement(NSSavePanel *panel, NSView *accessory, Base base, CGFloat extra, const char *what) {
    NSRect frame = inContent(panel, accessory);
    NSScrollView *list = findList([panel contentView]);
    NSButton *ok = findButton([panel contentView], [panel prompt]);
    fprintf(stderr, "  %s: content %gx%g list %gx%g accessory %g,%g %gx%g\n", what, contentSize(panel).width,
            contentSize(panel).height, [list frame].size.width, [list frame].size.height, frame.origin.x,
            frame.origin.y, frame.size.width, frame.size.height);
    CHECK([accessory window] == panel);
    CHECK([accessory isDescendantOf: [panel contentView]]);
    CHECK(![accessory isHiddenOrHasHiddenAncestor]);
    CHECK(near(contentSize(panel).height, base.content.height + extra));
    CHECK(near([list frame].size.height, base.list.height));
    CHECK(NSMaxY(frame) <= NSMinY([list frame]) + 1);
    CHECK(ok != nil && NSMinY(frame) >= NSMaxY([ok frame]) - 1);
    CHECK(near(NSMidX(frame), contentSize(panel).width / 2));
    CHECK(NSMinX(frame) >= -1 && NSMaxX(frame) <= contentSize(panel).width + 1);
}

static void checkControlsReachable(NSSavePanel *panel) {
    NSView *content = [panel contentView];
    NSView *hitCheck = [content hitTest: [content convertPoint: NSMakePoint(NSMidX([check bounds]), NSMidY([check bounds]))
                                                      fromView: check]];
    NSView *hitPopUp = [content hitTest: [content convertPoint: NSMakePoint(NSMidX([popUp bounds]), NSMidY([popUp bounds]))
                                                      fromView: popUp]];
    CHECK(hitCheck == check || [hitCheck isDescendantOf: check]);
    CHECK(hitPopUp == popUp || [hitPopUp isDescendantOf: popUp]);
}

static void testSavePanel(void) {
    fprintf(stderr, "save panel\n");
    BOOL done;
    NSModalResponse response = -1;

    Base base = measureBase([NSSavePanel savePanel]);

    NSSavePanel *panel = [NSSavePanel savePanel];
    NSView *accessory = makeAccessory(300, 60);
    [panel setAccessoryView: accessory];
    // in the panel's view hierarchy as soon as it is set
    CHECK([accessory window] == panel);
    CHECK([accessory superview] != nil);
    CHECK([panel accessoryView] == accessory);

    show(panel, &done, &response);
    CHECK([panel isVisible]);
    checkPlacement(panel, accessory, base, 60, "shown");
    checkControlsReachable(panel);

    // the view's height changes
    [accessory setFrame: NSMakeRect(0, 0, 300, 140)];
    settle();
    checkPlacement(panel, accessory, base, 140, "taller view");
    [accessory setFrame: NSMakeRect(0, 0, 300, 60)];
    settle();
    checkPlacement(panel, accessory, base, 60, "back to 60");

    // a view wider than the panel makes the panel as wide
    [accessory setFrame: NSMakeRect(0, 0, base.content.width + 120, 60)];
    settle();
    CHECK(near(contentSize(panel).width, base.content.width + 120));
    CHECK(near(NSMinX(inContent(panel, accessory)), 0));
    [accessory setFrame: NSMakeRect(0, 0, 300, 60)];
    settle();
    CHECK(near(contentSize(panel).width, base.content.width));

    // removing and setting the view while the panel is up
    [panel setAccessoryView: nil];
    settle();
    CHECK([accessory superview] == nil);
    CHECK([accessory window] == nil);
    CHECK(near(contentSize(panel).height, base.content.height));
    CHECK(near([findList([panel contentView]) frame].size.height, base.list.height));
    NSView *second = makeAccessory(300, 90);
    [panel setAccessoryView: second];
    settle();
    checkPlacement(panel, second, base, 90, "second view");
    // replacing one by another
    NSView *third = makeAccessory(300, 50);
    [panel setAccessoryView: third];
    settle();
    CHECK([second superview] == nil);
    checkPlacement(panel, third, base, 50, "third view");
    checkControlsReachable(panel);

    // the controls work, and what the user chose is there after OK
    int checks = counter->checkActions, popUps = counter->popUpActions;
    CHECK([check state] == NSOffState);
    [check performClick: nil];
    CHECK([check state] == NSOnState);
    CHECK(counter->checkActions == checks + 1);
    [popUp selectItemAtIndex: 2];
    [popUp sendAction: [popUp action] to: [popUp target]];
    CHECK(counter->popUpActions == popUps + 1);

    [panel setNameFieldStringValue: @"accessory-test.txt"];
    [panel setDirectory: NSTemporaryDirectory()];
    [panel ok: nil];
    for (int i = 0; i < 30 && !done; i++)
        spin(0.1);
    CHECK(done && response == NSModalResponseOK);
    CHECK([check state] == NSOnState);
    CHECK([popUp indexOfSelectedItem] == 2);
    CHECK([[[panel URL] lastPathComponent] isEqualToString: @"accessory-test.txt"]);
    CHECK(![panel isVisible]);
}


// A view laid out by Auto Layout, as a nib that sets translatesAutoresizingMaskIntoConstraints to NO gives: its frame
// is empty until something lays it out, and the panel takes the size its constraints ask for.
static void testAutoLayoutAccessory(BOOL open) {
    fprintf(stderr, open ? "auto layout accessory view, open panel\n" : "auto layout accessory view\n");
    BOOL done;
    NSModalResponse response = -1;
    Base base = measureBase(open ? [NSOpenPanel openPanel] : [NSSavePanel savePanel]);

    NSSavePanel *panel = open ? [NSOpenPanel openPanel] : [NSSavePanel savePanel];
    NSView *view = [[[NSView alloc] initWithFrame: NSZeroRect] autorelease];
    [view setTranslatesAutoresizingMaskIntoConstraints: NO];
    check = [NSButton checkboxWithTitle: @"Ignore rich text commands" target: counter action: @selector(check:)];
    popUp = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect(0, 0, 100, 24) pullsDown: NO] autorelease];
    [popUp addItemsWithTitles: @[ @"Automatic", @"Unicode (UTF-8)" ]];
    [check setTranslatesAutoresizingMaskIntoConstraints: NO];
    [popUp setTranslatesAutoresizingMaskIntoConstraints: NO];
    [view addSubview: check];
    [view addSubview: popUp];
    NSDictionary *views = NSDictionaryOfVariableBindings(check, popUp);
    [view addConstraints: [NSLayoutConstraint constraintsWithVisualFormat: @"H:|-20-[popUp(==220)]-20-|"
                                                                  options: 0 metrics: nil views: views]];
    [view addConstraints: [NSLayoutConstraint constraintsWithVisualFormat: @"H:|-20-[check]"
                                                                  options: 0 metrics: nil views: views]];
    [view addConstraints: [NSLayoutConstraint constraintsWithVisualFormat: @"V:|-10-[popUp]-8-[check]-10-|"
                                                                  options: 0 metrics: nil views: views]];
    NSSize fitting = [view fittingSize];
    CHECK(fitting.width >= 260 && fitting.height >= 50);
    // what the panel made while taking the view must not depend on this pool
    @autoreleasepool {
        [panel setAccessoryView: view];
    }
    show(panel, &done, &response);
    if (open) {
        CHECK([view isHiddenOrHasHiddenAncestor]);
        [(id) panel setAccessoryViewDisclosed: YES];
        settle();
    }
    CHECK([view translatesAutoresizingMaskIntoConstraints] == NO);
    CHECK(near([view frame].size.width, fitting.width) && near([view frame].size.height, fitting.height));
    checkPlacement(panel, view, base, fitting.height, "constraint-based view");
    // laid out inside: the pop-up above the check box, both within the view
    CHECK(NSMaxY([popUp frame]) <= [view bounds].size.height + 1 && NSMinY([check frame]) >= -1);
    CHECK(NSMinY([popUp frame]) >= NSMaxY([check frame]) - 1);
    checkControlsReachable(panel);
    dismiss(panel, &done);
}

static void testOpenPanel(void) {
    fprintf(stderr, "open panel\n");
    BOOL done;
    NSModalResponse response = -1;

    NSOpenPanel *basePanel = [NSOpenPanel openPanel];
    CHECK(![basePanel respondsToSelector: @selector(isAccessoryViewDisclosed)] || ![(id) basePanel isAccessoryViewDisclosed]);
    Base base = measureBase(basePanel);

    NSOpenPanel *panel = [NSOpenPanel openPanel];
    CHECK([panel respondsToSelector: @selector(isAccessoryViewDisclosed)] &&
          [panel respondsToSelector: @selector(setAccessoryViewDisclosed:)]);
    if (![panel respondsToSelector: @selector(isAccessoryViewDisclosed)])
        return;
    NSView *accessory = makeAccessory(300, 60);
    [panel setAccessoryView: accessory];
    CHECK([accessory window] == panel);
    CHECK(![(id) panel isAccessoryViewDisclosed]);

    show(panel, &done, &response);
    // not disclosed: in the hierarchy, not shown, and the panel is as it was
    CHECK([accessory window] == panel);
    CHECK([accessory isHiddenOrHasHiddenAncestor]);
    CHECK(near(contentSize(panel).height, base.content.height));

    // the Options button discloses it
    NSButton *options = findButton([panel contentView], @"Options");
    CHECK(options != nil);
    [options performClick: nil];
    settle();
    CHECK([(id) panel isAccessoryViewDisclosed]);
    checkPlacement(panel, accessory, base, 60, "disclosed by the button");
    checkControlsReachable(panel);

    [(id) panel setAccessoryViewDisclosed: NO];
    settle();
    CHECK([accessory isHiddenOrHasHiddenAncestor]);
    CHECK(near(contentSize(panel).height, base.content.height));
    [(id) panel setAccessoryViewDisclosed: YES];
    settle();
    CHECK(![accessory isHiddenOrHasHiddenAncestor]);
    checkPlacement(panel, accessory, base, 60, "disclosed by the property");

    [accessory setFrame: NSMakeRect(0, 0, 300, 100)];
    settle();
    checkPlacement(panel, accessory, base, 100, "taller view");

    // the controls work and the values are there after OK
    [check performClick: nil];
    [popUp selectItemAtIndex: 1];
    [panel setCanChooseFiles: NO];
    [panel setCanChooseDirectories: YES];
    [panel setDirectory: NSTemporaryDirectory()];
    [panel ok: nil];
    for (int i = 0; i < 30 && !done; i++)
        spin(0.1);
    CHECK(done && response == NSModalResponseOK);
    CHECK([check state] == NSOnState);
    CHECK([popUp indexOfSelectedItem] == 1);
    CHECK([[panel URLs] count] == 1);

    // the same panel, once more: the view is still there and disclosed
    CHECK([accessory window] == panel);
    CHECK([(id) panel isAccessoryViewDisclosed]);
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        counter = [[Counter alloc] init];
        testSavePanel();
        testAutoLayoutAccessory(NO);
        testAutoLayoutAccessory(YES);
        testOpenPanel();
        printf(failures == 0 ? "PASS\n" : "FAIL: %d check(s)\n", failures);
        return failures != 0;
    }
}
