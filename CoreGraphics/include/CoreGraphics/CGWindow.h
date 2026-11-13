/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

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

#include <CoreFoundation/CoreFoundation.h>
#import <CoreGraphics/CGSubWindow.h>
#import <CoreGraphics/CGWindowLevel.h>
#import <CoreGraphics/CGImage.h>
#ifdef __OBJC__
#import <Foundation/Foundation.h>
#endif
#import <OpenGL/CGLTypes.h>

extern const CFStringRef kCGWindowAlpha;
extern const CFStringRef kCGWindowBounds;
extern const CFStringRef kCGWindowLayer;
extern const CFStringRef kCGWindowName;
extern const CFStringRef kCGWindowIsOnscreen;
extern const CFStringRef kCGWindowOwnerName;
extern const CFStringRef kCGWindowOwnerPID;
extern const CFStringRef kCGWindowNumber;
extern const CFStringRef kCGWindowStoreType;
extern const CFStringRef kCGWindowSharingState;
extern const CFStringRef kCGWindowMemoryUsage;

typedef CF_ENUM(uint32_t, CGWindowSharingType) {
    kCGWindowSharingNone      = 0,
    kCGWindowSharingReadOnly  = 1,
    kCGWindowSharingReadWrite = 2,
};

typedef CF_ENUM(uint32_t, CGWindowBackingType) {
    kCGBackingStoreRetained    = 0,
    kCGBackingStoreNonretained = 1,
    kCGBackingStoreBuffered    = 2,
};

#ifdef __OBJC__
@class CGEvent;
#endif

typedef enum {
    CGSBackingStoreRetained = 0,
    CGSBackingStoreNonretained = 1,
    CGSBackingStoreBuffered = 2
} CGSBackingStoreType;

typedef CF_OPTIONS(uint32_t, CGWindowListOption) {
    kCGWindowListOptionAll                 = 0,
    kCGWindowListOptionOnScreenOnly        = (1 << 0),
    kCGWindowListOptionOnScreenAboveWindow = (1 << 1),
    kCGWindowListOptionOnScreenBelowWindow = (1 << 2),
    kCGWindowListOptionIncludingWindow     = (1 << 3),
    kCGWindowListExcludeDesktopElements    = (1 << 4),
};

typedef CF_OPTIONS(uint32_t, CGWindowImageOption) {
    kCGWindowImageDefault             = 0,
    kCGWindowImageBoundsIgnoreFraming = (1 << 0),
    kCGWindowImageShouldBeOpaque      = (1 << 1),
    kCGWindowImageOnlyShadows         = (1 << 2),
    kCGWindowImageBestResolution      = (1 << 3),
    kCGWindowImageNominalResolution   = (1 << 4),
};

typedef uint32_t CGWindowID;
#define kCGNullWindowID ((CGWindowID) 0)

#ifdef __OBJC__
@interface CGWindow : NSObject

- (void) setDelegate: delegate;
- delegate;

- (void) invalidate;
- (void) syncDelegateProperties;

// Goes in private interface
//- (O2Context *)cgContext;
- (CGLContextObj) cglContext;

// Per-window rendering scale, or zero to use the screen scale.
- (CGFloat) backingScaleFactor;

- (NSUInteger) styleMask;

- (void) setLevel: (int) value;
- (void) setStyleMask: (NSUInteger) mask;
- (void) setTitle: (NSString *) title;
- (void) setFrame: (CGRect) frame;
- (void) setOpaque: (BOOL) value;
- (void) setAlphaValue: (CGFloat) value;
- (void) setHasShadow: (BOOL) value;

- (void) sheetOrderFrontFromFrame: (NSRect) frame
                      aboveWindow: (CGWindow *) aboveWindow;
- (void) sheetOrderOutToFrame: (NSRect) frame;

- (void) showWindowForAppActivation: (NSRect) frame;
- (void) hideWindowForAppDeactivation: (NSRect) frame;

- (void) hideWindow;
- (void) showWindowWithoutActivation;

+ windowWithWindowNumber: (NSInteger) windowNumber;
// The number of this process's window whose platform window is the given
// one, or 0.
+ (NSInteger) windowNumberForPlatformWindowID: (unsigned long) platformWindowID;

- (NSInteger) windowNumber;
// The window system's identifier of the window (an X11 Window, for example),
// or 0 if it has none.
- (unsigned long) platformWindowID;

- (void) placeAboveWindow: (NSInteger) otherNumber;
- (void) placeBelowWindow: (NSInteger) otherNumber;

- (void) makeKey;
- (void) makeMain;
- (void) captureEvents;
- (void) miniaturize;
- (void) deminiaturize;
- (BOOL) isMiniaturized;

- (void) disableFlushWindow;
- (void) enableFlushWindow;
- (void) flushBuffer;

- (NSPoint) mouseLocationOutsideOfEventStream;

- (void) sendEvent: (CGEvent *) event;

- (void) addEntriesToDeviceDictionary: (NSDictionary *) entries;
- (void) flashWindow;

- (void) addCGLContext: (CGLContextObj) cglContext;
- (void) removeCGLContext: (CGLContextObj) cglContext;

- (void) flushCGLContext: (CGLContextObj) cglContext;

- (CGSubWindow *) createSubWindowWithFrame: (CGRect) frame;

@end

@interface NSObject (CGWindow_delegate)

- (void) platformWindow: (CGWindow *) window
           frameChanged: (NSRect) frame
                didSize: (BOOL) didSize;
- (NSSize) platformWindow: (CGWindow *) window
        frameSizeWillChange: (NSSize) size;
- (void) platformWindowWillBeginSizing: (CGWindow *) window;
- (void) platformWindowDidEndSizing: (CGWindow *) window;
- (void) platformWindowExitMove: (CGWindow *) window;

- (void) platformWindow: (CGWindow *) window needsDisplayInRect: (NSRect) rect;
- (void) platformWindowStyleChanged: (CGWindow *) window;
- (void) platformWindowWillClose: (CGWindow *) window;

- (void) platformWindowWillMove: (CGWindow *) window;
- (void) platformWindowDidMove: (CGWindow *) window;

- (void) platformWindowDeminiaturized: (CGWindow *) window;
- (void) platformWindowMiniaturized: (CGWindow *) window;
- (void) platformWindowActivated: (CGWindow *) window
                 displayIfNeeded: (BOOL) displayIfNeeded;
- (void) platformWindowDeactivated: (CGWindow *) window
           checkForAppDeactivation: (BOOL) checkForApp;

- (void) platformWindowExposed: (CGWindow *) window inRect: (NSRect) rect;

- (BOOL) platformWindowIgnoreModalMessages: (CGWindow *) window;

- (BOOL) platformWindowSetCursorEvent: (CGWindow *) window;

- (void) platformWindowDidInvalidateCGContext: (CGWindow *) window;

- (void) platformWindowShouldZoom: (CGWindow *) window;

@end
#endif

CF_IMPLICIT_BRIDGING_ENABLED

COREGRAPHICS_EXPORT CFArrayRef CGWindowListCopyWindowInfo(CGWindowListOption option, CGWindowID relativeToWindow);
COREGRAPHICS_EXPORT CFArrayRef CGWindowListCreate(CGWindowListOption option, CGWindowID relativeToWindow);
COREGRAPHICS_EXPORT CFArrayRef CGWindowListCreateDescriptionFromArray(CFArrayRef windowArray);
COREGRAPHICS_EXPORT CGImageRef CGWindowListCreateImageFromArray(CGRect screenBounds, CFArrayRef  windowArray, CGWindowImageOption imageOption);

COREGRAPHICS_EXPORT CFArrayRef CGWindowListCreate(CGWindowListOption option, CGWindowID relativeToWindow);
COREGRAPHICS_EXPORT CGImageRef CGWindowListCreateImage(CGRect screenBounds,
                                                       CGWindowListOption listOption,
                                                       CGWindowID windowID,
                                                       CGWindowImageOption imageOption);

CF_IMPLICIT_BRIDGING_DISABLED
