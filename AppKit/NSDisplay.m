/* Copyright (c) 2006-2007 Christopher J. W. Lloyd <cjwl@objc.net>

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <AppKit/NSDisplay.h>
#import <AppKit/NSGlobalMenu+Private.h>
#import <AppKit/NSErrors.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSColorList.h>
#import <AppKit/NSScreen.h>
#import <CoreGraphics/CGDirectDisplay.h>
#import <CoreGraphics/CGDisplayConfiguration.h>
#import <CoreGraphics/CGSPointerController.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#import <CoreGraphics/CGSCursor.h>
#import <CoreGraphics/CGSNativeConnection.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSImage.h>
#import "NSEventQueue.h"
#import "NSWindow-Private.h"

// What CoreGraphics' pointer functions (CGDisplayHideCursor() and the rest, see CGSPointerController.h) reach
// the display through: CoreGraphics does not know AppKit, so the display registers this when it starts.
@interface _NSDisplayPointerController : NSObject <CGSPointerController> {
    NSDisplay *_display; // The process' display never goes away.
}
- (instancetype) initWithDisplay: (NSDisplay *) display;
@end

@implementation _NSDisplayPointerController
- (instancetype) initWithDisplay: (NSDisplay *) display {
    if ((self = [super init]))
        _display = display;
    return self;
}
- (void) hideCursor {
    [_display hideCursorCounted];
}
- (void) unhideCursor {
    [_display unhideCursorCounted];
}
- (void) forceShowCursor {
    [_display forceShowCursor];
}
- (void) warpPointerToPoint: (CGPoint) point {
    [_display warpMouse: NSMakePoint(point.x, point.y)];
}
- (void) setMouseAssociatedWithCursor: (BOOL) associated {
    // Disconnecting the mouse from the cursor is what -grabMouse: YES does: the cursor stays put and
    // the mouse only produces deltas.
    [_display grabMouse: !associated];
}
- (void) takeMouseDeltaX: (int32_t *) dx y: (int32_t *) dy {
    [_display takeMouseDeltaX: dx y: dy];
}
- (BOOL) cursorIsVisible {
    return [_display cursorIsVisible];
}
@end

static NSDisplay *processDisplay = nil;

// The displays changed, as CoreGraphics reports it for a change made by this process or by anything else
// (a window manager, another client). On macOS this is what makes the application post
// NSApplicationDidChangeScreenParametersNotification.
static void displaysReconfigured(CGDirectDisplayID display, CGDisplayChangeSummaryFlags flags, void *info) {
    if (flags & kCGDisplayBeginConfigurationFlag)
        return;
    NSDisplay *current = processDisplay;
    [current _invalidateScreens];
    if ([NSThread isMainThread])
        [current _postScreenParametersChanged];
    else
        [current performSelectorOnMainThread: @selector(_postScreenParametersChanged)
                                  withObject: nil
                               waitUntilDone: NO
                                       modes: @[ NSRunLoopCommonModes ]];
}

@implementation NSDisplay

+ (void) initialize {
    if (self == [NSDisplay class]) {
        NSDictionary *map = @{
            @"LeftControl" : @"Command",
            @"LeftAlt" : @"Alt",
            @"RightControl" : @"Control",
            @"RightAlt" : @"Alt"
        };
        NSDictionary *modifierMapping = @{@"NSModifierFlagMapping" : map};

        [[NSUserDefaults standardUserDefaults]
                registerDefaults: modifierMapping];
    }
}

// There is one window-server connection per process, shared by every thread.
// The instance is published only after the backend has initialized, so a
// backend that fails to start (or raises) leaves nothing behind and a later
// call tries again.
//
// A process that has denied itself connections to the window system
// (CGSSetDenyWindowServerConnections()) has no display: this returns nil
// instead of raising, so that NSApplication still initializes and the
// process sees no screens, as on macOS.
+ (NSDisplay *) currentDisplay {
    @synchronized([NSDisplay class]) {
        if (processDisplay == nil) {
            if (_CGSWindowServerConnectionsDenied()) {
                return nil;
            }
            processDisplay = [[NSDisplay alloc] init];
        }
        return processDisplay;
    }
}

- (instancetype) init {
    if ([self class] != [NSDisplay class]) {
        // Initializing a concrete subclass.
        _mouseDeltaLock = [NSLock new];
        _mainScreenMaxY = NAN;
        [[NSNotificationCenter defaultCenter]
                addObserver: self
                   selector: @selector(_screensDidChange:)
                       name: NSApplicationDidChangeScreenParametersNotification
                     object: nil];
        // The window system's events are kept from now on, also before the application first
        // waits for one
        _NSEventQueueBeginReading();

        static dispatch_once_t once;
        dispatch_once(&once, ^{
            // A backend whose connection decodes the pointer itself (X11) keeps that state in CoreGraphics.
            if ([self usesPointerController]) {
                static _NSDisplayPointerController *controller;
                controller = [[_NSDisplayPointerController alloc] initWithDisplay: self];
                _CGSSetPointerController(controller);
            }
            CGDisplayRegisterReconfigurationCallback(displaysReconfigured, NULL);
        });
        return self;
    }

    // NSDisplay is a (singleton) class cluster; we load
    // the installed backends and initialize on of them.
    [self release];

    // Discover the installed backends.
    NSBundle *appKitBundle = [NSBundle bundleForClass: [NSDisplay class]];
    NSMutableArray *backends = [NSMutableArray new];
    for (NSString *path in
         [appKitBundle pathsForResourcesOfType: @"backend"
                                   inDirectory: @"Backends"]) {
        NSBundle *backendBundle = [NSBundle bundleWithPath: path];
        if ([backendBundle load]) {
            [backends addObject: backendBundle];
        }
    }

    // Sort them according to the NSPriority key in their Info.plist files.
    [backends sortUsingComparator: ^(NSBundle *b1, NSBundle *b2) {
      NSNumber *p1 = [b1 objectForInfoDictionaryKey: @"NSPriority"];
      NSNumber *p2 = [b2 objectForInfoDictionaryKey: @"NSPriority"];
      return [p2 compare: p1];
    }];

    // Try to instantiate them in that order.
    for (NSBundle *backendBundle in backends) {
        NSDisplay *display = [[[backendBundle principalClass] alloc] init];
        if (display != nil) {
            // The first one to initialize successfully becomes the
            // one that we're going to use.
            [backends release];
            return display;
        }
    }

    // None of the backends can be used.
    NSArray *available = [[backends copy] autorelease];
    [backends release];
    [NSException raise: NSWindowServerCommunicationException
                format: @"Failed to connect to a window server. Available "
                        @"backends are: %@",
                        available];
    return nil;
}

- (void) dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [_mouseDeltaLock release];
    [super dealloc];
}

- (void) _screensDidChange: (NSNotification *) note {
    _mainScreenMaxY = NAN;
}

// The top of the main screen is its height: the global space has its origin at the main screen's
// bottom-left corner. Without a display the origin is at the top.
- (CGFloat) _mainScreenMaxY {
    CGFloat maxY = _mainScreenMaxY;

    if (isnan(maxY)) {
        CGDirectDisplayID main = CGMainDisplayID();

        maxY = main != kCGNullDirectDisplay ? CGDisplayBounds(main).size.height : 0;
        _mainScreenMaxY = maxY;
    }
    return maxY;
}

// RandR and wl_output report one change as several events, and CoreGraphics reports a change for
// each display, so the notification is queued and merged per run loop pass, and goes out on the next
// pass like the notification on macOS (the screens themselves are already up to date).
- (void) _postScreenParametersChanged {
    NSNotification *note = [NSNotification
            notificationWithName: NSApplicationDidChangeScreenParametersNotification
                          object: NSApp];
    [[NSNotificationQueue defaultQueue] enqueueNotification: note
                                               postingStyle: NSPostASAP
                                               coalesceMask: NSNotificationCoalescingOnName |
                                                             NSNotificationCoalescingOnSender
                                                   forModes: nil];
}

- (void) _invalidateScreens {
    @synchronized(self) {
        [_screens release];
        _screens = nil;
    }
    _mainScreenMaxY = NAN;
}

- (void) _mainMenuDidChange: (NSMenu *) menu {
}

// Whether the session has a desktop that shows application menus: something on the session bus registered for them (the
// bus is the application's, not CoreGraphics', so the display that exports the menu looks). The backends answer.
- (BOOL) _probeGlobalMenuRegistrar {
    return NO;
}

// Asked once, because the answer decides whether the application exports its menu at all. The window system carries
// the address of a window's menu only where it can (CoreGraphics says), and the answer is a flag of its connection
// (see _CGSNativeConnectionGlobalMenuAvailable()).
- (BOOL) _desktopShowsMainMenu {
    if (!_desktopMenuProbed) {
        _desktopMenuProbed = YES;
        if (_CGSNativeConnectionCarriesApplicationMenuAddress())
            _CGSNativeConnectionSetGlobalMenuAvailable([self _probeGlobalMenuRegistrar]);
    }
    return _CGSNativeConnectionGlobalMenuAvailable();
}

// The menu is outside the windows when the window system places a menu bar window of the application at the top of the
// screen (a window manager that handles docks, a compositor with a layer shell), or the desktop shows it itself. Under
// a window manager that does not handle docks the bar would float over the windows of the application, so the windows
// draw the menu themselves unless the desktop has a global menu.
- (BOOL) _showsMainMenuOutsideWindows {
    if (_CGSNativeConnectionKind() == CGSNativeConnectionKindNone)
        return YES;
    return _CGSNativeConnectionPlacesMenuBar() || [self _desktopShowsMainMenu];
}

// The screens are the displays of CoreGraphics (this framework sits above it): the frame is the
// display's bounds moved into Cocoa's global space, which has its origin at the main screen's
// bottom-left corner and y pointing up, and the backing scale, the name and the EDID are the display's.
- (NSArray<NSScreen *> *) _screensFromDisplays {
    uint32_t count = 0;

    if (CGGetActiveDisplayList(0, NULL, &count) != kCGErrorSuccess)
        count = 0;
    CGDirectDisplayID *displays = calloc(count > 0 ? count : 1, sizeof *displays);

    if (displays == NULL || CGGetActiveDisplayList(count, displays, &count) != kCGErrorSuccess)
        count = 0;

    NSMutableArray<NSScreen *> *screens = [NSMutableArray arrayWithCapacity: count];
    CGFloat mainHeight = count > 0 ? CGDisplayBounds(displays[0]).size.height : 0;

    for (uint32_t i = 0; i < count; i++) {
        CGRect bounds = CGDisplayBounds(displays[i]);
        NSRect frame = NSMakeRect(bounds.origin.x,
                                  mainHeight - bounds.origin.y - bounds.size.height,
                                  bounds.size.width, bounds.size.height);
        NSScreen *screen = [[[NSScreen alloc] initWithFrame: frame visibleFrame: frame] autorelease];

        [screen setCgDirectDisplayID: displays[i]];
        [screen _setBackingScaleFactor: _CGSDisplayBackingScaleFactor(displays[i])];
        CFDataRef edid = _CGSDisplayCopyEDID(displays[i]);
        if (edid != NULL) {
            [screen setEdid: (NSData *) edid];
            CFRelease(edid);
        }
        CFStringRef name = _CGSDisplayCopyOutputName(displays[i]);
        if (name != NULL) {
            [screen _setOutputName: (NSString *) name];
            CFRelease(name);
        }
        [screens addObject: screen];
    }
    free(displays);

    if ([screens count] == 0) {
        // No display is known (yet). An application still needs a screen to put its windows on.
        static const CGFloat fallbackWidth = 1920, fallbackHeight = 1080;
        static BOOL logged;
        if (!logged) {
            NSLog(@"AppKit: no display is known, assuming a %.0fx%.0f screen", fallbackWidth, fallbackHeight);
            logged = YES;
        }
        NSRect frame = NSMakeRect(0, 0, fallbackWidth, fallbackHeight);
        [screens addObject: [[[NSScreen alloc] initWithFrame: frame visibleFrame: frame] autorelease]];
    }
    return screens;
}

- (NSArray<NSScreen *> *) screens {
    @synchronized(self) {
        if (_screens == nil)
            _screens = [[NSArray alloc] initWithArray: [self _screensFromDisplays]];
        return [[_screens retain] autorelease];
    }
}

- (NSPasteboard *) pasteboardWithName: (NSPasteboardName) name {
    NSInvalidAbstractInvocation();
    return nil;
}

- (NSDraggingManager *) draggingManager {
    NSInvalidAbstractInvocation();
    return nil;
}

- (CGWindow *) newWindowWithDelegate: (NSWindow *) delegate {
    NSInvalidAbstractInvocation();
    return nil;
}

- (NSColor *) colorWithName: (NSString *) colorName {
    NSInvalidAbstractInvocation();
    return nil;
}

- (void) _addSystemColor: (NSColor *) result forName: (NSString *) colorName {
    NSInvalidAbstractInvocation();
}

- (NSTimeInterval) textCaretBlinkInterval {
    NSInvalidAbstractInvocation();
    return 1;
}

// Whether the pointer functions of CoreGraphics reach this display (see CGSPointerController.h).
- (BOOL) usesPointerController {
    return YES;
}

// Whether no hide is pending.
- (BOOL) cursorIsVisible {
    return _cursorHideCount == 0;
}

- (void) hideCursor {
    NSInvalidAbstractInvocation();
}

- (void) unhideCursor {
    NSInvalidAbstractInvocation();
}

// The backend hides the cursor while something hid it.
- (void) _applyCursorHidden {
    BOOL hidden = _cursorHideCount > 0;

    if (hidden == _cursorIsHidden)
        return;
    _cursorIsHidden = hidden;
    if (hidden)
        [self hideCursor];
    else
        [self unhideCursor];
}

- (void) hideCursorCounted {
    _cursorHideCount++;
    [self _applyCursorHidden];
}

// An unhide with nothing hidden does nothing.
- (void) unhideCursorCounted {
    if (_cursorHideCount > 0) {
        _cursorHideCount--;
        [self _applyCursorHidden];
    }
}

// Shows the cursor and forgets every pending hide (CGSForceShowCursor).
- (void) forceShowCursor {
    _cursorHideCount = 0;
    _cursorHiddenUntilMouseMoves = NO;
    [self _applyCursorHidden];
}

// The flag is idempotent and counts as one hide, so the hide/unhide pair stays balanced and an
// explicit +[NSCursor hide] is neither undone by it nor undoes it.
- (void) setCursorHiddenUntilMouseMoves: (BOOL) flag {
    if (_cursorHiddenUntilMouseMoves == flag)
        return;

    _cursorHiddenUntilMouseMoves = flag;
    if (flag)
        [self hideCursorCounted];
    else
        [self unhideCursorCounted];
}

// A backend calls this when the pointer genuinely moves. It cancels a pending
// -setCursorHiddenUntilMouseMoves:YES, as the cursor reappears on macOS.
- (void) pointerMoved {
    if (_cursorHiddenUntilMouseMoves) {
        _cursorHiddenUntilMouseMoves = NO;
        [self unhideCursorCounted];
    }
}

// The cursors are CoreGraphics' (see CGSCursor.h): a cursor is a CGSCursorRef, which is an Objective-C object, and the
// one the process shows is selected with CGSCursorSetCurrent(). CoreGraphics gives it to the window system for the
// pointer's focus at the scale of each output, and keeps it through a hide and a show.

// The shape of each name of NSCursor's standard cursors (an unknown name is the arrow).
static CGSCursorShape CursorShapeForName(NSString *name) {
    static NSDictionary *shapes;

    if (shapes == nil) {
        shapes = [[NSDictionary alloc] initWithObjectsAndKeys:
            [NSNumber numberWithInt: kCGSCursorShapeArrow], @"arrowCursor",
            [NSNumber numberWithInt: kCGSCursorShapeClosedHand], @"closedHandCursor",
            [NSNumber numberWithInt: kCGSCursorShapeCrosshair], @"crosshairCursor",
            [NSNumber numberWithInt: kCGSCursorShapeIBeam], @"IBeamCursor",
            [NSNumber numberWithInt: kCGSCursorShapeVerticalIBeam], @"IBeamCursorForVerticalLayout",
            [NSNumber numberWithInt: kCGSCursorShapeZoomIn], @"zoomInCursor",
            [NSNumber numberWithInt: kCGSCursorShapeZoomOut], @"zoomOutCursor",
            [NSNumber numberWithInt: kCGSCursorShapeOpenHand], @"openHandCursor",
            [NSNumber numberWithInt: kCGSCursorShapePointingHand], @"pointingHandCursor",
            [NSNumber numberWithInt: kCGSCursorShapeResizeDown], @"resizeDownCursor",
            [NSNumber numberWithInt: kCGSCursorShapeResizeLeft], @"resizeLeftCursor",
            [NSNumber numberWithInt: kCGSCursorShapeResizeLeftRight], @"resizeLeftRightCursor",
            [NSNumber numberWithInt: kCGSCursorShapeResizeRight], @"resizeRightCursor",
            [NSNumber numberWithInt: kCGSCursorShapeResizeUp], @"resizeUpCursor",
            [NSNumber numberWithInt: kCGSCursorShapeResizeUpDown], @"resizeUpDownCursor",
            [NSNumber numberWithInt: kCGSCursorShapeResizeNorthWest], @"frameResizeNorthWestCursor",
            [NSNumber numberWithInt: kCGSCursorShapeResizeNorthEast], @"frameResizeNorthEastCursor",
            [NSNumber numberWithInt: kCGSCursorShapeResizeSouthEast], @"frameResizeSouthEastCursor",
            [NSNumber numberWithInt: kCGSCursorShapeResizeSouthWest], @"frameResizeSouthWestCursor",
            [NSNumber numberWithInt: kCGSCursorShapeResizeNorthWestSouthEast], @"frameResizeNorthWestSouthEastCursor",
            [NSNumber numberWithInt: kCGSCursorShapeResizeNorthEastSouthWest], @"frameResizeNorthEastSouthWestCursor",
            nil];
    }
    NSNumber *shape = [shapes objectForKey: name];
    return shape != nil ? (CGSCursorShape) [shape intValue] : kCGSCursorShapeArrow;
}

- (id) cursorWithName: (NSString *) name {
    return [(id) CGSCursorCreateWithShape(CursorShapeForName(name)) autorelease];
}

// The pixels per point an image cursor is drawn at: the densest display's whole scale, from which CoreGraphics
// scales down to the display the pointer is on.
static CGFloat CursorRenderScale(void) {
    CGDirectDisplayID displays[16];
    uint32_t count = 0;
    double scale = 1;

    if (CGGetActiveDisplayList(16, displays, &count) == kCGErrorSuccess) {
        for (uint32_t i = 0; i < count; i++)
            scale = MAX(scale, _CGSDisplayBackingScaleFactor(displays[i]));
    }
    return MIN(ceil(scale), 4.0);
}

- (id) cursorWithImage: (NSImage *) image hotSpot: (NSPoint) hotSpot {
    NSSize size = [image size];
    double logicalWidth = ceil(size.width), logicalHeight = ceil(size.height);
    CGFloat scale = CursorRenderScale();

    if (isfinite(logicalWidth) && isfinite(logicalHeight) && logicalWidth >= 1 && logicalHeight >= 1 &&
        logicalWidth * scale <= 0x7FFF && logicalHeight * scale <= 0x7FFF) {
        size_t width = (size_t) (logicalWidth * scale), height = (size_t) (logicalHeight * scale);
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, colorSpace,
                kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
        CGColorSpaceRelease(colorSpace);

        if (context != NULL) {
            @autoreleasepool {
                NSGraphicsContext *graphicsContext = [NSGraphicsContext graphicsContextWithGraphicsPort: context
                                                                                                flipped: NO];

                [NSGraphicsContext saveGraphicsState];
                [NSGraphicsContext setCurrentContext: graphicsContext];
                CGContextScaleCTM(context, width / size.width, height / size.height);
                [image drawInRect: NSMakeRect(0, 0, size.width, size.height)
                         fromRect: NSZeroRect
                        operation: NSCompositeCopy
                         fraction: 1.0];
                [NSGraphicsContext restoreGraphicsState];
            }
            CGImageRef rendered = CGBitmapContextCreateImage(context);
            CGContextRelease(context);
            if (rendered != NULL) {
                CGSCursorRef cursor = CGSCursorCreateWithImage(rendered, CGSizeMake(logicalWidth, logicalHeight),
                                                               CGPointMake(hotSpot.x, hotSpot.y));
                CGImageRelease(rendered);
                if (cursor != NULL)
                    return [(id) cursor autorelease];
            }
        }
    }
    // Nothing a window system could show: the arrow.
    return [self cursorWithName: @"arrowCursor"];
}

- (void) setCursor: (id) cursor {
    CGSCursorSetCurrent((CGSCursorRef) cursor);
}

- (NSEvent *) nextEventMatchingMask: (NSUInteger) mask
                          untilDate: (NSDate *) untilDate
                             inMode: (NSString *) mode
                            dequeue: (BOOL) dequeue
{
    [self willWaitForEvents];
    NSEvent *result = _NSEventQueueNextEvent(mask, untilDate, mode, dequeue);

    if (result == nil) {
        result = [[[NSEvent alloc] initWithType: NSAppKitSystem
                                       location: NSZeroPoint
                                  modifierFlags: 0
                                         window: nil] autorelease];
    }
    return result;
}

- (void) discardEventsMatchingMask: (NSUInteger) mask
                       beforeEvent: (NSEvent *) event
{
    _NSEventQueueDiscard(mask, event);
}

- (BOOL) windowNumber: (NSInteger *) windowNumber
             location: (NSPoint *) location
          forKeyEvent: (struct __CGEvent *) event
{
    NSWindow *keyWindow = [NSApp keyWindow];

    *windowNumber = [keyWindow windowNumber];
    *location = [keyWindow mouseLocationOutsideOfEventStream];
    return YES;
}

- (NSEvent *) keyEventCreated: (NSEvent *) event fromCGEvent: (struct __CGEvent *) cgEvent {
    return event;
}

- (void) pointerEventCreated: (NSEvent *) event fromCGEvent: (struct __CGEvent *) cgEvent {
}

- (BOOL) windowNumber: (NSInteger *) windowNumber
             location: (NSPoint *) location
          hasLocation: (BOOL *) hasLocation
      forPointerEvent: (struct __CGEvent *) event
{
    return NO;
}

- (void) willWaitForEvents {
}

- (void) accumulateMouseDeltaX: (CGFloat) dx y: (CGFloat) dy {
    [_mouseDeltaLock lock];
    _mouseDeltaX += dx;
    _mouseDeltaY += dy;
    [_mouseDeltaLock unlock];
}

// Whole units are taken; the fraction stays for the next call, so a slow
// motion in a fractional scale is not lost.
- (void) takeMouseDeltaX: (int32_t *) dx y: (int32_t *) dy {
    [_mouseDeltaLock lock];
    double wholeX = _mouseDeltaX < 0 ? ceil(_mouseDeltaX) : floor(_mouseDeltaX);
    double wholeY = _mouseDeltaY < 0 ? ceil(_mouseDeltaY) : floor(_mouseDeltaY);
    _mouseDeltaX -= wholeX;
    _mouseDeltaY -= wholeY;
    [_mouseDeltaLock unlock];
    if (dx != NULL)
        *dx = (int32_t) wholeX;
    if (dy != NULL)
        *dy = (int32_t) wholeY;
}

// QUIRK: what an application posts with -[NSApplication postEvent:atStart:] is queued as it is: posted drags are
// dequeued one by one, never coalesced. Not documented. Evidence: black-box observation on macOS 26.7.3 and 10.14.4 (tier 2; darling's tests/collection-view.md).
// Test: appkit-posted-events-not-coalesced.m
- (void) _postEventWithoutCoalescing: (NSEvent *) event atStart: (BOOL) atStart {
    _NSEventQueuePost(event, atStart);
}

- (BOOL) containsAndRemovePeriodicEvents {
    return _NSEventQueueDiscard(NSPeriodicMask, nil) > 0;
}

- (NSEventModifierFlags) modifierForDefault: (NSString *) key
                                   standard: (NSEventModifierFlags) standard
{
    NSDictionary *modmap = [[NSUserDefaults standardUserDefaults]
            dictionaryForKey: @"NSModifierFlagMapping"];
    NSString *remap = modmap[key];

    if ([remap isEqualToString: @"Command"])
        return NSCommandKeyMask;
    if ([remap isEqualToString: @"Alt"])
        return NSAlternateKeyMask;
    if ([remap isEqualToString: @"Control"])
        return NSControlKeyMask;

    return standard;
}

- (BOOL) controlStandsInForCommand: (NSEventModifierFlags) flags
                       keyEquivalent: (unichar) key
{
    return NO;
}

- (void) beep {
    NSInvalidAbstractInvocation();
}

- (NSSet *) allFontFamilyNames {
    NSInvalidAbstractInvocation();
    return nil;
}

- (NSArray *) fontTypefacesForFamilyName: (NSString *) name {
    NSInvalidAbstractInvocation();
    return nil;
}

- (NSString *) substituteFamilyName: (NSString *) familyName {
    return nil;
}

- (NSString *) fontFamilyNameForGenericFamily: (NSString *) generic {
    NSInvalidAbstractInvocation();
    return nil;
}

- (CGFloat) scrollerWidth {
    NSInvalidAbstractInvocation();
    return 0;
}

- (int) runModalPageLayoutWithPrintInfo: (NSPrintInfo *) printInfo {
    NSInvalidAbstractInvocation();
    return 0;
}

- (int) runModalPrintPanelWithPrintInfoDictionary:
        (NSMutableDictionary *) attributes
{
    NSInvalidAbstractInvocation();
    return 0;
}

- (CGContextRef) graphicsPortForPrintOperationWithView: (NSView *) view
                                             printInfo:
                                                     (NSPrintInfo *) printInfo
                                             pageRange: (NSRange) pageRange
{
    NSInvalidAbstractInvocation();
    return nil;
}

- (BOOL) implementsCustomPanelForClass: (Class) panelClass {
    return NO;
}

- (NSString *) portalParentHandleForWindow: (NSWindow *) window {
    return nil;
}

- (int) savePanel: (NSSavePanel *) savePanel
        runModalForDirectory: (NSString *) directory
                        file: (NSString *) file
{
    NSInvalidAbstractInvocation();
    return 0;
}

- (int) openPanel: (NSOpenPanel *) openPanel
        runModalForDirectory: (NSString *) directory
                        file: (NSString *) file
                       types: (NSArray *) types
{
    NSInvalidAbstractInvocation();
    return 0;
}

- (NSArray *) orderedWindowNumbers {
    NSInvalidAbstractInvocation();
    return nil;
}

// The native border of a window is outside the frame the framework works with on every backend: the window
// manager's decorations are the window system's, and a window the framework decorates itself is drawn inside its
// frame. So the content and the frame rectangles are the same ones.
- (CGRect) insetRect: (CGRect) frame
        forNativeWindowBorderWithStyle: (NSUInteger) styleMask
{
    return frame;
}

- (CGRect) outsetRect: (CGRect) frame
        forNativeWindowBorderWithStyle: (NSUInteger) styleMask
{
    return frame;
}

// Backends whose window system has no session protocol keep the default: no session is started and
// nothing is persisted for one. Wayland overrides these when it binds xdg_session_manager_v1.
- (void) beginWindowSessionWithReason: (NSUInteger) reason identifier: (NSString *) identifier {
    (void) reason;
    (void) identifier;
}

- (NSString *) windowSessionIdentifier {
    return nil;
}

- (BOOL) supportsWindowSessions {
    return NO;
}

@end

void NSColorSetCatalogColor(NSString *catalogName, NSString *colorName,
                            NSColor *color)
{
    NSColorList *colors = [NSColorList colorListNamed: catalogName];

    [colors setColor: color forKey: colorName];
}

NSColor *NSColorGetCatalogColor(NSString *catalogName, NSString *colorName) {
    NSColorList *colors = [NSColorList colorListNamed: catalogName];

    if (colors != nil)
        return [colors colorWithKey: colorName];

    return nil;
}
