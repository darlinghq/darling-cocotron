/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// NSView API with documented defaults and small behaviours: the deprecated
// touch flags, conversions to and from layer coordinates, the contextual menu
// notification hooks, the responsive scrolling hooks, safe area insets,
// ancestorSharedWithView: and the override hooks that must do nothing.
// Expected values were observed on macOS 10.14.4 and 26.7.3.
#import <AppKit/AppKit.h>
#include <stdio.h>
#include <string.h>

// Declared here so that the test also builds against headers that predate
// them; the signatures are the public ones.
@interface NSView (ViewGeometryTest)
- (BOOL) layerUsesCoreImageFilters;
- (void) setLayerUsesCoreImageFilters: (BOOL) flag;
- (BOOL) allowsVibrancy;
+ (BOOL) isCompatibleWithResponsiveScrolling;
- (void) prepareContentInRect: (NSRect) rect;
- (NSRect) rectForSmartMagnificationAtPoint: (NSPoint) location
                                     inRect: (NSRect) visibleRect;
- (NSPoint) convertPointToLayer: (NSPoint) point;
- (NSPoint) convertPointFromLayer: (NSPoint) point;
- (NSSize) convertSizeToLayer: (NSSize) size;
- (NSSize) convertSizeFromLayer: (NSSize) size;
- (NSRect) convertRectToLayer: (NSRect) rect;
- (NSRect) convertRectFromLayer: (NSRect) rect;
- (void) willOpenMenu: (NSMenu *) menu withEvent: (NSEvent *) event;
- (void) didCloseMenu: (NSMenu *) menu withEvent: (NSEvent *) event;
- (void) noteFocusRingMaskChanged;
- (NSRect) safeAreaRect;
- (NSEdgeInsets) additionalSafeAreaInsets;
- (void) setAdditionalSafeAreaInsets: (NSEdgeInsets) insets;
@end

@interface FlippedView : NSView
@end
@implementation FlippedView
- (BOOL) isFlipped {
    return YES;
}
@end

@interface SubviewRecorder : NSView {
  @public
    int added, willRemove;
}
@end
@implementation SubviewRecorder
- (void) didAddSubview: (NSView *) subview {
    [super didAddSubview: subview];
    added++;
}
- (void) willRemoveSubview: (NSView *) subview {
    [super willRemoveSubview: subview];
    willRemove++;
}
@end

static int failures;

static void expect(BOOL condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

static BOOL rectIs(NSRect r, CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
    return r.origin.x == x && r.origin.y == y && r.size.width == w &&
           r.size.height == h;
}

// QUIRK pin: macOS 10.14 mirrors the y axis of a flipped layer-backed view
// within its bounds when converting to layer coordinates; macOS 11 and later
// return the value unchanged. Darling follows 10.14.
static BOOL mirrorsFlippedViews(void) {
    if ([[NSFileManager defaultManager] fileExistsAtPath: @"/Volumes/SystemRoot"])
        return YES;
    NSOperatingSystemVersion v = [[NSProcessInfo processInfo] operatingSystemVersion];
    return v.majorVersion == 10;
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];

        NSView *view = [[NSView alloc] initWithFrame: NSMakeRect(10, 20, 100, 50)];

        // Touch flags (deprecated): off by default and stored.
        expect(![view acceptsTouchEvents], "acceptsTouchEvents defaults to NO");
        expect(![view wantsRestingTouches], "wantsRestingTouches defaults to NO");
        [view setAcceptsTouchEvents: YES];
        [view setWantsRestingTouches: YES];
        expect([view acceptsTouchEvents], "acceptsTouchEvents is stored");
        expect([view wantsRestingTouches], "wantsRestingTouches is stored");
        [view setAcceptsTouchEvents: NO];
        expect(![view acceptsTouchEvents], "acceptsTouchEvents can be cleared");
        expect([view wantsRestingTouches],
               "the two touch flags are independent");

        // Documented defaults.
        expect(![view acceptsFirstMouse: nil], "acceptsFirstMouse: is NO");
        expect(![view shouldDelayWindowOrderingForEvent: nil],
               "shouldDelayWindowOrderingForEvent: is NO");
        expect([view wantsDefaultClipping], "wantsDefaultClipping is YES");
        expect(![view preservesContentDuringLiveResize],
               "preservesContentDuringLiveResize is NO");
        expect(NSIsEmptyRect([view rectPreservedDuringLiveResize]),
               "no preserved rect by default");
        expect([view shouldDrawColor], "shouldDrawColor is YES");
        expect([NSView defaultFocusRingType] == NSFocusRingTypeExterior,
               "defaultFocusRingType is exterior");
        expect(![view allowsVibrancy], "allowsVibrancy is NO");
        expect(![view layerUsesCoreImageFilters],
               "layerUsesCoreImageFilters is NO");
        [view setLayerUsesCoreImageFilters: YES];
        expect([view layerUsesCoreImageFilters],
               "layerUsesCoreImageFilters is stored");
        expect([NSView isCompatibleWithResponsiveScrolling],
               "views are compatible with responsive scrolling");
        expect(NSIsEmptyRect([view rectForSmartMagnificationAtPoint: NSMakePoint(5, 5)
                                                             inRect: NSMakeRect(0, 0, 100, 50)]),
               "no smart magnification rect by default");
        [view prepareContentInRect: NSMakeRect(1, 2, 30, 40)];
        expect(rectIs([view preparedContentRect], 1, 2, 30, 40),
               "prepareContentInRect: sets preparedContentRect");

        // Hooks that do nothing but must exist.
        [view willOpenMenu: [[NSMenu alloc] init] withEvent: nil];
        [view didCloseMenu: [[NSMenu alloc] init] withEvent: nil];
        [view noteFocusRingMaskChanged];
        expect(![view performMnemonic: @"x"], "performMnemonic: is NO");

        // Subview hooks are called, and the defaults are harmless.
        SubviewRecorder *parent = [[SubviewRecorder alloc] initWithFrame: NSMakeRect(0, 0, 50, 50)];
        NSView *child = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
        [parent addSubview: child];
        expect(parent->added == 1, "didAddSubview: called");
        [child removeFromSuperview];
        expect(parent->willRemove == 1, "willRemoveSubview: called");

        // ancestorSharedWithView:
        NSView *a = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 50, 50)];
        NSView *b = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
        NSView *c = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
        NSView *root = [[NSView alloc] initWithFrame: NSMakeRect(0, 0, 100, 100)];
        [root addSubview: a];
        [root addSubview: b];
        [a addSubview: c];
        expect([c ancestorSharedWithView: b] == root, "shared ancestor of cousins");
        expect([c ancestorSharedWithView: a] == a, "shared ancestor with a parent");
        expect([a ancestorSharedWithView: a] == a, "a view shares itself");
        expect([root ancestorSharedWithView: c] == root, "root shares with a descendant");
        expect([c ancestorSharedWithView: [[NSView alloc] init]] == nil,
               "unrelated views share nothing");

        // Safe area: nothing is unsafe, additional insets shrink the rect
        // (additionalSafeAreaInsets is 11.0 and later).
        if ([view respondsToSelector: @selector(safeAreaRect)]) {
            expect(rectIs([view safeAreaRect], 0, 0, 100, 50),
                   "safeAreaRect is the bounds");
            NSEdgeInsets insets = [view additionalSafeAreaInsets];
            expect(insets.top == 0 && insets.left == 0 && insets.bottom == 0 &&
                           insets.right == 0,
                   "no additional safe area by default");
            [view setAdditionalSafeAreaInsets: NSEdgeInsetsMake(5, 10, 15, 20)];
            expect(rectIs([view safeAreaRect], 10, 15, 70, 30),
                   "additional insets shrink the safe area rect");
            NSView *flipped = [[FlippedView alloc] initWithFrame: NSMakeRect(0, 0, 100, 50)];
            [flipped setAdditionalSafeAreaInsets: NSEdgeInsetsMake(5, 10, 15, 20)];
            expect(rectIs([flipped safeAreaRect], 10, 5, 70, 30),
                   "the top inset is at the low y end of a flipped view");
        }

        // Layer coordinates. Without a layer nothing changes.
        NSPoint p = [view convertPointToLayer: NSMakePoint(5, 7)];
        expect(p.x == 5 && p.y == 7, "no layer: point unchanged");
        NSWindow *window = [[NSWindow alloc]
                initWithContentRect: NSMakeRect(100, 100, 300, 200)
                          styleMask: NSWindowStyleMaskTitled
                            backing: NSBackingStoreBuffered
                              defer: YES];
        NSView *content = [window contentView];
        NSView *plain = [[NSView alloc] initWithFrame: NSMakeRect(10, 20, 100, 50)];
        [content addSubview: plain];
        [plain setWantsLayer: YES];
        [plain setBoundsOrigin: NSMakePoint(30, 40)];
        p = [plain convertPointToLayer: NSMakePoint(35, 47)];
        expect(p.x == 35 && p.y == 47, "layer, not flipped: point unchanged");
        p = [plain convertPointFromLayer: NSMakePoint(35, 47)];
        expect(p.x == 35 && p.y == 47, "layer, not flipped: point from layer unchanged");
        NSSize s = [plain convertSizeToLayer: NSMakeSize(5, 7)];
        expect(s.width == 5 && s.height == 7, "size unchanged");
        s = [plain convertSizeFromLayer: NSMakeSize(5, 7)];
        expect(s.width == 5 && s.height == 7, "size from layer unchanged");
        expect(rectIs([plain convertRectToLayer: NSMakeRect(30, 40, 10, 20)], 30, 40, 10, 20),
               "layer, not flipped: rect unchanged");

        [plain setBoundsSize: NSMakeSize(200, 100)];
        [plain setBoundsOrigin: NSZeroPoint];
        p = [plain convertPointToLayer: NSMakePoint(10, 10)];
        expect(p.x == 10 && p.y == 10, "scaled bounds: point unchanged");

        FlippedView *flipped = [[FlippedView alloc] initWithFrame: NSMakeRect(10, 20, 100, 50)];
        [content addSubview: flipped];
        [flipped setWantsLayer: YES];
        BOOL mirror = mirrorsFlippedViews();
        p = [flipped convertPointToLayer: NSMakePoint(5, 7)];
        expect(p.x == 5 && p.y == (mirror ? 43 : 7), "flipped layer: point to layer");
        p = [flipped convertPointFromLayer: NSMakePoint(5, 7)];
        expect(p.x == 5 && p.y == (mirror ? 43 : 7), "flipped layer: point from layer");
        [flipped setBoundsOrigin: NSMakePoint(30, 40)];
        p = [flipped convertPointToLayer: NSMakePoint(35, 47)];
        expect(p.x == 35 && p.y == (mirror ? 83 : 47),
               "flipped layer with bounds origin: point to layer");
        NSRect r = [flipped convertRectToLayer: NSMakeRect(30, 40, 10, 20)];
        expect(rectIs(r, 30, mirror ? 70 : 40, 10, 20),
               "flipped layer with bounds origin: rect to layer");
        r = [flipped convertRectFromLayer: r];
        expect(rectIs(r, 30, 40, 10, 20), "rect round trip");
    }

    if (failures == 0)
        printf("PASS appkit-view-geometry-api\n");
    return failures != 0;
}
