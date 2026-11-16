/* Copyright (c) 2006-2007 Christopher J. W. Lloyd <cjwl@objc.net>
                 2009 Markus Hitter <mah@jump-ing.de>

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

#import <AppKit/NSApplication.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSCursor.h>
#import <AppKit/NSDisplay.h>
#import <AppKit/NSDraggingManager.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSEvent_CoreGraphics.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSImageView.h>
#import <AppKit/NSMainMenuView.h>
#import <AppKit/NSGlobalMenu+Private.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSPanel.h>
#import <AppKit/NSPasteboard.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSScreen.h>
#import <AppKit/NSSheetContext.h>
#import <AppKit/NSTextView.h>
#import <AppKit/NSThemeFrame.h>
#import <AppKit/NSToolTipWindow.h>
#import <AppKit/NSToolbar.h>
#import <AppKit/NSTrackingArea.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow-Private.h>
#import <AppKit/NSWindow.h>
#import "DarlingLayout.h"
#import <AppKit/NSWindowAnimationContext.h>
#import <ApplicationServices/ApplicationServices.h>
#import <CoreGraphics/CGWindowPrivate.h>
#include <math.h>
#import "NSGestureRecognizer-Private.h"

const NSNotificationName NSWindowDidBecomeKeyNotification =
        @"NSWindowDidBecomeKeyNotification";
const NSNotificationName NSWindowDidResignKeyNotification =
        @"NSWindowDidResignKeyNotification";
const NSNotificationName NSWindowDidBecomeMainNotification =
        @"NSWindowDidBecomeMainNotification";
const NSNotificationName NSWindowDidResignMainNotification =
        @"NSWindowDidResignMainNotification";
const NSNotificationName NSWindowWillMiniaturizeNotification =
        @"NSWindowWillMiniaturizeNotification";
const NSNotificationName NSWindowDidMiniaturizeNotification =
        @"NSWindowDidMiniaturizeNotification";
const NSNotificationName NSWindowDidDeminiaturizeNotification =
        @"NSWindowDidDeminiaturizeNotification";
const NSNotificationName NSWindowDidMoveNotification =
        @"NSWindowDidMoveNotification";
const NSNotificationName NSWindowDidResizeNotification =
        @"NSWindowDidResizeNotification";
const NSNotificationName NSWindowDidUpdateNotification =
        @"NSWindowDidUpdateNotification";
const NSNotificationName NSWindowWillCloseNotification =
        @"NSWindowWillCloseNotification";
const NSNotificationName NSWindowWillMoveNotification =
        @"NSWindowWillMoveNotification";
const NSNotificationName NSWindowWillStartLiveResizeNotification =
        @"NSWindowWillStartLiveResizeNotification";
const NSNotificationName NSWindowDidEndLiveResizeNotification =
        @"NSWindowDidEndLiveResizeNotification";
const NSNotificationName NSWindowWillBeginSheetNotification =
        @"NSWindowWillBeginSheetNotification";

const NSNotificationName NSWindowWillAnimateNotification =
        @"NSWindowWillAnimateNotification";
const NSNotificationName NSWindowAnimatingNotification =
        @"NSWindowAnimatingNotification";
const NSNotificationName NSWindowDidAnimateNotification =
        @"NSWindowDidAnimateNotification";

const NSNotificationName NSWindowDidChangeBackingPropertiesNotification =
        @"NSWindowDidChangeBackingPropertiesNotification";
const NSNotificationName NSWindowDidChangeScreenProfileNotification =
        @"NSWindowDidChangeScreenProfileNotification";
NSString *const NSBackingPropertyOldScaleFactorKey =
        @"NSBackingPropertyOldScaleFactorKey";
const NSNotificationName NSWindowDidChangeOcclusionStateNotification =
        @"NSWindowDidChangeOcclusionStateNotification";
const NSNotificationName NSWindowDidChangeScreenNotification =
        @"NSWindowDidChangeScreenNotification";
const NSNotificationName NSWindowDidEndSheetNotification =
        @"NSWindowDidEndSheetNotification";
const NSNotificationName NSWindowDidEnterFullScreenNotification =
        @"NSWindowDidEnterFullScreenNotification";
const NSNotificationName NSWindowDidExitFullScreenNotification =
        @"NSWindowDidExitFullScreenNotification";
const NSNotificationName NSWindowDidOrderOffScreenNotification =
        @"NSWindowDidOrderOffScreenNotification";
const NSNotificationName NSWindowDidOrderOnScreenNotification =
        @"_NSWindowDidBecomeVisible";
const NSNotificationName NSWindowWillEnterFullScreenNotification =
        @"NSWindowWillEnterFullScreenNotification";
const NSNotificationName NSWindowWillExitFullScreenNotification =
        @"NSWindowWillExitFullScreenNotification";
const NSNotificationName NSWindowDidExposeNotification =
        @"NSWindowDidExposeNotification";
const NSNotificationName NSWindowWillEnterVersionBrowserNotification =
        @"NSWindowWillEnterVersionBrowserNotification";
const NSNotificationName NSWindowDidEnterVersionBrowserNotification =
        @"NSWindowDidEnterVersionBrowserNotification";
const NSNotificationName NSWindowWillExitVersionBrowserNotification =
        @"NSWindowWillExitVersionBrowserNotification";
const NSNotificationName NSWindowDidExitVersionBrowserNotification =
        @"NSWindowDidExitVersionBrowserNotification";

NSInteger NSBitsPerPixelFromDepth(NSWindowDepth depth) {
    switch (depth) {
    case NSWindowDepthOnehundredtwentyeightBitRGB:
        return 128;
    case NSWindowDepthSixtyfourBitRGB:
        return 64;
    case NSWindowDepthTwentyfourBitRGB:
        return 24;
    }

    return 0;
}

@interface CGWindow (private)
- (void) dirtyRect: (CGRect) rect;
@end

@interface NSToolbar (NSToolbar_privateForWindow)
- (void) _setWindow: (NSWindow *) window;
- (NSView *) _view;
- (CGFloat) visibleHeight;
- (void) layoutFrameSizeWithWidth: (CGFloat) width;
@end

@interface NSWindow ()

- (NSRect) zoomedFrame;
- (void) _postOcclusionChangeIfVisibleWas: (BOOL) wasVisible;

@end

@interface NSApplication (private)
- (void) _setMainWindow: (NSWindow *) window;
- (void) _setKeyWindow: (NSWindow *) window;
@end

@interface _NSKeyViewPosition : NSObject {
    NSView *_view;
    NSRect _rect;
}

+ (NSArray *) sortedKeyViewPositionsWithView: (NSView *) view;

- initWithView: (NSView *) view;

- (NSView *) view;

- (NSComparisonResult) compareKeyViewPosition: (_NSKeyViewPosition *) other;

@end

@implementation _NSKeyViewPosition

+ (void) addKeyViewPositionsWithView: (NSView *) view
                             toArray: (NSMutableArray *) array
{
    [array addObject: [[[_NSKeyViewPosition alloc] initWithView: view]
                              autorelease]];

    for (NSView *child in [view subviews])
        [self addKeyViewPositionsWithView: child toArray: array];
}

+ (NSArray *) sortedKeyViewPositionsWithView: (NSView *) view {
    NSMutableArray *result = [NSMutableArray array];

    [self addKeyViewPositionsWithView: view toArray: result];
    [result sortUsingSelector: @selector(compareKeyViewPosition:)];

    return result;
}

- (instancetype) initWithView: (NSView *) view {
    _view = view;
    _rect = [[_view superview] convertRect: [_view frame] toView: nil];
    return self;
}

- (NSView *) view {
    return _view;
}

- (NSComparisonResult) compareKeyViewPosition: (_NSKeyViewPosition *) other {

    // Sort by larger Y (cartesian coordinates)
    if (NSMaxY(_rect) < NSMaxY(other->_rect))
        return NSOrderedDescending;
    else {
        // Then sort by smaller X
        if (NSMinX(_rect) < NSMinX(other->_rect))
            return NSOrderedAscending;
        else
            return NSOrderedDescending;
    }
}

@end

// Modal delegate that hands the return code of a sheet to a completion handler.
@interface NSWindowSheetCompletion : NSObject {
    void (^_handler)(NSInteger returnCode);
}
@end

@interface NSView (NSWindowBackingProperties)
- (void) _backingPropertiesDidChange;
@end

@implementation NSWindowSheetCompletion

- initWithHandler: (void (^)(NSInteger returnCode)) handler {
    if ((self = [super init]))
        _handler = [handler copy];
    return self;
}

- (void) dealloc {
    [_handler release];
    [super dealloc];
}

- (void) sheetDidEnd: (NSWindow *) sheet
          returnCode: (NSInteger) returnCode
         contextInfo: (void *) contextInfo
{
    if (_handler != nil)
        _handler(returnCode);
    // NSSheetContext doesn't retain its delegate, so this balances the alloc
    // in -beginSheet:completionHandler:.
    [self release];
}

@end

// The dragging information handed to destinations by an in-process drag
// (see -_dragImageInProcess:...).
@interface NSWindowLocalDraggingInfo : NSObject <NSDraggingInfo> {
  @public
    NSPasteboard *_pasteboard;
    NSImage *_image;
    id _source;
    NSWindow *_destinationWindow;
    NSPoint _screenPoint;
    NSDragOperation _sourceMask;
}
@end

@implementation NSWindowLocalDraggingInfo

- (void) dealloc {
    [_destinationWindow release];
    [super dealloc];
}

- (NSPasteboard *) draggingPasteboard {
    return _pasteboard;
}

- (NSDragOperation) draggingSourceOperationMask {
    return _sourceMask;
}

- (NSPoint) draggingLocation {
    if (_destinationWindow == nil)
        return _screenPoint;
    return [_destinationWindow convertScreenToBase: _screenPoint];
}

- (NSImage *) draggedImage {
    return _image;
}

- (NSPoint) draggedImageLocation {
    return [self draggingLocation];
}

- (NSWindow *) draggingDestinationWindow {
    return _destinationWindow;
}

- (id) draggingSource {
    return _source;
}

- (void) slideDraggedImageTo: (NSPoint) point {
}

- (int) draggingSequenceNumber {
    return 0;
}

- (NSArray *) namesOfPromisedFilesDroppedAtDestination: (NSURL *) destination {
    return nil;
}

@end

// Shows the dragged image under the pointer. It never becomes key, so the
// window system leaves it alone.
@interface NSWindowDragImageWindow : NSWindow
@end

@implementation NSWindowDragImageWindow

- (BOOL) canBecomeKeyWindow {
    return NO;
}

- (BOOL) canBecomeMainWindow {
    return NO;
}

@end

// Lets run loop sources (timers, other threads' replies) run while a drag
// holds the main thread, until none is pending or the time is up.
static void runPendingSourcesDuringDrag(NSTimeInterval budget) {
    CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + budget;

    while (CFAbsoluteTimeGetCurrent() < deadline) {
        SInt32 result = CFRunLoopRunInMode(
                (CFStringRef) NSEventTrackingRunLoopMode, 0, true);
        if (result != kCFRunLoopRunHandledSource)
            break;
    }
}

@implementation NSWindow

static NSRect constrainRectToScreen(NSRect rect, NSScreen *screen);

// -contentRectForFrameRect:, without sending it to a subclass.
static NSRect contentRectInFrame(NSWindow *window, NSRect frameRect) {
    NSRect result = [[NSDisplay currentDisplay] insetRect: frameRect
                           forNativeWindowBorderWithStyle: NS_EXTRA(NSWindow, window)->_styleMask];

    if ([window hasMainMenu]) {
        result.size.height -= [NSMainMenuView menuHeight];
    }

    NSToolbar *toolbar = window->_toolbar;
    if ([toolbar _view] != nil && ![[toolbar _view] isHidden]) {
        result.size.height -= [[toolbar _view] frame].size.height;
    }

    return result;
}

NS_EXTRA_SYNTHESIZE_RETAIN(NSWindow, appearance, _appearance, NSAppearance *, appearance, setAppearance:)
NS_EXTRA_SYNTHESIZE_COPY(NSWindow, identifier, _identifier, NSUserInterfaceItemIdentifier, identifier, setIdentifier:)
NS_EXTRA_SYNTHESIZE_ASSIGN(NSWindow, accessibilityElement, _isAccessible, BOOL, isAccessibilityElement, setAccessibilityElement:)
NS_EXTRA_SYNTHESIZE_ASSIGN(NSWindow, restorable, _restorable, BOOL, isRestorable, setRestorable:)

static BOOL _allowsAutomaticWindowTabbing;

+ (NSWindowDepth) defaultDepthLimit {
    return 0;
}

// Darling setting DarlingInWindowMenuBar (boolean, off by default): draw the
// main menu as a strip inside each titled window instead of in the desktop's
// global menu or the application's own menu bar. It is read from the
// application's preferences, falling back to NSGlobalDomain, and from the
// org.darlinghq.AppKit domain. The answer is fixed at first use, because the
// frame of every window depends on it.
+ (BOOL) _usesInWindowMenuBar {
    static BOOL value;
    static dispatch_once_t once;

    dispatch_once(&once, ^{
      CFStringRef key = CFSTR("DarlingInWindowMenuBar");
      Boolean valid = false;
      Boolean flag = CFPreferencesGetAppBooleanValue(
              key, kCFPreferencesCurrentApplication, &valid);

      if (!valid)
          flag = CFPreferencesGetAppBooleanValue(
                  key, CFSTR("org.darlinghq.AppKit"), &valid);
      value = valid && flag;
    });
    return value;
}

/* This method is Cococtron specific and can be override by subclasses, do not
 * change method name */
+ (BOOL) hasMainMenuForStyleMask: (NSWindowStyleMask) styleMask {
    // The main menu is shown by the desktop or by the application's menu bar
    // window unless the in-window strip is asked for.
    if (![NSWindow _usesInWindowMenuBar])
        return NO;

    // A full-size content view covers the whole frame, leaving no room for
    // the menu.
    return (styleMask & NSTitledWindowMask) &&
           !(styleMask & NSWindowStyleMaskFullSizeContentView);
}

/* This method is Cococtron specific and can be override by subclasses, do not
 * change method name. */
- (BOOL) hasMainMenu {
    return [[self class] hasMainMenuForStyleMask: NS_EXTRA(NSWindow, self)->_styleMask];
}

+ (NSRect) frameRectForContentRect: (NSRect) contentRect
                         styleMask: (NSWindowStyleMask) styleMask
{
    NSRect result = [[NSDisplay currentDisplay] outsetRect: contentRect
                            forNativeWindowBorderWithStyle: styleMask];

    if ([self hasMainMenuForStyleMask: styleMask])
        result.size.height += [NSMainMenuView menuHeight];

    return result;
}

+ (NSRect) contentRectForFrameRect: (NSRect) frameRect
                         styleMask: (NSWindowStyleMask) styleMask
{
    NSRect result = [[NSDisplay currentDisplay] insetRect: frameRect
                           forNativeWindowBorderWithStyle: styleMask];

    if ([self hasMainMenuForStyleMask: styleMask])
        result.size.height -= [NSMainMenuView menuHeight];

    return result;
}

+ (CGFloat) minFrameWidthWithTitle: (NSString *) title
                         styleMask: (NSWindowStyleMask) styleMask
{
    NSUnimplementedMethod();
    return 0;
}

+ (NSInteger) windowNumberAtPoint: (NSPoint) point
        belowWindowWithWindowNumber: (NSInteger) window
{
    NSUnimplementedMethod();
    return 0;
}

+ (NSArray *) windowNumbersWithOptions: (NSWindowNumberListOptions) options {
    NSUnimplementedMethod();
    return nil;
}

+ (void) removeFrameUsingName: (NSString *) name {
    NSUnimplementedMethod();
}

// The title bar is drawn by the window manager, so these buttons are not
// shown; they let callers query and configure the buttons a window has.
+ (NSButton *) standardWindowButton: (NSWindowButton) button
                       forStyleMask: (NSWindowStyleMask) styleMask
{
    // QUIRK: a titled window has either none of the close, miniaturize and zoom
    // buttons (when its style is none of closable, miniaturizable and resizable) or all
    // three, each enabled only if the style asks for it. Not documented. Evidence:
    // black-box observation on macOS 27.0.1 (tier 2), for Titled, Titled|Closable,
    // Titled|Miniaturizable, Titled|Resizable and untitled styles.
    // Test: appkit_view_window_macos_defaults ("window buttons").
    const NSWindowStyleMask buttonStyles = NSWindowStyleMaskClosable
            | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
    NSWindowStyleMask enabling;
    switch (button) {
    case NSWindowCloseButton:
        enabling = NSWindowStyleMaskClosable;
        break;
    case NSWindowMiniaturizeButton:
        enabling = NSWindowStyleMaskMiniaturizable;
        break;
    case NSWindowZoomButton:
        enabling = NSWindowStyleMaskResizable;
        break;
    default:
        return nil;
    }
    if (!(styleMask & NSWindowStyleMaskTitled) || !(styleMask & buttonStyles))
        return nil;

    NSButton *result =
            [[NSButton alloc] initWithFrame: NSMakeRect(0, 0, 14, 14)];
    [result setBordered: NO];
    [result setEnabled: (styleMask & enabling) != 0];
    return [result autorelease];
}

+ (void) menuChanged: (NSMenu *) menu {
    NSUnimplementedMethod();
}

- (void) encodeWithCoder: (NSCoder *) coder {
    NSUnimplementedMethod();
}

// This is Apple private API
+ (Class) frameViewClassForStyleMask: (NSWindowStyleMask) styleMask {
    return [NSThemeFrame class];
}

- (instancetype) init {
    return [self initWithContentRect: NSMakeRect(100, 100, 100, 100)
                           styleMask: NSTitledWindowMask
                             backing: NSBackingStoreBuffered
                               defer: NO];
}

- (instancetype) initWithCoder: (NSCoder *) coder {
    [NSException raise: NSInvalidArgumentException
                format: @"-[%@ %s] is not implemented for coder %@",
                        [self class], sel_getName(_cmd), coder];
    return self;
}

- (instancetype) initWithContentRect: (NSRect) contentRect
                           styleMask: (NSWindowStyleMask) styleMask
                             backing: (NSBackingStoreType) backing
                               defer: (BOOL) defer
{
    // Make sure NSApplication is initialized.
    if (!NSApp) {
        [NSApplication sharedApplication];
    }
    NS_EXTRA(NSWindow, self)->_styleMask = styleMask;
    NS_EXTRA(NSWindow, self)->_isMovable = YES;
    NS_EXTRA(NSWindow, self)->_alphaValue = 1.0;
    NS_EXTRA(NSWindow, self)->_backingType = backing;
    NS_EXTRA(NSWindow, self)->_isDeferred = defer;

    // QUIRK: the initializer computes the frame with the class method
    // +frameRectForContentRect:styleMask: and installs the default content
    // view with -setContentView:, but sends neither -frameRectForContentRect:
    // nor -contentRectForFrameRect: to the instance. A subclass override of
    // those two methods therefore does not run before the subclass's own
    // initializer has. The frame is moved onto the screen here, without
    // sending -constrainFrameRect:toScreen: either; ordering the window in
    // later does not move it again. Not documented. Evidence: black-box
    // observation on macOS 27.0.1 arm64 (tier 2) of an NSWindow subclass
    // that records the overrides called during
    // -initWithContentRect:styleMask:backing:defer:, for titled and
    // borderless windows, deferred or not, and of the frame of a window
    // created partly off screen, after init and after -orderFront:.
    // Test: appkit_window_init_overrides.m (window init QUIRK).
    _frame = [[self class] frameRectForContentRect: contentRect
                                         styleMask: styleMask];
    _frame = constrainRectToScreen(_frame, [NSScreen mainScreen]);
    NS_EXTRA(NSWindow, self)->_savedFrame = _frame;

    _level = NSNormalWindowLevel;
    NS_EXTRA(NSWindow, self)->_minSize = NSZeroSize;
    // "The default maximum size of a window is {FLT_MAX, FLT_MAX}"
    NS_EXTRA(NSWindow, self)->_maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    NS_EXTRA(NSWindow, self)->_title = @"";
    NS_EXTRA(NSWindow, self)->_miniwindowTitle = @"";
    _backgroundColor = [[NSColor windowBackgroundColor] copy];
    _firstResponder = self;
    NS_EXTRA(NSWindow, self)->_makeSureIsOnAScreen = YES;
    NS_EXTRA(NSWindow, self)->_releaseWhenClosed = YES;
    NS_EXTRA(NSWindow, self)->_viewsNeedDisplay = YES;
    // Titled windows are restorable by default, borderless ones are not.
    NS_EXTRA(NSWindow, self)->_restorable = (styleMask & NSWindowStyleMaskTitled) != 0;
    NS_EXTRA(NSWindow, self)->_bottomCornerRounded = YES;
    NS_EXTRA(NSWindow, self)->_flushNeeded = YES;
    NS_EXTRA(NSWindow, self)->_resizeIncrements = NSMakeSize(1, 1);
    NS_EXTRA(NSWindow, self)->_contentResizeIncrements = NSMakeSize(1, 1);

    NS_EXTRA(NSWindow, self)->_threadToContext = [[NSMutableDictionary alloc] init];

    NSRect backgroundFrame = {NSZeroPoint, _frame.size};
    _backgroundView = [[[[self class] frameViewClassForStyleMask: styleMask]
            alloc] initWithFrame: backgroundFrame];
    [_backgroundView setAutoresizesSubviews: YES];
    [_backgroundView
            setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
    [_backgroundView _setWindow: self];
    [_backgroundView setNextResponder: self];

    // See the QUIRK above: not -contentRectForFrameRect:.
    NSRect contentViewFrame = contentRectInFrame(self, backgroundFrame);
    NSView *contentView = [[NSView alloc] initWithFrame: contentViewFrame];
    [contentView setAutoresizesSubviews: YES];
    [contentView
            setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];

    if ([self hasMainMenu]) {
        NSRect menuFrame = NSMakeRect(
                contentViewFrame.origin.x, NSMaxY(contentViewFrame),
                contentViewFrame.size.width, [NSMainMenuView menuHeight]);

        // We all need to share the main menu!
        NS_EXTRA(NSWindow, self)->_menu = [[NSApp mainMenu] retain];

        NS_EXTRA(NSWindow, self)->_menuView = [[NSMainMenuView alloc] initWithFrame: menuFrame
                                                     menu: NS_EXTRA(NSWindow, self)->_menu];
        [NS_EXTRA(NSWindow, self)->_menuView setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
        [_backgroundView addSubview: NS_EXTRA(NSWindow, self)->_menuView];
    }

    [self setContentView: contentView];
    [contentView release];
    [_backgroundView setNeedsDisplay: YES];

    if (!(NS_EXTRA(NSWindow, self)->_styleMask & NSAppKitPrivateWindow)) {
        [[NSApplication sharedApplication] _addWindow: self];
    }
    return self;
}

- (instancetype) initWithContentRect: (NSRect) contentRect
                           styleMask: (NSWindowStyleMask) styleMask
                             backing: (NSBackingStoreType) backing
                               defer: (BOOL) defer
                              screen: (NSScreen *) screen
{
    // FIX, relocate contentRect
    return [self initWithContentRect: contentRect
                           styleMask: styleMask
                             backing: backing
                               defer: defer];
}

+ defaultAnimationForKey: (NSString *) key {
    return nil;
}

- (instancetype) animator {
    // Property changes are applied immediately, so the window is its own
    // animator rather than a proxy that animates them.
    return self;
}

- (NSDictionary *) animations {
    return NS_EXTRA(NSWindow, self)->_animations;
}

- animationForKey: (NSString *) key {
    return [NS_EXTRA(NSWindow, self)->_animations objectForKey: key];
}

- (void) setAnimations: (NSDictionary *) dictionary {
    dictionary = [dictionary copy];
    [NS_EXTRA(NSWindow, self)->_animations release];
    NS_EXTRA(NSWindow, self)->_animations = dictionary;
}

- (NSWindow *) initWithWindowRef: (void *) carbonRef {
    NSUnimplementedMethod();
    return nil;
}

- (void) dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    for (NSUInteger i = 0; i < 3; i++)
        [NS_EXTRA(NSWindow, self)->_standardWindowButtons[i] release];
    [NS_EXTRA(NSWindow, self)->_animations release];
    [NS_EXTRA(NSWindow, self)->_tabbingIdentifier release];
    [NS_EXTRA(NSWindow, self)->_subtitle release];
    [NS_EXTRA(NSWindow, self)->_childWindows release];
    [NS_EXTRA(NSWindow, self)->_representedFilename release];
    [_representedURL release];
    [NS_EXTRA(NSWindow, self)->_title release];
    [NS_EXTRA(NSWindow, self)->_miniwindowTitle release];
    [_miniwindowImage release];
    [NS_EXTRA(NSWindow, self)->_appearance release];
    objc_storeWeak(&NS_EXTRA(NSWindow, self)->_appearanceSource, nil);
    [_backgroundView _setWindow: nil];
    [_backgroundView release];
    [NS_EXTRA(NSWindow, self)->_menu release];
    [NS_EXTRA(NSWindow, self)->_menuView release];
    [_contentView release];
    [NS_EXTRA(NSWindow, self)->_contentViewController release];
    [_backgroundColor release];
    [_sharedFieldEditor release];
    [NS_EXTRA(NSWindow, self)->_draggedTypes release];
    [NS_EXTRA(NSWindow, self)->_trackingAreas release];
    [NS_EXTRA(NSWindow, self)->_mouseDownViews release];
    [_autosaveFrameName release];
    [_platformWindow invalidate];
    [_platformWindow release];
    _platformWindow = nil;
    [NS_EXTRA(NSWindow, self)->_threadToContext release];
    [NS_EXTRA(NSWindow, self)->_undoManager release];
    [NS_EXTRA(NSWindow, self)->_identifier release];
    [NS_EXTRA(NSWindow, self)->_titlebarAccessoryViewControllers release];
    NS_EXTRA_FREE(NSWindow, self);
    [super dealloc];
}

- (void) _updatePlatformWindowTitle {
    NSString *title;

    if ([self isMiniaturized])
        title = [self miniwindowTitle];
    else
        title = [self title];

    if (NS_EXTRA(NSWindow, self)->_isDocumentEdited)
        title = [@"* " stringByAppendingString: title];

    [_platformWindow setTitle: title];
}

/*
  There are issues when creating a Win32 handle on a non-main thread, so we
  always do it on the main thread
 */
- (void) _createPlatformWindowOnMainThread {
    if (_platformWindow != nil)
        return;
    _platformWindow = [[NSDisplay currentDisplay] newWindowWithDelegate: self];

    [self _updatePlatformWindowTitle];

    [[NSDraggingManager draggingManager] registerWindow: self dragTypes: nil];
}

- (CGContextRef) cgContext {
    return [[self platformWindow] cgContext];
}

- (void) setStyleMask: (NSWindowStyleMask) mask {
    NS_EXTRA(NSWindow, self)->_styleMask = mask;
    [_platformWindow setStyleMask: NS_EXTRA(NSWindow, self)->_styleMask];

    [self _hideMenuViewIfNeeded];

    [_backgroundView resizeSubviewsWithOldSize: [_backgroundView frame].size];
    [_backgroundView setNeedsDisplay: YES]; // FIXME: verify this is done
}

- (void) postNotificationName: (NSNotificationName) name {
    [[NSNotificationCenter defaultCenter] postNotificationName: name
                                                        object: self];
}

- (NSGraphicsContext *) graphicsContext {
    NSValue *key = [NSValue valueWithPointer: [NSThread currentThread]];
    NSGraphicsContext *context = NS_EXTRA(NSWindow, self)->_threadToContext[key];

    if (!context) {
        context = [NSGraphicsContext graphicsContextWithWindow: self];
        NS_EXTRA(NSWindow, self)->_threadToContext[key] = context;
    }

    return context;
}

- (void) platformWindowDidInvalidateCGContext: (CGWindow *) window {
    [NS_EXTRA(NSWindow, self)->_threadToContext removeAllObjects];
}

- (NSDictionary *) deviceDescription {
    return @{
        NSDeviceResolution : [NSValue valueWithSize: NSMakeSize(72.0, 72.0)],
        NSDeviceSize : [NSValue valueWithSize: [self frame].size],
        NSDeviceColorSpaceName : NSDeviceRGBColorSpace,
        NSDeviceBitsPerSample : @8,
        NSDeviceIsScreen : @YES
    };
}

- (void *) windowRef {
    NSUnimplementedMethod();
    return NULL;
}

// Views are drawn on the main thread one after another whatever this says,
// which the documentation allows: the flag only permits concurrent drawing.
- (BOOL) allowsConcurrentViewDrawing {
    return !NS_EXTRA(NSWindow, self)->_concurrentViewDrawingDisabled;
}

- (void) setAllowsConcurrentViewDrawing: (BOOL) allows {
    NS_EXTRA(NSWindow, self)->_concurrentViewDrawingDisabled = !allows;
}

- (NSView *) contentView {
    return _contentView;
}

- (id) delegate {
    return _delegate;
}

- (NSString *) title {
    return NS_EXTRA(NSWindow, self)->_title;
}

- (NSString *) representedFilename {
    return NS_EXTRA(NSWindow, self)->_representedFilename;
}

- (NSURL *) representedURL {
    return _representedURL;
}

- (NSWindowLevel) level {
    return _level;
}

- (NSRect) frame {
    return _frame;
}

- (NSWindowStyleMask) styleMask {
    return NS_EXTRA(NSWindow, self)->_styleMask;
}

- (NSBackingStoreType) backingType {
    return NS_EXTRA(NSWindow, self)->_backingType;
}

- (NSWindowBackingLocation) preferredBackingLocation {
    NSUnimplementedMethod();
    return 0;
}

- (void) setPreferredBackingLocation: (NSWindowBackingLocation) location {
    NSUnimplementedMethod();
}

- (NSWindowBackingLocation) backingLocation {
    NSUnimplementedMethod();
    return 0;
}

- (NSSize) minSize {
    return NS_EXTRA(NSWindow, self)->_minSize;
}

- (NSSize) maxSize {
    return NS_EXTRA(NSWindow, self)->_maxSize;
}

- (NSSize) contentMinSize {
    return NS_EXTRA(NSWindow, self)->_contentMinSize;
}

- (NSSize) contentMaxSize {
    return NS_EXTRA(NSWindow, self)->_contentMaxSize;
}

// Stored only: Cocotron has no full screen mode that applies them.
- (NSSize) minFullScreenContentSize {
    return NS_EXTRA(NSWindow, self)->_minFullScreenContentSize;
}

- (void) setMinFullScreenContentSize: (NSSize) value {
    NS_EXTRA(NSWindow, self)->_minFullScreenContentSize = value;
}

- (NSSize) maxFullScreenContentSize {
    return NS_EXTRA(NSWindow, self)->_maxFullScreenContentSize;
}

- (void) setMaxFullScreenContentSize: (NSSize) value {
    NS_EXTRA(NSWindow, self)->_maxFullScreenContentSize = value;
}

- (BOOL) isOneShot {
    return NS_EXTRA(NSWindow, self)->_isOneShot;
}

- (BOOL) isOpaque {
    return NS_EXTRA(NSWindow, self)->_isOpaque;
}

- (BOOL) hasDynamicDepthLimit {
    return NS_EXTRA(NSWindow, self)->_dynamicDepthLimit;
}

- (BOOL) isReleasedWhenClosed {
    return NS_EXTRA(NSWindow, self)->_releaseWhenClosed;
}

- (BOOL) preventsApplicationTerminationWhenModal {
    return !NS_EXTRA(NSWindow, self)->_allowsTerminationWhenModal;
}

- (void) setPreventsApplicationTerminationWhenModal: (BOOL) prevents {
    NS_EXTRA(NSWindow, self)->_allowsTerminationWhenModal = !prevents;
}

- (BOOL) hidesOnDeactivate {
    return NS_EXTRA(NSWindow, self)->_hidesOnDeactivate;
}

- (BOOL) worksWhenModal {
    // We do work when we're running a modal session
    return (NS_EXTRA(NSWindow, self)->_sheetContext && [NS_EXTRA(NSWindow, self)->_sheetContext modalSession] != nil);
}

- (BOOL) isSheet {
    return (NS_EXTRA(NSWindow, self)->_styleMask & NSDocModalWindowMask) ? YES : NO;
}

- (BOOL) acceptsMouseMovedEvents {
    return NS_EXTRA(NSWindow, self)->_acceptsMouseMovedEvents;
}

- (BOOL) isExcludedFromWindowsMenu {
    return NS_EXTRA(NSWindow, self)->_excludedFromWindowsMenu;
}

- (BOOL) isAutodisplay {
    return NS_EXTRA(NSWindow, self)->_isAutodisplay;
}

- (BOOL) isFlushWindowDisabled {
    return NS_EXTRA(NSWindow, self)->_isFlushWindowDisabled;
}

- (NSString *) frameAutosaveName {
    return _autosaveFrameName;
}

- (BOOL) hasShadow {
    return NS_EXTRA(NSWindow, self)->_hasShadow;
}

- (BOOL) ignoresMouseEvents {
    return NS_EXTRA(NSWindow, self)->_ignoresMouseEvents;
}

- (NSSize) aspectRatio {
    return NSMakeSize(1.0, NS_EXTRA(NSWindow, self)->_resizeIncrements.height / NS_EXTRA(NSWindow, self)->_resizeIncrements.width);
}

- (NSSize) contentAspectRatio {
    return NSMakeSize(1.0, NS_EXTRA(NSWindow, self)->_contentResizeIncrements.height /
                                   NS_EXTRA(NSWindow, self)->_contentResizeIncrements.width);
}

- (BOOL) autorecalculatesKeyViewLoop {
    return NS_EXTRA(NSWindow, self)->_autorecalculatesKeyViewLoop;
}

- (BOOL) canHide {
    return NS_EXTRA(NSWindow, self)->_canHide;
}

- (BOOL) canStoreColor {
    return NS_EXTRA(NSWindow, self)->_canStoreColor;
}

- (BOOL) showsResizeIndicator {
    return NS_EXTRA(NSWindow, self)->_showsResizeIndicator;
}

- (BOOL) showsToolbarButton {
    return NS_EXTRA(NSWindow, self)->_showsToolbarButton;
}

- (BOOL) displaysWhenScreenProfileChanges {
    return NS_EXTRA(NSWindow, self)->_displaysWhenScreenProfileChanges;
}

- (BOOL) isMovableByWindowBackground {
    return NS_EXTRA(NSWindow, self)->_isMovableByWindowBackground;
}

- (BOOL) allowsToolTipsWhenApplicationIsInactive {
    return NS_EXTRA(NSWindow, self)->_allowsToolTipsWhenApplicationIsInactive;
}

- (NSImage *) miniwindowImage {
    return _miniwindowImage;
}

- (NSString *) miniwindowTitle {
    return NS_EXTRA(NSWindow, self)->_miniwindowTitle;
}

- (NSDockTile *) dockTile {
    NSUnimplementedMethod();
    return nil;
}

- (NSColor *) backgroundColor {
    return _backgroundColor;
}

- (CGFloat) alphaValue {
    return NS_EXTRA(NSWindow, self)->_alphaValue;
}

- (NSWindowDepth) depthLimit {
    return 0;
}

- (NSSize) resizeIncrements {
    return NS_EXTRA(NSWindow, self)->_resizeIncrements;
}

- (NSSize) contentResizeIncrements {
    return NS_EXTRA(NSWindow, self)->_contentResizeIncrements;
}

- (BOOL) preservesContentDuringLiveResize {
    return NO;
}

- (NSToolbar *) toolbar {
    return _toolbar;
}

- (NSView *) initialFirstResponder {
    return _initialFirstResponder;
}

- (void) removeObserver: (NSNotificationName) name selector: (SEL) selector {
    if ([_delegate respondsToSelector: selector]) {
        [[NSNotificationCenter defaultCenter] removeObserver: _delegate
                                                        name: name
                                                      object: self];
    }
}

- (void) addObserver: (NSNotificationName) name selector: (SEL) selector {
    if ([_delegate respondsToSelector: selector]) {
        [[NSNotificationCenter defaultCenter] addObserver: _delegate
                                                 selector: selector
                                                     name: name
                                                   object: self];
    }
}

- (void) setDelegate: (id<NSWindowDelegate>) delegate {
    struct note {
        NSNotificationName name;
        SEL selector;
    } notes[] = {
            {NSWindowDidBecomeKeyNotification, @selector(windowDidBecomeKey:)},
            {NSWindowDidBecomeMainNotification,
             @selector(windowDidBecomeMain:)},
            {NSWindowDidDeminiaturizeNotification,
             @selector(windowDidDeminiaturize:)},
            {NSWindowDidMiniaturizeNotification,
             @selector(windowDidMiniaturize:)},
            {NSWindowDidMoveNotification, @selector(windowDidMove:)},
            {NSWindowDidChangeOcclusionStateNotification,
             @selector(windowDidChangeOcclusionState:)},
            {NSWindowDidResignKeyNotification, @selector(windowDidResignKey:)},
            {NSWindowDidResignMainNotification,
             @selector(windowDidResignMain:)},
            {NSWindowDidResizeNotification, @selector(windowDidResize:)},
            {NSWindowWillStartLiveResizeNotification,
             @selector(windowWillStartLiveResize:)},
            {NSWindowDidEndLiveResizeNotification,
             @selector(windowDidEndLiveResize:)},
            {NSWindowDidUpdateNotification, @selector(windowDidUpdate:)},
            {NSWindowDidChangeScreenNotification,
             @selector(windowDidChangeScreen:)},
            {NSWindowDidChangeScreenProfileNotification,
             @selector(windowDidChangeScreenProfile:)},
            {NSWindowDidExposeNotification, @selector(windowDidExpose:)},
            {NSWindowDidChangeBackingPropertiesNotification,
             @selector(windowDidChangeBackingProperties:)},
            {NSWindowWillBeginSheetNotification,
             @selector(windowWillBeginSheet:)},
            {NSWindowDidEndSheetNotification, @selector(windowDidEndSheet:)},
            {NSWindowWillEnterFullScreenNotification,
             @selector(windowWillEnterFullScreen:)},
            {NSWindowDidEnterFullScreenNotification,
             @selector(windowDidEnterFullScreen:)},
            {NSWindowWillExitFullScreenNotification,
             @selector(windowWillExitFullScreen:)},
            {NSWindowDidExitFullScreenNotification,
             @selector(windowDidExitFullScreen:)},
            {NSWindowWillEnterVersionBrowserNotification,
             @selector(windowWillEnterVersionBrowser:)},
            {NSWindowDidEnterVersionBrowserNotification,
             @selector(windowDidEnterVersionBrowser:)},
            {NSWindowWillExitVersionBrowserNotification,
             @selector(windowWillExitVersionBrowser:)},
            {NSWindowDidExitVersionBrowserNotification,
             @selector(windowDidExitVersionBrowser:)},
            {NSWindowWillCloseNotification, @selector(windowWillClose:)},
            {NSWindowWillMiniaturizeNotification,
             @selector(windowWillMiniaturize:)},
            {NSWindowWillMoveNotification, @selector(windowWillMove:)},
            {nil, NULL}};

    if (_delegate != nil) {
        for (struct note *note = &notes[0]; note->name != nil; note++) {
            [self removeObserver: note->name selector: note->selector];
        }
    }

    _delegate = delegate;

    if (_delegate != nil) {
        for (struct note *note = &notes[0]; note->name != nil; note++) {
            [self addObserver: note->name selector: note->selector];
        }
    }
}

- (void) _makeSureIsOnAScreen {
    if (!NS_EXTRA(NSWindow, self)->_makeSureIsOnAScreen || ![self isVisible] || [self isMiniaturized]) {
        return;
    }

    NSRect frame = _frame;
    BOOL changed = NO;
#if 1
    BOOL tooFarLeft = YES, tooFarRight = YES, tooFarUp = YES, tooFarDown = YES;
    CGFloat leastX = 0, maxX = 0, leastY = 0, maxY = 0;

    for (NSScreen *screen in [NSScreen screens]) {
        NSRect screenFrame = [screen frame];

        if (NSMaxX(frame) > screenFrame.origin.x + 20)
            tooFarLeft = NO;
        if (frame.origin.x < NSMaxX(screenFrame) - 20)
            tooFarRight = NO;
        if (frame.origin.y < NSMaxY(screenFrame) - 20)
            tooFarUp = NO;
        if (NSMaxY(frame) > screenFrame.origin.y + 20)
            tooFarDown = NO;

        if (screenFrame.origin.x < leastX)
            leastX = screenFrame.origin.x;
        if (screenFrame.origin.y < leastY)
            leastY = screenFrame.origin.y;
        if (NSMaxX(screenFrame) > maxX)
            maxX = NSMaxX(screenFrame);
        if (NSMaxY(screenFrame) > maxY)
            maxY = NSMaxY(screenFrame);
    }

    if (tooFarLeft) {
        frame.origin.x = (leastX + 20) - frame.size.width;
        changed = YES;
    }
    if (tooFarRight) {
        frame.origin.x = maxX - 20;
        changed = YES;
    }
    if (tooFarUp) {
        frame.origin.y = (maxY - 20) - frame.size.height;
        changed = YES;
    }
    if (tooFarDown) {
        changed = YES;
        frame.origin.y = (leastY + 20) - frame.size.height;
    }
#else
    NSRect virtual = NSZeroRect;

    for (NSScreen *screen in [NSScreen screens]) {
        NSRect screenFrame = [screen frame];
        virtual = NSUnionRect(virtual, screen);
    }
    virtual = NSInsetRect(virtual, 20, 20);

    if (NSMaxX(frame) < virtual.origin.x) {
        frame.origin.x = virtual.origin.x - frame.size.width;
        changed = YES;
    }
    if (frame.origin.x > NSMaxX(virtual)) {
        frame.origin.x = NSMaxX(virtual);
        changed = YES;
    }

    if (NSMaxY(frame) > NSMaxY(virtual)) {
        frame.origin.y = NSMaxY(virtual) - frame.size.height;
        changed = YES;
    }
    if (NSMaxY(frame) < virtual.origin.y) {
        changed = YES;
        frame.origin.y = virtual.origin.y - frame.size.height;
    }
#endif

    if (changed) {
        [self setFrame: frame display: YES];
    }
    NS_EXTRA(NSWindow, self)->_makeSureIsOnAScreen = NO;
}

- (void) setFrame: (NSRect) frame display: (BOOL) display {
    [self setFrame: frame display: display animate: NO];
}

- (void) _animateWithContext: (NSWindowAnimationContext *) context {
    NSRect frame = [self frame];
    NSDictionary *userInfo = @{@"NSWindowAnimationContext" : context};

    if (NS_EXTRA(NSWindow, self)->_animationContext == nil)
        NS_EXTRA(NSWindow, self)->_animationContext = [context retain];

    if (NS_EXTRA(NSWindow, self)->_animationContext != context)
        [NSException raise: NSInvalidArgumentException
                    format: @"-[%@ %@]: attempt to animate frame while "
                            @"animation still in progress",
                            [self class], NSStringFromSelector(_cmd)];

    [[NSNotificationCenter defaultCenter]
            postNotificationName: NSWindowWillAnimateNotification
                          object: self
                        userInfo: userInfo];

    [context decrement];

    if ([context stepCount] > 0) {
        frame.origin.x += [context stepRect].origin.x;
        frame.origin.y += [context stepRect].origin.y;
        frame.size.width += [context stepRect].size.width;
        frame.size.height += [context stepRect].size.height;
    } else
        frame = [context targetRect];

    [self setFrame: frame display: [context display]];

    [[NSNotificationCenter defaultCenter]
            postNotificationName: NSWindowAnimatingNotification
                          object: self
                        userInfo: userInfo];

    if ([context stepCount] > 0) {
        [self performSelector: _cmd
                   withObject: context
                   afterDelay: [context stepInterval]];
    } else {
        [[NSNotificationCenter defaultCenter]
                postNotificationName: NSWindowDidAnimateNotification
                              object: self
                            userInfo: userInfo];

        [NS_EXTRA(NSWindow, self)->_animationContext release];
        NS_EXTRA(NSWindow, self)->_animationContext = nil;
#if 0
        if ([_backgroundView cachesImageForAnimation])
            [_backgroundView invalidateCachedImage];
#endif
    }
}

- (NSWindowAnimationContext *) _animationContext {
    return NS_EXTRA(NSWindow, self)->_animationContext;
}

- (void) setFrame: (NSRect) newFrame
          display: (BOOL) display
          animate: (BOOL) animate
{
    BOOL didSize = !NSEqualSizes(newFrame.size, _frame.size);
    BOOL didMove = !NSEqualPoints(newFrame.origin, _frame.origin);

    _frame = newFrame;
    NS_EXTRA(NSWindow, self)->_makeSureIsOnAScreen = YES;

    [_backgroundView setFrameSize: _frame.size];
    [_platformWindow setFrame: _frame];

    if (didSize) {
        [self resetCursorRects];
        [self postNotificationName: NSWindowDidResizeNotification];
    }

    if (didMove) {
        [self postNotificationName: NSWindowDidMoveNotification];
    }

    // If you setFrame:display:YES before rearranging views with only setFrame:
    // calls (which do not mark the view for display) Cocoa will properly
    // redisplay the views. So, doing a hard display right here is not the right
    // thing to do, delay it.
    if (display) {
        if (!NS_EXTRA(NSWindow, self)->_isDeferred || _platformWindow != nil)
            [self platformWindow];
        [_backgroundView setNeedsDisplay: YES];
    }

    if (animate) {
        NSWindowAnimationContext *context;
        context = [NSWindowAnimationContext
                contextToTransformWindow: self
                               startRect: [self frame]
                              targetRect: newFrame
                              resizeTime: [self animationResizeTime: newFrame]
                                 display: display];
        [self _animateWithContext: context];
    }
}

- (void) setContentSize: (NSSize) size {
    NSRect content = [self contentRectForFrameRect: [self frame]];
    content.size = size;
    NSRect frame = [self frameRectForContentRect: content];
    [self setFrame: frame display: YES];
}

- (void) setFrameOrigin: (NSPoint) point {
    NSRect frame = [self frame];
    frame.origin = point;
    [self setFrame: frame display: NO];
}

- (void) setFrameTopLeftPoint: (NSPoint) point {
    NSRect frame = [self frame];

    frame.origin.x = point.x;
    frame.origin.y = point.y - frame.size.height;

    [self setFrame: frame display: NO];
}

- (void) setMinSize: (NSSize) size {
    NS_EXTRA(NSWindow, self)->_minSize = size;
}

- (void) setMaxSize: (NSSize) size {
    NS_EXTRA(NSWindow, self)->_maxSize = size;
}

- (void) setContentMinSize: (NSSize) value {
    // The value was already being stored; the unimplemented marker made every
    // caller raise instead.
    NS_EXTRA(NSWindow, self)->_contentMinSize = value;
}

- (void) setContentMaxSize: (NSSize) value {
    NS_EXTRA(NSWindow, self)->_contentMaxSize = value;
}

- (void) setContentBorderThickness: (CGFloat) thickness
                           forEdge: (NSRectEdge) edge
{
    // FIXME: should warn, but low priority cosmetic, so we dont, still needs to
    // be implemented
    //   NSUnimplementedMethod();
}

- (void) setMovable: (BOOL) movable {
    NS_EXTRA(NSWindow, self)->_isMovable = movable;
}

- (void) performWindowDragWithEvent: (NSEvent *) event {
    if (!NS_EXTRA(NSWindow, self)->_isMovable || [event type] != NSLeftMouseDown)
        return;

    // Follow the pointer in screen coordinates. An event's location in the
    // window is measured against where the window really is, which lags
    // behind -setFrameOrigin: while the window system catches up, so
    // converting it with the new frame would feed that lag back in.
    NSPoint origin = [self frame].origin;
    NSPoint first = [NSEvent mouseLocation];
    for (;;) {
        NSEvent *next = [self nextEventMatchingMask: NSLeftMouseUpMask |
                                                     NSLeftMouseDraggedMask];
        if (next == nil || [next type] == NSLeftMouseUp)
            break;

        NSPoint point = [NSEvent mouseLocation];
        [self setFrameOrigin: NSMakePoint(origin.x + point.x - first.x,
                                          origin.y + point.y - first.y)];
    }
}

- (void) setBackingType: (NSBackingStoreType) value {
    NS_EXTRA(NSWindow, self)->_backingType = value;
    NSUnimplementedMethod();
}

- (void) setDynamicDepthLimit: (BOOL) value {
    NS_EXTRA(NSWindow, self)->_dynamicDepthLimit = value;
}

- (void) setOneShot: (BOOL) flag {
    NS_EXTRA(NSWindow, self)->_isOneShot = flag;
}

- (void) setReleasedWhenClosed: (BOOL) flag {
    NS_EXTRA(NSWindow, self)->_releaseWhenClosed = flag;
}

- (void) setHidesOnDeactivate: (BOOL) flag {
    NS_EXTRA(NSWindow, self)->_hidesOnDeactivate = flag;
}

- (void) setAcceptsMouseMovedEvents: (BOOL) flag {
    NS_EXTRA(NSWindow, self)->_acceptsMouseMovedEvents = flag;
    [_platformWindow syncDelegateProperties];
}

- (void) setExcludedFromWindowsMenu: (BOOL) value {
    NS_EXTRA(NSWindow, self)->_excludedFromWindowsMenu = value;
}

- (void) setAutodisplay: (BOOL) value {
    NS_EXTRA(NSWindow, self)->_isAutodisplay = value;
}

- (void) setAutorecalculatesContentBorderThickness: (BOOL) automatic
                                           forEdge: (NSRectEdge) edge
{
    // FIXME: should warn, but low priority cosmetic, so we dont, still needs to
    // be implemented
    //   NSUnimplementedMethod();
}

- (BOOL) _isApplicationWindow {
    return ![self isKindOfClass: [NSPanel class]] && [self isVisible] &&
           ![self isExcludedFromWindowsMenu];
}

- (void) setTitle: (NSString *) title {
    title = [title copy];
    [NS_EXTRA(NSWindow, self)->_title release];
    NS_EXTRA(NSWindow, self)->_title = title;

    [NS_EXTRA(NSWindow, self)->_miniwindowTitle release];
    NS_EXTRA(NSWindow, self)->_miniwindowTitle = [title copy];

    [self _updatePlatformWindowTitle];

    if ([self _isApplicationWindow])
        [NSApp changeWindowsItem: self title: title filename: NO];
}

- (void) setTitleWithRepresentedFilename: (NSString *) filename {
    [self setTitle: [NSString
                            stringWithFormat:
                                    @"%@  --  %@", [filename lastPathComponent],
                                    [filename
                                            stringByDeletingLastPathComponent]]];

    if ([self _isApplicationWindow])
        [NSApp changeWindowsItem: self title: filename filename: YES];
}

+ (instancetype) windowWithContentViewController: (NSViewController *) controller {
    NSSize size = [controller preferredContentSize];
    if (NSEqualSizes(size, NSZeroSize))
        size = [[controller view] frame].size;
    NSWindow *window = [[[self alloc]
            initWithContentRect: NSMakeRect(0, 0, size.width, size.height)
                      styleMask: NSTitledWindowMask | NSClosableWindowMask |
                                 NSMiniaturizableWindowMask | NSResizableWindowMask
                        backing: NSBackingStoreBuffered
                          defer: YES] autorelease];
    [window setContentViewController: controller];
    if ([controller title] != nil)
        [window setTitle: [controller title]];
    return window;
}

- (NSViewController *) contentViewController {
    return NS_EXTRA(NSWindow, self)->_contentViewController;
}

- (void) setContentViewController: (NSViewController *) controller {
    [controller retain];
    [NS_EXTRA(NSWindow, self)->_contentViewController release];
    NS_EXTRA(NSWindow, self)->_contentViewController = controller;
    if (controller != nil)
        [self setContentView: [controller view]];
}

- (void) setContentView: (NSView *) view {
    view = [view retain];
    // The initializer installs the first content view with its frame set.
    if (_contentView != nil)
        [view setFrame: [_contentView frame]];

    [_contentView removeFromSuperview];
    [_contentView release];

    _contentView = view;

    [_backgroundView addSubview: _contentView];
}

- (void) setInitialFirstResponder: (NSView *) view {
    _initialFirstResponder = view;
}

- (void) setMiniwindowImage: (NSImage *) image {
    image = [image retain];
    [_miniwindowImage release];
    _miniwindowImage = image;
}

- (void) setMiniwindowTitle: (NSString *) title {
    title = [title copy];
    [NS_EXTRA(NSWindow, self)->_miniwindowTitle release];
    NS_EXTRA(NSWindow, self)->_miniwindowTitle = title;

    [self _updatePlatformWindowTitle];
}

- (void) setBackgroundColor: (NSColor *) color {
    if (color == nil)
        color = [NSColor windowBackgroundColor];
    color = [color copy];
    [_backgroundColor release];
    _backgroundColor = color;
    [_backgroundView setNeedsDisplay: YES];
}

- (void) setAlphaValue: (CGFloat) value {
    NS_EXTRA(NSWindow, self)->_alphaValue = value;
    [_platformWindow setAlphaValue: value];
}

- (void) _toolbarSizeDidChangeFromOldHeight: (CGFloat) oldHeight {
    NSView *toolbarView = [_toolbar _view];
    NSAutoresizingMaskOptions mask = [[self contentView] autoresizingMask];
    NSRect frame = [self frame];

    [_toolbar
            layoutFrameSizeWithWidth: NSWidth([[self _backgroundView] bounds])];
    CGFloat newHeight = [_toolbar visibleHeight];
    CGFloat contentHeightDelta = newHeight - oldHeight;

    frame.size.height += contentHeightDelta;
    frame.origin.y -= contentHeightDelta;

    NSRect backgroundBounds = [self _backgroundView].bounds;
    NSPoint toolbarOrigin;
    toolbarOrigin.x = backgroundBounds.origin.x;
    toolbarOrigin.y = NSMaxY([[self contentView] frame]) - contentHeightDelta;
    [toolbarView setFrameOrigin: toolbarOrigin];

    [[self contentView] setAutoresizingMask: NSViewNotSizable];
    [self setFrame: frame display: NO animate: NO];

    [[self contentView] setAutoresizingMask: mask];
}

- (void) setToolbar: (NSToolbar *) toolbar {
    if (toolbar == _toolbar) {
        return;
    }
    toolbar = [toolbar retain];

    CGFloat oldHeight = [_toolbar visibleHeight];
    [_toolbar _setWindow: nil];
    [[_toolbar _view] removeFromSuperview];
    [_toolbar release];
    if (_toolbar != nil) {
        [[self _backgroundView] setNeedsDisplay: YES];
    }

    _toolbar = toolbar;

    if (_toolbar != nil) {
        [_toolbar _setWindow: self];
        [[self _backgroundView] addSubview: [_toolbar _view]];
        [[self _backgroundView] setNeedsDisplay: YES];
    }
    [self _toolbarSizeDidChangeFromOldHeight: oldHeight];
}

- (void) setDefaultButtonCell: (NSButtonCell *) buttonCell {
    [_defaultButtonCell autorelease];
    _defaultButtonCell = [buttonCell retain];
    [_defaultButtonCell setKeyEquivalent: @"\r"];
    [[_defaultButtonCell controlView] setNeedsDisplay: YES];
}

- (void) setWindowController: (NSWindowController *) value {
    NS_EXTRA(NSWindow, self)->_windowController = value;
    /*
      Cocoa does not setReleasedWhenClosed: NO when setWindowController: is
      called. The NSWindowController class does setReleasedWhenClosed: NO in
      conjunction with setWindowController:

      However, there is one application (AC), which calls setWindowController:
      standalone and does _something else_ which also does
      setReleasedWhenClosed: NO. Perhaps some byproduct of NSDocument,
      NSWindowController or NSWindow. THis hasn't been figured out yet. So, in
      the meantime we do setReleasedWhenClosed: NO since all cases which do call
      setWindowController: also want setReleasedWhenClosed: NO.
    */
    [self setReleasedWhenClosed: NO];
}

- (void) setDocumentEdited: (BOOL) flag {
    NS_EXTRA(NSWindow, self)->_isDocumentEdited = flag;
    [self _updatePlatformWindowTitle];
}

- (void) setContentAspectRatio: (NSSize) value {
    NS_EXTRA(NSWindow, self)->_resizeIncrements.width = 1.0;
    NS_EXTRA(NSWindow, self)->_resizeIncrements.height = value.height / value.width;
}

- (void) setHasShadow: (BOOL) value {
    NS_EXTRA(NSWindow, self)->_hasShadow = value;
    [_platformWindow setHasShadow: value];
}

- (void) setIgnoresMouseEvents: (BOOL) value {
    NS_EXTRA(NSWindow, self)->_ignoresMouseEvents = value;
    [_platformWindow syncDelegateProperties];
}

- (void) setAspectRatio: (NSSize) value {
    NS_EXTRA(NSWindow, self)->_resizeIncrements.width = 1.0;
    NS_EXTRA(NSWindow, self)->_resizeIncrements.height = value.height / value.width;
}

- (void) setAutorecalculatesKeyViewLoop: (BOOL) value {
    NS_EXTRA(NSWindow, self)->_autorecalculatesKeyViewLoop = value;
}

- (void) setCanHide: (BOOL) value {
    NS_EXTRA(NSWindow, self)->_canHide = value;
}

// There is no login window to show windows on, so the flag is only stored.
- (void) setCanBecomeVisibleWithoutLogin: (BOOL) flag {
    NS_EXTRA(NSWindow, self)->_canBecomeVisibleWithoutLogin = flag;
}

- (NSArray<NSWindow *> *) tabbedWindows {
    // Windows without a tab bar have no tab group. Cocotron does not yet
    // provide native window tabbing.
    return nil;
}

- (BOOL) bottomCornerRounded {
    return NS_EXTRA(NSWindow, self)->_bottomCornerRounded;
}

- (id) tab {
    // A window without a tab group has no tab object.
    return nil;
}

- (void) setBottomCornerRounded: (BOOL) rounded {
    NS_EXTRA(NSWindow, self)->_bottomCornerRounded = rounded;
}

- (void) setLevel: (NSInteger) value {
    _level = value;
    [_platformWindow setLevel: _level];
}

- (void) setOpaque: (BOOL) value {
    NS_EXTRA(NSWindow, self)->_isOpaque = value;
    [_platformWindow setOpaque: NS_EXTRA(NSWindow, self)->_isOpaque];
}

- (void) setParentWindow: (NSWindow *) value {
    NS_EXTRA(NSWindow, self)->_parentWindow = value;
}

- (void) setPreservesContentDuringLiveResize: (BOOL) value {
    // _preservesContentDuringLiveResize=value;
}

// The represented filename and URL describe the same file; setting one updates
// the other. A non-file URL has no filename.
- (void) setRepresentedFilename: (NSString *) value {
    value = [value copy];
    [NS_EXTRA(NSWindow, self)->_representedFilename release];
    NS_EXTRA(NSWindow, self)->_representedFilename = value;

    [_representedURL release];
    _representedURL = [value length] > 0
            ? [[NSURL fileURLWithPath: value] retain] : nil;
}

- (void) setRepresentedURL: (NSURL *) newURL {
    newURL = [newURL copy];
    [_representedURL release];
    _representedURL = newURL;

    [NS_EXTRA(NSWindow, self)->_representedFilename release];
    NS_EXTRA(NSWindow, self)->_representedFilename = [newURL isFileURL] ? [[newURL path] copy] : nil;
}

- (void) setResizeIncrements: (NSSize) value {
    NS_EXTRA(NSWindow, self)->_resizeIncrements = value;
}

- (void) setShowsResizeIndicator: (BOOL) value {
    NS_EXTRA(NSWindow, self)->_showsResizeIndicator = value;
}

- (void) setShowsToolbarButton: (BOOL) value {
    NS_EXTRA(NSWindow, self)->_showsToolbarButton = value;
    NSUnimplementedMethod();
}

- (void) setContentResizeIncrements: (NSSize) value {
    NS_EXTRA(NSWindow, self)->_contentResizeIncrements = value;
}

- (void) setDepthLimit: (NSWindowDepth) value {
    NSUnimplementedMethod();
}

- (void) setDisplaysWhenScreenProfileChanges: (BOOL) value {
    NS_EXTRA(NSWindow, self)->_displaysWhenScreenProfileChanges = value;
}

- (void) setMovableByWindowBackground: (BOOL) value {
    NS_EXTRA(NSWindow, self)->_isMovableByWindowBackground = value;
}

- (void) setAllowsToolTipsWhenApplicationIsInactive: (BOOL) value {
    NS_EXTRA(NSWindow, self)->_allowsToolTipsWhenApplicationIsInactive = value;
}

- (BOOL) autorecalculatesContentBorderThicknessForEdge: (NSRectEdge) edge {
    NSUnimplementedMethod();
    return NO;
}

- (CGFloat) contentBorderThicknessForEdge: (NSRectEdge) edge {
    NSUnimplementedMethod();
    return 0.;
}

- (NSString *) _autosaveFrameKeyWithName: (NSString *) name {
    return [NSString stringWithFormat: @"NSWindow frame %@ %@", name,
                                       NSStringFromRect([[self screen] frame])];
}

- (BOOL) setFrameUsingName: (NSString *) name {
    return [self setFrameUsingName: name force: NO];
}

- (BOOL) setFrameUsingName: (NSString *) name force: (BOOL) force {
    NSString *key = [self _autosaveFrameKeyWithName: name];
    NSString *value = [[NSUserDefaults standardUserDefaults] objectForKey: key];

    if ([value length] == 0)
        return NO;

    [self setFrameFromString: value];
    return YES;
}

- (void) _setFrameAutosaveNameNoIO: (NSString *) name {
    name = [name copy];
    [_autosaveFrameName release];
    _autosaveFrameName = name;
}

- (BOOL) setFrameAutosaveName: (NSString *) name {
    [self _setFrameAutosaveNameNoIO: name];

    [self setFrameUsingName: _autosaveFrameName];
    [self saveFrameUsingName: _autosaveFrameName];
    return YES;
}

- (void) postAwakeFromNib {
    /*
      We do this after awakeFromNib because a saved frame is also post
      awakeFromNib. If awakeFromNib modifies the windows adornments we need to
      wait until here to actually set it.
    */
    if ([_autosaveFrameName length] > 0) {
        [self setFrameUsingName: _autosaveFrameName];
        [self saveFrameUsingName: _autosaveFrameName];
    }
}

- (void) saveFrameUsingName: (NSString *) name {
    if ([name length] > 0) {
        NSString *key = [self _autosaveFrameKeyWithName: name];
        NSString *value = [self stringWithSavedFrame];

        [[NSUserDefaults standardUserDefaults] setObject: value forKey: key];
    }
}

- (void) setFrameFromString: (NSString *) value {
    NSRect rect = NSRectFromString(value);

    if (!NSIsEmptyRect(rect)) {
        [self setFrame: rect display: YES];
    }
}

- (NSString *) stringWithSavedFrame {
    return NSStringFromRect([self frame]);
}

- (NSEventModifierFlags) resizeFlags {
    NSUnimplementedMethod();
    return 0;
}

- (CGFloat) userSpaceScaleFactor {
    return 1.0;
}

- (NSResponder *) firstResponder {
    if ([_firstResponder isKindOfClass: [NSDrawer class]])
        return [_firstResponder nextResponder];
    else
        return _firstResponder;
}

- (NSButton *) standardWindowButton: (NSWindowButton) value {
    if (value > NSWindowZoomButton)
        return nil;
    if (NS_EXTRA(NSWindow, self)->_standardWindowButtons[value] == nil)
        NS_EXTRA(NSWindow, self)->_standardWindowButtons[value] = [[[self class]
                standardWindowButton: value
                        forStyleMask: NS_EXTRA(NSWindow, self)->_styleMask] retain];
    return NS_EXTRA(NSWindow, self)->_standardWindowButtons[value];
}

- (NSButtonCell *) defaultButtonCell {
    return _defaultButtonCell;
}

- (NSWindow *) attachedSheet {
    return [NS_EXTRA(NSWindow, self)->_sheetContext sheet];
}

- (NSWindow *) sheetParent {
    // The sheet is recorded on the window it is attached to.
    for (NSWindow *window in [NSApp windows]) {
        if (window != self && [window attachedSheet] == self)
            return window;
    }
    return nil;
}

- (id) windowController {
    return NS_EXTRA(NSWindow, self)->_windowController;
}

- (NSArray *) drawers {
    return NS_EXTRA(NSWindow, self)->_drawers;
}

- (NSInteger) windowNumber {
    // A deferred window has no window device, and so no number, until it is
    // first ordered in; asking for the number must not create the device.
    if (NS_EXTRA(NSWindow, self)->_isDeferred && _platformWindow == nil)
        return -1;
    return [[self platformWindow] windowNumber];
}

- (int) gState {
    NSUnimplementedMethod();
    return 0;
}

- (NSScreen *) screen {
    NSRect mostRect = NSZeroRect;
    NSScreen *mostScreen = nil;

    for (NSScreen *screen in [NSScreen screens]) {
        NSRect intersect = NSIntersectionRect([screen frame], _frame);
        if (intersect.size.width * intersect.size.height >
            mostRect.size.width * mostRect.size.height) {
            mostRect = intersect;
            mostScreen = screen;
        }
    }

    return mostScreen;
}

- (NSScreen *) deepestScreen {
    NSUnimplementedMethod();
    return 0;
}

- (NSColorSpace *) colorSpace {
    NSUnimplementedMethod();
    return nil;
}

- (void) setColorSpace: (NSColorSpace *) newColorSpace {
    NSUnimplementedMethod();
}

// There is a single space, so every window is on the active one.
- (BOOL) isOnActiveSpace {
    return YES;
}

- (NSWindowAnimationBehavior) animationBehavior {
    return NS_EXTRA(NSWindow, self)->_animationBehavior;
}

- (void) setAnimationBehavior: (NSWindowAnimationBehavior) behavior {
    NS_EXTRA(NSWindow, self)->_animationBehavior = behavior;
}

- (NSWindowSharingType) sharingType {
    NSUnimplementedMethod();
    return 0;
}

- (void) setSharingType: (NSWindowSharingType) type {
    NSUnimplementedMethod();
}

- (BOOL) isDocumentEdited {
    return NS_EXTRA(NSWindow, self)->_isDocumentEdited;
}

- (BOOL) isZoomed {
    NSRect zoomedFrame = [self zoomedFrame];
    return NSEqualRects(_frame, zoomedFrame);
}

- (BOOL) isVisible {
    return NS_EXTRA(NSWindow, self)->_isVisible;
}

- (NSWindowOcclusionState) occlusionState {
    return [self isVisible] ? NSWindowOcclusionStateVisible : 0;
}

- (BOOL) isKeyWindow {
    return ([NSApp keyWindow] == self) ? YES : NO;
}

- (BOOL) isMainWindow {
    return ([NSApp mainWindow] == self) ? YES : NO;
}

- (BOOL) isMiniaturized {
    return [_platformWindow isMiniaturized];
}

- (BOOL) isMovable {
    return NS_EXTRA(NSWindow, self)->_isMovable;
}

- (BOOL) inLiveResize {
    return NS_EXTRA(NSWindow, self)->_isInLiveResize;
}

- (BOOL) canBecomeKeyWindow {
    // The NSWindow implementation returns YES if the window has a title bar or
    // a resize bar, or NO otherwise. Mac OS X 10.14 behaves this way for a
    // Resizable mask without Titled too; macOS 26 answers NO for it. We follow
    // 10.14.
    return (NS_EXTRA(NSWindow, self)->_styleMask & (NSTitledWindowMask | NSResizableWindowMask)) != 0;
}

- (BOOL) canBecomeMainWindow {
    // The NSWindow implementation returns YES if the window is visible and has
    // a title bar or a resize mechanism. Otherwise it returns NO
    return [self isVisible] &&
           (NS_EXTRA(NSWindow, self)->_styleMask & (NSTitledWindowMask | NSResizableWindowMask));
}

- (BOOL) canBecomeVisibleWithoutLogin {
    return NS_EXTRA(NSWindow, self)->_canBecomeVisibleWithoutLogin;
}

- (NSWindowCollectionBehavior) collectionBehavior {
    return NS_EXTRA(NSWindow, self)->_collectionBehavior;
}

- (void) setCollectionBehavior: (NSWindowCollectionBehavior) behavior {
    // Terminal sets this on every window it creates, and the previous
    // unimplemented marker made the setter raise, so ordinary window setup
    // aborted. The value is plain window state and is kept.
    NS_EXTRA(NSWindow, self)->_collectionBehavior = behavior;
}

- (NSWindowTabbingMode) tabbingMode {
    return NS_EXTRA(NSWindow, self)->_tabbingMode;
}

- (void) setTabbingMode: (NSWindowTabbingMode)tabbingMode {
    NS_EXTRA(NSWindow, self)->_tabbingMode = tabbingMode;
}

// Until one is set, windows of the same class share an identifier.
- (NSWindowTabbingIdentifier) tabbingIdentifier {
    if (NS_EXTRA(NSWindow, self)->_tabbingIdentifier == nil)
        return NSStringFromClass([self class]);
    return NS_EXTRA(NSWindow, self)->_tabbingIdentifier;
}

- (void) setTabbingIdentifier: (NSWindowTabbingIdentifier) value {
    value = [value copy];
    [NS_EXTRA(NSWindow, self)->_tabbingIdentifier release];
    NS_EXTRA(NSWindow, self)->_tabbingIdentifier = value;
}

- (NSString *) subtitle {
    return NS_EXTRA(NSWindow, self)->_subtitle != nil ? NS_EXTRA(NSWindow, self)->_subtitle : @"";
}

- (void) setSubtitle: (NSString *) value {
    value = [value copy];
    [NS_EXTRA(NSWindow, self)->_subtitle release];
    NS_EXTRA(NSWindow, self)->_subtitle = value;
}

- (NSWindowTitleVisibility) titleVisibility {
    return NS_EXTRA(NSWindow, self)->_titleVisibility;
}

- (void) setTitleVisibility: (NSWindowTitleVisibility) value {
    NS_EXTRA(NSWindow, self)->_titleVisibility = value;
}

- (BOOL) titlebarAppearsTransparent {
    return NS_EXTRA(NSWindow, self)->_titlebarAppearsTransparent;
}

- (void) setTitlebarAppearsTransparent: (BOOL) value {
    NS_EXTRA(NSWindow, self)->_titlebarAppearsTransparent = value;
    // Whether the platform draws a title bar depends on it for full-size content views.
    if ([_platformWindow respondsToSelector: @selector(updateDecorationsForStyleMask:)])
        [(id) _platformWindow updateDecorationsForStyleMask: NS_EXTRA(NSWindow, self)->_styleMask];
}

- (NSTitlebarSeparatorStyle) titlebarSeparatorStyle {
    return NS_EXTRA(NSWindow, self)->_titlebarSeparatorStyle;
}

- (void) setTitlebarSeparatorStyle: (NSTitlebarSeparatorStyle) value {
    NS_EXTRA(NSWindow, self)->_titlebarSeparatorStyle = value;
}

- (NSWindowToolbarStyle) toolbarStyle {
    return NS_EXTRA(NSWindow, self)->_toolbarStyle;
}

- (void) setToolbarStyle: (NSWindowToolbarStyle) value {
    NS_EXTRA(NSWindow, self)->_toolbarStyle = value;
}

- (NSPoint) convertBaseToScreen: (NSPoint) point {
    NSRect frame = [self frame];

    point.x += frame.origin.x;
    point.y += frame.origin.y;

    return point;
}

- (NSPoint) convertScreenToBase: (NSPoint) point {
    NSRect frame = [self frame];

    point.x -= frame.origin.x;
    point.y -= frame.origin.y;

    return point;
}

- (NSRect) frameRectForContentRect: (NSRect) contentRect {
    // hasMainMenu is an instance method so we can't just use the class method
    //  frameRectForContentRect:styleMask:

    NSRect result = [[NSDisplay currentDisplay] outsetRect: contentRect
                            forNativeWindowBorderWithStyle: [self styleMask]];

    if ([self hasMainMenu]) {
        result.size.height += [NSMainMenuView menuHeight];
    }

    if ([_toolbar _view] != nil && ![[_toolbar _view] isHidden]) {
        result.size.height += [[_toolbar _view] frame].size.height;
    }

    return result;
}

- (NSRect) contentRectForFrameRect: (NSRect) frameRect {
    return contentRectInFrame(self, frameRect);
}

// Borderless windows are left where they are; titled ones are kept inside
// the visible frame of the screen. A window taller than the visible frame
// keeps its top edge (and with it the title bar) on the screen.
- (NSRect) constrainFrameRect: (NSRect) rect toScreen: (NSScreen *) screen {
    if (!(NS_EXTRA(NSWindow, self)->_styleMask & NSWindowStyleMaskTitled)) {
        return rect;
    }
    return constrainRectToScreen(rect, screen);
}

// Run when a window that was not on screen is ordered in: the frame may have
// been set to an off-screen position since the window was created, and the
// subclass-overridable -constrainFrameRect:toScreen: decides what to do.
// Windows that are already visible are not moved again.
- (void) _constrainFrameBeforeOrderingIn {
    NSScreen *screen = [self screen];
    if (screen == nil) {
        screen = [NSScreen mainScreen];
    }
    NSRect constrained = [self constrainFrameRect: _frame toScreen: screen];
    if (!NSEqualRects(constrained, _frame)) {
        [self setFrame: constrained display: NO];
    }
}

// -constrainFrameRect:toScreen:, without sending it to a subclass.
static NSRect constrainRectToScreen(NSRect rect, NSScreen *screen) {
    if (!screen) {
        return rect;
    }
    NSRect visRect = [screen visibleFrame];

    if (NSMaxX(rect) > NSMaxX(visRect)) {
        rect.origin.x = NSMaxX(visRect) - rect.size.width;
    }
    if (NSMinX(rect) < NSMinX(visRect)) {
        rect.origin.x = NSMinX(visRect);
    }
    if (NSMinY(rect) < NSMinY(visRect)) {
        rect.origin.y = NSMinY(visRect);
    }
    // Last, so that the top edge wins for a window taller than the screen.
    if (NSMaxY(rect) > NSMaxY(visRect)) {
        rect.origin.y = NSMaxY(visRect) - rect.size.height;
    }
    return rect;
}

- (NSWindow *) parentWindow {
    return NS_EXTRA(NSWindow, self)->_parentWindow;
}

- (NSArray *) childWindows {
    return NS_EXTRA(NSWindow, self)->_childWindows;
}

- (void) addChildWindow: (NSWindow *) child
                ordered: (NSWindowOrderingMode) ordered
{
    if (NS_EXTRA(NSWindow, self)->_childWindows == nil) {
        NS_EXTRA(NSWindow, self)->_childWindows = [NSMutableArray new];
    }

    [NS_EXTRA(NSWindow, self)->_childWindows addObject: child];
    [child setParentWindow: self];
    [child makeKeyAndOrderFront: nil];
}

- (void) removeChildWindow: (NSWindow *) child {
    [child orderOut: nil];
    [child setParentWindow: nil];
    [NS_EXTRA(NSWindow, self)->_childWindows removeObjectIdenticalTo: child];
}

- (void) _parentWindowDidClose: (NSWindow *) parent {
    [self orderOut: nil];
}

- (void) _parentWindowDidActivate: (NSWindow *) parent {
    [self orderWindow: NSWindowAbove relativeTo: [NS_EXTRA(NSWindow, self)->_parentWindow windowNumber]];
}

- (void) _parentWindowDidDeactivate: (NSWindow *) parent {
    [self orderWindow: NSWindowAbove relativeTo: [NS_EXTRA(NSWindow, self)->_parentWindow windowNumber]];
}

- (void) _parentWindowDidMiniaturize: (NSWindow *) parent {
    [self orderOut: nil];
}

- (void) _parentWindowDidChangeFrame: (NSWindow *) parent {
}

- (void) _parentWindowDidExitMove: (NSWindow *) parent {
    [self orderWindow: NSWindowAbove relativeTo: [NS_EXTRA(NSWindow, self)->_parentWindow windowNumber]];
}

- (BOOL) acceptsFirstResponder {
    return YES;
}

- (BOOL) makeFirstResponder: (NSResponder *) responder {
    if (_firstResponder == responder) {
        return YES;
    }
    if ([responder isKindOfClass: [NSControl class]] &&
        _firstResponder == [(NSControl *) responder currentEditor]) {
        return YES;
    }

    if (![_firstResponder resignFirstResponder]) {
        return NO;
    }

    _firstResponder = responder;

    if ([_firstResponder becomeFirstResponder]) {
        return YES;
    } else {
        _firstResponder = self;
        return NO;
    }
}

- (void) makeKeyWindow {
    [[self platformWindow] makeKey];

    if (NS_EXTRA(NSWindow, self)->_hasBeenOnScreen) {
        return;
    }
    NS_EXTRA(NSWindow, self)->_hasBeenOnScreen = YES;

    // Ref. http://www.cocoadev.com/index.pl?KeyViewLoopGuidelines
    // If there is an initial first responder there is a manual key view loop
    // and we don't calculate one
    if ([self initialFirstResponder] != nil) {
        [self makeFirstResponder: [self initialFirstResponder]];
    } else {
        // Otherwise calculate one and set the first responder.
        if ([self autorecalculatesKeyViewLoop]) {
            [self recalculateKeyViewLoop];
        }
        if ([self firstResponder] == self) {
            [self makeFirstResponder: [_contentView nextValidKeyView]];
        }
    }
}

- (void) makeMainWindow {
    [self becomeMainWindow];
}

- (void) becomeKeyWindow {
    // The platform should always be told to become key when we want to become
    // key.
    [self makeKeyWindow];

    // If we don't return early we may resign ourselves.
    if ([self isKeyWindow]) {
        return;
    }

    // Become key window before the previous key window resigns so that the new
    // key window is valid before NSWindowDidResignKeyNotification is sent.
    NSWindow *keyWindow = [NSApp keyWindow];
    [NSApp _setKeyWindow: self];
    [keyWindow resignKeyWindow];

    if (_firstResponder != self && [_firstResponder respondsToSelector: _cmd])
        [_firstResponder performSelector: _cmd];

    [self postNotificationName: NSWindowDidBecomeKeyNotification];
}

- (void) resignKeyWindow {
    if (_firstResponder != self && [_firstResponder respondsToSelector: _cmd])
        [_firstResponder performSelector: _cmd];

    [self postNotificationName: NSWindowDidResignKeyNotification];
}

- (void) becomeMainWindow {
    if ([self isMainWindow]) {
        return;
    }

    NSWindow *mainWindow = [NSApp mainWindow];
    [[self platformWindow] makeMain];
    [NSApp _setMainWindow: self];
    [mainWindow resignMainWindow];

    [self postNotificationName: NSWindowDidBecomeMainNotification];
}

- (void) resignMainWindow {
    [self postNotificationName: NSWindowDidResignMainNotification];
}

- (NSTimeInterval) animationResizeTime: (NSRect) frame {
    return 0.20;
}

- (void) selectNextKeyView: sender {
    if ([_firstResponder isKindOfClass: [NSView class]]) {
        NSView *view = (NSView *) _firstResponder;

        [self selectKeyViewFollowingView: view];
    }
}

- (void) selectPreviousKeyView: sender {
    if ([_firstResponder isKindOfClass: [NSView class]]) {
        NSView *view = (NSView *) _firstResponder;

        [self selectKeyViewPrecedingView: view];
    }
}

- (void) selectKeyViewFollowingView: (NSView *) view {
    NSView *next = [view nextValidKeyView];
    [self makeFirstResponder: next];
}

- (void) selectKeyViewPrecedingView: (NSView *) view {
    NSView *next = [view previousValidKeyView];
    [self makeFirstResponder: next];
}

- (void) recalculateKeyViewLoopIfNeeded {
    // _needsKeyViewLoop = NO;
    NSArray<_NSKeyViewPosition *> *sorted =
            [_NSKeyViewPosition sortedKeyViewPositionsWithView: _contentView];
    NSUInteger count = [sorted count];

    for (NSUInteger i = 0; i < count; i++) {
        _NSKeyViewPosition *position = sorted[i];
        if (i + 1 < count) {
            [[position view] setNextKeyView: [sorted[i + 1] view]];
        } else {
            [[position view] setNextKeyView: [sorted[0] view]];
        }
    }
}

- (void) recalculateKeyViewLoop {
    // _needsKeyViewLoop = YES;
    // This should be deferred.
    [self recalculateKeyViewLoopIfNeeded];
}

// Key view selection is not tracked, so it is always direct.
- (NSSelectionDirection) keyViewSelectionDirection {
    return NSDirectSelection;
}

- (void) disableKeyEquivalentForDefaultButtonCell {
    NS_EXTRA(NSWindow, self)->_defaultButtonCellKeyEquivalentDisabled = YES;
}

- (void) enableKeyEquivalentForDefaultButtonCell {
    NS_EXTRA(NSWindow, self)->_defaultButtonCellKeyEquivalentDisabled = NO;
}

- (NSText *) fieldEditor: (BOOL) create forObject: (id) object {
    NSTextView *newFieldEditor = nil;
    if ([_delegate respondsToSelector: @selector(windowWillReturnFieldEditor:
                                                                    toObject:)])
        newFieldEditor = [_delegate windowWillReturnFieldEditor: self
                                                       toObject: object];

    if (create && newFieldEditor == nil && _sharedFieldEditor == nil) {
        newFieldEditor = _sharedFieldEditor = [[NSTextView alloc] init];
        // Cells draw their titles without padding; keep editing aligned.
        [[_sharedFieldEditor textContainer] setLineFragmentPadding: 0];
    }

    if (newFieldEditor)
        NS_EXTRA(NSWindow, self)->_currentFieldEditor = newFieldEditor;
    else
        NS_EXTRA(NSWindow, self)->_currentFieldEditor = _sharedFieldEditor;

    if (NS_EXTRA(NSWindow, self)->_currentFieldEditor) {
        [NS_EXTRA(NSWindow, self)->_currentFieldEditor setHorizontallyResizable: NO];
        [NS_EXTRA(NSWindow, self)->_currentFieldEditor setVerticallyResizable: NO];
        [NS_EXTRA(NSWindow, self)->_currentFieldEditor setFieldEditor: YES];
        [NS_EXTRA(NSWindow, self)->_currentFieldEditor
                setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
    }

    return NS_EXTRA(NSWindow, self)->_currentFieldEditor;
}

- (void) endEditingFor: (id) object {
    if (NS_EXTRA(NSWindow, self)->_currentFieldEditor) {
        if ((NSResponder *) NS_EXTRA(NSWindow, self)->_currentFieldEditor == _firstResponder) {
            _firstResponder = object;
            [NS_EXTRA(NSWindow, self)->_currentFieldEditor resignFirstResponder];
        }
        [NS_EXTRA(NSWindow, self)->_currentFieldEditor setDelegate: nil];
        [NS_EXTRA(NSWindow, self)->_currentFieldEditor removeFromSuperview];
        [NS_EXTRA(NSWindow, self)->_currentFieldEditor setString: @""];
        NS_EXTRA(NSWindow, self)->_currentFieldEditor = nil;
    }
}

- (void) disableScreenUpdatesUntilFlush {
    NSUnimplementedMethod();
}

- (void) useOptimizedDrawing: (BOOL) flag {
    // Do nothing.
}

- (BOOL) viewsNeedDisplay {
    return NS_EXTRA(NSWindow, self)->_viewsNeedDisplay;
}

- (void) setViewsNeedDisplay: (BOOL) viewsNeedDisplay {
    if (viewsNeedDisplay == NS_EXTRA(NSWindow, self)->_viewsNeedDisplay) {
        // the desired state is already the active one; do nothing
        return;
    } else if (!viewsNeedDisplay && NS_EXTRA(NSWindow, self)->_viewsNeedDisplay) {
        // if we're told we don't need to display, set that
        // Apple's AppKit leaves the redraw queued, so lets do the same and not cancel the performer
        NS_EXTRA(NSWindow, self)->_viewsNeedDisplay = viewsNeedDisplay;
        return;
    }
    // otherwise, `viewsNeedDisplay && !_viewsNeedDisplay`, so let's set up a performer to re-draw us

    // NSApplication does a _displayAllWindowsIfNeeded before every event, but
    // there are some things which won't generate an event such as
    // performOnMainThread, so we do the callout here too. There is probably a
    // better way to do this.

    // Be sure we don't accumulate unneeded perform operations.
    NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
    [runLoop cancelPerformSelector: @selector(_displayAllWindowsIfNeeded)
                            target: NSApp
                          argument: nil];
    [runLoop performSelector: @selector(_displayAllWindowsIfNeeded)
                      target: NSApp
                    argument: nil
                       order: 0
                       modes: @[
                           NSDefaultRunLoopMode, NSModalPanelRunLoopMode,
                           NSEventTrackingRunLoopMode
                       ]];
    NS_EXTRA(NSWindow, self)->_viewsNeedDisplay = viewsNeedDisplay;
}

- (void) disableFlushWindow {
    NS_EXTRA(NSWindow, self)->_flushDisabled++;
    [_platformWindow disableFlushWindow];
}

- (void) enableFlushWindow {
    NS_EXTRA(NSWindow, self)->_flushDisabled--;
    [_platformWindow enableFlushWindow];
}

- (void) flushWindow {
    if (NS_EXTRA(NSWindow, self)->_flushDisabled > 0) {
        NS_EXTRA(NSWindow, self)->_flushNeeded = YES;
        return;
    }

    NS_EXTRA(NSWindow, self)->_flushNeeded = NO;
    BOOL doFlush = YES;

    if ([self isOpaque] && [_contentView isKindOfClass: [NSOpenGLView class]] &&
        [_contentView isOpaque]) {
        doFlush = NO;
    }
    if (doFlush) {
        [[self platformWindow] flushBuffer];
    }
}

- (void) flushWindowIfNeeded {
    if (NS_EXTRA(NSWindow, self)->_flushNeeded) {
        [self flushWindow];
    }
}

- (void) displayIfNeeded {
    if (![self isVisible] || [self isMiniaturized] ||
        ![self viewsNeedDisplay]) {
        return;
    }

    @autoreleasepool {
        if ([NSGraphicsContext quartzDebuggingIsEnabled]) {
            // Show all the views getting redrawn.
            [NSGraphicsContext setQuartzDebugMode: YES];
            [self disableFlushWindow];
            [_backgroundView displayIfNeeded];
            [self enableFlushWindow];
            [self flushWindowIfNeeded];
        }

        [NSGraphicsContext setQuartzDebugMode: NO];
        [self disableFlushWindow];
        [_backgroundView displayIfNeeded];
        [self enableFlushWindow];
        [self flushWindowIfNeeded];
        [self setViewsNeedDisplay: NO];
    }
}

- (void) updateConstraintsIfNeeded {
    [_contentView updateConstraintsForSubtreeIfNeeded];
}

/* Resizes the window to the size its content view's constraints ask for. The window resists
   resizing at NSLayoutPriorityWindowSizeStayPut, so constraints of a higher priority (including
   required ones) win, even over the minimum and maximum content sizes. The top left corner stays
   where it is. */
- (void) _fitContentSizeToConstraints {
    if (_contentView == nil || [self isMiniaturized])
        return;

    [self updateConstraintsIfNeeded];

    NSRect content = [self contentRectForFrameRect: _frame];
    NSSize size = DarlingLayoutPreferredSize(_contentView, content.size);

    if (size.width < 0 || size.height < 0 || NSEqualSizes(size, content.size))
        return;

    content.size = size;
    NSRect frame = [self frameRectForContentRect: content];
    frame.origin.y = NSMaxY(_frame) - NSHeight(frame);
    [self setFrame: frame display: YES];
}

- (void) layoutIfNeeded {
    [self _fitContentSizeToConstraints];
    [self updateConstraintsIfNeeded];
    [_contentView layoutSubtreeIfNeeded];
}

- (void) display {
    // FIXME: See Issue #405, display when the window is not visible causes
    // layout problems (maybe the underlying Win32 window doesn't exist and
    // we're not getting resize feedback messages?), so there is a problem. The
    // fix is to not display when we aren't visible, displayIfNeeded does this
    // already so it makes sense. The underlying problem should be fixed too
    // though.
    if (![self isVisible]) {
        // If we were asked to display and weren't visible, mark it for display
        [_backgroundView setNeedsDisplay: YES];
        return;
    }
    @autoreleasepool {
        if ([NSGraphicsContext quartzDebuggingIsEnabled]) {
            // Show all the views getting redrawn.
            [NSGraphicsContext setQuartzDebugMode: YES];
            [self disableFlushWindow];
            [_backgroundView display];
            [self enableFlushWindow];
            [self flushWindowIfNeeded];
        }

        [NSGraphicsContext setQuartzDebugMode: NO];
        [self disableFlushWindow];
        [_backgroundView display];
        [self enableFlushWindow];
        [self flushWindowIfNeeded];
    }
}

- (void) invalidateShadow {
    // Do nothing.
}

- (void) cacheImageInRect: (NSRect) rect {
    NSUnimplementedMethod();
}

- (void) restoreCachedImage {
    NSUnimplementedMethod();
}

- (void) discardCachedImage {
    NSUnimplementedMethod();
}

- (BOOL) areCursorRectsEnabled {
    return (NS_EXTRA(NSWindow, self)->_cursorRectsDisabled <= 0) ? YES : NO;
}

- (void) disableCursorRects {
    NS_EXTRA(NSWindow, self)->_cursorRectsDisabled++;
    if (NS_EXTRA(NSWindow, self)->_cursorRectsDisabled == 1)
        [self _invalidateTrackingAreas];
}

- (void) enableCursorRects {
    NS_EXTRA(NSWindow, self)->_cursorRectsDisabled--;
    if (NS_EXTRA(NSWindow, self)->_cursorRectsDisabled == 0)
        [self _invalidateTrackingAreas];
}

- (void) discardCursorRects {
    [[self _backgroundView] discardCursorRects];
    [self _invalidateTrackingAreas];
}

// Apple docs say: "sends -resetCursorRects to every NSView object in the [...]
// hierarchy", and it means that. No [[self _backgroundView] resetCursorRects]
// and trusting in recursion through the view hierarchy.
- (void) _resetCursorRectsInView: (NSView *) view {
    for (NSView *subview in [view subviews]) {
        [self _resetCursorRectsInView: subview];
    }
    [view resetCursorRects];
}

- (void) resetCursorRects {
    [self discardCursorRects];
    [self _resetCursorRectsInView: _backgroundView];
    [self _invalidateTrackingAreas];
}

- (void) invalidateCursorRectsForView: (NSView *) view {
    [view discardCursorRects];
    [self _resetCursorRectsInView: view];
    [self _invalidateTrackingAreas];
}

// This shall be received in case of
// - -[NSWindows areCursorRectsEnabled] changes
// - -[NSApplication isActive] changes
// - the number or TrackingAreas has changed
// - a property of one of the TrackingAreas has changed
// - a frame of this window or one the relevant views has changed.
- (void) _invalidateTrackingAreas {
    // Rebuild it on demand.
    [NS_EXTRA(NSWindow, self)->_trackingAreas release];
    NS_EXTRA(NSWindow, self)->_trackingAreas = nil;
}

// Never send this directly, except you actually need _trackingAreas.
- (void) _resetTrackingAreas {
    if (NS_EXTRA(NSWindow, self)->_trackingAreas != nil) {
        return;
    }
    NSInteger count;
    BOOL toolTipsAllowed =
            [NSApp isActive] || [self allowsToolTipsWhenApplicationIsInactive];

    NSMutableArray *collectedAreas = [[NSMutableArray alloc] init];
    [[self _backgroundView] _collectTrackingAreasForWindowInto: collectedAreas];
    NS_EXTRA(NSWindow, self)->_trackingAreas = collectedAreas;

    count = [NS_EXTRA(NSWindow, self)->_trackingAreas count];
    while (--count >= 0) {
        NSTrackingArea *area = NS_EXTRA(NSWindow, self)->_trackingAreas[count];

        if ((NS_EXTRA(NSWindow, self)->_cursorRectsDisabled > 0 &&
             [area options] & NSTrackingCursorUpdate) ||
            ([area _isToolTip] && !toolTipsAllowed)) {
            [NS_EXTRA(NSWindow, self)->_trackingAreas removeObjectAtIndex: count];
        }
    }

    if (!toolTipsAllowed) {
        // We have to do this here as Area handling won't even recignize
        // ToolTips now.
        NSToolTipWindow *toolTipWindow = [NSToolTipWindow sharedToolTipWindow];

        [NSObject
                cancelPreviousPerformRequestsWithTarget: toolTipWindow
                                               selector: @selector(orderFront:)
                                                 object: nil];
        [toolTipWindow orderOut: nil];
    }
}

- (void) close {
    // A window that is already closed is not closed again, so that
    // NSWindowWillCloseNotification is posted once per close cycle and the
    // window is not released twice.
    if (NS_EXTRA(NSWindow, self)->_isClosed)
        return;
    NS_EXTRA(NSWindow, self)->_isClosed = YES;
    /*
      I am not sure if orderOut comes before the notification or not. If we
      order out after the notification, Windows sends the window a bunch of
      messages from the HIDE, and we end up potentially drawing, updating a
      window when it is not supposed to be, especially if the delegate has
      already released objects that will be messaged during a draw/update.

      We either orderOut: before the notification, or have an _isClosed flag
      which causes some platformWindow messages to be ignored. Ones that would
      crash the app.
    */
    [self orderOut: nil];

    [NS_EXTRA(NSWindow, self)->_childWindows makeObjectsPerformSelector: @selector(_parentWindowDidClose:)
                                   withObject: self];
    [NS_EXTRA(NSWindow, self)->_drawers makeObjectsPerformSelector: @selector(parentWindowDidClose:)
                              withObject: self];

    [self postNotificationName: NSWindowWillCloseNotification];

    if (NS_EXTRA(NSWindow, self)->_releaseWhenClosed)
        [self autorelease];
}

- (void) center {
    NSScreen *screen = [self screen];
    if (screen == nil)
        screen = [NSScreen screens][0];

    NSRect screenFrame = [screen frame];

    NSRect frame = [self frame];
    frame.origin.x = floor(screenFrame.origin.x + screenFrame.size.width / 2 -
                           frame.size.width / 2);
    frame.origin.y = floor(screenFrame.origin.y + screenFrame.size.height / 2 -
                           frame.size.height / 2);

    [self setFrame: frame display: YES];
}

- (void) orderWindow: (NSWindowOrderingMode) place
          relativeTo: (NSInteger) relativeTo
{
    BOOL wasVisible = NS_EXTRA(NSWindow, self)->_isVisible;

    // The move notifications are sent under unknown conditions around
    // orderFront: in the Apple AppKit, we do them all the time here until it's
    // figured out. I suspect it is a side effect of off-screen windows being at
    // off-screen coordinates (as opposed to just being hidden).

    [self postNotificationName: NSWindowWillMoveNotification];

    switch (place) {
    case NSWindowAbove:
        NS_EXTRA(NSWindow, self)->_isClosed = NO;
        if (!wasVisible && ![self isMiniaturized]) {
            [self _constrainFrameBeforeOrderingIn];
        }
        [self update];
        NS_EXTRA(NSWindow, self)->_isVisible = YES;
        [[self platformWindow] placeAboveWindow: relativeTo];
        /* In some instances when a COMMAND is issued from a menu item to bring
           a window front, the window is not displayed right (black,
           incomplete). This may be the right place to do this, maybe not,
           further investigation is required.
        */
        [self displayIfNeeded];
        // This is here since it would seem that doing this any earlier will not
        // work.
        if (![self isKindOfClass: [NSPanel class]] &&
            ![self isExcludedFromWindowsMenu]) {
            [NSApp changeWindowsItem: self title: NS_EXTRA(NSWindow, self)->_title filename: NO];
        }
        break;

    case NSWindowBelow:
        NS_EXTRA(NSWindow, self)->_isClosed = NO;
        if (!wasVisible && ![self isMiniaturized]) {
            [self _constrainFrameBeforeOrderingIn];
        }
        [self update];
        NS_EXTRA(NSWindow, self)->_isVisible = YES;
        [[self platformWindow] placeBelowWindow: relativeTo];
        /* In some instances when a COMMAND is issued from a menu item to bring
           a window front, the window is not displayed right (black,
           incomplete). This may be the right place to do this, maybe not,
           further investigation is required.
        */
        [self displayIfNeeded];
        // This is here since it would seem that doing this any earlier will not
        // work.
        if (![self isKindOfClass: [NSPanel class]] &&
            ![self isExcludedFromWindowsMenu]) {
            [NSApp changeWindowsItem: self title: NS_EXTRA(NSWindow, self)->_title filename: NO];
        }
        break;

    case NSWindowOut:
        // Note: _isClosed is deliberately NOT reset here because -[NSWindow close]
        // calls -[self orderOut: nil] with _isClosed = YES already set.
        // Resetting here would immediately defeat double-close protection.
        NS_EXTRA(NSWindow, self)->_isVisible = NO;
        [[self platformWindow] hideWindow];
        if (![self isKindOfClass: [NSPanel class]]) {
            [NSApp removeWindowsItem: self];
        }
        if ([self isKeyWindow])
            [self _passKeyToFrontmostWindow];
        break;
    }

    [self _postOcclusionChangeIfVisibleWas: wasVisible];
    [self postNotificationName: NSWindowDidMoveNotification];
}

// Like macOS, ordering out the key window makes the frontmost remaining
// window that can become key the key window; without one, none is key.
- (void) _passKeyToFrontmostWindow {
    for (NSWindow *window in [NSApp orderedWindows]) {
        if (window != self && [window isVisible] &&
            [window canBecomeKeyWindow]) {
            [window becomeKeyWindow];
            return;
        }
    }
    [NSApp _setKeyWindow: nil];
    [self resignKeyWindow];
}

- (void) orderFrontRegardless {
    // XXX: this should maybe do something extra?
    [self orderFront: nil];
}

- (NSPoint) mouseLocationOutsideOfEventStream {
    return [_platformWindow mouseLocationOutsideOfEventStream];
}

- (NSEvent *) currentEvent {
    return [NSApp currentEvent];
}

- (NSEvent *) nextEventMatchingMask: (NSUInteger) mask {
    return [self nextEventMatchingMask: mask
                             untilDate: [NSDate distantFuture]
                                inMode: NSEventTrackingRunLoopMode
                               dequeue: YES];
}

- (NSEvent *) nextEventMatchingMask: (NSUInteger) mask
                          untilDate: (NSDate *) untilDate
                             inMode: (NSRunLoopMode) mode
                            dequeue: (BOOL) dequeue
{
    // This should get migrated down into event queue.
    [[self platformWindow] captureEvents];

    NSEvent *event;
    do {
        event = [NSApp nextEventMatchingMask: mask
                                   untilDate: untilDate
                                      inMode: mode
                                     dequeue: dequeue];
    } while (!(mask & NSEventMaskFromType([event type])));

    return event;
}

- (void) discardEventsMatchingMask: (NSUInteger) mask
                       beforeEvent: (NSEvent *) event
{
    NSUnimplementedMethod();
}

// Each mouse button remembers the view that received its mouse-down; drags and
// the mouse-up of that button go to that view whatever the other buttons do in
// between. A view that has left the window by then receives nothing more.
- (NSInteger) _otherButtonOfEvent: (NSEvent *) event {
    NSInteger button = [event buttonNumber];

    return (button < 2) ? 2 : button;
}

- (void) _setMouseDownView: (NSView *) view forButton: (NSInteger) button {
    NSNumber *key = @(button);

    if (view == nil) {
        [NS_EXTRA(NSWindow, self)->_mouseDownViews removeObjectForKey: key];
        return;
    }
    if (NS_EXTRA(NSWindow, self)->_mouseDownViews == nil) {
        NS_EXTRA(NSWindow, self)->_mouseDownViews = [[NSMutableDictionary alloc] init];
    }
    NS_EXTRA(NSWindow, self)->_mouseDownViews[key] = view;
}

- (NSView *) _mouseDownViewForButton: (NSInteger) button {
    // Keep the view alive for the caller even if the entry is removed next.
    NSView *view = [[NS_EXTRA(NSWindow, self)->_mouseDownViews[@(button)] retain] autorelease];

    return ([view window] == self) ? view : nil;
}

- (NSView *) _takeMouseDownViewForButton: (NSInteger) button {
    NSView *view = [self _mouseDownViewForButton: button];

    [NS_EXTRA(NSWindow, self)->_mouseDownViews removeObjectForKey: @(button)];
    return view;
}

// The recognizers of the view an event goes to and of that view's ancestors,
// innermost first. Releases and drags go to the view that received the press
// of the same button.
- (NSArray *) _gestureRecognizersForEvent: (NSEvent *) event {
    NSView *target;

    switch ([event type]) {
    case NSEventTypeLeftMouseDown:
    case NSEventTypeRightMouseDown:
    case NSEventTypeOtherMouseDown:
    case NSEventTypeMagnify:
    case NSEventTypeRotate:
        target = [_backgroundView hitTest: [event locationInWindow]];
        break;
    case NSEventTypeLeftMouseUp:
    case NSEventTypeLeftMouseDragged:
        target = [self _mouseDownViewForButton: 0];
        break;
    case NSEventTypeRightMouseUp:
    case NSEventTypeRightMouseDragged:
        target = [self _mouseDownViewForButton: 1];
        break;
    case NSEventTypeOtherMouseUp:
    case NSEventTypeOtherMouseDragged:
        target = [self _mouseDownViewForButton: [self _otherButtonOfEvent: event]];
        break;
    default:
        return nil;
    }

    NSMutableArray *recognizers = [NSMutableArray array];
    for (NSView *view = target; view != nil; view = [view superview]) {
        [recognizers addObjectsFromArray: [view gestureRecognizers]];
    }
    return recognizers;
}

- (void) sendEvent: (NSEvent *) event {
    // Some events can cause our window to be destroyed
    // So make sure self lives at least through this current run loop...
    [[self retain] autorelease];

    if (NS_EXTRA(NSWindow, self)->_sheetContext != nil) {
        NSView *view = [_backgroundView hitTest: [event locationInWindow]];

        // Pretend that the event goes to the toolbar's view, no matter where it
        // really is. Could cause problems if custom views wanted to do
        // something while the palette is running; however they shouldn't be
        // doing that!
        if ([[self toolbar] customizationPaletteIsRunning] &&
            (view == [[self toolbar] _view] ||
             [[[[self toolbar] _view] subviews] containsObject: view])) {
            switch ([event type]) {
            case NSLeftMouseDown:
                [[[self toolbar] _view] mouseDown: event];
                break;
            case NSLeftMouseUp:
                [[[self toolbar] _view] mouseUp: event];
                break;
            case NSLeftMouseDragged:
                [[[self toolbar] _view] mouseDragged: event];
                break;
            default:
                break;
            }
            return;
        } else if ([event type] == NSPlatformSpecific) {
            // [self _setSheetOriginAndFront];
            [_platformWindow
                    sendEvent: [(NSEvent_CoreGraphics *)
                                               event coreGraphicsEvent]];
            return;
        }
    }

    NSArray *recognizers = [self _gestureRecognizersForEvent: event];
    for (NSGestureRecognizer *recognizer in recognizers)
        [recognizer _receiveEvent: event];

    BOOL shouldValidateToolbarItems = YES;
    // OK let's see if anyone else wants it.
    switch ([event type]) {

    case NSLeftMouseDown: {
        NSView *view = [_backgroundView hitTest: [event locationInWindow]];

        if ([view acceptsFirstResponder]) {
            if ([view needsPanelToBecomeKey]) {
                [self makeFirstResponder: view];
            }
        }

        // Event goes to view, not first responder.
        [self _setMouseDownView: view forButton: 0];
        [view mouseDown: event];
        break;
    }

    case NSLeftMouseUp:
        [[self _takeMouseDownViewForButton: 0] mouseUp: event];
        break;

    case NSRightMouseDown: {
        NSView *view = [_backgroundView hitTest: [event locationInWindow]];

        [self _setMouseDownView: view forButton: 1];
        [view rightMouseDown: event];
        break;
    }

    case NSRightMouseUp:
        [[self _takeMouseDownViewForButton: 1] rightMouseUp: event];
        break;

    case NSOtherMouseDown: {
        NSView *view = [_backgroundView hitTest: [event locationInWindow]];

        [self _setMouseDownView: view forButton: [self _otherButtonOfEvent: event]];
        [view otherMouseDown: event];
        break;
    }

    case NSOtherMouseUp:
        [[self _takeMouseDownViewForButton: [self _otherButtonOfEvent: event]]
                otherMouseUp: event];
        break;

    case NSMouseMoved: {
        NSView *hit = [_backgroundView hitTest: [event locationInWindow]];

        if (hit == nil) {
            [self mouseMoved: event];
        } else {
            [hit mouseMoved: event];
        }
        break;
    }

    case NSLeftMouseDragged:
        [[self _mouseDownViewForButton: 0] mouseDragged: event];
        break;

    case NSRightMouseDragged:
        [[self _mouseDownViewForButton: 1] rightMouseDragged: event];
        break;

    case NSOtherMouseDragged:
        [[self _mouseDownViewForButton: [self _otherButtonOfEvent: event]]
                otherMouseDragged: event];
        break;

    case NSMouseEntered:
        [[_backgroundView hitTest: [event locationInWindow]]
                mouseEntered: event];
        break;

    case NSMouseExited:
        [[_backgroundView hitTest: [event locationInWindow]]
                mouseExited: event];
        break;

    case NSKeyDown:
        [_firstResponder keyDown: event];
        break;

    case NSKeyUp:
        [_firstResponder keyUp: event];
        break;

    case NSFlagsChanged:
        [_firstResponder flagsChanged: event];
        break;

    case NSPlatformSpecific:
        [_platformWindow
                sendEvent: [(NSEvent_CoreGraphics *) event coreGraphicsEvent]];
        break;

    case NSScrollWheel:
        [[_backgroundView hitTest: [event locationInWindow]]
                scrollWheel: event];
        break;

    case NSEventTypeMagnify:
        [[_backgroundView hitTest: [event locationInWindow]]
                magnifyWithEvent: event];
        break;

    case NSEventTypeRotate:
        [[_backgroundView hitTest: [event locationInWindow]]
                rotateWithEvent: event];
        break;

    case NSAppKitDefined:
        // Nothing special to do.
        break;

    default:
        shouldValidateToolbarItems = NO;
        NSUnimplementedMethod();
        break;
    }
    for (NSGestureRecognizer *recognizer in recognizers)
        [recognizer _resetIfFinished];

    if (shouldValidateToolbarItems && [self toolbar]) {
        [NSObject cancelPreviousPerformRequestsWithTarget: [self toolbar]
                                                 selector: @selector
                                                 (validateVisibleItems)
                                                   object: nil];
        [[self toolbar] performSelector: @selector(validateVisibleItems)
                             withObject: nil
                             afterDelay: .5];
    }
}

- (void) postEvent: (NSEvent *) event atStart: (BOOL) atStart {
    [NSApp postEvent: event atStart: atStart];
}

- (BOOL) tryToPerform: (SEL) selector with: (id) object {
    if ([super tryToPerform: selector with: object]) {
        return YES;
    }

    if ([_delegate respondsToSelector: selector]) {
        [_delegate performSelector: selector withObject: object];
        return YES;
    }
    return NO;
}

- (NSPoint) cascadeTopLeftFromPoint: (NSPoint) topLeftPoint {
    BOOL reposition = NO;
    NSSize screenSize = [[self screen] frame].size;
    NSRect frame = [self frame];

    if (frame.origin.x < 0.0 ||
        screenSize.width <= frame.origin.x + frame.size.width) {
        frame.origin.x = 2.0;
        reposition = YES;
    }

    if (frame.origin.y < 0.0 ||
        screenSize.height <= frame.origin.y + frame.size.height) {
        frame.origin.y = 2.0;
        reposition = YES;
    }

    if (topLeftPoint.x != 0.0 &&
        topLeftPoint.x + frame.size.width + 20.0 < screenSize.width) {
        topLeftPoint.x += 18.0;
        frame.origin.x = topLeftPoint.x;
        reposition = YES;
    } else {
        topLeftPoint.x = frame.origin.x;
    }

    if (topLeftPoint.y != 0.0 &&
        topLeftPoint.y - frame.size.height - 23.0 >= 0.0) {
        topLeftPoint.y -= 21.0;
        frame.origin.y = topLeftPoint.y - frame.size.height;
        reposition = YES;
    } else {
        topLeftPoint.y = frame.origin.y + frame.size.height;
    }

    if (reposition) {
        [self setFrame: frame display: YES];
    }

    return topLeftPoint;
}

- (NSData *) dataWithEPSInsideRect: (NSRect) rect {
    return [_backgroundView dataWithEPSInsideRect: rect];
}

- (NSData *) dataWithPDFInsideRect: (NSRect) rect {
    return [_backgroundView dataWithPDFInsideRect: rect];
}

- (void) registerForDraggedTypes: (NSArray *) types {
    NS_EXTRA(NSWindow, self)->_draggedTypes = [types copy];
}

- (void) unregisterDraggedTypes {
    [NS_EXTRA(NSWindow, self)->_draggedTypes release];
    NS_EXTRA(NSWindow, self)->_draggedTypes = nil;
}

// The registered drag destination under screenPoint in this window, if any.
- (NSView *) _inProcessDragDestinationAt: (NSPoint) screenPoint
                                   types: (NSArray *) types
{
    NSView *view = [_backgroundView
            hitTest: [self convertScreenToBase: screenPoint]];

    while (view != nil &&
           [[view registeredDraggedTypes] firstObjectCommonWithArray: types] ==
                   nil)
        view = [view superview];
    return view;
}

// The visible window under screenPoint, preferring this one.
- (NSWindow *) _inProcessDragWindowAt: (NSPoint) screenPoint
                            excluding: (NSWindow *) excluded
{
    if (NSPointInRect(screenPoint, [self frame]))
        return self;

    for (NSWindow *window in [NSApp orderedWindows]) {
        if (window != excluded && [window isVisible] &&
            NSPointInRect(screenPoint, [window frame]))
            return window;
    }
    return nil;
}

// A drag for displays without a dragging manager. It covers drags between
// this application's own windows; nothing reaches other applications. As
// with a system drag, it returns once the drag is over, and the source is
// always told how it ended.
- (void) _dragImageInProcess: (NSImage *) image
                          at: (NSPoint) imageLocation
                       event: (NSEvent *) event
                  pasteboard: (NSPasteboard *) pasteboard
                      source: (id) source
{
    NSWindowLocalDraggingInfo *info = [[NSWindowLocalDraggingInfo alloc] init];
    info->_pasteboard = pasteboard;
    info->_image = image;
    info->_source = source;
    info->_sourceMask = NSDragOperationEvery;
    if ([source respondsToSelector: @selector(draggingSourceOperationMaskForLocal:)])
        info->_sourceMask = [source draggingSourceOperationMaskForLocal: YES];

    NSPoint screenPoint;
    if ([event window] != nil)
        screenPoint = [[event window] convertBaseToScreen: [event locationInWindow]];
    else
        screenPoint = [self convertBaseToScreen: [self mouseLocationOutsideOfEventStream]];

    // The image keeps its offset from the pointer.
    NSWindowDragImageWindow *imageWindow = nil;
    NSPoint imageOffset = NSZeroPoint;
    NSSize imageSize = [image size];
    NSPoint imageOrigin = [self convertBaseToScreen: imageLocation];
    if (imageSize.width >= 1 && imageSize.height >= 1) {
        imageOffset = NSMakePoint(screenPoint.x - imageOrigin.x,
                                  screenPoint.y - imageOrigin.y);
        imageWindow = [[NSWindowDragImageWindow alloc]
                initWithContentRect: NSMakeRect(imageOrigin.x, imageOrigin.y,
                                                imageSize.width, imageSize.height)
                          styleMask: NSBorderlessWindowMask
                            backing: NSBackingStoreBuffered
                              defer: NO];
        [imageWindow setReleasedWhenClosed: NO];
        [imageWindow setIgnoresMouseEvents: YES];
        [imageWindow setLevel: NSPopUpMenuWindowLevel];
        [imageWindow setHasShadow: NO];
        NSImageView *imageView = [[NSImageView alloc]
                initWithFrame: NSMakeRect(0, 0, imageSize.width, imageSize.height)];
        [imageView setImage: image];
        [imageView setImageScaling: NSImageScaleNone];
        [imageWindow setContentView: imageView];
        [imageView release];
        [imageWindow orderFront: nil];
    }

    if ([source respondsToSelector: @selector(draggedImage:beganAt:)])
        [source draggedImage: image beganAt: imageOrigin];

    NSArray *types = [pasteboard types];
    id destination = nil;
    NSDragOperation operation = NSDragOperationNone;
    BOOL dropped = NO;
    BOOL moved = YES;

    for (;;) {
        if (moved) {
            NSWindow *window = [self _inProcessDragWindowAt: screenPoint
                                                  excluding: imageWindow];
            info->_screenPoint = screenPoint;
            if (info->_destinationWindow != window) {
                [info->_destinationWindow release];
                info->_destinationWindow = [window retain];
            }
            NSView *view = [window _inProcessDragDestinationAt: screenPoint
                                                         types: types];

            if (view != destination) {
                if ([destination respondsToSelector: @selector(draggingExited:)])
                    [destination draggingExited: info];
                [destination release];
                destination = [view retain];
                operation = NSDragOperationNone;
                if ([destination respondsToSelector: @selector(draggingEntered:)])
                    operation = [destination draggingEntered: info];
            } else if ([destination respondsToSelector: @selector(draggingUpdated:)]) {
                operation = [destination draggingUpdated: info];
            }
            [imageWindow setFrameOrigin: NSMakePoint(screenPoint.x - imageOffset.x,
                                                     screenPoint.y - imageOffset.y)];
            if ([source respondsToSelector: @selector(draggedImage:movedTo:)])
                [source draggedImage: image movedTo: screenPoint];
            runPendingSourcesDuringDrag(0.008);
        }
        if (dropped)
            break;

        // A short timeout: a button released before the loop started never
        // arrives as an event, so the button state is checked as well.
        NSEvent *next = [NSApp
                nextEventMatchingMask: NSLeftMouseUpMask | NSLeftMouseDraggedMask |
                                       NSMouseMovedMask | NSKeyDownMask
                            untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]
                               inMode: NSEventTrackingRunLoopMode
                              dequeue: YES];
        moved = NO;
        if (next == nil) {
            if (([NSEvent pressedMouseButtons] & 1) == 0)
                dropped = moved = YES;
            continue;
        }
        if ([next type] == NSKeyDown) {
            // Escape cancels the drag.
            if ([[next characters] isEqual: @"\033"])
                break;
            continue;
        }
        if ([next window] != nil)
            screenPoint = [[next window] convertBaseToScreen: [next locationInWindow]];
        else
            screenPoint = [next locationInWindow];
        moved = YES;
        if ([next type] == NSLeftMouseUp)
            dropped = YES;
    }

    [imageWindow orderOut: nil];
    [imageWindow release];

    BOOL performed = NO;
    if (dropped && destination != nil && operation != NSDragOperationNone) {
        performed = YES;
        if ([destination respondsToSelector: @selector(prepareForDragOperation:)])
            performed = [destination prepareForDragOperation: info];
        if (performed)
            performed = [destination respondsToSelector: @selector(performDragOperation:)] &&
                        [destination performDragOperation: info];
        if (performed && [destination respondsToSelector: @selector(concludeDragOperation:)])
            [destination concludeDragOperation: info];
    } else if ([destination respondsToSelector: @selector(draggingExited:)]) {
        [destination draggingExited: info];
    }
    if (!performed)
        operation = NSDragOperationNone;
    if ([destination respondsToSelector: @selector(draggingEnded:)])
        [destination draggingEnded: info];

    if ([source respondsToSelector: @selector(draggedImage:endedAt:operation:)])
        [source draggedImage: image endedAt: screenPoint operation: operation];
    [destination release];
    [info release];
}

- (void) dragImage: (NSImage *) image
                at: (NSPoint) location
            offset: (NSSize) offset
             event: (NSEvent *) event
        pasteboard: (NSPasteboard *) pasteboard
            source: (id) source
         slideBack: (BOOL) slideBack
{
    if ([NSDraggingManager draggingManager] == nil) {
        [self _dragImageInProcess: image
                               at: location
                            event: event
                       pasteboard: pasteboard
                           source: source];
        return;
    }
    [[NSDraggingManager draggingManager] dragImage: image
                                                at: location
                                            offset: offset
                                             event: event
                                        pasteboard: pasteboard
                                            source: source
                                         slideBack: slideBack];
}

- validRequestorForSendType: (NSString *) sendType
                 returnType: (NSString *) returnType
{
    NSUnimplementedMethod();
    return nil;
}

- (void) update {
    [[self toolbar] validateVisibleItems];
    [[NSNotificationCenter defaultCenter]
            postNotificationName: NSWindowDidUpdateNotification
                          object: self];
}

- (void) makeKeyAndOrderFront: (id) sender {
    if ([self isMiniaturized]) {
        [_platformWindow deminiaturize];
    }

    // Order window before making it key, per docs and behavior/

    [self orderWindow: NSWindowAbove relativeTo: 0];

    if ([self canBecomeKeyWindow]) {
        [self makeKeyWindow];
    }
    if ([self canBecomeMainWindow]) {
        [self makeMainWindow];
    }
}

- (void) setIsVisible: (BOOL) visible {
    if (NS_EXTRA(NSWindow, self)->_isVisible == visible) {
        return;
    }
    NS_EXTRA(NSWindow, self)->_isVisible = visible;
    if (visible) {
        [[self platformWindow] showWindowWithoutActivation];
    } else {
        [[self platformWindow] hideWindow];
    }
    [self _postOcclusionChangeIfVisibleWas: !visible];
}

- (void) orderFront: (id) sender {
    [self orderWindow: NSWindowAbove relativeTo: 0];
}

- (void) orderBack: (id) sender {
    [self orderWindow: NSWindowBelow relativeTo: 0];
}

- (void) orderOut: (id) sender {
    [self orderWindow: NSWindowOut relativeTo: 0];
}

- (void) performClose: (id) sender {
    if ([_delegate respondsToSelector: @selector(windowShouldClose:)]) {
        if (![_delegate windowShouldClose: self]) {
            return;
        }
    } else if ([self respondsToSelector: @selector(windowShouldClose:)]) {
        if (![(id<NSWindowDelegate>) self windowShouldClose: self]) {
            return;
        }
    }

    NSDocument *document = [NS_EXTRA(NSWindow, self)->_windowController document];
    if (document) {
        [document shouldCloseWindowController: NS_EXTRA(NSWindow, self)->_windowController
                                     delegate: self
                          shouldCloseSelector: @selector(_document:
                                                       shouldClose:contextInfo:)
                                  contextInfo: NULL];
    } else {
        // Clicking the close button on a Window generates a performClose:, in a
        // non-modal case we just close the window. If the window is a modal
        // window, we abort the session, but do not close the window. So far it
        // looks like we should not close the window too.
        if ([NSApp modalWindow] == self) {
            [NSApp abortModal];
        } else {
            [self close];
        }
    }
}

- (void) _document: (NSDocument *) document
        shouldClose: (BOOL) shouldClose
        contextInfo: (void *) context
{
    // Callback used by performClose:
    if (shouldClose) {
        [self close];
    }
}

- (void) performMiniaturize: (id) sender {
    [self miniaturize: sender];
}

- (void) performZoom: (id) sender {
    [self zoom: sender];
}

- (NSRect) zoomedFrame {
    NSScreen *screen = [self screen];
    NSRect zoomedFrame = [screen visibleFrame];

    if ([_delegate respondsToSelector: @selector
                   (windowWillUseStandardFrame:defaultFrame:)]) {
        zoomedFrame = [_delegate windowWillUseStandardFrame: self
                                               defaultFrame: zoomedFrame];
    } else if ([self respondsToSelector: @selector
                       (windowWillUseStandardFrame:defaultFrame:)]) {
        zoomedFrame = [(id<NSWindowDelegate>) self
                windowWillUseStandardFrame: self
                              defaultFrame: zoomedFrame];
    }
    // zoomedFrame = [self constrainFrameRect: zoomedFrame toScreen: screen];

    return zoomedFrame;
}

- (void) zoom: (id) sender {
    NSRect zoomedFrame = [self zoomedFrame];
    if (NSEqualRects(_frame, zoomedFrame)) {
        zoomedFrame = NS_EXTRA(NSWindow, self)->_savedFrame;
    }

    // Make sure we obey our minimums.
    NSSize minSize = [self minSize];
    if (NSWidth(zoomedFrame) < minSize.width) {
        zoomedFrame.size.width = minSize.width;
    }
    if (NSHeight(zoomedFrame) < minSize.height) {
        zoomedFrame.size.height = minSize.height;
    }

    BOOL shouldZoom = YES;
    if ([_delegate respondsToSelector: @selector(windowShouldZoom:toFrame:)]) {
        shouldZoom = [_delegate windowShouldZoom: self toFrame: zoomedFrame];
    } else if ([self respondsToSelector: @selector(windowShouldZoom:
                                                            toFrame:)]) {
        shouldZoom =
                [(id<NSWindowDelegate>) self windowShouldZoom: self
                                                      toFrame: zoomedFrame];
    }

    if (shouldZoom) {
        NS_EXTRA(NSWindow, self)->_savedFrame = [self frame];
        [self setFrame: zoomedFrame display: YES];
    }
}

- (void) platformWindowShouldZoom: (CGWindow *) window {
    [self zoom: nil];
}

- (void) miniaturize: (id) sender {
    [[self platformWindow] miniaturize];
}

- (void) deminiaturize: (id) sender {
    [[self platformWindow] deminiaturize];
}

- (void) print: (id) sender {
    [_backgroundView print: sender];
}

// Full screen is a transition the window system has to confirm: the style mask
// gains NSWindowStyleMaskFullScreen when the request is made and the Did
// notification follows the platform window's confirmation. A window the system
// does not put into (or take out of) full screen reports the failure to the
// delegate and returns to its previous state.
enum {
    FullScreenIdle,
    FullScreenEntering,
    FullScreenExiting,
};

// How long the window system has to confirm a full screen change.
static const NSTimeInterval FullScreenConfirmationTimeout = 3.0;

- (void) toggleFullScreen: (id) sender {
    if (NS_EXTRA(NSWindow, self)->_fullScreenTransition != FullScreenIdle)
        return;

    BOOL entering = !(NS_EXTRA(NSWindow, self)->_styleMask & NSWindowStyleMaskFullScreen);

    NS_EXTRA(NSWindow, self)->_fullScreenTransition = entering ? FullScreenEntering : FullScreenExiting;
    NS_EXTRA(NSWindow, self)->_fullScreenTransitionGeneration++;
    [self postNotificationName: entering ? NSWindowWillEnterFullScreenNotification
                                         : NSWindowWillExitFullScreenNotification];

    NSWindowStyleMask mask = NS_EXTRA(NSWindow, self)->_styleMask;
    if (entering)
        mask |= NSWindowStyleMaskFullScreen;
    else
        mask &= ~NSWindowStyleMaskFullScreen;
    [self setStyleMask: mask];

    // The window system may already be in the requested state.
    if ([_platformWindow respondsToSelector: @selector(isFullScreen)] &&
        [(id) _platformWindow isFullScreen] == entering) {
        [self platformWindow: _platformWindow didChangeFullScreen: entering];
        return;
    }

    // Without a mapped window there is nobody to confirm: fail without waiting.
    NSTimeInterval wait = [self isVisible] ? FullScreenConfirmationTimeout : 0;
    [self performSelector: @selector(_fullScreenTransitionTimedOut:)
               withObject: @(NS_EXTRA(NSWindow, self)->_fullScreenTransitionGeneration)
               afterDelay: wait
                  inModes: @[NSRunLoopCommonModes]];
}

- (void) _finishFullScreenTransition {
    [NSObject cancelPreviousPerformRequestsWithTarget: self
                                             selector: @selector(_fullScreenTransitionTimedOut:)
                                               object: @(NS_EXTRA(NSWindow, self)->_fullScreenTransitionGeneration)];
    NS_EXTRA(NSWindow, self)->_fullScreenTransition = FullScreenIdle;
}

- (void) _fullScreenTransitionTimedOut: (NSNumber *) generation {
    if ([generation unsignedIntegerValue] != NS_EXTRA(NSWindow, self)->_fullScreenTransitionGeneration)
        return;

    NSInteger transition = NS_EXTRA(NSWindow, self)->_fullScreenTransition;
    if (transition == FullScreenIdle)
        return;
    NS_EXTRA(NSWindow, self)->_fullScreenTransition = FullScreenIdle;

    // Return to the state before the request.
    NSWindowStyleMask mask = NS_EXTRA(NSWindow, self)->_styleMask;
    if (transition == FullScreenEntering)
        mask &= ~NSWindowStyleMaskFullScreen;
    else
        mask |= NSWindowStyleMaskFullScreen;
    [self setStyleMask: mask];

    SEL failure = transition == FullScreenEntering ? @selector(windowDidFailToEnterFullScreen:)
                                                   : @selector(windowDidFailToExitFullScreen:);
    if ([_delegate respondsToSelector: failure])
        [_delegate performSelector: failure withObject: self];
}

// The window system reports whether the window is shown fullscreen now.
- (void) platformWindow: (CGWindow *) window didChangeFullScreen: (BOOL) fullScreen {
    NSInteger transition = NS_EXTRA(NSWindow, self)->_fullScreenTransition;

    if (transition == FullScreenEntering && fullScreen) {
        [self _finishFullScreenTransition];
        [self postNotificationName: NSWindowDidEnterFullScreenNotification];
    } else if (transition == FullScreenExiting && !fullScreen) {
        [self _finishFullScreenTransition];
        [self postNotificationName: NSWindowDidExitFullScreenNotification];
    } else if (transition == FullScreenIdle && !fullScreen &&
               (NS_EXTRA(NSWindow, self)->_styleMask & NSWindowStyleMaskFullScreen)) {
        // The window system took the window out of full screen on its own.
        [self postNotificationName: NSWindowWillExitFullScreenNotification];
        [self setStyleMask: NS_EXTRA(NSWindow, self)->_styleMask & ~NSWindowStyleMaskFullScreen];
        [self postNotificationName: NSWindowDidExitFullScreenNotification];
    }
}

- (void) toggleToolbarShown: (id) sender {
    [_toolbar setVisible: ![_toolbar isVisible]];
    [sender setTitle: [NSString stringWithFormat: @"%@ Toolbar",
                                                  [_toolbar isVisible]
                                                          ? @"Hide"
                                                          : @"Show"]];
}

- (void) runToolbarCustomizationPalette: (id) sender {
    [_toolbar runCustomizationPalette: sender];
}

- (void) keyDown: (NSEvent *) event {
    if ([self performKeyEquivalent: event])
        return;
    // A window that is its own first responder passes a key it does not handle along the responder chain
    // (an application can put its own responder after the window).
    if ([self nextResponder] != nil)
        [[self nextResponder] keyDown: event];
    else
        [self interpretKeyEvents: [NSArray arrayWithObject: event]];
}

- (void) doCommandBySelector: (SEL) selector {
    if ([_delegate respondsToSelector: selector]) {
        [_delegate performSelector: selector withObject: nil];
    } else {
        [super doCommandBySelector: selector];
    }
}

- (void) insertTab: (id) sender {
    [self selectNextKeyView: nil];
}

- (void) insertBacktab: (id) sender {
    [self selectPreviousKeyView: nil];
}

- (void) insertNewline: (id) sender {
    if (_defaultButtonCell != nil)
        [(NSControl *) [_defaultButtonCell controlView] performClick: nil];
}

// YES while the window is hidden only because the application was
// deactivated; it is still open.
- (BOOL) _isHiddenForDeactivation {
    return NS_EXTRA(NSWindow, self)->_hiddenForDeactivate;
}

- (void) _showForActivation {
    if (NS_EXTRA(NSWindow, self)->_hiddenForDeactivate) {
        NS_EXTRA(NSWindow, self)->_hiddenForDeactivate = NO;
        [[self platformWindow] showWindowForAppActivation: _frame];
    }
}

- (void) _hideForDeactivation {
    if ([self hidesOnDeactivate] && [self isVisible] &&
        ![self isMiniaturized]) {
        NS_EXTRA(NSWindow, self)->_hiddenForDeactivate = YES;
        [[self platformWindow] hideWindowForAppDeactivation: _frame];
    }
}

- (void) _forcedHideForDeactivation {
    if ([self isVisible]) {
        NS_EXTRA(NSWindow, self)->_hiddenForDeactivate = YES;
        // _hiddenKeyWindow=[self isKeyWindow];
        [[self platformWindow] hideWindowForAppDeactivation: _frame];
    }
}

- (BOOL) performKeyEquivalent: (NSEvent *) event {
    return [_backgroundView performKeyEquivalent: event];
}

#if 0
- (void) keyDown: (NSEvent *) event {
    if (![self performKeyEquivalent: event]) {
        NSString *characters = [event charactersIgnoringModifiers];

        if ([characters isEqualToString: @" "]) {
            [_firstResponder tryToPerform: @selector(performClick:) with: nil];
        } else if ([characters isEqualToString: @"\t"]) {
            if ([event modifierFlags] & NSShiftKeyMask) {
                [self selectPreviousKeyView: nil];
            } else {
                [self selectNextKeyView:nil];
            }
        }
    }
}
#endif

- (void) _resizeWithOldMenuViewSize: (NSSize) oldSize {
    NSSize backSize = [_backgroundView frame].size;
    NSSize newSize = [NS_EXTRA(NSWindow, self)->_menuView frame].size;
    if ([NS_EXTRA(NSWindow, self)->_menuView isHidden]) {
        newSize.height = 0;
    }

    backSize.height += newSize.height - oldSize.height;
    [_backgroundView setAutoresizesSubviews: NO];
    [_backgroundView setFrameSize: backSize];
    [_backgroundView setAutoresizesSubviews: YES];

    NSRect frame = [self frame];
    frame.size.height += newSize.height - oldSize.height;
    // No display because setMenu: is called before awakeFromNib.
    [self setFrame: frame display: NO];
    // Do we even need this?
    [_backgroundView setNeedsDisplay: YES];
}

- (void) _hideMenuViewIfNeeded {
    if ([self hasMainMenu] && NS_EXTRA(NSWindow, self)->_menuView != nil && ![NS_EXTRA(NSWindow, self)->_menuView isHidden]) {
        [NS_EXTRA(NSWindow, self)->_menuView setHidden: YES];
        [self _resizeWithOldMenuViewSize: [NS_EXTRA(NSWindow, self)->_menuView frame].size];
    }
}

- (void) _showMenuViewIfNeeded {
    if ([self hasMainMenu] && NS_EXTRA(NSWindow, self)->_menuView != nil && [NS_EXTRA(NSWindow, self)->_menuView isHidden]) {
        [NS_EXTRA(NSWindow, self)->_menuView setHidden: NO];
        [self _resizeWithOldMenuViewSize: NSZeroSize];
    }
}

- (void) setMenu: (NSMenu *) menu {
    if (NS_EXTRA(NSWindow, self)->_menuView != nil) {
        NSSize oldSize = [NS_EXTRA(NSWindow, self)->_menuView frame].size;
        [NS_EXTRA(NSWindow, self)->_menuView setMenu: menu];
        [self _resizeWithOldMenuViewSize: oldSize];
    }

    [menu retain];
    [NS_EXTRA(NSWindow, self)->_menu release];
    NS_EXTRA(NSWindow, self)->_menu = menu;
}

- (NSMenu *) menu {
    return NS_EXTRA(NSWindow, self)->_menu;
}

- (BOOL) _isActive {
    return NS_EXTRA(NSWindow, self)->_isActive;
}

- (void) _setVisible: (BOOL) visible {
    BOOL wasVisible = NS_EXTRA(NSWindow, self)->_isVisible;

    NS_EXTRA(NSWindow, self)->_isVisible = visible;
    [self _postOcclusionChangeIfVisibleWas: wasVisible];
}

// The occlusion state follows visibility (see -occlusionState), so it
// changes whenever the window is shown or hidden.
- (void) _postOcclusionChangeIfVisibleWas: (BOOL) wasVisible {
    if (wasVisible != NS_EXTRA(NSWindow, self)->_isVisible)
        [self postNotificationName: NSWindowDidChangeOcclusionStateNotification];
}

// default NSDraggingDestination
- (NSDragOperation) draggingEntered: (id<NSDraggingInfo>) sender {
    return NSDragOperationNone;
}

- (NSDragOperation) draggingUpdated: (id<NSDraggingInfo>) sender {
    return [sender draggingSourceOperationMask];
}

- (void) draggingExited: (id<NSDraggingInfo>) sender {
    // do nothing
}

- (BOOL) prepareForDragOperation: (id<NSDraggingInfo>) sender {
    // Apple documents prepareForDragOperation: as optional; an absent implementation
    // is treated as accepting (prepared to receive data). Return YES by default.
    return YES;
}

- (BOOL) performDragOperation: (id<NSDraggingInfo>) sender {
    return NO;
}

- (void) concludeDragOperation: (id<NSDraggingInfo>) sender {
    // do nothing
}

- (NSArray *) _draggedTypes {
    return NS_EXTRA(NSWindow, self)->_draggedTypes;
}

- (void) _setSheetOrigin {
    NSWindow *sheet = [NS_EXTRA(NSWindow, self)->_sheetContext sheet];
    NSRect sheetFrame = [sheet frame];
    NSRect frame = [self frame];

    NSPoint origin;
    origin.y = frame.origin.y + (frame.size.height - sheetFrame.size.height);
    origin.x = frame.origin.x +
               floor((frame.size.width - sheetFrame.size.width) / 2);

    if ([self toolbar] != nil) {
        if (NS_EXTRA(NSWindow, self)->_menuView != nil)
            origin.y -= [NS_EXTRA(NSWindow, self)->_menuView frame].size.height;

        origin.y -= [[[self toolbar] _view] frame].size.height;

        // Depending on the final border types used on the toolbar and the
        // sheets, the sheet placement sometimes looks better with a little
        // "adjustment"....
        origin.y++;
    }

    [sheet setFrameOrigin: origin];
}

- (void) _setSheetOriginAndFront {
    if (NS_EXTRA(NSWindow, self)->_sheetContext != nil) {
        [self _setSheetOrigin];
        [[NS_EXTRA(NSWindow, self)->_sheetContext sheet] orderFront: nil];
    }
}

- (void) _attachSheetContextOrderFrontAndAnimate:
        (NSSheetContext *) sheetContext
{
    NSWindow *sheet = [sheetContext sheet];

    [self postNotificationName: NSWindowWillBeginSheetNotification];

    if ([sheet styleMask] != NSDocModalWindowMask)
        [sheet setStyleMask: NSDocModalWindowMask];

    [NS_EXTRA(NSWindow, self)->_sheetContext autorelease];
    NS_EXTRA(NSWindow, self)->_sheetContext = [sheetContext retain];

    [(NSThemeFrame *) [sheet _backgroundView]
            setWindowBorderType: NSWindowSheetBorderType];

    [self _setSheetOrigin];
    NSRect sheetFrame = [sheet frame];

    BOOL sheetWasVisible = NS_EXTRA(NSWindow, sheet)->_isVisible;
    NS_EXTRA(NSWindow, sheet)->_isVisible = YES;
    [sheet _postOcclusionChangeIfVisibleWas: sheetWasVisible];
    [sheet display];
    [[sheet platformWindow] sheetOrderFrontFromFrame: sheetFrame
                                         aboveWindow: [self platformWindow]];
    [sheet makeKeyWindow];
}

- (void) _setSheetContext: (NSSheetContext *) sheetContext {
    [sheetContext retain];
    [NS_EXTRA(NSWindow, self)->_sheetContext release];
    NS_EXTRA(NSWindow, self)->_sheetContext = sheetContext;
}

- (NSSheetContext *) _sheetContext {
    return NS_EXTRA(NSWindow, self)->_sheetContext;
}

- (void) _detachSheetContextAnimateAndOrderOut {
    NSWindow *sheet = [NS_EXTRA(NSWindow, self)->_sheetContext sheet];
    NSRect sheetFrame = [sheet frame];
    sheetFrame.origin.y = NSMaxY(sheetFrame);
    sheetFrame.size.height = 0;

    BOOL sheetWasVisible = NS_EXTRA(NSWindow, sheet)->_isVisible;
    NS_EXTRA(NSWindow, sheet)->_isVisible = NO;
    [[sheet platformWindow] sheetOrderOutToFrame: sheetFrame];
    [sheet _postOcclusionChangeIfVisibleWas: sheetWasVisible];
    [(NSThemeFrame *) [sheet _backgroundView] setWindowBorderType: NSNoBorder];

    [NS_EXTRA(NSWindow, self)->_sheetContext release];
    NS_EXTRA(NSWindow, self)->_sheetContext = nil;

    [self postNotificationName: NSWindowDidEndSheetNotification];
}

- (void) _flashWindow {
    if ([self _isApplicationWindow])
        [[self platformWindow] flashWindow];
}

- (void) platformWindowActivated: (CGWindow *) window
                 displayIfNeeded: (BOOL) displayIfNeeded
{
    [NSApp _windowWillBecomeActive: self];

    [self _setSheetOriginAndFront];
    [NS_EXTRA(NSWindow, self)->_childWindows
            makeObjectsPerformSelector: @selector(_parentWindowDidActivate:)
                            withObject: self];
    [NS_EXTRA(NSWindow, self)->_drawers makeObjectsPerformSelector: @selector(parentWindowDidActivate:)
                              withObject: self];

    NS_EXTRA(NSWindow, self)->_isActive = YES;
    if ([self canBecomeKeyWindow]) {
        [self becomeKeyWindow];
    }
    if ([self canBecomeMainWindow] && ![self isMainWindow]) {
        [self becomeMainWindow];
    }

    [NS_EXTRA(NSWindow, self)->_menuView setNeedsDisplay: YES];
    if (displayIfNeeded) {
        [self displayIfNeeded];
    }

    [NSApp _windowDidBecomeActive: self];
    [NSApp updateWindows];
}

- (void) platformWindowDeactivated: (CGWindow *) window
           checkForAppDeactivation: (BOOL) checkForAppDeactivation
{
    [NSApp _windowWillBecomeDeactive: self];

    [NS_EXTRA(NSWindow, self)->_childWindows
            makeObjectsPerformSelector: @selector(_parentWindowDidDeactivate:)
                            withObject: self];
    [NS_EXTRA(NSWindow, self)->_drawers makeObjectsPerformSelector: @selector(parentWindowDidDeactivate:)
                              withObject: self];

    NS_EXTRA(NSWindow, self)->_isActive = NO;

    [NS_EXTRA(NSWindow, self)->_menuView setNeedsDisplay: YES];
    [self displayIfNeeded];

    if (checkForAppDeactivation)
        [NSApp performSelector: @selector(_checkForAppActivation)];

    [NSApp _windowDidBecomeDeactive: self];
    [NSApp updateWindows];
}

- (void) platformWindowDeminiaturized: (CGWindow *) window {
    [self _updatePlatformWindowTitle];
    if (NS_EXTRA(NSWindow, self)->_sheetContext != nil) {
        [[NS_EXTRA(NSWindow, self)->_sheetContext sheet] orderWindow: NSWindowAbove
                                relativeTo: [self windowNumber]];
    }
    [self postNotificationName: NSWindowDidDeminiaturizeNotification];
    [NSApp updateWindows];
}

- (void) platformWindowMiniaturized: (CGWindow *) window {
    NS_EXTRA(NSWindow, self)->_isActive = NO;

    [self _updatePlatformWindowTitle];
    if (NS_EXTRA(NSWindow, self)->_sheetContext != nil) {
        [[NS_EXTRA(NSWindow, self)->_sheetContext sheet] orderWindow: NSWindowOut relativeTo: 0];
    }

    [self postNotificationName: NSWindowDidMiniaturizeNotification];

    if ([self isKeyWindow]) {
        [self resignKeyWindow];
    }

    if ([self isMainWindow]) {
        [self resignMainWindow];
    }

    [NS_EXTRA(NSWindow, self)->_childWindows
            makeObjectsPerformSelector: @selector(_parentWindowDidMiniaturize:)
                            withObject: self];
    [NS_EXTRA(NSWindow, self)->_drawers makeObjectsPerformSelector: @selector(parentWindowDidMiniaturize:)
                              withObject: self];

    [NSApp updateWindows];
}

- (void) platformWindowExposed: (CGWindow *) window inRect: (NSRect) rect {
    NSValue *nsrect = [NSValue valueWithRect: rect];
    NSDictionary *userInfo = @{@"NSExposedRect" : nsrect};

    [[NSNotificationCenter defaultCenter]
            postNotificationName: NSWindowDidExposeNotification
                          object: self
                        userInfo: userInfo];
}

- (void) platformWindow: (CGWindow *) window
           frameChanged: (NSRect) frame
                didSize: (BOOL) didSize
{
    // Don't allow the platform window changes to violate our window size limits
    // (if we have them). Windows (for example) likes to make the platform
    // window very small so it fits in the task bar...
    if (!NSEqualSizes([self minSize], NSMakeSize(0, 0))) {
        frame.size.width = MAX(NSWidth(frame), [self minSize].width);
        frame.size.height = MAX(NSHeight(frame), [self minSize].height);
    }

    if (!NSEqualSizes([self maxSize], NSMakeSize(FLT_MAX, FLT_MAX))) {
        frame.size.width = MIN(NSWidth(frame), [self maxSize].width);
        frame.size.height = MIN(NSHeight(frame), [self maxSize].height);
    }

    // We don't want the miniaturized frame.
    if (![self isMiniaturized]) {
        _frame = frame;
    }

    NS_EXTRA(NSWindow, self)->_makeSureIsOnAScreen = YES;

    [self _setSheetOriginAndFront];
    [NS_EXTRA(NSWindow, self)->_childWindows
            makeObjectsPerformSelector: @selector(_parentWindowDidChangeFrame:)
                            withObject: self];
    [NS_EXTRA(NSWindow, self)->_drawers makeObjectsPerformSelector: @selector(parentWindowDidChangeFrame:)
                              withObject: self];

    if (didSize) {
        // Don't redraw everything unless we really have to.
        [_backgroundView setFrameSize: _frame.size];
        [_backgroundView setNeedsDisplay: YES];
        [self resetCursorRects];
        [self saveFrameUsingName: _autosaveFrameName];
        [self postNotificationName: NSWindowDidResizeNotification];
    } else {
        [self saveFrameUsingName: _autosaveFrameName];
        [self postNotificationName: NSWindowDidMoveNotification];
    }
}

- (void) platformWindowExitMove: (CGWindow *) window {
    [self _setSheetOriginAndFront];
    [NS_EXTRA(NSWindow, self)->_childWindows
            makeObjectsPerformSelector: @selector(_parentWindowDidExitMove:)
                            withObject: self];
    [NS_EXTRA(NSWindow, self)->_drawers makeObjectsPerformSelector: @selector(parentWindowDidExitMove:)
                              withObject: self];
}

- (NSSize) platformWindow: (CGWindow *) window
        frameSizeWillChange: (NSSize) size
{
    if (NS_EXTRA(NSWindow, self)->_resizeIncrements.width != 1 || NS_EXTRA(NSWindow, self)->_resizeIncrements.height != 1) {
        NSSize vertical = size;
        NSSize horizontal = size;

        vertical.width = vertical.height *
                         (NS_EXTRA(NSWindow, self)->_resizeIncrements.width / NS_EXTRA(NSWindow, self)->_resizeIncrements.height);
        horizontal.height = horizontal.width * (NS_EXTRA(NSWindow, self)->_resizeIncrements.height /
                                                NS_EXTRA(NSWindow, self)->_resizeIncrements.width);
        if (vertical.width * vertical.height >
            horizontal.width * horizontal.height) {
            size = vertical;
        } else {
            size = horizontal;
        }
    }

    if ([_delegate respondsToSelector: @selector(windowWillResize:toSize:)])
        size = [_delegate windowWillResize: self toSize: size];

    return size;
}

- (void) platformWindowWillBeginSizing: (CGWindow *) window {
    [self postNotificationName: NSWindowWillStartLiveResizeNotification];
    NS_EXTRA(NSWindow, self)->_isInLiveResize = YES;
    [_backgroundView viewWillStartLiveResize];
}

- (void) platformWindowDidEndSizing: (CGWindow *) window {
    NS_EXTRA(NSWindow, self)->_isInLiveResize = NO;
    [_backgroundView viewDidEndLiveResize];
    [self postNotificationName: NSWindowDidEndLiveResizeNotification];
}

- (void) platformWindow: (CGWindow *) window needsDisplayInRect: (NSRect) rect {
    [self display];
}

// The window's backing scale changed (it moved to an output with another
// scale, or the output's scale changed): post the notification, then tell the
// views so they can reload scale dependent resources before they redraw.
- (void) platformWindow: (CGWindow *) window didChangeBackingScaleFrom: (CGFloat) oldScale {
    if (oldScale == [self backingScaleFactor])
        return;

    NSMutableDictionary *info = [NSMutableDictionary
            dictionaryWithObject: [NSNumber numberWithDouble: oldScale]
                          forKey: NSBackingPropertyOldScaleFactorKey];
    NSColorSpace *colorSpace = [[self screen] colorSpace];
    if (colorSpace != nil)
        [info setObject: colorSpace forKey: NSBackingPropertyOldColorSpaceKey];
    [[NSNotificationCenter defaultCenter]
            postNotificationName: NSWindowDidChangeBackingPropertiesNotification
                          object: self
                        userInfo: info];
    [_backgroundView _backingPropertiesDidChange];
}

- (void) platformWindowStyleChanged: (CGWindow *) window {
    [self display];
}

- (void) platformWindowWillClose: (CGWindow *) window {
    [self performClose: nil];
}

- (void) platformWindowWillMove: (CGWindow *) window {
    [self postNotificationName: NSWindowWillMoveNotification];
}

- (void) platformWindowDidMove: (CGWindow *) window {
    [self postNotificationName: NSWindowDidMoveNotification];
}

- (BOOL) platformWindowIgnoreModalMessages: (CGWindow *) window {
    if ([NSApp modalWindow] == nil) {
        return NO;
    }

    if ([self worksWhenModal]) {
        return NO;
    }

    return [NSApp modalWindow] != self;
}

- (BOOL) platformWindowSetCursorEvent: (CGWindow *) window {
    NSMutableArray *exited = [NSMutableArray array];
    NSMutableArray *entered = [NSMutableArray array];
    NSMutableArray *moved = [NSMutableArray array];
    NSMutableArray *update = [NSMutableArray array];
    // Cursor-update areas the pointer was in and still is in.
    NSMutableArray *remaining = [NSMutableArray array];
    BOOL cursorAreaExited = NO;

    BOOL cursorIsSet = NO;
    BOOL raiseToolTipWindow = NO;
    NSPoint mousePoint = [self mouseLocationOutsideOfEventStream];

    // This collects only the active ones.
    [self _resetTrackingAreas];

    for (NSTrackingArea *area in NS_EXTRA(NSWindow, self)->_trackingAreas) {
        BOOL mouseWasInside = [area _mouseInside];
        BOOL mouseIsInside = NSPointInRect(mousePoint, [area _rectInWindow]);
        id owner = [area owner];

        if ([area _isToolTip]) {
            NSToolTipWindow *toolTipWindow =
                    [NSToolTipWindow sharedToolTipWindow];

            if ((![NSApp isActive] && ![self allowsToolTipsWhenApplicationIsInactive]) ||
                [self _sheetContext] != nil) {
                mouseIsInside = NO;
            }

            if (mouseWasInside && !mouseIsInside &&
                [toolTipWindow _trackingArea] == area) {
                [NSObject cancelPreviousPerformRequestsWithTarget: toolTipWindow
                                                         selector: @selector
                                                         (orderFront:)
                                                           object: nil];
                [toolTipWindow orderOut: nil];
            }
            if (!mouseWasInside && mouseIsInside) {
                // AllowsToolTipsWhenApplicationIsInactive
                // is handled when rebuilding areas.
                [NSObject cancelPreviousPerformRequestsWithTarget: toolTipWindow
                                                         selector: @selector
                                                         (orderFront:)
                                                           object: nil];
                [toolTipWindow orderOut: nil];
                NSString *tooltip = nil;

                if ([owner respondsToSelector: @selector
                            (view:stringForToolTip:point:userData:)]) {
                    NSPoint pt = [[area _view] convertPoint: mousePoint
                                                   fromView: nil];
                    tooltip = [owner view: [area _view]
                            stringForToolTip: area
                                       point: pt
                                    userData: [area userInfo]];
                } else {
                    tooltip = [owner description];
                }

                if (tooltip) {
                    [toolTipWindow setToolTip: tooltip];
                    // This gives us some protection when ToolTip areas overlap.
                    [toolTipWindow _setTrackingArea: area];
                    raiseToolTipWindow = YES;
                }
            }
        } else {
            // Not ToolTip.
            NSTrackingAreaOptions options = [area options];

            // Options by view activation.
            if (options & NSTrackingActiveAlways) {
            } else if (options & NSTrackingActiveInActiveApp &&
                       ![NSApp isActive]) {
                mouseIsInside = NO;
            } else if (options & NSTrackingActiveInKeyWindow &&
                       (![self isKeyWindow] || [self _sheetContext] != nil)) {
                mouseIsInside = NO;
            } else if (options & NSTrackingActiveWhenFirstResponder &&
                       [area _view] != [self firstResponder]) {
                mouseIsInside = NO;
            }

            if (options & NSTrackingInVisibleRect) {
                // This does not do hit testing, it just checks if it's inside
                // the visible rect, child views will cause the test to fail if
                // they aren't tracking anything
                NSPoint check = [[area _view] convertPoint: mousePoint
                                                  fromView: nil];

                if (!NSMouseInRect(check, [[area _view] visibleRect],
                                   [[area _view] isFlipped]))
                    mouseIsInside = NO;
            }

            // FIXME:
            if (options & NSTrackingEnabledDuringMouseDrag) {
                // NSLog(@"NSTrackingEnabledDuringMouseDrag handling
                // unimplemented.");
            }

            // Send appropriate events.
            if (options & NSTrackingMouseEnteredAndExited && !mouseWasInside &&
                mouseIsInside) {
                [entered addObject: area];
            }
            if (options & (NSTrackingMouseEnteredAndExited |
                           NSTrackingCursorUpdate) &&
                mouseWasInside && !mouseIsInside) {
                [exited addObject: area];
            }
            if (options & NSTrackingMouseMoved &&
                [self acceptsMouseMovedEvents]) {
                [moved addObject: area];
            }
            if (options & NSTrackingCursorUpdate && !mouseWasInside &&
                mouseIsInside && !(options & NSTrackingActiveAlways)) {
                cursorIsSet = YES;
                [update addObject: area];
            }
            if (options & NSTrackingCursorUpdate && mouseWasInside &&
                mouseIsInside && !(options & NSTrackingActiveAlways)) {
                [remaining addObject: area];
            }
        }
        // (not) ToolTip

        [area _setMouseInside: mouseIsInside];
    }

    // Exited events need to be sent before entered events
    // The order of the other two is not specific at this time

    for (NSTrackingArea *check in exited) {
        if ([check options] & NSTrackingCursorUpdate) {
            cursorAreaExited = YES;
        }
    }

    // The cursor goes back to the arrow when the pointer leaves a cursor-update
    // area. This happens before the owners are told about exits and entries,
    // which may set a cursor of their own, and before cursorUpdate: is sent for
    // the areas the pointer entered.
    if (cursorAreaExited) {
        [[NSCursor arrowCursor] set];

        // If the pointer is still inside another cursor-update area (it left
        // an area nested in, or overlapping, a larger one) and entered no
        // other, that area decides the cursor again. Of several the one
        // collected last, which is the frontmost, is used.
        if ([update count] == 0 && [remaining count] > 0) {
            [update addObject: [remaining lastObject]];
            cursorIsSet = YES;
        }
    }

    for (NSTrackingArea *check in exited) {
        id owner = [check owner];

        if ([owner respondsToSelector: @selector(mouseExited:)]) {
            NSEvent *event = [NSEvent
                    enterExitEventWithType: NSMouseExited
                                  location: mousePoint
                             modifierFlags: [NSEvent modifierFlags]
                                 timestamp:
                                         [NSDate timeIntervalSinceReferenceDate]
                              windowNumber: [self windowNumber]
                                   context: [self graphicsContext]
                               eventNumber: 0 // NSEvent currently ignores this.
                            trackingNumber: (NSInteger) check
                                  userData: [check userInfo]];
            [owner mouseExited: event];
        }
    }

    for (NSTrackingArea *check in entered) {
        id owner = [check owner];

        if ([owner respondsToSelector: @selector(mouseEntered:)]) {
            NSEvent *event = [NSEvent
                    enterExitEventWithType: NSMouseEntered
                                  location: mousePoint
                             modifierFlags: [NSEvent modifierFlags]
                                 timestamp:
                                         [NSDate timeIntervalSinceReferenceDate]
                              windowNumber: [self windowNumber]
                                   context: [self graphicsContext]
                               eventNumber: 0 // NSEvent currently ignores this.
                            trackingNumber: (NSInteger) check
                                  userData: [check userInfo]];
            [owner mouseEntered: event];
        }
    }

    for (NSTrackingArea *check in moved) {
        id owner = [check owner];

        if ([owner respondsToSelector: @selector(mouseMoved:)]) {
            NSEvent *event = [NSEvent
                    mouseEventWithType: NSMouseMoved
                              location: mousePoint
                         modifierFlags: [NSEvent modifierFlags]
                             timestamp: [NSDate timeIntervalSinceReferenceDate]
                          windowNumber: [self windowNumber]
                               context: [self graphicsContext]
                           eventNumber: 0 // NSEvent currently ignores this.
                            clickCount: 0
                              pressure: 0.];
            [owner mouseMoved: event];
        }
    }

    for (NSTrackingArea *check in update) {
        id owner = [check owner];

        if ([owner respondsToSelector: @selector(cursorUpdate:)]) {
            NSEvent *event = [NSEvent
                    enterExitEventWithType: NSCursorUpdate
                                  location: mousePoint
                             modifierFlags: [NSEvent modifierFlags]
                                 timestamp:
                                         [NSDate timeIntervalSinceReferenceDate]
                              windowNumber: [self windowNumber]
                                   context: [self graphicsContext]
                               eventNumber: 0 // NSEvent currently ignores this.
                            trackingNumber: (NSInteger) check
                                  userData: [check userInfo]];
            [owner cursorUpdate: event];
        }
    }

    if (raiseToolTipWindow) {
        NSTimeInterval delay =
                ((NSTimeInterval) [[NSUserDefaults standardUserDefaults]
                        integerForKey: @"NSInitialToolTipDelay"]) /
                1000.;

        if (delay <= 0.) {
            delay = 2.;
        }
        [[NSToolTipWindow sharedToolTipWindow]
                performSelector: @selector(orderFront:)
                     withObject: nil
                     afterDelay: delay];
    }

    if (!cursorIsSet) {
        NSPoint check = [_contentView convertPoint: mousePoint fromView: nil];

        // We set the cursor to the current cursor if it is inside the content
        // area, this will need to be changed if we're drawing out own window
        // frame.
        if (NSMouseInRect(check, [_contentView bounds],
                          [_contentView isFlipped])) {
            if ([NSCursor currentCursor] == nil) {
                [[NSCursor arrowCursor] set];
            } else {
                [[NSCursor currentCursor] set];
            }
            cursorIsSet = YES;
        }
    }

    return cursorIsSet;
}

- (NSUndoManager *) undoManager {
    if ([_delegate respondsToSelector: @selector(windowWillReturnUndoManager:)])
        return [_delegate windowWillReturnUndoManager: self];

    // If this window is associated with a document, return the document's undo
    // manager. Apple's documentation says this is the delegate's
    // responsibility, but that's not how it works in real life.
    if (NS_EXTRA(NSWindow, self)->_undoManager == nil) {
        NS_EXTRA(NSWindow, self)->_undoManager =
                [[[[self windowController] document] undoManager] retain];
    }

    //  If the delegate does not implement this method, the NSWindow creates an
    //  NSUndoManager for the window and all its views. -- seems like some
    //  duplication vs. NSDocument, but oh well..
    if (NS_EXTRA(NSWindow, self)->_undoManager == nil) {
        NS_EXTRA(NSWindow, self)->_undoManager = [[NSUndoManager alloc] init];
        [NS_EXTRA(NSWindow, self)->_undoManager setRunLoopModes: @[
            NSDefaultRunLoopMode, NSModalPanelRunLoopMode,
            NSEventTrackingRunLoopMode
        ]];
    }

    return NS_EXTRA(NSWindow, self)->_undoManager;
}

- (void) undo: (id) sender {
    [[self undoManager] undo];
}

- (void) redo: (id) sender {
    [[self undoManager] redo];
}

- (BOOL) validateMenuItem: (NSMenuItem *) item {
    if ([item action] == @selector(undo:))
        return [[self undoManager] canUndo];
    if ([item action] == @selector(redo:))
        return [[self undoManager] canRedo];

    return YES;
}

- (void) _attachDrawer: (NSDrawer *) drawer {
    if (NS_EXTRA(NSWindow, self)->_drawers == nil)
        NS_EXTRA(NSWindow, self)->_drawers = [[NSMutableArray alloc] init];

    [NS_EXTRA(NSWindow, self)->_drawers addObject: drawer];
}

- (void) _detachDrawer: (NSDrawer *) drawer {
    [NS_EXTRA(NSWindow, self)->_drawers removeObject: drawer];
}

- (NSView *) _backgroundView {
    return _backgroundView;
}

- (void) dirtyRect: (NSRect) rect {
    [[self platformWindow] dirtyRect: rect];
}

- (CGSubWindow *) _createSubWindowWithFrame: (CGRect) frame {
    // A view can get a layer or an OpenGL context before the window is first
    // shown, which is when the platform window is otherwise created. The
    // subwindow needs its parent, so create the platform window now.
    return [[self platformWindow] createSubWindowWithFrame: frame];
}

+ (BOOL) allowsAutomaticWindowTabbing {
    return _allowsAutomaticWindowTabbing;
}

+ (void) setAllowsAutomaticWindowTabbing: (BOOL) allowsAutomaticWindowTabbing {
    _allowsAutomaticWindowTabbing = allowsAutomaticWindowTabbing;
}

- (NSAppearance *) effectiveAppearance {
    if (NS_EXTRA(NSWindow, self)->_appearance != nil)
        return NS_EXTRA(NSWindow, self)->_appearance;

    id source = [self appearanceSource];
    if (source != self && source != NSApp && source != nil)
        return [source effectiveAppearance];
    return [NSApp effectiveAppearance];
}

- (NSObject<NSAppearanceCustomization> *) appearanceSource {
    NSObject<NSAppearanceCustomization> *source =
            objc_loadWeak(&NS_EXTRA(NSWindow, self)->_appearanceSource);
    return source != nil ? source : (id) NSApp;
}

- (void) setAppearanceSource: (NSObject<NSAppearanceCustomization> *) source {
    [self willChangeValueForKey: @"effectiveAppearance"];
    objc_storeWeak(&NS_EXTRA(NSWindow, self)->_appearanceSource, source);
    [self didChangeValueForKey: @"effectiveAppearance"];
}

// Private AppKit method that applications call on a mouse down to find out
// whether the pointer is on a resize edge or corner of the window. The answer
// is -1 when the window cannot be resized there, otherwise a direction: 0
// right, 1 top right, 2 top, 3 top left, 4 left, 5 bottom left, 6 bottom, 7
// bottom right. The location is in window coordinates.
//
// The region geometry is approximate: it was observed on macOS at one pixel
// per point for a window of 300 by 200 points. An edge band is about 4 points
// wide inside the frame (titled windows also react up to 3 points outside it)
// and corners are squares of about 10 points (the observed arm lengths were
// between 6 and 11 points, depending on the window part). Resizing itself is
// done by the window manager, so these regions only drive the answer of this
// method.
- (NSInteger) _resizeDirectionForMouseLocation: (NSPoint) location {
    if (!(NS_EXTRA(NSWindow, self)->_styleMask & NSWindowStyleMaskResizable))
        return -1;

    NSSize size = [self frame].size;
    CGFloat outside = (NS_EXTRA(NSWindow, self)->_styleMask & NSWindowStyleMaskTitled) ? 3.0 : 0.0;
    const CGFloat band = 4.0, corner = 10.0;

    if (location.x < -outside || location.y < -outside ||
        location.x >= size.width + outside || location.y >= size.height + outside)
        return -1;

    BOOL left = location.x < band;
    BOOL right = location.x >= size.width - band;
    BOOL bottom = location.y < band;
    BOOL top = location.y >= size.height - band;

    if (!left && !right && !bottom && !top) {
        // Inside the frame, away from every edge, except for the corner
        // squares.
        left = location.x < corner;
        right = location.x >= size.width - corner;
        bottom = location.y < corner;
        top = location.y >= size.height - corner;
        if (!((left || right) && (bottom || top)))
            return -1;
    } else {
        // On an edge band: near a corner it is the corner.
        if (left || right) {
            bottom = bottom || location.y < corner;
            top = top || location.y >= size.height - corner;
        }
        if (top || bottom) {
            left = left || location.x < corner;
            right = right || location.x >= size.width - corner;
        }
    }

    if (top)
        return left ? 3 : right ? 1 : 2;
    if (bottom)
        return left ? 5 : right ? 7 : 6;
    return left ? 4 : 0;
}

// The part of the content area that is not under the title bar or the
// toolbar, in window coordinates. A window whose content view is not
// full-size has the content rect itself; a full-size content view extends
// under the title bar, which is then still excluded here.
- (NSRect) contentLayoutRect {
    NSRect frame = [self frame];
    NSRect result;

    if (NS_EXTRA(NSWindow, self)->_styleMask & NSWindowStyleMaskFullSizeContentView) {
        result = [[NSDisplay currentDisplay]
                         insetRect: frame
                forNativeWindowBorderWithStyle: NS_EXTRA(NSWindow, self)->_styleMask & ~NSWindowStyleMaskFullSizeContentView];
        NSToolbar *toolbar = _toolbar;
        if ([toolbar _view] != nil && ![[toolbar _view] isHidden])
            result.size.height -= [[toolbar _view] frame].size.height;
    } else {
        result = [self contentRectForFrameRect: frame];
    }
    result.origin.x -= frame.origin.x;
    result.origin.y -= frame.origin.y;
    return result;
}

// The rect, in screen coordinates, with its edges moved onto whole backing
// pixels of the window.
- (NSRect) backingAlignedRect: (NSRect) rect options: (NSAlignmentOptions) options {
    CGFloat scale = [self backingScaleFactor];

    if (!(scale > 0))
        scale = 1.0;
    rect = NSMakeRect(rect.origin.x * scale, rect.origin.y * scale,
                      rect.size.width * scale, rect.size.height * scale);
    rect = _NSAlignRectToPixelGrid(rect, options);
    return NSMakeRect(rect.origin.x / scale, rect.origin.y / scale,
                      rect.size.width / scale, rect.size.height / scale);
}

// The window's frame in screen coordinates.
- (NSRect) accessibilityFrame {
    return [self frame];
}

// effectiveAppearance follows the window's own appearance, and the
// application's through -[NSApplication setAppearance:].
+ (NSSet *) keyPathsForValuesAffectingEffectiveAppearance {
    return [NSSet setWithObject: @"appearance"];
}

- (CGFloat) backingScaleFactor {
    // Query only an existing native window: asking for a scale must not map it.
    if ([_platformWindow respondsToSelector: @selector(backingScaleFactor)]) {
        CGFloat scale = [_platformWindow backingScaleFactor];
        if (isfinite(scale) && scale > 0) return scale;
    }
    NSScreen *screen = [self screen];
    return screen != nil ? [screen backingScaleFactor] : 1.0;
}

- (NSPoint) convertPointToScreen: (NSPoint) point {
    return [self convertBaseToScreen: point];
}

- (NSPoint) convertPointFromScreen: (NSPoint) point {
    return [self convertScreenToBase: point];
}

- (NSRect) convertRectToScreen: (NSRect) rect {
    rect.origin = [self convertBaseToScreen: rect.origin];
    return rect;
}

- (NSRect) convertRectFromScreen: (NSRect) rect {
    rect.origin = [self convertScreenToBase: rect.origin];
    return rect;
}

static inline NSRect scaleWindowRect(NSRect rect, CGFloat scale) {
    return NSMakeRect(rect.origin.x * scale, rect.origin.y * scale,
                      rect.size.width * scale, rect.size.height * scale);
}

- (NSRect) convertRectToBacking: (NSRect) rect {
    CGFloat scale = [self backingScaleFactor];
    if (scale <= 0) scale = 1.0;
    return scaleWindowRect(rect, scale);
}

- (NSRect) convertRectFromBacking: (NSRect) rect {
    CGFloat scale = [self backingScaleFactor];
    if (scale <= 0) scale = 1.0;
    return scaleWindowRect(rect, 1.0 / scale);
}

- (NSPoint) convertPointToBacking: (NSPoint) point {
    return [self convertRectToBacking: (NSRect){point, NSZeroSize}].origin;
}

- (NSPoint) convertPointFromBacking: (NSPoint) point {
    return [self convertRectFromBacking: (NSRect){point, NSZeroSize}].origin;
}

- (NSSize) convertSizeToBacking: (NSSize) size {
    return [self convertRectToBacking: (NSRect){NSZeroPoint, size}].size;
}

- (NSSize) convertSizeFromBacking: (NSSize) size {
    return [self convertRectFromBacking: (NSRect){NSZeroPoint, size}].size;
}

- (void) beginSheet: (NSWindow *) sheet
        completionHandler: (void (^)(NSInteger returnCode)) handler
{
    // Sheets aren't queued: attaching would drop the current sheet's context
    // without ending it, so a second sheet is refused and its handler never runs.
    if ([self attachedSheet] != nil) {
        NSLog(@"-[NSWindow beginSheet:completionHandler:] %@ already has a sheet", self);
        return;
    }
    [NSApp beginSheet: sheet
            modalForWindow: self
             modalDelegate: [[NSWindowSheetCompletion alloc]
                                    initWithHandler: handler]
            didEndSelector: @selector(sheetDidEnd:returnCode:contextInfo:)
               contextInfo: NULL];
}

- (void) endSheet: (NSWindow *) sheet {
    [NSApp endSheet: sheet];
}

- (void) endSheet: (NSWindow *) sheet returnCode: (NSInteger) returnCode {
    [NSApp endSheet: sheet returnCode: returnCode];
}

@end

@implementation NSWindow (Darling)

- (CGWindow *) platformWindow {
    if (_platformWindow == nil) {
        [self performSelectorOnMainThread: @selector
                (_createPlatformWindowOnMainThread)
                               withObject: nil
                            waitUntilDone: YES
                                    modes: @[ NSDefaultRunLoopMode ]];
    }

    return _platformWindow;
}

@end

@implementation NSWindow (NSWindowTitlebarAccessories)

- (NSArray *) titlebarAccessoryViewControllers {
    return NS_EXTRA(NSWindow, self)->_titlebarAccessoryViewControllers
            ? [NSArray arrayWithArray: NS_EXTRA(NSWindow, self)->_titlebarAccessoryViewControllers]
            : [NSArray array];
}

- (void) addTitlebarAccessoryViewController:
        (NSTitlebarAccessoryViewController *) controller
{
    if (controller == nil)
        return;
    if (NS_EXTRA(NSWindow, self)->_titlebarAccessoryViewControllers == nil)
        NS_EXTRA(NSWindow, self)->_titlebarAccessoryViewControllers = [[NSMutableArray alloc] init];
    [NS_EXTRA(NSWindow, self)->_titlebarAccessoryViewControllers addObject: controller];
}

@end

@implementation NSWindow (NSWindowTitlebarAccessoryIndexing)

- (void) insertTitlebarAccessoryViewController:
                 (NSTitlebarAccessoryViewController *) controller
                                       atIndex: (NSInteger) index
{
    NSMutableArray *accessories =
            NS_EXTRA(NSWindow, self)->_titlebarAccessoryViewControllers;

    if (index < 0 || index > (NSInteger) [accessories count]) {
        [NSException raise: NSInternalInconsistencyException
                    format: @"-[NSWindow insertTitlebarAccessoryViewController:atIndex:]: index %ld is out of range",
                            (long) index];
    }
    if (controller == nil || [accessories containsObject: controller])
        return;
    if (accessories == nil)
        accessories = NS_EXTRA(NSWindow, self)->_titlebarAccessoryViewControllers = [[NSMutableArray alloc] init];
    [accessories insertObject: controller atIndex: index];
}

- (void) removeTitlebarAccessoryViewControllerAtIndex: (NSInteger) index {
    NSMutableArray *accessories =
            NS_EXTRA(NSWindow, self)->_titlebarAccessoryViewControllers;

    if (index < 0 || index >= (NSInteger) [accessories count]) {
        [NSException raise: NSRangeException
                    format: @"-[NSWindow removeTitlebarAccessoryViewControllerAtIndex:]: index %ld is out of range",
                            (long) index];
    }
    [accessories removeObjectAtIndex: index];
}

@end

@implementation NSWindow (NSWindowAdditionalAPI)

- (NSArray<NSWindow *> *) sheets {
    NSWindow *sheet = [self attachedSheet];
    return sheet != nil ? [NSArray arrayWithObject: sheet] : [NSArray array];
}

- (void) beginCriticalSheet: (NSWindow *) sheetWindow
          completionHandler: (void (^)(NSModalResponse returnCode)) handler
{
    [self beginSheet: sheetWindow completionHandler: handler];
}

- (BOOL) canRepresentDisplayGamut: (NSDisplayGamut) displayGamut {
    return displayGamut == NSDisplayGamutSRGB;
}

+ (NSWindowUserTabbingPreference) userTabbingPreference {
    // The System Settings choice is stored as one of three strings; a missing
    // or unknown value means tabs in full screen only.
    NSString *mode = [[NSUserDefaults standardUserDefaults]
            stringForKey: @"AppleWindowTabbingMode"];

    if ([mode isEqualToString: @"always"])
        return NSWindowUserTabbingPreferenceAlways;
    if ([mode isEqualToString: @"manual"])
        return NSWindowUserTabbingPreferenceManual;
    return NSWindowUserTabbingPreferenceInFullScreen;
}

- (NSUserInterfaceLayoutDirection) windowTitlebarLayoutDirection {
    return [NSApp userInterfaceLayoutDirection];
}

- (NSRect) cascadingReferenceFrame {
    return [self frame];
}

- (void) selectNextTab: (id) sender {
    // No tab UI: nothing to select.
}

- (void) selectPreviousTab: (id) sender {
    // No tab UI: nothing to select.
}

- (void) moveTabToNewWindow: (id) sender {
    // A window that is the only tab of its group is already in its own window.
}

- (void) toggleTabBar: (id) sender {
    // No tab bar to show or hide.
}

- (void) toggleTabOverview: (id) sender {
    // No tab overview to show or hide.
}

- (void) trackEventsMatchingMask: (NSEventMask) mask
                         timeout: (NSTimeInterval) timeout
                            mode: (NSRunLoopMode) mode
                         handler: (void (^)(NSEvent *event, BOOL *stop)) trackingHandler
{
    BOOL stop = NO;

    while (!stop) {
        NSDate *limit = timeout >= 1e9 ? [NSDate distantFuture]
                : [NSDate dateWithTimeIntervalSinceNow: timeout];
        NSEvent *event = [NSApp nextEventMatchingMask: mask
                                            untilDate: limit
                                               inMode: mode
                                              dequeue: YES];

        // A nil event reports that the timeout elapsed; tracking goes on
        // until the handler asks to stop.
        trackingHandler(event, &stop);
    }
}

@end

NSString * const NSBackingPropertyOldColorSpaceKey = @"NSBackingPropertyOldColorSpaceKey";
