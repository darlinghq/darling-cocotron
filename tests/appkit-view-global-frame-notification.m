/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// NSViewGlobalFrameDidChangeNotification is posted for a view that has an
// NSOpenGLContext attached when its frame changes (an application observes it
// to call -[NSOpenGLContext update]); other views do not post it. On macOS it
// is posted from inside -setFrame:; here it is delivered when the run loop is
// idle, so the test waits for it. Also: -trackingAreas is a snapshot, so
// removing areas while walking it is safe.
#import <AppKit/AppKit.h>
#import <OpenGL/OpenGL.h>
#include <stdio.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

static void spin(NSTimeInterval seconds) {
    [[NSRunLoop currentRunLoop]
            runUntilDate: [NSDate dateWithTimeIntervalSinceNow: seconds]];
}

static BOOL waitFor(int (^done)(void), NSTimeInterval seconds) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow: seconds];
    while (!done() && [end timeIntervalSinceNow] > 0)
        spin(0.05);
    return done();
}

@interface Counter : NSObject {
    int _count;
}
@property(nonatomic) int count;
@end

@implementation Counter
@synthesize count = _count;
- (void) changed: (NSNotification *) note {
    _count++;
}
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        Counter *counter = [[Counter alloc] init];

        NSWindow *window = [[NSWindow alloc]
                initWithContentRect: NSMakeRect(100, 100, 400, 300)
                          styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                            backing: NSBackingStoreBuffered
                              defer: NO];
        NSView *child = [[NSView alloc] initWithFrame: NSMakeRect(10, 10, 50, 50)];
        [[window contentView] addSubview: child];
        [[NSNotificationCenter defaultCenter] addObserver: counter
                                                 selector: @selector(changed:)
                                                     name: NSViewGlobalFrameDidChangeNotification
                                                   object: child];

        // A view without a context posts nothing.
        [child setFrame: NSMakeRect(20, 20, 60, 60)];
        spin(0.3);
        expect(counter.count == 0, "a view without a context posts no global frame notification");

        // A view with a context attached posts when its frame changes.
        NSOpenGLPixelFormatAttribute attributes[] = {NSOpenGLPFADoubleBuffer, 0};
        NSOpenGLPixelFormat *format = [[NSOpenGLPixelFormat alloc] initWithAttributes: attributes];
        NSOpenGLContext *context = [[NSOpenGLContext alloc] initWithFormat: format shareContext: nil];
        [context setView: child];
        [child setFrame: NSMakeRect(30, 30, 60, 60)];
        expect(waitFor(^int { return counter.count >= 1; }, 2.0),
               "a view with a context posts a global frame notification when its frame changes");
        int before = counter.count;
        [child setFrame: NSMakeRect(30, 30, 60, 60)];
        spin(0.3);
        expect(counter.count == before, "an unchanged frame posts none");

        // A window resize reaches the view through autoresizing.
        [child setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
        [window makeKeyAndOrderFront: nil];
        spin(0.5);
        counter.count = 0;
        NSRect frame = [window frame];
        frame.size.width += 100;
        [window setFrame: frame display: YES];
        expect(waitFor(^int { return counter.count > 0; }, 3.0),
               "a window resize reaches the context's view");

        // -trackingAreas is a snapshot.
        for (int i = 0; i < 3; i++) {
            NSTrackingArea *area = [[NSTrackingArea alloc]
                    initWithRect: NSMakeRect(0, 0, 10 + i, 10)
                         options: NSTrackingMouseMoved | NSTrackingActiveAlways
                           owner: child
                        userInfo: nil];
            [child addTrackingArea: area];
        }
        NSArray *areas = [child trackingAreas];
        expect([areas count] == 3, "three tracking areas");
        @try {
            NSArray *walked = [child trackingAreas];
            for (NSUInteger i = 0, n = [walked count]; i < n; i++)
                [child removeTrackingArea: [walked objectAtIndex: i]];
            expect([[child trackingAreas] count] == 0, "all areas removed through the snapshot");
        } @catch (NSException *exception) {
            expect(NO, "removing areas while walking -trackingAreas does not raise");
        }
        expect([areas count] == 3, "an earlier snapshot is not changed by later removals");

        [[NSNotificationCenter defaultCenter] removeObserver: counter];
        [context clearDrawable];
        [window close];
    }
    if (failures == 0)
        printf("PASS\n");
    return failures != 0;
}
