// Copyright (C) 2026 Lubos Dolezel
//
// Guest test: -[NSWindow registerScrollViewSeparatorTrackingAdapter:] and
// -unregisterScrollViewSeparatorTrackingAdapter:, and
// -[NSAppearance _usesMetricsAppearance], SPI that WKWebView uses when it is
// put in a window. Observed on macOS 26.7.3 (x86_64) with the same calls:
// every named appearance uses the metrics appearance; registering asks the
// adapter for its frame at once, returns YES (also again, and for a view that
// is not in the window), raises for nil and for an object without
// -scrollViewFrame; unregistering is harmless whether or not registered.
#import <Cocoa/Cocoa.h>
#include <stdio.h>

@interface NSAppearance (MetricsSPI)
- (BOOL)_usesMetricsAppearance;
@end

@interface NSWindow (SeparatorTrackingSPI)
- (BOOL)registerScrollViewSeparatorTrackingAdapter:(id)adapter;
- (void)unregisterScrollViewSeparatorTrackingAdapter:(id)adapter;
@end

@interface TestAdapter : NSView
@property int frameCalls;
@end
@implementation TestAdapter
- (NSRect)scrollViewFrame
{
    self.frameCalls++;
    return self.frame;
}
- (BOOL)hasScrolledContentsUnderTitlebar
{
    return NO;
}
@end

static int failures;

static void report(const char *name, BOOL ok)
{
    printf("%s: %s\n", ok ? "PASS" : "FAIL", name);
    if (!ok)
        failures++;
}

static BOOL raises(void (^block)(void))
{
    @try {
        block();
    } @catch (NSException *exception) {
        return YES;
    }
    return NO;
}

int main(void)
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        BOOL all = YES;
        for (NSAppearanceName name in @[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua, NSAppearanceNameVibrantLight, NSAppearanceNameVibrantDark ])
            all = all && [[NSAppearance appearanceNamed: name] _usesMetricsAppearance];
        report("every named appearance uses the metrics appearance", all);

        NSWindow *window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 300, 200)
                                                       styleMask: NSWindowStyleMaskTitled
                                                         backing: NSBackingStoreBuffered
                                                           defer: NO];
        TestAdapter *adapter = [[[TestAdapter alloc] initWithFrame: NSMakeRect(0, 0, 300, 200)] autorelease];
        [window setContentView: adapter];
        report("the content view uses the metrics appearance", [[adapter effectiveAppearance] _usesMetricsAppearance]);

        report("registering returns YES", [window registerScrollViewSeparatorTrackingAdapter: adapter]);
        report("registering asks for the frame", adapter.frameCalls >= 1);
        report("registering again returns YES", [window registerScrollViewSeparatorTrackingAdapter: adapter]);
        TestAdapter *outside = [[[TestAdapter alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)] autorelease];
        report("a view not in the window can register", [window registerScrollViewSeparatorTrackingAdapter: outside]);
        report("an object without -scrollViewFrame raises",
               raises(^{ [window registerScrollViewSeparatorTrackingAdapter: [[NSObject new] autorelease]]; }));
        report("nil raises", raises(^{ [window registerScrollViewSeparatorTrackingAdapter: nil]; }));

        report("unregistering is harmless", !raises(^{
            [window unregisterScrollViewSeparatorTrackingAdapter: adapter];
            [window unregisterScrollViewSeparatorTrackingAdapter: adapter];
            [window unregisterScrollViewSeparatorTrackingAdapter: [[NSObject new] autorelease]];
        }));
        report("registering after unregistering returns YES", [window registerScrollViewSeparatorTrackingAdapter: adapter]);
        [window unregisterScrollViewSeparatorTrackingAdapter: adapter];
        [window unregisterScrollViewSeparatorTrackingAdapter: outside];
        [window close];
    }
    return failures != 0;
}
