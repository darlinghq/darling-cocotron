// Copyright (C) 2026 Lubos Dolezel
// An idle window does not lay out again: display cycles that only redraw a view must not read the
// intrinsic sizes of constrained views, call their -layout or update the constraints of a stack view
// that arranges its views with constraints. Layout still runs, without an explicit
// -layoutSubtreeIfNeeded, when a constraint constant changes, when an intrinsic size is invalidated
// (also of a view in the stack view) and when the window is resized. Resizing a view that is in no
// view tree, as a scroll view does with a scroller it removed, lays nothing out, while such a view
// is laid out itself after its size changed. A window whose content needs a fractional width
// gets the nearest whole points (300 for 300.25) and then stays idle.
#import <Cocoa/Cocoa.h>
#include <stdio.h>

static int failures;
#define CHECK(condition) do { if (!(condition)) { \
    fprintf(stderr, "failed line %d: %s\n", __LINE__, #condition); failures++; \
} } while (0)

static long intrinsicReads, layoutCalls, drawCalls, stackConstraintUpdates;

@interface RowView : NSView {
@public
    CGFloat _width;
}
@end
@implementation RowView
- (NSSize)intrinsicContentSize { intrinsicReads++; return NSMakeSize(_width, 18); }
- (void)layout { layoutCalls++; [super layout]; }
@end

@interface CountingStackView : NSStackView
@end
@implementation CountingStackView
- (void)updateConstraints { stackConstraintUpdates++; [super updateConstraints]; }
- (void)layout { layoutCalls++; [super layout]; }
@end

@interface DrawView : NSView
@end
@implementation DrawView
- (void)drawRect:(NSRect)rect { drawCalls++; [[NSColor grayColor] set]; NSRectFill(rect); }
@end

@interface Poker : NSObject {
@public
    NSView *view;
    NSView *lone;
    int ticks;
}
@end
@implementation Poker
- (void)poke:(NSTimer *)timer
{
    [view setNeedsDisplay:YES];
    [lone setFrameSize:NSMakeSize(++ticks % 2 ? 120 : 100, 15)];
}
@end

static void spin(double seconds)
{
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while ([end timeIntervalSinceNow] > 0) {
        NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:end inMode:NSDefaultRunLoopMode dequeue:YES];
        if (event != nil)
            [NSApp sendEvent:event];
    }
}

static void resetCounters(void) { intrinsicReads = 0; layoutCalls = 0; drawCalls = 0; stackConstraintUpdates = 0; }

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        [NSApp finishLaunching];

        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 500, 400)
                                                       styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                                         backing:NSBackingStoreBuffered defer:NO];
        NSView *content = [window contentView];
        enum { kRows = 40 };
        RowView *rows[kRows];
        NSLayoutConstraint *firstLeading = nil;
        NSView *previous = nil;
        for (int i = 0; i < kRows; ++i) {
            RowView *row = [[RowView alloc] initWithFrame:NSZeroRect];
            row->_width = 100 + i;
            [row setTranslatesAutoresizingMaskIntoConstraints:NO];
            [content addSubview:row];
            NSLayoutConstraint *leading = [[row leadingAnchor] constraintEqualToAnchor:[content leadingAnchor] constant:20];
            NSLayoutConstraint *top = previous ? [[row topAnchor] constraintEqualToAnchor:[previous bottomAnchor] constant:2]
                                               : [[row topAnchor] constraintEqualToAnchor:[content topAnchor] constant:4];
            [leading setActive:YES];
            [top setActive:YES];
            if (i == 0)
                firstLeading = leading;
            rows[i] = row;
            previous = row;
        }
        // a view that follows the window's right edge
        DrawView *corner = [[DrawView alloc] initWithFrame:NSZeroRect];
        [corner setTranslatesAutoresizingMaskIntoConstraints:NO];
        [content addSubview:corner];
        [[[corner trailingAnchor] constraintEqualToAnchor:[content trailingAnchor] constant:-10] setActive:YES];
        [[[corner bottomAnchor] constraintEqualToAnchor:[content bottomAnchor] constant:-10] setActive:YES];
        [[[corner widthAnchor] constraintEqualToConstant:30] setActive:YES];
        [[[corner heightAnchor] constraintEqualToConstant:30] setActive:YES];

        // a stack view placed by constraints, which arranges its views with constraints
        CountingStackView *stack = [[CountingStackView alloc] initWithFrame:NSZeroRect];
        [stack setTranslatesAutoresizingMaskIntoConstraints:NO];
        [stack setOrientation:NSUserInterfaceLayoutOrientationHorizontal];
        RowView *stacked[2];
        for (int i = 0; i < 2; ++i) {
            stacked[i] = [[RowView alloc] initWithFrame:NSZeroRect];
            stacked[i]->_width = 60;
            [stack addArrangedSubview:stacked[i]];
        }
        [content addSubview:stack];
        [[[stack leadingAnchor] constraintEqualToAnchor:[content leadingAnchor] constant:20] setActive:YES];
        [[[stack bottomAnchor] constraintEqualToAnchor:[content bottomAnchor] constant:-10] setActive:YES];

        [window makeKeyAndOrderFront:nil];
        spin(0.5);
        CHECK(NSMinX([rows[0] frame]) == 20);
        CHECK(NSWidth([rows[3] frame]) == 103);
        CHECK(NSMaxX([corner frame]) == NSWidth([content bounds]) - 10);
        CHECK(NSWidth([stacked[1] frame]) == 60);

        // 1. Display cycles that only redraw a view lay nothing out.
        Poker *poker = [[Poker alloc] init];
        poker->view = corner;
        poker->lone = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 15)];
        NSTimer *timer = [NSTimer timerWithTimeInterval:0.01 target:poker selector:@selector(poke:) userInfo:nil repeats:YES];
        [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
        resetCounters();
        spin(0.6);
        fprintf(stderr, "idle: draws %ld, intrinsic reads %ld, layout calls %ld, stack constraint updates %ld\n", drawCalls,
                intrinsicReads, layoutCalls, stackConstraintUpdates);
        CHECK(drawCalls >= 5);
        CHECK(intrinsicReads == 0);
        CHECK(layoutCalls == 0);
        CHECK(stackConstraintUpdates == 0);

        // 2. A changed constant is laid out at the next display cycle.
        [firstLeading setConstant:45];
        spin(0.2);
        CHECK(NSMinX([rows[0] frame]) == 45);

        // 3. An invalidated intrinsic size is read again and applied.
        rows[5]->_width = 150;
        [rows[5] invalidateIntrinsicContentSize];
        spin(0.2);
        CHECK(NSWidth([rows[5] frame]) == 150);
        stacked[1]->_width = 90;
        [stacked[1] invalidateIntrinsicContentSize];
        spin(0.2);
        CHECK(NSWidth([stacked[1] frame]) == 90);

        // 4. A resized window lays out its content again.
        NSRect frame = [window frame];
        frame.size.width += 60;
        [window setFrame:frame display:YES];
        spin(0.2);
        CHECK(NSMaxX([corner frame]) == NSWidth([content bounds]) - 10);
        CHECK(NSWidth([content bounds]) == 560);

        // 5. And then it is idle again.
        resetCounters();
        spin(0.4);
        fprintf(stderr, "idle again: draws %ld, intrinsic reads %ld, layout calls %ld, stack constraint updates %ld\n",
                drawCalls, intrinsicReads, layoutCalls, stackConstraintUpdates);
        CHECK(drawCalls >= 3);
        CHECK(intrinsicReads == 0);
        CHECK(layoutCalls == 0);
        CHECK(stackConstraintUpdates == 0);

        [timer invalidate];

        // 6. A view in no view tree is laid out itself after its size changed.
        RowView *alone = [[RowView alloc] initWithFrame:NSMakeRect(0, 0, 50, 18)];
        [alone layoutSubtreeIfNeeded];
        resetCounters();
        [alone setFrameSize:NSMakeSize(70, 18)];
        CHECK([alone needsLayout]);
        [alone layoutSubtreeIfNeeded];
        CHECK(layoutCalls == 1);
        CHECK(![alone needsLayout]);

        // 7. A fractional minimum content width.
        NSWindow *narrow = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 200, 150)
                                                       styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                                         backing:NSBackingStoreBuffered defer:NO];
        RowView *fill = [[RowView alloc] initWithFrame:NSZeroRect];
        fill->_width = NSViewNoIntrinsicMetric;
        [fill setTranslatesAutoresizingMaskIntoConstraints:NO];
        NSView *narrowContent = [narrow contentView];
        [narrowContent addSubview:fill];
        [[[fill leadingAnchor] constraintEqualToAnchor:[narrowContent leadingAnchor]] setActive:YES];
        [[[fill trailingAnchor] constraintEqualToAnchor:[narrowContent trailingAnchor]] setActive:YES];
        [[[fill topAnchor] constraintEqualToAnchor:[narrowContent topAnchor]] setActive:YES];
        [[[fill bottomAnchor] constraintEqualToAnchor:[narrowContent bottomAnchor]] setActive:YES];
        [[[fill widthAnchor] constraintGreaterThanOrEqualToConstant:300.25] setActive:YES];
        [narrow makeKeyAndOrderFront:nil];
        spin(0.5);
        fprintf(stderr, "fractional minimum: content width %g\n", NSWidth([narrowContent bounds]));
        CHECK(NSWidth([narrowContent bounds]) == 300);
        resetCounters();
        spin(0.5);
        CHECK(layoutCalls == 0);
        CHECK(intrinsicReads == 0);
        [narrow orderOut:nil];
        [window orderOut:nil];
    }
    if (failures == 0)
        printf("PASS\n");
    return failures ? 1 : 0;
}
