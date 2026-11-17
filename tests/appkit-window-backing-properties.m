// Copyright (C) 2026 Lubos Dolezel
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>

// NSWindowDidChangeBackingPropertiesNotification: when the window's backing scale
// factor changes (a window system backend reports it, as the Wayland backend does
// when a window moves to an output with another scale) the window posts the
// notification with the previous scale in NSBackingPropertyOldScaleFactorKey, the
// delegate's windowDidChangeBackingProperties: runs, and every view of the window,
// parent first, gets viewDidChangeBackingProperties. Nothing is sent when the scale
// did not actually change. The backend's report is simulated: the platform window
// is made to return another scale and then tells the window, as a backend does.
// Darling only (macOS windows have no platform window); skipped there.

static CGFloat reportedScale = 1.0;
static int failures;

static void expectTrue(BOOL ok, const char *what) {
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

static NSMutableArray *events;

static CGFloat reportedScaleImp(id self, SEL _cmd) {
    return reportedScale;
}

@interface ScaleView : NSView {
@public
    NSString *label;
}
@end
@implementation ScaleView
- (void) viewDidChangeBackingProperties {
    [events addObject: [@"view:" stringByAppendingString: label]];
}
@end

@interface ScaleDelegate : NSObject <NSWindowDelegate>
@end
@implementation ScaleDelegate
- (void) windowDidChangeBackingProperties: (NSNotification *) note {
    [events addObject: @"delegate"];
}
@end

@interface ScaleObserver : NSObject {
@public
    NSNumber *oldScale;
    id oldColorSpace;
    NSUInteger count;
}
- (void) changed: (NSNotification *) note;
@end
@implementation ScaleObserver
- (void) changed: (NSNotification *) note {
    count++;
    oldScale = [[note userInfo] objectForKey: NSBackingPropertyOldScaleFactorKey];
    oldColorSpace = [[note userInfo] objectForKey: NSBackingPropertyOldColorSpaceKey];
    [events addObject: @"note"];
}
@end

@interface NSWindow (BackingPropertiesTest)
- (id) platformWindow;
@end
@interface NSObject (BackendReport)
- (void) platformWindow: (id) window didChangeBackingScaleFrom: (CGFloat) oldScale;
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        events = [NSMutableArray array];
        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(50, 50, 200, 150)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        if (![window respondsToSelector: @selector(platformWindow)]) {
            puts("SKIP: no platform window (macOS)");
            return 0;
        }
        id platform = [window platformWindow];
        Method method = class_getInstanceMethod([platform class], @selector(backingScaleFactor));
        if (platform == nil || method == NULL) {
            puts("SKIP: the platform window has no backingScaleFactor");
            return 0;
        }
        method_setImplementation(method, (IMP) reportedScaleImp);

        ScaleView *parent = [[ScaleView alloc] initWithFrame: NSMakeRect(0, 0, 200, 150)];
        parent->label = @"parent";
        ScaleView *child = [[ScaleView alloc] initWithFrame: NSMakeRect(10, 10, 50, 50)];
        child->label = @"child";
        [parent addSubview: child];
        [window setContentView: parent];
        ScaleDelegate *delegate = [ScaleDelegate new];
        window.delegate = delegate;
        ScaleObserver *observer = [ScaleObserver new];
        [[NSNotificationCenter defaultCenter] addObserver: observer
                                                 selector: @selector(changed:)
                                                     name: NSWindowDidChangeBackingPropertiesNotification
                                                   object: window];

        expectTrue([window backingScaleFactor] == 1.0, "the window starts at scale 1");

        reportedScale = 2.0;
        [window platformWindow: platform didChangeBackingScaleFrom: 1.0];
        expectTrue(observer->count == 1, "one notification for the change");
        expectTrue([observer->oldScale doubleValue] == 1.0, "NSBackingPropertyOldScaleFactorKey holds the previous scale");
        expectTrue([window backingScaleFactor] == 2.0, "the window reports the new scale");
        NSArray *want = @[@"delegate", @"note", @"view:parent", @"view:child"];
        // The delegate is an observer registered before the test's, so it runs first.
        expectTrue([events isEqualToArray: want], "delegate, observer, then the views parent first");
        if (![events isEqualToArray: want])
            printf("events=%s\n", [[events componentsJoinedByString: @","] UTF8String]);

        [events removeAllObjects];
        [window platformWindow: platform didChangeBackingScaleFrom: 2.0];
        expectTrue([events count] == 0, "nothing is sent when the scale did not change");

        reportedScale = 1.5;
        [window platformWindow: platform didChangeBackingScaleFrom: 2.0];
        expectTrue(observer->count == 2 && [observer->oldScale doubleValue] == 2.0, "a second change reports its own previous scale");

        [window close];
    }
    printf("%s\n", failures ? "FAIL" : "PASS");
    return failures != 0;
}
