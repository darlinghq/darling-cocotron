/* Copyright (c) 2006-2007 Christopher J. W. Lloyd <cjwl@objc.net>
                 2009 Markus Hitter <mah@jump-ing.de>

   Permission is hereby granted, free of charge, to any person obtaining a copy
   of this software and associated documentation files (the "Software"), to
   deal in the Software without restriction, including without limitation the
   rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
   sell copies of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:

   The above copyright notice and this permission notice shall be included in
   all copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
   IN THE SOFTWARE. */

#import <AppKit/NSApplication.h>
#import <AppKit/NSColor.h>
#import <AppKit/NSCursor.h>
#import <AppKit/NSDisplay.h>
#import <AppKit/NSDraggingManager.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSEvent_CoreGraphics.h>
#import <AppKit/NSGraphics.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSMainMenuView.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSPanel.h>
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
#import <AppKit/NSWindowAnimationContext.h>
#import <ApplicationServices/ApplicationServices.h>
#import <CoreGraphics/CGWindow.h>

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
                             toArray: (NSMutableArray *) array {
    [array addObject: [[[_NSKeyViewPosition alloc] initWithView: view]
                          autorelease]];

    for (NSView *child in [view subviews]) {
        [self addKeyViewPositionsWithView: child toArray: array];
    }
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
    if (NSMaxY(_rect) < NSMaxY(other->_rect)) {
        return NSOrderedDescending;
    } else {
        // Then sort by smaller X
        if (NSMinX(_rect) < NSMinX(other->_rect)) {
            return NSOrderedAscending;
        } else {
            return NSOrderedDescending;
        }
    }
}

@end

@implementation NSWindow

static BOOL _allowsAutomaticWindowTabbing;

+ (NSWindowDepth) defaultDepthLimit {
    return 0;
}

/* This method is Cococtron specific and can be override by subclasses, do not
 * change method name */
+ (BOOL) hasMainMenuForStyleMask: (NSWindowStyleMask) styleMask {
    return styleMask & NSTitledWindowMask;
}

/* This method is Cococtron specific and can be override by subclasses, do not
 * change method name. */
- (BOOL) hasMainMenu {
    return [[self class] hasMainMenuForStyleMask: _styleMask];
}

+ (NSRect) frameRectForContentRect: (NSRect) contentRect
                         styleMask: (NSWindowStyleMask) styleMask {
    NSRect result = [[NSDisplay currentDisplay] outsetRect: contentRect
                            forNativeWindowBorderWithStyle: styleMask];

    if ([self hasMainMenuForStyleMask: styleMask]) {
        result.size.height += [NSMainMenuView menuHeight];
    }

    return result;
}

+ (NSRect) contentRectForFrameRect: (NSRect) frameRect
                         styleMask: (NSWindowStyleMask) styleMask {
    NSRect result = [[NSDisplay currentDisplay] insetRect: frameRect
                           forNativeWindowBorderWithStyle: styleMask];

    if ([self hasMainMenuForStyleMask: styleMask]) {
        result.size.height -= [NSMainMenuView menuHeight];
    }

    return result;
}

+ (CGFloat) minFrameWidthWithTitle: (NSString *) title
                         styleMask: (NSWindowStyleMask) styleMask {
    NSUnimplementedMethod();
    return 0;
}

+ (NSInteger) windowNumberAtPoint: (NSPoint) point
      belowWindowWithWindowNumber: (NSInteger) window {
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

+ (NSButton *) standardWindowButton: (NSWindowButton) button
                       forStyleMask: (NSWindowStyleMask) styleMask {
    NSUnimplementedMethod();
    return nil;
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
                               defer: (BOOL) defer {
    // Make sure NSApplication is initialized.
    if (!NSApp) {
        [NSApplication sharedApplication];
    }
    _styleMask = styleMask;
    _backingType = backing;
    _isDeferred = defer;

    _frame = [self frameRectForContentRect: contentRect];
    _frame = [self constrainFrameRect: _frame toScreen: [NSScreen mainScreen]];
    _savedFrame = _frame;

    _level = NSNormalWindowLevel;
    _minSize = NSZeroSize;
    // "The default maximum size of a window is {FLT_MAX, FLT_MAX}"
    _maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    _title = @"";
    _miniwindowTitle = @"";
    _backgroundColor = [[NSColor windowBackgroundColor] copy];
    _firstResponder = self;
    _makeSureIsOnAScreen = YES;
    _releaseWhenClosed = YES;
    _viewsNeedDisplay = YES;
    _flushNeeded = YES;
    _resizeIncrements = NSMakeSize(1, 1);
    _contentResizeIncrements = NSMakeSize(1, 1);

    _threadToContext = [[NSMutableDictionary alloc] init];

    NSRect backgroundFrame = {NSZeroPoint, _frame.size};
    _backgroundView = [[[[self class] frameViewClassForStyleMask: styleMask]
        alloc] initWithFrame: backgroundFrame];
    [_backgroundView setAutoresizesSubviews: YES];
    [_backgroundView
        setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
    [_backgroundView _setWindow: self];
    [_backgroundView setNextResponder: self];

    NSRect contentViewFrame = [self contentRectForFrameRect: backgroundFrame];
    _contentView = [[NSView alloc] initWithFrame: contentViewFrame];
    [_contentView setAutoresizesSubviews: YES];
    [_contentView
        setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];

    if ([self hasMainMenu]) {
        NSRect menuFrame = NSMakeRect(
            contentViewFrame.origin.x, NSMaxY(contentViewFrame),
            contentViewFrame.size.width, [NSMainMenuView menuHeight]);

        // We all need to share the main menu!
        _menu = [[NSApp mainMenu] retain];

        _menuView = [[NSMainMenuView alloc] initWithFrame: menuFrame
                                                     menu: _menu];
        [_menuView setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
        [_backgroundView addSubview: _menuView];
    }

    [_backgroundView addSubview: _contentView];
    [_backgroundView setNeedsDisplay: YES];

    if (!(_styleMask & NSAppKitPrivateWindow)) {
        [[NSApplication sharedApplication] _addWindow: self];
    }
    return self;
}

- (instancetype) initWithContentRect: (NSRect) contentRect
                           styleMask: (NSWindowStyleMask) styleMask
                             backing: (NSBackingStoreType) backing
                               defer: (BOOL) defer
                              screen: (NSScreen *) screen {
    // FIX, relocate contentRect
    return [self initWithContentRect: contentRect
                           styleMask: styleMask
                             backing: backing
                               defer: defer];
}

- (NSWindow *) initWithWindowRef: (void *) carbonRef {
    NSUnimplementedMethod();
    return nil;
}

- (void) dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [_childWindows release];
    [_title release];
    [_miniwindowTitle release];
    [_miniwindowImage release];
    [_backgroundView _setWindow: nil];
    [_backgroundView release];
    [_menu release];
    [_menuView release];
    [_contentView release];
    [_backgroundColor release];
    [_sharedFieldEditor release];
    [_draggedTypes release];
    [_trackingAreas release];
    [_autosaveFrameName release];
    [_platformWindow invalidate];
    [_platformWindow release];
    _platformWindow = nil;
    [_threadToContext release];
    [_undoManager release];
    [super dealloc];
}

- (void) _updatePlatformWindowTitle {
    NSString *title;

    if ([self isMiniaturized]) {
        title = [self miniwindowTitle];
    } else {
        title = [self title];
    }

    if (_isDocumentEdited) {
        title = [@"* " stringByAppendingString: title];
    }

    [_platformWindow setTitle: title];
}

/*
   There are issues when creating a Win32 handle on a non-main thread, so we
   always do it on the main thread
 */
- (void) _createPlatformWindowOnMainThread {
    if (_platformWindow != nil) {
        return;
    }
    _platformWindow = [[NSDisplay currentDisplay] newWindowWithDelegate: self];

    [self _updatePlatformWindowTitle];

    [[NSDraggingManager draggingManager] registerWindow: self dragTypes: nil];
}

- (CGContextRef) cgContext {
    return [[self platformWindow] cgContext];
}

- (void) setStyleMask: (NSWindowStyleMask) mask {
    _styleMask = mask;
    [_platformWindow setStyleMask: _styleMask];

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
    NSGraphicsContext *context = _threadToContext[key];

    if (!context) {
        context = [NSGraphicsContext graphicsContextWithWindow: self];
        _threadToContext[key] = context;
    }

    return context;
}

- (void) platformWindowDidInvalidateCGContext: (CGWindow *) window {
    [_threadToContext removeAllObjects];
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

- (BOOL) allowsConcurrentViewDrawing {
    NSUnimplementedMethod();
    return NO;
}

- (void) setAllowsConcurrentViewDrawing: (BOOL) allows {
    NSUnimplementedMethod();
}

- (NSView *) contentView {
    return _contentView;
}

- (id) delegate {
    return _delegate;
}

- (NSString *) title {
    return _title;
}

- (NSString *) representedFilename {
    return _representedFilename;
}

- (NSURL *) representedURL {
    NSUnimplementedMethod();
    return nil;
}

- (NSWindowLevel) level {
    return _level;
}

- (NSRect) frame {
    return _frame;
}

- (NSWindowStyleMask) styleMask {
    return _styleMask;
}

- (NSBackingStoreType) backingType {
    return _backingType;
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
    return _minSize;
}

- (NSSize) maxSize {
    return _maxSize;
}

- (NSSize) contentMinSize {
    return _contentMinSize;
}

- (NSSize) contentMaxSize {
    return _contentMaxSize;
}

- (BOOL) isOneShot {
    return _isOneShot;
}

- (BOOL) isOpaque {
    return _isOpaque;
}

- (BOOL) hasDynamicDepthLimit {
    return _dynamicDepthLimit;
}

- (BOOL) isReleasedWhenClosed {
    return _releaseWhenClosed;
}

- (BOOL) preventsApplicationTerminationWhenModal {
    NSUnimplementedMethod();
    return NO;
}

- (void) setPreventsApplicationTerminationWhenModal: (BOOL) prevents {
    NSUnimplementedMethod();
}

- (BOOL) hidesOnDeactivate {
    return _hidesOnDeactivate;
}

- (BOOL) worksWhenModal {
    // We do work when we're running a modal session
    return (_sheetContext && [_sheetContext modalSession] != nil);
}

- (BOOL) isSheet {
    return (_styleMask & NSDocModalWindowMask) ? YES : NO;
}

- (BOOL) acceptsMouseMovedEvents {
    return _acceptsMouseMovedEvents;
}

- (BOOL) isExcludedFromWindowsMenu {
    return _excludedFromWindowsMenu;
}

- (BOOL) isAutodisplay {
    return _isAutodisplay;
}

- (BOOL) isFlushWindowDisabled {
    return _isFlushWindowDisabled;
}

- (NSString *) frameAutosaveName {
    return _autosaveFrameName;
}

- (BOOL) hasShadow {
    return _hasShadow;
}

- (BOOL) ignoresMouseEvents {
    return _ignoresMouseEvents;
}

- (NSSize) aspectRatio {
    return NSMakeSize(1.0, _resizeIncrements.height / _resizeIncrements.width);
}

- (NSSize) contentAspectRatio {
    return NSMakeSize(1.0, _contentResizeIncrements.height /
                               _contentResizeIncrements.width);
}

- (BOOL) autorecalculatesKeyViewLoop {
    return _autorecalculatesKeyViewLoop;
}

- (BOOL) canHide {
    return _canHide;
}

- (BOOL) canStoreColor {
    return _canStoreColor;
}

- (BOOL) showsResizeIndicator {
    return _showsResizeIndicator;
}

- (BOOL) showsToolbarButton {
    return _showsToolbarButton;
}

- (BOOL) displaysWhenScreenProfileChanges {
    return _displaysWhenScreenProfileChanges;
}

- (BOOL) isMovableByWindowBackground {
    return _isMovableByWindowBackground;
}

- (BOOL) allowsToolTipsWhenApplicationIsInactive {
    return _allowsToolTipsWhenApplicationIsInactive;
}

- (NSImage *) miniwindowImage {
    return _miniwindowImage;
}

- (NSString *) miniwindowTitle {
    return _miniwindowTitle;
}

- (NSDockTile *) dockTile {
    NSUnimplementedMethod();
    return nil;
}

- (NSColor *) backgroundColor {
    return _backgroundColor;
}

- (CGFloat) alphaValue {
    return _alphaValue;
}

- (NSWindowDepth) depthLimit {
    return 0;
}

- (NSSize) resizeIncrements {
    return _resizeIncrements;
}

- (NSSize) contentResizeIncrements {
    return _contentResizeIncrements;
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
        {NSWindowDidBecomeMainNotification, @selector(windowDidBecomeMain:)},
        {NSWindowDidDeminiaturizeNotification,
         @selector(windowDidDeminiaturize:)},
        {NSWindowDidMiniaturizeNotification, @selector(windowDidMiniaturize:)},
        {NSWindowDidMoveNotification, @selector(windowDidMove:)},
        {NSWindowDidResignKeyNotification, @selector(windowDidResignKey:)},
        {NSWindowDidResignMainNotification, @selector(windowDidResignMain:)},
        {NSWindowDidResizeNotification, @selector(windowDidResize:)},
        {NSWindowWillStartLiveResizeNotification,
         @selector(windowWillStartLiveResize:)},
        {NSWindowDidEndLiveResizeNotification,
         @selector(windowDidEndLiveResize:)},
        {NSWindowDidUpdateNotification, @selector(windowDidUpdate:)},
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
    if (!_makeSureIsOnAScreen || ![self isVisible] || [self isMiniaturized]) {
        return;
    }

    NSRect frame = _frame;
    BOOL changed = NO;
#if 1
    BOOL tooFarLeft = YES, tooFarRight = YES, tooFarUp = YES, tooFarDown = YES;
    CGFloat leastX = 0, maxX = 0, leastY = 0, maxY = 0;

    for (NSScreen *screen in [NSScreen screens]) {
        NSRect screenFrame = [screen frame];

        if (NSMaxX(frame) > screenFrame.origin.x + 20) {
            tooFarLeft = NO;
        }
        if (frame.origin.x < NSMaxX(screenFrame) - 20) {
            tooFarRight = NO;
        }
        if (frame.origin.y < NSMaxY(screenFrame) - 20) {
            tooFarUp = NO;
        }
        if (NSMaxY(frame) > screenFrame.origin.y + 20) {
            tooFarDown = NO;
        }

        if (screenFrame.origin.x < leastX) {
            leastX = screenFrame.origin.x;
        }
        if (screenFrame.origin.y < leastY) {
            leastY = screenFrame.origin.y;
        }
        if (NSMaxX(screenFrame) > maxX) {
            maxX = NSMaxX(screenFrame);
        }
        if (NSMaxY(screenFrame) > maxY) {
            maxY = NSMaxY(screenFrame);
        }
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
    _makeSureIsOnAScreen = NO;
}

- (void) setFrame: (NSRect) frame display: (BOOL) display {
    [self setFrame: frame display: display animate: NO];
}

- (void) _animateWithContext: (NSWindowAnimationContext *) context {
    NSRect frame = [self frame];
    NSDictionary *userInfo = @{@"NSWindowAnimationContext" : context};

    if (_animationContext == nil) {
        _animationContext = [context retain];
    }

    if (_animationContext != context) {
        [NSException
             raise: NSInvalidArgumentException
            format: @"-[%@ %@]: attempt to animate frame while animation "
                    @"still in progress",
                    [self class], NSStringFromSelector(_cmd)];
    }

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
    } else {
        frame = [context targetRect];
    }

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

        [_animationContext release];
        _animationContext = nil;
#if 0
        if ([_backgroundView cachesImageForAnimation]) {
            [_backgroundView invalidateCachedImage];
        }
#endif
    }
}

- (NSWindowAnimationContext *) _animationContext {
    return _animationContext;
}

- (void) setFrame: (NSRect) newFrame
          display: (BOOL) display
          animate: (BOOL) animate {
    BOOL didSize = !NSEqualSizes(newFrame.size, _frame.size);
    BOOL didMove = !NSEqualPoints(newFrame.origin, _frame.origin);

    _frame = newFrame;
    _makeSureIsOnAScreen = YES;

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
    _minSize = size;
}

- (void) setMaxSize: (NSSize) size {
    _maxSize = size;
}

- (void) setContentMinSize: (NSSize) value {
    _contentMinSize = value;
    NSUnimplementedMethod();
}

- (void) setContentMaxSize: (NSSize) value {
    _contentMaxSize = value;
}

- (void) setContentBorderThickness: (CGFloat) thickness
                           forEdge: (NSRectEdge) edge {
    // FIXME: should warn, but low priority cosmetic, so we dont, still needs to
    // be implemented
    //   NSUnimplementedMethod();
}

- (void) setMovable: (BOOL) movable {
    NSUnimplementedMethod();
}

- (void) setBackingType: (NSBackingStoreType) value {
    _backingType = value;
    NSUnimplementedMethod();
}

- (void) setDynamicDepthLimit: (BOOL) value {
    _dynamicDepthLimit = value;
}

- (void) setOneShot: (BOOL) flag {
    _isOneShot = flag;
}

- (void) setReleasedWhenClosed: (BOOL) flag {
    _releaseWhenClosed = flag;
}

- (void) setHidesOnDeactivate: (BOOL) flag {
    _hidesOnDeactivate = flag;
}

- (void) setAcceptsMouseMovedEvents: (BOOL) flag {
    _acceptsMouseMovedEvents = flag;
    [_platformWindow syncDelegateProperties];
}

- (void) setExcludedFromWindowsMenu: (BOOL) value {
    _excludedFromWindowsMenu = value;
}

- (void) setAutodisplay: (BOOL) value {
    _isAutodisplay = value;
}

- (void) setAutorecalculatesContentBorderThickness: (BOOL) automatic
                                           forEdge: (NSRectEdge) edge {
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
    [_title release];
    _title = title;

    [_miniwindowTitle release];
    _miniwindowTitle = [title copy];

    [self _updatePlatformWindowTitle];

    if ([self _isApplicationWindow]) {
        [NSApp changeWindowsItem: self title: title filename: NO];
    }
}

- (void) setTitleWithRepresentedFilename: (NSString *) filename {
    [self
        setTitle: [NSString stringWithFormat:
                                @"%@  --  %@", [filename lastPathComponent],
                                [filename stringByDeletingLastPathComponent]]];

    if ([self _isApplicationWindow]) {
        [NSApp changeWindowsItem: self title: filename filename: YES];
    }
}

- (void) setContentView: (NSView *) view {
    view = [view retain];
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
    [_miniwindowTitle release];
    _miniwindowTitle = title;

    [self _updatePlatformWindowTitle];
}

- (void) setBackgroundColor: (NSColor *) color {
    if (color == nil) {
        color = [NSColor windowBackgroundColor];
    }
    color = [color copy];
    [_backgroundColor release];
    _backgroundColor = color;
    [_backgroundView setNeedsDisplay: YES];
}

- (void) setAlphaValue: (CGFloat) value {
    _alphaValue = value;
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
    _windowController = value;
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
    _isDocumentEdited = flag;
    [self _updatePlatformWindowTitle];
}

- (void) setContentAspectRatio: (NSSize) value {
    _resizeIncrements.width = 1.0;
    _resizeIncrements.height = value.height / value.width;
}

- (void) setHasShadow: (BOOL) value {
    _hasShadow = value;
    [_platformWindow setHasShadow: value];
}

- (void) setIgnoresMouseEvents: (BOOL) value {
    _ignoresMouseEvents = value;
}

- (void) setAspectRatio: (NSSize) value {
    _resizeIncrements.width = 1.0;
    _resizeIncrements.height = value.height / value.width;
}

- (void) setAutorecalculatesKeyViewLoop: (BOOL) value {
    _autorecalculatesKeyViewLoop = value;
}

- (void) setCanHide: (BOOL) value {
    _canHide = value;
}

- (void) setCanBecomeVisibleWithoutLogin: (BOOL) flag {
    //   NSUnimplementedMethod();
}

- (void) setCollectionBehavior: (NSWindowCollectionBehavior) behavior {
    NSUnimplementedMethod();
}

- (void) setLevel: (NSInteger) value {
    _level = value;
    [_platformWindow setLevel: _level];
}

- (void) setOpaque: (BOOL) value {
    _isOpaque = value;
    [_platformWindow setOpaque: _isOpaque];
}

- (void) setParentWindow: (NSWindow *) value {
    _parentWindow = value;
}

- (void) setPreservesContentDuringLiveResize: (BOOL) value {
    // _preservesContentDuringLiveResize=value;
}

- (void) setRepresentedFilename: (NSString *) value {
    value = [value copy];
    [_representedFilename release];
    _representedFilename = value;
}

- (void) setRepresentedURL: (NSURL *) newURL {
    NSUnimplementedMethod();
}

- (void) setResizeIncrements: (NSSize) value {
    _resizeIncrements = value;
}

- (void) setShowsResizeIndicator: (BOOL) value {
    _showsResizeIndicator = value;
    NSUnimplementedMethod();
}

- (void) setShowsToolbarButton: (BOOL) value {
    _showsToolbarButton = value;
    NSUnimplementedMethod();
}

- (void) setContentResizeIncrements: (NSSize) value {
    _contentResizeIncrements = value;
}

- (void) setDepthLimit: (NSWindowDepth) value {
    NSUnimplementedMethod();
}

- (void) setDisplaysWhenScreenProfileChanges: (BOOL) value {
    _displaysWhenScreenProfileChanges = value;
}

- (void) setMovableByWindowBackground: (BOOL) value {
    _isMovableByWindowBackground = value;
}

- (void) setAllowsToolTipsWhenApplicationIsInactive: (BOOL) value {
    _allowsToolTipsWhenApplicationIsInactive = value;
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

    if ([value length] == 0) {
        return NO;
    }

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
    if ([_firstResponder isKindOfClass: [NSDrawer class]]) {
        return [_firstResponder nextResponder];
    } else {
        return _firstResponder;
    }
}

- (NSButton *) standardWindowButton: (NSWindowButton) value {
    NSUnimplementedMethod();
    return nil;
}

- (NSButtonCell *) defaultButtonCell {
    return _defaultButtonCell;
}

- (NSWindow *) attachedSheet {
    return [_sheetContext sheet];
}

- (id) windowController {
    return _windowController;
}

- (NSArray *) drawers {
    return _drawers;
}

- (NSInteger) windowNumber {
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

- (BOOL) isOnActiveSpace {
    NSUnimplementedMethod();
    return YES;
}

- (NSWindowSharingType) sharingType {
    NSUnimplementedMethod();
    return 0;
}

- (void) setSharingType: (NSWindowSharingType) type {
    NSUnimplementedMethod();
}

- (BOOL) isDocumentEdited {
    return _isDocumentEdited;
}

- (BOOL) isZoomed {
    NSRect zoomedFrame = [self zoomedFrame];
    return NSEqualRects(_frame, zoomedFrame);
}

- (BOOL) isVisible {
    return _isVisible;
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
    NSUnimplementedMethod();
    return NO;
}

- (BOOL) inLiveResize {
    return _isInLiveResize;
}

- (BOOL) canBecomeKeyWindow {
    // The NSWindow implementation returns YES if the window has a title bar or
    // a resize bar, or NO otherwise
    return (_styleMask & (NSTitledWindowMask | NSResizableWindowMask)) != 0;
}

- (BOOL) canBecomeMainWindow {
    // The NSWindow implementation returns YES if the window is visible and has
    // a title bar or a resize mechanism. Otherwise it returns NO
    return [self isVisible] &&
           (_styleMask & (NSTitledWindowMask | NSResizableWindowMask));
}

- (BOOL) canBecomeVisibleWithoutLogin {
    NSUnimplementedMethod();
    return NO;
}

- (NSWindowCollectionBehavior) collectionBehavior {
    NSUnimplementedMethod();
    return 0;
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
    NSRect result = [[NSDisplay currentDisplay] insetRect: frameRect
                           forNativeWindowBorderWithStyle: [self styleMask]];

    if ([self hasMainMenu]) {
        result.size.height -= [NSMainMenuView menuHeight];
    }

    if ([_toolbar _view] != nil && ![[_toolbar _view] isHidden]) {
        result.size.height -= [[_toolbar _view] frame].size.height;
    }

    return result;
}

- (NSRect) constrainFrameRect: (NSRect) rect toScreen: (NSScreen *) screen {
    if (!screen) {
        return rect;
    }
    NSRect visRect = [screen visibleFrame];

    if (NSMaxX(rect) > NSMaxX(visRect)) {
        rect.origin.x = NSMaxX(visRect) - rect.size.width;
    }
    if (NSMaxY(rect) > NSMaxY(visRect)) {
        rect.origin.y = NSMaxY(visRect) - rect.size.height;
    }
    if (NSMinX(rect) < NSMinX(visRect)) {
        rect.origin.x = NSMinX(visRect);
    }
    if (NSMinY(rect) < NSMinY(visRect)) {
        rect.origin.y = NSMinY(visRect);
    }
    return rect;
}

- (NSWindow *) parentWindow {
    return _parentWindow;
}

- (NSArray *) childWindows {
    return _childWindows;
}

- (void) addChildWindow: (NSWindow *) child
                ordered: (NSWindowOrderingMode) ordered {
    if (_childWindows == nil) {
        _childWindows = [NSMutableArray new];
    }

    [_childWindows addObject: child];
    [child setParentWindow: self];
    [child makeKeyAndOrderFront: nil];
}

- (void) removeChildWindow: (NSWindow *) child {
    [child orderOut: nil];
    [child setParentWindow: nil];
    [_childWindows removeObjectIdenticalTo: child];
}

- (void) _parentWindowDidClose: (NSWindow *) parent {
    [self orderOut: nil];
}

- (void) _parentWindowDidActivate: (NSWindow *) parent {
    [self orderWindow: NSWindowAbove relativeTo: [_parentWindow windowNumber]];
}

- (void) _parentWindowDidDeactivate: (NSWindow *) parent {
    [self orderWindow: NSWindowAbove relativeTo: [_parentWindow windowNumber]];
}

- (void) _parentWindowDidMiniaturize: (NSWindow *) parent {
    [self orderOut: nil];
}

- (void) _parentWindowDidChangeFrame: (NSWindow *) parent {
}

- (void) _parentWindowDidExitMove: (NSWindow *) parent {
    [self orderWindow: NSWindowAbove relativeTo: [_parentWindow windowNumber]];
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

    if (_hasBeenOnScreen) {
        return;
    }
    _hasBeenOnScreen = YES;

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

    if (_firstResponder != self && [_firstResponder respondsToSelector: _cmd]) {
        [_firstResponder performSelector: _cmd];
    }

    [self postNotificationName: NSWindowDidBecomeKeyNotification];
}

- (void) resignKeyWindow {
    if (_firstResponder != self && [_firstResponder respondsToSelector: _cmd]) {
        [_firstResponder performSelector: _cmd];
    }

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

- (NSSelectionDirection) keyViewSelectionDirection {
    NSUnimplementedMethod();
    return 0;
}

- (void) disableKeyEquivalentForDefaultButtonCell {
    _defaultButtonCellKeyEquivalentDisabled = YES;
}

- (void) enableKeyEquivalentForDefaultButtonCell {
    _defaultButtonCellKeyEquivalentDisabled = NO;
}

- (NSText *) fieldEditor: (BOOL) create forObject: (id) object {
    NSTextView *newFieldEditor = nil;
    if ([_delegate respondsToSelector: @selector
                   (windowWillReturnFieldEditor:toObject:)]) {
        newFieldEditor = [_delegate windowWillReturnFieldEditor: self
                                                       toObject: object];
    }

    if (create && newFieldEditor == nil && _sharedFieldEditor == nil) {
        newFieldEditor = _sharedFieldEditor = [[NSTextView alloc] init];
    }

    if (newFieldEditor) {
        _currentFieldEditor = newFieldEditor;
    } else {
        _currentFieldEditor = _sharedFieldEditor;
    }

    if (_currentFieldEditor) {
        [_currentFieldEditor setHorizontallyResizable: NO];
        [_currentFieldEditor setVerticallyResizable: NO];
        [_currentFieldEditor setFieldEditor: YES];
        [_currentFieldEditor
            setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
    }

    return _currentFieldEditor;
}

- (void) endEditingFor: (id) object {
    if (_currentFieldEditor) {
        if ((NSResponder *) _currentFieldEditor == _firstResponder) {
            _firstResponder = object;
            [_currentFieldEditor resignFirstResponder];
        }
        [_currentFieldEditor setDelegate: nil];
        [_currentFieldEditor removeFromSuperview];
        [_currentFieldEditor setString: @""];
        _currentFieldEditor = nil;
    }
}

- (void) disableScreenUpdatesUntilFlush {
    NSUnimplementedMethod();
}

- (void) useOptimizedDrawing: (BOOL) flag {
    // Do nothing.
}

- (BOOL) viewsNeedDisplay {
    return _viewsNeedDisplay;
}

- (void) setViewsNeedDisplay: (BOOL) viewsNeedDisplay {
    if (!viewsNeedDisplay || _viewsNeedDisplay) {
        return;
    }
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
    _viewsNeedDisplay = viewsNeedDisplay;
}

- (void) disableFlushWindow {
    _flushDisabled++;
    [_platformWindow disableFlushWindow];
}

- (void) enableFlushWindow {
    _flushDisabled--;
    [_platformWindow enableFlushWindow];
}

- (void) flushWindow {
    if (_flushDisabled > 0) {
        _flushNeeded = YES;
        return;
    }

    _flushNeeded = NO;
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
    if (_flushNeeded) {
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
    return (_cursorRectsDisabled <= 0) ? YES : NO;
}

- (void) disableCursorRects {
    _cursorRectsDisabled++;
    if (_cursorRectsDisabled == 1) {
        [self _invalidateTrackingAreas];
    }
}

- (void) enableCursorRects {
    _cursorRectsDisabled--;
    if (_cursorRectsDisabled == 0) {
        [self _invalidateTrackingAreas];
    }
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
    [_trackingAreas release];
    _trackingAreas = nil;
}

// Never send this directly, except you actually need _trackingAreas.
- (void) _resetTrackingAreas {
    if (_trackingAreas != nil) {
        return;
    }
    NSInteger count;
    BOOL toolTipsAllowed =
        [NSApp isActive] || [self allowsToolTipsWhenApplicationIsInactive];

    NSMutableArray *collectedAreas = [[NSMutableArray alloc] init];
    [[self _backgroundView] _collectTrackingAreasForWindowInto: collectedAreas];
    _trackingAreas = collectedAreas;

    count = [_trackingAreas count];
    while (--count >= 0) {
        NSTrackingArea *area = _trackingAreas[count];

        if ((_cursorRectsDisabled > 0 &&
             [area options] & NSTrackingCursorUpdate) ||
            ([area _isToolTip] && !toolTipsAllowed)) {
            [_trackingAreas removeObjectAtIndex: count];
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

    [_childWindows makeObjectsPerformSelector: @selector(_parentWindowDidClose:)
                                   withObject: self];
    [_drawers makeObjectsPerformSelector: @selector(parentWindowDidClose:)
                              withObject: self];

    [self postNotificationName: NSWindowWillCloseNotification];

    if (_releaseWhenClosed) {
        [self autorelease];
    }
}

- (void) center {
    NSScreen *screen = [self screen];
    if (screen == nil) {
        screen = [NSScreen screens][0];
    }

    NSRect screenFrame = [screen frame];

    NSRect frame = [self frame];
    frame.origin.x = floor(screenFrame.origin.x + screenFrame.size.width / 2 -
                           frame.size.width / 2);
    frame.origin.y = floor(screenFrame.origin.y + screenFrame.size.height / 2 -
                           frame.size.height / 2);

    [self setFrame: frame display: YES];
}

- (void) orderWindow: (NSWindowOrderingMode) place
          relativeTo: (NSInteger) relativeTo {
    // The move notifications are sent under unknown conditions around
    // orderFront: in the Apple AppKit, we do them all the time here until it's
    // figured out. I suspect it is a side effect of off-screen windows being at
    // off-screen coordinates (as opposed to just being hidden).

    [self postNotificationName: NSWindowWillMoveNotification];

    switch (place) {
    case NSWindowAbove:
        [self update];
        _isVisible = YES;
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
            [NSApp changeWindowsItem: self title: _title filename: NO];
        }
        break;

    case NSWindowBelow:
        [self update];
        _isVisible = YES;
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
            [NSApp changeWindowsItem: self title: _title filename: NO];
        }
        break;

    case NSWindowOut:
        _isVisible = NO;
        [[self platformWindow] hideWindow];
        if (![self isKindOfClass: [NSPanel class]]) {
            [NSApp removeWindowsItem: self];
        }
        break;
    }

    [self postNotificationName: NSWindowDidMoveNotification];
}

- (void) orderFrontRegardless {
    NSUnimplementedMethod();
}

- (NSPoint) mouseLocationOutsideOfEventStream {
    return [_platformWindow mouseLocationOutsideOfEventStream];
}

- (NSEvent *) currentEvent {
    return [NSApp currentEvent];
}

- (NSEvent *) nextEventMatchingMask: (NSEventMask) mask {
    return [self nextEventMatchingMask: mask
                             untilDate: [NSDate distantFuture]
                                inMode: NSEventTrackingRunLoopMode
                               dequeue: YES];
}

- (NSEvent *) nextEventMatchingMask: (NSEventMask) mask
                          untilDate: (NSDate *) untilDate
                             inMode: (NSRunLoopMode) mode
                            dequeue: (BOOL) dequeue {
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

- (void) discardEventsMatchingMask: (NSEventMask) mask
                       beforeEvent: (NSEvent *) event {
    NSUnimplementedMethod();
}

- (void) sendEvent: (NSEvent *) event {
    // Some events can cause our window to be destroyed
    // So make sure self lives at least through this current run loop...
    [[self retain] autorelease];

    if (_sheetContext != nil) {
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
                sendEvent: [(NSEvent_CoreGraphics *) event coreGraphicsEvent]];
            return;
        }
    }

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
        [view mouseDown: event];
        _mouseDownLocationInWindow = [event locationInWindow];
        break;
    }

    case NSLeftMouseUp:
        [[_backgroundView hitTest: _mouseDownLocationInWindow] mouseUp: event];
        _mouseDownLocationInWindow = NSMakePoint(NAN, NAN);
        break;

    case NSRightMouseDown:
        _mouseDownLocationInWindow = [event locationInWindow];
        [[_backgroundView hitTest: [event locationInWindow]]
            rightMouseDown: event];
        break;

    case NSRightMouseUp:
        [[_backgroundView hitTest: _mouseDownLocationInWindow]
            rightMouseUp: event];
        _mouseDownLocationInWindow = NSMakePoint(NAN, NAN);
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
        [[_backgroundView hitTest: _mouseDownLocationInWindow]
            mouseDragged: event];
        break;

    case NSRightMouseDragged:
        [[_backgroundView hitTest: _mouseDownLocationInWindow]
            rightMouseDragged: event];
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

    case NSAppKitDefined:
        // Nothing special to do.
        break;

    default:
        shouldValidateToolbarItems = NO;
        NSUnimplementedMethod();
        break;
    }
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
    _draggedTypes = [types copy];
}

- (void) unregisterDraggedTypes {
    [_draggedTypes release];
    _draggedTypes = nil;
}

- (void) dragImage: (NSImage *) image
                at: (NSPoint) location
            offset: (NSSize) offset
             event: (NSEvent *) event
        pasteboard: (NSPasteboard *) pasteboard
            source: (id) source
         slideBack: (BOOL) slideBack {
    [[NSDraggingManager draggingManager] dragImage: image
                                                at: location
                                            offset: offset
                                             event: event
                                        pasteboard: pasteboard
                                            source: source
                                         slideBack: slideBack];
}

- validRequestorForSendType: (NSString *) sendType
                 returnType: (NSString *) returnType {
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
    if (_isVisible == visible) {
        return;
    }
    _isVisible = visible;
    if (visible) {
        [[self platformWindow] showWindowWithoutActivation];
    } else {
        [[self platformWindow] hideWindow];
    }
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

    NSDocument *document = [_windowController document];
    if (document) {
        [document shouldCloseWindowController: _windowController
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
       contextInfo: (void *) context {
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
        zoomedFrame = _savedFrame;
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
        _savedFrame = [self frame];
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

- (void) toggleFullScreen: (id) sender {
    NSWindowStyleMask mask = _styleMask;

    if (mask & NSWindowStyleMaskFullScreen) {
        mask &= ~NSWindowStyleMaskFullScreen;
    } else {
        mask |= NSWindowStyleMaskFullScreen;
    }

    [self setStyleMask: mask];
}

- (void) toggleToolbarShown: (id) sender {
    [_toolbar setVisible: ![_toolbar isVisible]];
    [sender
        setTitle: [NSString stringWithFormat: @"%@ Toolbar",
                                              [_toolbar isVisible] ? @"Hide"
                                                                   : @"Show"]];
}

- (void) runToolbarCustomizationPalette: (id) sender {
    [_toolbar runCustomizationPalette: sender];
}

- (void) keyDown: (NSEvent *) event {
    if ([self performKeyEquivalent: event] == NO) {
        [self interpretKeyEvents: [NSArray arrayWithObject: event]];
    }
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
    if (_defaultButtonCell != nil) {
        [(NSControl *) [_defaultButtonCell controlView] performClick: nil];
    }
}

- (void) _showForActivation {
    if (_hiddenForDeactivate) {
        _hiddenForDeactivate = NO;
        [[self platformWindow] showWindowForAppActivation: _frame];
    }
}

- (void) _hideForDeactivation {
    if ([self hidesOnDeactivate] && [self isVisible] &&
        ![self isMiniaturized]) {
        _hiddenForDeactivate = YES;
        [[self platformWindow] hideWindowForAppDeactivation: _frame];
    }
}

- (void) _forcedHideForDeactivation {
    if ([self isVisible]) {
        _hiddenForDeactivate = YES;
        // _hiddenKeyWindow=[self isKeyWindow];
        [[self platformWindow] hideWindowForAppDeactivation: _frame];
    }
}

- (BOOL) performKeyEquivalent: (NSEvent *) event {
    return [_backgroundView performKeyEquivalent: event];
}

#if 0
- (void) keyDown: (NSEvent*) event {
    if (![self performKeyEquivalent: event]) {
        NSString* characters = [event charactersIgnoringModifiers];

        if ([characters isEqualToString: @" "]) {
            [_firstResponder tryToPerform: @selector(performClick:) with: nil];
        } else if ([characters isEqualToString: @"\t"]) {
            if ([event modifierFlags] & NSShiftKeyMask) {
                [self selectPreviousKeyView: nil];
            } else {
                [self selectNextKeyView: nil];
            }
        }
    }
}
#endif

- (void) _resizeWithOldMenuViewSize: (NSSize) oldSize {
    NSSize backSize = [_backgroundView frame].size;
    NSSize newSize = [_menuView frame].size;
    if ([_menuView isHidden]) {
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
    if ([self hasMainMenu] && _menuView != nil && ![_menuView isHidden]) {
        [_menuView setHidden: YES];
        [self _resizeWithOldMenuViewSize: [_menuView frame].size];
    }
}

- (void) _showMenuViewIfNeeded {
    if ([self hasMainMenu] && _menuView != nil && [_menuView isHidden]) {
        [_menuView setHidden: NO];
        [self _resizeWithOldMenuViewSize: NSZeroSize];
    }
}

- (void) setMenu: (NSMenu *) menu {
    if (_menuView != nil) {
        NSSize oldSize = [_menuView frame].size;
        [_menuView setMenu: menu];
        [self _resizeWithOldMenuViewSize: oldSize];
    }

    [menu retain];
    [_menu release];
    _menu = menu;
}

- (NSMenu *) menu {
    return _menu;
}

- (BOOL) _isActive {
    return _isActive;
}

- (void) _setVisible: (BOOL) visible {
    _isVisible = visible;
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
    return NO;
}

- (BOOL) performDragOperation: (id<NSDraggingInfo>) sender {
    return NO;
}

- (void) concludeDragOperation: (id<NSDraggingInfo>) sender {
    // do nothing
}

- (NSArray *) _draggedTypes {
    return _draggedTypes;
}

- (void) _setSheetOrigin {
    NSWindow *sheet = [_sheetContext sheet];
    NSRect sheetFrame = [sheet frame];
    NSRect frame = [self frame];

    NSPoint origin;
    origin.y = frame.origin.y + (frame.size.height - sheetFrame.size.height);
    origin.x =
        frame.origin.x + floor((frame.size.width - sheetFrame.size.width) / 2);

    if ([self toolbar] != nil) {
        if (_menuView != nil) {
            origin.y -= [_menuView frame].size.height;
        }

        origin.y -= [[[self toolbar] _view] frame].size.height;

        // Depending on the final border types used on the toolbar and the
        // sheets, the sheet placement sometimes looks better with a little
        // "adjustment"....
        origin.y++;
    }

    [sheet setFrameOrigin: origin];
}

- (void) _setSheetOriginAndFront {
    if (_sheetContext != nil) {
        [self _setSheetOrigin];
        [[_sheetContext sheet] orderFront: nil];
    }
}

- (void) _attachSheetContextOrderFrontAndAnimate:
    (NSSheetContext *) sheetContext {
    NSWindow *sheet = [sheetContext sheet];

    if ([sheet styleMask] != NSDocModalWindowMask) {
        [sheet setStyleMask: NSDocModalWindowMask];
    }

    [_sheetContext autorelease];
    _sheetContext = [sheetContext retain];

    [(NSThemeFrame *) [sheet _backgroundView]
        setWindowBorderType: NSWindowSheetBorderType];

    [self _setSheetOrigin];
    NSRect sheetFrame = [sheet frame];
    sheetFrame.origin.y = NSMaxY(sheetFrame);
    sheetFrame.size.height = 0;

    sheet->_isVisible = YES;
    [sheet display];
    [[sheet platformWindow] sheetOrderFrontFromFrame: sheetFrame
                                         aboveWindow: [self platformWindow]];
    [self makeKeyWindow];
}

- (void) _setSheetContext: (NSSheetContext *) sheetContext {
    [sheetContext retain];
    [_sheetContext release];
    _sheetContext = sheetContext;
}

- (NSSheetContext *) _sheetContext {
    return _sheetContext;
}

- (void) _detachSheetContextAnimateAndOrderOut {
    NSWindow *sheet = [_sheetContext sheet];
    NSRect sheetFrame = [sheet frame];
    sheetFrame.origin.y = NSMaxY(sheetFrame);
    sheetFrame.size.height = 0;

    sheet->_isVisible = NO;
    [[sheet platformWindow] sheetOrderOutToFrame: sheetFrame];

    [_sheetContext release];
    _sheetContext = nil;
}

- (void) _flashWindow {
    if ([self _isApplicationWindow]) {
        [[self platformWindow] flashWindow];
    }
}

- (void) platformWindowActivated: (CGWindow *) window
                 displayIfNeeded: (BOOL) displayIfNeeded {
    [NSApp _windowWillBecomeActive: self];

    [self _setSheetOriginAndFront];
    [_childWindows
        makeObjectsPerformSelector: @selector(_parentWindowDidActivate:)
                        withObject: self];
    [_drawers makeObjectsPerformSelector: @selector(parentWindowDidActivate:)
                              withObject: self];

    _isActive = YES;
    if ([self canBecomeKeyWindow]) {
        [self becomeKeyWindow];
    }
    if ([self canBecomeMainWindow] && ![self isMainWindow]) {
        [self becomeMainWindow];
    }

    [_menuView setNeedsDisplay: YES];
    if (displayIfNeeded) {
        [self displayIfNeeded];
    }

    [NSApp _windowDidBecomeActive: self];
    [NSApp updateWindows];
}

- (void) platformWindowDeactivated: (CGWindow *) window
           checkForAppDeactivation: (BOOL) checkForAppDeactivation {
    [NSApp _windowWillBecomeDeactive: self];

    [_childWindows
        makeObjectsPerformSelector: @selector(_parentWindowDidDeactivate:)
                        withObject: self];
    [_drawers makeObjectsPerformSelector: @selector(parentWindowDidDeactivate:)
                              withObject: self];

    _isActive = NO;

    [_menuView setNeedsDisplay: YES];
    [self displayIfNeeded];

    if (checkForAppDeactivation) {
        [NSApp performSelector: @selector(_checkForAppActivation)];
    }

    [NSApp _windowDidBecomeDeactive: self];
    [NSApp updateWindows];
}

- (void) platformWindowDeminiaturized: (CGWindow *) window {
    [self _updatePlatformWindowTitle];
    if (_sheetContext != nil) {
        [[_sheetContext sheet] orderWindow: NSWindowAbove
                                relativeTo: [self windowNumber]];
    }
    [self postNotificationName: NSWindowDidDeminiaturizeNotification];
    [NSApp updateWindows];
}

- (void) platformWindowMiniaturized: (CGWindow *) window {
    _isActive = NO;

    [self _updatePlatformWindowTitle];
    if (_sheetContext != nil) {
        [[_sheetContext sheet] orderWindow: NSWindowOut relativeTo: 0];
    }

    [self postNotificationName: NSWindowDidMiniaturizeNotification];

    if ([self isKeyWindow]) {
        [self resignKeyWindow];
    }

    if ([self isMainWindow]) {
        [self resignMainWindow];
    }

    [_childWindows
        makeObjectsPerformSelector: @selector(_parentWindowDidMiniaturize:)
                        withObject: self];
    [_drawers makeObjectsPerformSelector: @selector(parentWindowDidMiniaturize:)
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
                didSize: (BOOL) didSize {
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

    _makeSureIsOnAScreen = YES;

    [self _setSheetOriginAndFront];
    [_childWindows
        makeObjectsPerformSelector: @selector(_parentWindowDidChangeFrame:)
                        withObject: self];
    [_drawers makeObjectsPerformSelector: @selector(parentWindowDidChangeFrame:)
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
    [_childWindows
        makeObjectsPerformSelector: @selector(_parentWindowDidExitMove:)
                        withObject: self];
    [_drawers makeObjectsPerformSelector: @selector(parentWindowDidExitMove:)
                              withObject: self];
}

- (NSSize) platformWindow: (CGWindow *) window
      frameSizeWillChange: (NSSize) size {
    if (_resizeIncrements.width != 1 || _resizeIncrements.height != 1) {
        NSSize vertical = size;
        NSSize horizontal = size;

        vertical.width = vertical.height *
                         (_resizeIncrements.width / _resizeIncrements.height);
        horizontal.height = horizontal.width * (_resizeIncrements.height /
                                                _resizeIncrements.width);
        if (vertical.width * vertical.height >
            horizontal.width * horizontal.height) {
            size = vertical;
        } else {
            size = horizontal;
        }
    }

    if ([_delegate respondsToSelector: @selector(windowWillResize:toSize:)]) {
        size = [_delegate windowWillResize: self toSize: size];
    }

    return size;
}

- (void) platformWindowWillBeginSizing: (CGWindow *) window {
    [self postNotificationName: NSWindowWillStartLiveResizeNotification];
    _isInLiveResize = YES;
    [_backgroundView viewWillStartLiveResize];
}

- (void) platformWindowDidEndSizing: (CGWindow *) window {
    _isInLiveResize = NO;
    [_backgroundView viewDidEndLiveResize];
    [self postNotificationName: NSWindowDidEndLiveResizeNotification];
}

- (void) platformWindow: (CGWindow *) window needsDisplayInRect: (NSRect) rect {
    [self display];
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

    BOOL cursorIsSet = NO;
    BOOL raiseToolTipWindow = NO;
    NSPoint mousePoint = [self mouseLocationOutsideOfEventStream];

    // This collects only the active ones.
    [self _resetTrackingAreas];

    for (NSTrackingArea *area in _trackingAreas) {
        BOOL mouseWasInside = [area _mouseInside];
        BOOL mouseIsInside = NSPointInRect(mousePoint, [area _rectInWindow]);
        id owner = [area owner];

        if ([area _isToolTip]) {
            NSToolTipWindow *toolTipWindow =
                [NSToolTipWindow sharedToolTipWindow];

            if (![self isKeyWindow] || [self _sheetContext] != nil) {
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
                                   [[area _view] isFlipped])) {
                    mouseIsInside = NO;
                }
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
#if 0
            if (options & NSTrackingCursorUpdate && mouseIsInside) {
                cursorIsSet = YES;
            }
#endif
        }
        // (not) ToolTip

        [area _setMouseInside: mouseIsInside];
    }

    // Exited events need to be sent before entered events
    // The order of the other two is not specific at this time

    for (NSTrackingArea *check in exited) {
        id owner = [check owner];

        if ([check options] & NSTrackingCursorUpdate) {
            [[NSCursor arrowCursor] set];
        }

        if ([owner respondsToSelector: @selector(mouseExited:)]) {
            NSEvent *event = [NSEvent
                enterExitEventWithType: NSMouseExited
                              location: mousePoint
                         modifierFlags: [NSEvent modifierFlags]
                             timestamp: [NSDate timeIntervalSinceReferenceDate]
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
                             timestamp: [NSDate timeIntervalSinceReferenceDate]
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
                             timestamp: [NSDate timeIntervalSinceReferenceDate]
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
    if ([_delegate
            respondsToSelector: @selector(windowWillReturnUndoManager:)]) {
        return [_delegate windowWillReturnUndoManager: self];
    }

    // If this window is associated with a document, return the document's undo
    // manager. Apple's documentation says this is the delegate's
    // responsibility, but that's not how it works in real life.
    if (_undoManager == nil) {
        _undoManager =
            [[[[self windowController] document] undoManager] retain];
    }

    //  If the delegate does not implement this method, the NSWindow creates an
    //  NSUndoManager for the window and all its views. -- seems like some
    //  duplication vs. NSDocument, but oh well..
    if (_undoManager == nil) {
        _undoManager = [[NSUndoManager alloc] init];
        [_undoManager setRunLoopModes: @[
            NSDefaultRunLoopMode, NSModalPanelRunLoopMode,
            NSEventTrackingRunLoopMode
        ]];
    }

    return _undoManager;
}

- (void) undo: (id) sender {
    [[self undoManager] undo];
}

- (void) redo: (id) sender {
    [[self undoManager] redo];
}

- (BOOL) validateMenuItem: (NSMenuItem *) item {
    if ([item action] == @selector(undo:)) {
        return [[self undoManager] canUndo];
    }
    if ([item action] == @selector(redo:)) {
        return [[self undoManager] canRedo];
    }

    return YES;
}

- (void) _attachDrawer: (NSDrawer *) drawer {
    if (_drawers == nil) {
        _drawers = [[NSMutableArray alloc] init];
    }

    [_drawers addObject: drawer];
}

- (void) _detachDrawer: (NSDrawer *) drawer {
    [_drawers removeObject: drawer];
}

- (NSView *) _backgroundView {
    return _backgroundView;
}

- (void) dirtyRect: (NSRect) rect {
    [[self platformWindow] dirtyRect: rect];
}

- (CGSubWindow *) _createSubWindowWithFrame: (CGRect) frame {
    return [_platformWindow createSubWindowWithFrame: frame];
}

+ (BOOL) allowsAutomaticWindowTabbing {
    return _allowsAutomaticWindowTabbing;
}

+ (void) setAllowsAutomaticWindowTabbing: (BOOL) allowsAutomaticWindowTabbing {
    _allowsAutomaticWindowTabbing = allowsAutomaticWindowTabbing;
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
