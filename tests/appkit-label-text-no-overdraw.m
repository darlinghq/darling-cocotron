// Copyright (C) 2026 Lubos Dolezel
//
// Labels whose text changes must not show the old text. The program builds windows the way a
// typical installer-style window is laid out (a window content view, a custom box behind a column of
// non-bezeled, non-background labels, a plain container view whose subviews are replaced) and
// changes the label strings and fonts. A driver captures the screen at each state: after the
// change ("B") and in a second window built directly in that final state ("ref"); the two must be
// identical. Usage: prog <state-dir>; the program writes <state-dir>/<name>.state and waits for
// <state-dir>/<name>.ack.
#import <Cocoa/Cocoa.h>
#include <stdio.h>
#include <unistd.h>

static NSString *stateDir;
static void (^pendingChange)(void);

// An application that runs the pending change while it dispatches an event, as an action
// triggered by a click or a key does.
@interface EventApp : NSApplication
@end
@implementation EventApp
- (void)sendEvent:(NSEvent *)e
{
    if ([e type] == NSEventTypeApplicationDefined && [e subtype] == 42 && pendingChange) {
        void (^c)(void) = pendingChange;
        pendingChange = nil;
        c();
    }
    [super sendEvent:e];
}
@end

// An opaque 8x8 marker in the top-left corner of the content, so the driver can find the window.
@interface Anchor : NSView
@end
@implementation Anchor
- (BOOL)isOpaque { return YES; }
- (void)drawRect:(NSRect)r { [[NSColor colorWithCalibratedRed:1 green:0 blue:1 alpha:1] set]; NSRectFill([self bounds]); }
@end

enum { W = 420, H = 260 };

static NSWindow *makeWindow(void)
{
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(200, 300, W, H)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    [w setReleasedWhenClosed:NO];
    Anchor *a = [[Anchor alloc] initWithFrame:NSMakeRect(0, H - 8, 8, 8)];
    [[w contentView] addSubview:a];
    return w;
}

static NSArray *sidebarTitles(void) { return @[@"Introduction", @"License", @"Destination Select", @"Installation Type", @"Installation", @"Summary"]; }

// Scenario "sidebar": the labels sit over a custom filled box; the selected one is bold.
static NSMutableArray *buildSidebar(NSWindow *w, NSUInteger selected)
{
    NSView *root = [w contentView];
    NSBox *box = [[NSBox alloc] initWithFrame:NSMakeRect(0, 0, 160, H)];
    [box setBoxType:NSBoxCustom];
    [box setBorderType:NSNoBorder];
    [box setFillColor:[NSColor colorWithCalibratedWhite:0.93 alpha:1]];
    [box setTitlePosition:NSNoTitle];
    [root addSubview:box positioned:NSWindowBelow relativeTo:nil];
    NSMutableArray *labels = [NSMutableArray array];
    CGFloat y = H - 50;
    for (NSString *t in sidebarTitles()) {
        NSTextField *l = [NSTextField labelWithString:t];
        [l setFrame:NSMakeRect(28, y, 128, 16)];
        [l setFont:[labels count] == selected ? [NSFont boldSystemFontOfSize:12] : [NSFont systemFontOfSize:12]];
        [root addSubview:l];
        [labels addObject:l];
        y -= 28;
    }
    return labels;
}

static void selectStep(NSArray *labels, NSUInteger selected)
{
    NSArray *t = sidebarTitles();
    for (NSUInteger i = 0; i < [labels count]; i++) {
        [labels[i] setFont:i == selected ? [NSFont boldSystemFontOfSize:12] : [NSFont systemFontOfSize:12]];
        [labels[i] setStringValue:t[i]];
    }
}

// Scenario "shrink": one label directly in the content view; a longer text becomes a shorter one.
static NSTextField *buildTitle(NSWindow *w, NSString *text)
{
    NSTextField *l = [NSTextField wrappingLabelWithString:text];
    [l setFrame:NSMakeRect(20, 150, W - 40, 24)];
    [l setFont:[NSFont boldSystemFontOfSize:15]];
    [[w contentView] addSubview:l];
    return l;
}

// Scenario "swap": a plain container view; its subviews are replaced by a new label.
static NSView *buildContainer(NSWindow *w, NSString *text, NSView **outLabel)
{
    NSView *c = [[NSView alloc] initWithFrame:NSMakeRect(20, 20, W - 40, 200)];
    [[w contentView] addSubview:c];
    NSTextField *l = [NSTextField wrappingLabelWithString:text];
    [l setFrame:NSMakeRect(0, 150, W - 40, 24)];
    [l setFont:[NSFont boldSystemFontOfSize:15]];
    [c addSubview:l];
    if (outLabel) *outLabel = l;
    return c;
}



static NSString *const kLong = @"The installation completed successfully.";
static NSString *const kShort = @"Finishing the installation…";

static void show(NSWindow *w)
{
    [w makeKeyAndOrderFront:nil];
}


// The steps run from the application's own event loop: each action is delivered as an event (like a
// click's action), then the driver is told, and the next step starts when it acknowledges.
static NSMutableArray *steps;   // blocks
static NSMutableArray *names;
static NSUInteger stepIndex;
static NSWindow *win;

static void runNext(void);

static void waitForAck(NSString *name)
{
    NSString *a = [stateDir stringByAppendingPathComponent:[name stringByAppendingString:@".ack"]];
    if (access([a fileSystemRepresentation], F_OK) != 0) {
        [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:NO block:^(NSTimer *t) { waitForAck(name); }];
        return;
    }
    runNext();
}

static void runNext(void)
{
    if (stepIndex >= [steps count]) {
        printf("DONE\n");
        fflush(stdout);
        exit(0);
    }
    NSString *name = names[stepIndex];
    void (^action)(void) = steps[stepIndex];
    stepIndex++;
    pendingChange = [^{
        action();
        [NSTimer scheduledTimerWithTimeInterval:0.8 repeats:NO block:^(NSTimer *t) {
            NSString *s = [stateDir stringByAppendingPathComponent:[name stringByAppendingString:@".state"]];
            [@"x\n" writeToFile:s atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            printf("STATE %s\n", [name UTF8String]);
            fflush(stdout);
            waitForAck(name);
        }];
    } copy];
    [NSApp postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSZeroPoint modifierFlags:0
        timestamp:0 windowNumber:0 context:nil subtype:42 data1:0 data2:0] atStart:NO];
}

static void add(NSString *n, void (^b)(void)) { [names addObject:n]; [steps addObject:[b copy]]; }

// Marker: a small drawn view (a dot) next to the current step
@interface Dot : NSView
@end
@implementation Dot
- (void)drawRect:(NSRect)r { [[NSColor blackColor] set]; [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect([self bounds], 0.5, 0.5)] fill]; }
@end

static NSArray *gSide; static NSArray *gDots; static NSView *gContent;
static NSTextField *gTitle;
static void buildInstallerLike(NSWindow *w, NSUInteger sel, NSUInteger dotSel, NSString *title)
{
    NSView *root = [w contentView];
    NSBox *box = [[NSBox alloc] initWithFrame:NSMakeRect(0, 0, 160, H)];
    [box setBoxType:NSBoxCustom]; [box setBorderType:NSNoBorder];
    [box setFillColor:[NSColor colorWithCalibratedWhite:0.93 alpha:1]]; [box setTitlePosition:NSNoTitle];
    [root addSubview:box positioned:NSWindowBelow relativeTo:nil];
    NSMutableArray *l = [NSMutableArray array], *d = [NSMutableArray array];
    CGFloat y = H - 60;
    for (NSString *t in sidebarTitles()) {
        NSTextField *f = [NSTextField labelWithString:t];
        [f setFrame:NSMakeRect(28, y, 128, 16)];
        [root addSubview:f]; [l addObject:f];
        Dot *m = [[Dot alloc] initWithFrame:NSMakeRect(14, y + 5, 7, 7)];
        [m setHidden:YES]; [root addSubview:m]; [d addObject:m];
        y -= 28;
    }
    gSide = [l retain]; gDots = [d retain];
    gContent = [[NSView alloc] initWithFrame:NSMakeRect(176, 20, W - 190, 200)];
    [root addSubview:gContent];
    for (NSUInteger i = 0; i < [l count]; i++) {
        [l[i] setFont:i == sel ? [NSFont boldSystemFontOfSize:12] : [NSFont systemFontOfSize:12]];
        [l[i] setStringValue:sidebarTitles()[i]];
        [d[i] setHidden:i != dotSel];
    }
    gTitle = [NSTextField wrappingLabelWithString:title];
    [gTitle setFrame:NSMakeRect(0, 150, W - 190, 24)];
    [gTitle setFont:[NSFont boldSystemFontOfSize:15]];
    [gContent addSubview:gTitle];
}
// flags: 1 replaces the title, 2 changes the fonts and strings of the steps, 4 moves the marker dots
static void installerStep(NSUInteger sel, NSString *title, int flags)
{
    if (flags & 1)
        for (NSView *v in [[gContent subviews] copy]) [v removeFromSuperview];
    for (NSUInteger i = 0; i < [gSide count]; i++) {
        if (flags & 2) {
            [gSide[i] setFont:i == sel ? [NSFont boldSystemFontOfSize:12] : [NSFont systemFontOfSize:12]];
            [gSide[i] setStringValue:sidebarTitles()[i]];
        }
        if (flags & 4)
            [gDots[i] setHidden:i != sel];
    }
    if (flags & 1) {
        gTitle = [NSTextField wrappingLabelWithString:title];
        [gTitle setFrame:NSMakeRect(0, 150, W - 190, 24)];
        [gTitle setFont:[NSFont boldSystemFontOfSize:15]];
        [gContent addSubview:gTitle];
    }
}

@interface Starter : NSObject
@end
@implementation Starter
- (void)applicationDidFinishLaunching:(NSNotification *)n { runNext(); }
@end

int main(int argc, char **argv)
{
    @autoreleasepool {
        stateDir = [NSString stringWithUTF8String:argc > 1 ? argv[1] : "/tmp"];
        [EventApp sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        NSMenu *bar = [[NSMenu alloc] initWithTitle:@"Main"];
        NSMenuItem *appItem = [bar addItemWithTitle:@"Test" action:NULL keyEquivalent:@""];
        NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Test"];
        [appMenu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
        [appItem setSubmenu:appMenu];
        [NSApp setMainMenu:bar];
        static Starter *starter; starter = [[Starter alloc] init];
        [NSApp setDelegate:starter];
        steps = [NSMutableArray array]; names = [NSMutableArray array];

        // Objects the steps share live in a dictionary we own, so that the program is correct with and without ARC.
        static NSMutableDictionary *st; st = [[NSMutableDictionary alloc] init];
        // sidebar: step 1 selected -> step 2 selected
        add(@"sidebar-A", ^{ win = makeWindow(); st[@"labels"] = buildSidebar(win, 1); show(win); });
        add(@"sidebar-B", ^{ selectStep(st[@"labels"], 2); });
        add(@"sidebar-ref", ^{ [win close]; win = makeWindow(); buildSidebar(win, 2); show(win); });
        // shrink: long string -> short string, same font
        add(@"shrink-A", ^{ [win close]; win = makeWindow(); st[@"title"] = buildTitle(win, kLong); show(win); });
        add(@"shrink-B", ^{ [st[@"title"] setStringValue:kShort]; });
        add(@"shrink-ref", ^{ [win close]; win = makeWindow(); buildTitle(win, kShort); show(win); });
        // swap: remove the container's label, add another at the same place
        add(@"swap-A", ^{ [win close]; win = makeWindow(); NSView *old = nil; st[@"container"] = buildContainer(win, kShort, &old); st[@"old"] = old; show(win); });
        add(@"swap-B", ^{
            [st[@"old"] removeFromSuperview];
            NSTextField *n = [NSTextField wrappingLabelWithString:kLong];
            [n setFrame:NSMakeRect(0, 150, W - 40, 24)];
            [n setFont:[NSFont boldSystemFontOfSize:15]];
            [st[@"container"] addSubview:n];
        });
        add(@"swap-ref", ^{ [win close]; win = makeWindow(); buildContainer(win, kLong, NULL); show(win); });
        static const struct { const char *name; int flags; } variants[] = {
            { "installer", 7 }, { "installer-title", 1 }, { "installer-fonts", 2 }, { "installer-dots", 4 },
            { "installer-tf", 3 }, { "installer-fd", 6 } };
        for (int i = 0; i < 6; i++) {
            int fl = variants[i].flags;
            NSString *nm = [NSString stringWithUTF8String:variants[i].name];
            // the state after the change: the step only changes what the flags name
            NSUInteger selA = 1, selB = (fl & 6) ? 2 : 1;
            NSString *titleB = (fl & 1) ? kLong : kShort;
            add([nm stringByAppendingString:@"-A"], ^{ [win close]; win = makeWindow(); buildInstallerLike(win, selA, selA, kShort); show(win); });
            add([nm stringByAppendingString:@"-B"], ^{ installerStep(selB, titleB, fl); });
            add([nm stringByAppendingString:@"-ref"], ^{ [win close]; win = makeWindow(); buildInstallerLike(win, (fl & 2) ? selB : selA, (fl & 4) ? selB : selA, titleB); show(win); });
        }
        [NSApp run];
    }
    return 0;
}
