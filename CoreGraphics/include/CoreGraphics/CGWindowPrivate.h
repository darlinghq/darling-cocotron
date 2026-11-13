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

// The Cocotron half of CGWindow: the platform window class every AppKit backend
// subclasses, its delegate protocol, and the backing store type. None of this
// exists on macOS, and its Foundation and OpenGL dependencies are what forced a
// CoreGraphics module to re-enter Foundation. The CoreGraphics umbrella header
// deliberately does not include this file.

#ifndef COREGRAPHICS_CGWINDOWPRIVATE_H
#define COREGRAPHICS_CGWINDOWPRIVATE_H

#include <CoreGraphics/CGWindow.h>
#import <CoreGraphics/CGSubWindow.h>
#import <CoreGraphics/CGWindowLevel.h>
#ifdef __OBJC__
#import <Foundation/Foundation.h>
#endif
#import <OpenGL/CGLTypes.h>

typedef enum {
    CGSBackingStoreRetained = 0,
    CGSBackingStoreNonretained = 1,
    CGSBackingStoreBuffered = 2
} CGSBackingStoreType;

#ifdef __OBJC__
@class CGEvent;

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

#endif
