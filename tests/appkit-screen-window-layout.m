/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// NSScreen safe-area properties, NSWindow contentLayoutRect, accessibilityFrame
// and backingAlignedRect:options:, and the effectiveAppearance KVO
// dependencies of NSWindow and NSApplication. Expected values for the rect
// alignment and the observation counts were observed on macOS. The appearance
// part needs a display, because it orders a window in.
#import <AppKit/AppKit.h>
#include <stdio.h>

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

@interface Counter : NSObject
@property int count;
@end

@implementation Counter
- (void) observeValueForKeyPath: (NSString *) keyPath
                       ofObject: (id) object
                         change: (NSDictionary *) change
                        context: (void *) context
{
    self.count++;
}
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        // A screen without a camera housing: nothing is unsafe and there are
        // no auxiliary areas.
        NSScreen *screen = [NSScreen mainScreen];
        if (screen != nil) {
            NSEdgeInsets insets = [screen safeAreaInsets];
            expect(insets.top == 0 && insets.left == 0 && insets.bottom == 0 &&
                           insets.right == 0,
                   "safeAreaInsets is zero");
            expect(NSIsEmptyRect([screen auxiliaryTopLeftArea]),
                   "auxiliaryTopLeftArea is empty");
            expect(NSIsEmptyRect([screen auxiliaryTopRightArea]),
                   "auxiliaryTopRightArea is empty");
        }

        NSWindow *window = [[NSWindow alloc]
                initWithContentRect: NSMakeRect(100, 100, 300, 200)
                          styleMask: NSWindowStyleMaskTitled |
                                     NSWindowStyleMaskClosable
                            backing: NSBackingStoreBuffered
                              defer: YES];
        NSRect frame = [window frame];
        NSRect layout = [window contentLayoutRect];
        // In window coordinates and inside the window.
        expect(layout.origin.x >= 0 && layout.origin.y >= 0 &&
                       NSMaxX(layout) <= frame.size.width &&
                       NSMaxY(layout) <= frame.size.height,
               "contentLayoutRect lies inside the window in window coordinates");
        NSRect content = [window contentRectForFrameRect: frame];
        expect(NSEqualSizes(layout.size, content.size),
               "contentLayoutRect of a plain titled window is the content rect");
        expect(NSEqualRects([window accessibilityFrame], frame),
               "window accessibilityFrame is its frame in screen coordinates");

        NSWindow *borderless = [[NSWindow alloc]
                initWithContentRect: NSMakeRect(10, 20, 100, 50)
                          styleMask: NSWindowStyleMaskBorderless
                            backing: NSBackingStoreBuffered
                              defer: YES];
        expect(NSEqualRects([borderless contentLayoutRect], NSMakeRect(0, 0, 100, 50)),
               "contentLayoutRect of a borderless window is its whole area");

        // Edge alignment at one backing pixel per point.
        if ([window backingScaleFactor] == 1.0) {
            NSRect r = NSMakeRect(10.4, 20.6, 30.2, 40.7);
            expect(NSEqualRects([window backingAlignedRect: r options: NSAlignAllEdgesNearest],
                                NSMakeRect(10, 21, 31, 40)),
                   "alignment to the nearest edges");
            expect(NSEqualRects([window backingAlignedRect: r options: NSAlignAllEdgesInward],
                                NSMakeRect(11, 21, 29, 40)),
                   "alignment to inward edges");
            expect(NSEqualRects([window backingAlignedRect: r options: NSAlignAllEdgesOutward],
                                NSMakeRect(10, 20, 31, 42)),
                   "alignment to outward edges");
            expect(NSEqualRects([window backingAlignedRect: r
                                                   options: NSAlignMinXInward | NSAlignMaxXOutward |
                                                            NSAlignMinYNearest | NSAlignMaxYNearest],
                                NSMakeRect(11, 21, 30, 40)),
                   "alignment with a different mode per edge");
            expect(NSEqualRects([window backingAlignedRect: NSMakeRect(5, 6, 7, 8)
                                                   options: NSAlignAllEdgesNearest],
                                NSMakeRect(5, 6, 7, 8)),
                   "an aligned rect is unchanged");
        }

        // effectiveAppearance is key-value observable. The window is ordered
        // in first: a window that was never shown did not report the
        // application's appearance changes on macOS.
        [window orderFront: nil];
        [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.3]];
        Counter *windowCounter = [[Counter alloc] init];
        Counter *appCounter = [[Counter alloc] init];
        [window addObserver: windowCounter forKeyPath: @"effectiveAppearance" options: 0 context: NULL];
        [NSApp addObserver: appCounter forKeyPath: @"effectiveAppearance" options: 0 context: NULL];

        [window setAppearance: [NSAppearance appearanceNamed: NSAppearanceNameDarkAqua]];
        expect(windowCounter.count == 1, "window appearance change notifies the window's effectiveAppearance");
        expect(appCounter.count == 0, "window appearance change does not notify the application");

        [NSApp setAppearance: [NSAppearance appearanceNamed: NSAppearanceNameDarkAqua]];
        expect(appCounter.count == 1, "application appearance change notifies the application's effectiveAppearance");
        expect(windowCounter.count == 2, "application appearance change notifies the window's effectiveAppearance");

        [window setAppearance: nil];
        expect(windowCounter.count == 3, "clearing the window appearance notifies");
        [window orderOut: nil];

        [window removeObserver: windowCounter forKeyPath: @"effectiveAppearance"];
        [NSApp removeObserver: appCounter forKeyPath: @"effectiveAppearance"];
    }

    if (failures == 0)
        printf("PASS\n");
    return failures == 0 ? 0 : 1;
}
