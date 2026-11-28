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

#import <AppKit/NSEvent.h>
#import <AppKit/NSFont.h>
#import <AppKit/NSPasteboard.h>
#import <CarbonCore/UnicodeUtilities.h>
#import <CoreFoundation/CFRunLoop.h>
#import <Foundation/Foundation.h>

@class NSColor, NSDraggingManager, NSPrintInfo, NSView, NSSavePanel,
        NSOpenPanel, NSFontTypeface, CGWindow;

@interface NSDisplay : NSObject {
    BOOL _cursorHiddenUntilMouseMoves;
    NSInteger _cursorHideCount;
    BOOL _cursorIsHidden; // what the backend was last told
    NSLock *_mouseDeltaLock;
    double _mouseDeltaX, _mouseDeltaY;
    // The top of the main screen, for the global coordinates of the input's CGEvents; NAN until
    // known, and again when the screens change
    CGFloat _mainScreenMaxY;
    // The screens, made from CoreGraphics' displays and dropped when they change. Guarded by
    // @synchronized(self).
    NSArray *_screens;
    // Whether -_desktopShowsMainMenu looked for a desktop that shows application menus.
    BOOL _desktopMenuProbed;
}

+ (NSDisplay *) currentDisplay;

// The screens are CoreGraphics' active displays (CGGetActiveDisplayList()), the main display first, as
// NSScreen objects that stay the same until the displays change.
- (NSArray *) screens;
// Drops the screens and the main screen's height after the displays changed, so that the next
// -screens reads them again. CoreGraphics reports a change to its reconfiguration callbacks, which
// call this.
- (void) _invalidateScreens;
// Queues NSApplicationDidChangeScreenParametersNotification (merged per run loop pass).
- (void) _postScreenParametersChanged;

- (NSPasteboard *) pasteboardWithName: (NSPasteboardName) name;

- (NSDraggingManager *) draggingManager;

- (CGWindow *) newWindowWithDelegate: (NSWindow *) delegate;

- (NSColor *) colorWithName: (NSString *) colorName;
- (void) _addSystemColor: (NSColor *) result forName: (NSString *) colorName;

- (NSTimeInterval) textCaretBlinkInterval;

- (void) hideCursor;
- (void) unhideCursor;
// Counted hide and unhide, as on macOS: -hideCursor runs on the first hide and -unhideCursor
// when the last one is undone, so an explicit hide survives a pending hide-until-motion.
// +[NSCursor hide], CGDisplayHideCursor and -setCursorHiddenUntilMouseMoves: use these.
- (void) hideCursorCounted;
- (void) unhideCursorCounted;
// Shows the cursor whatever number of hides is pending, and forgets them (CGSForceShowCursor).
- (void) forceShowCursor;
// Hides the cursor until the pointer moves (+[NSCursor setHiddenUntilMouseMoves:]).
// The state is tracked here, so a backend reports motion with -pointerMoved.
- (void) setCursorHiddenUntilMouseMoves: (BOOL) flag;
- (void) pointerMoved;

- (id) cursorWithImage: (NSImage *) image hotSpot: (NSPoint) hotSpot;
- (id) cursorWithName: (NSString *) name;
- (void) setCursor: (id) cursor;

// Called on the main thread before each wait for events of -[NSApplication
// nextEventMatchingMask:...]: a backend handles here what its connection has already read, and
// sends what it has buffered. Does nothing by default.
- (void) willWaitForEvents;

// The NSEvent of a key event the window system's keyboard posted as a CGEvent (see
// -[NSApplication nextEventMatchingMask:...]): which window it is for and where the pointer is in
// that window. NO drops the event (no window of the application can take it). The default is the key
// window.
- (BOOL) windowNumber: (NSInteger *) windowNumber
             location: (NSPoint *) location
          forKeyEvent: (struct __CGEvent *) event;
// The NSEvent made for such a CGEvent, before it is handed to the application: the event to hand over,
// which a display may replace. The default is the event.
- (NSEvent *) keyEventCreated: (NSEvent *) event fromCGEvent: (struct __CGEvent *) cgEvent;
// The window and the pointer location of a mouse event CGEvent that names a window system window
// (kCGSEventNativeWindow): YES when the display knows the window, which is then the window number; the
// location (in the window, in points) only when it also knows it more exactly than the event's global
// location says (*hasLocation).
- (BOOL) windowNumber: (NSInteger *) windowNumber
             location: (NSPoint *) location
          hasLocation: (BOOL *) hasLocation
      forPointerEvent: (struct __CGEvent *) event;
// The NSEvent made for a mouse event CGEvent (not scroll wheel), before it is handed to the application.
- (void) pointerEventCreated: (NSEvent *) event fromCGEvent: (struct __CGEvent *) cgEvent;

// The events are those of HIToolbox's main event queue (NSEventQueue.m). These wait for the next one,
// as -[NSApplication nextEventMatchingMask:...] does but with an NSAppKitSystem event when there is
// none, and remove events, as -[NSApplication discardEventsMatchingMask:beforeEvent:] does.
- (NSEvent *) nextEventMatchingMask: (NSUInteger) mask
                          untilDate: (NSDate *) untilDate
                             inMode: (NSRunLoopMode) mode
                            dequeue: (BOOL) dequeue;

- (void) discardEventsMatchingMask: (NSUInteger) mask
                       beforeEvent: (NSEvent *) event;

// The input of the window system is not posted through the display: the backends of CoreGraphics
// post it as CGEvents, which go through the CoreGraphics event taps and stream (where mouse motion
// is coalesced) into the queue.
// What the application posts (-[NSApplication postEvent:atStart:])
- (void) _postEventWithoutCoalescing: (NSEvent *) event atStart: (BOOL) atStart;

- (BOOL) containsAndRemovePeriodicEvents;

- (NSEventModifierFlags) modifierForDefault: (NSString *) key
                                   standard: (NSEventModifierFlags) standard;

// Whether the host keyboard chord with these modifier flags (as the backend
// reports them for a key press) and this key is delivered to the application
// as the same chord with the Command modifier instead of Control, so that the
// host's Control+C/V/X can be the copy, paste and cut shortcuts. The one place
// that decides this: input conversion and the key equivalents menus show both
// ask it. A key is the character a key equivalent or key event reports.
// NO unless the backend maps Control.
- (BOOL) controlStandsInForCommand: (NSEventModifierFlags) flags
                       keyEquivalent: (unichar) key;

- (void) beep;

- (NSSet *) allFontFamilyNames;
- (NSArray<NSFontTypeface *> *) fontTypefacesForFamilyName: (NSString *) name;
// The installed family a font name no family lists is drawn with; nil when the display substitutes none.
- (NSString *) substituteFamilyName: (NSString *) familyName;
// nil when no installed family is configured for the generic family.
- (NSString *) fontFamilyNameForGenericFamily: (NSString *) generic;

- (CGFloat) scrollerWidth;

- (int) runModalPageLayoutWithPrintInfo: (NSPrintInfo *) printInfo;
- (int) runModalPrintPanelWithPrintInfoDictionary:
        (NSMutableDictionary *) attributes;

- (CGContextRef) graphicsPortForPrintOperationWithView: (NSView *) view
                                             printInfo:
                                                     (NSPrintInfo *) printInfo
                                             pageRange: (NSRange) pageRange;

- (BOOL) implementsCustomPanelForClass: (Class) panelClass;

// The parent window handle of the desktop file chooser portal for a window
// ("x11:<id>" with the id in hex), or nil when the window system has none.
- (NSString *) portalParentHandleForWindow: (NSWindow *) window;

- (int) savePanel: (NSSavePanel *) savePanel
        runModalForDirectory: (NSString *) directory
                        file: (NSString *) file;
- (int) openPanel: (NSOpenPanel *) openPanel
        runModalForDirectory: (NSString *) directory
                        file: (NSString *) file
                       types: (NSArray *) types;

- (NSArray *) orderedWindowNumbers;

- (CGRect) insetRect: (CGRect) frame
        forNativeWindowBorderWithStyle: (NSUInteger) styleMask;
- (CGRect) outsetRect: (CGRect) frame
        forNativeWindowBorderWithStyle: (NSUInteger) styleMask;

// Returns an opaque number of the current keyboard layout.
// This is because apps tend to call TISCopyCurrentKeyboardLayoutInputSource()
// repeatedly and expect to get the same pointer if layout hasn't changed.
- (int) keyboardLayoutId;
- (void) keyboardLayoutName: (NSString **) name
                   fullName: (NSString **) fullName;

// The text input client of `window` moved or changed its text: the platform's
// input method wants to place its candidate window next to the insertion point
// again. Optional; backends without an input method protocol don't implement it.
- (void) textInputCandidateRectChangedInWindow: (NSWindow *) window;

// position is in CoreGraphics' global space (origin at the main screen's top-left
// corner, y down), as CGWarpMouseCursorPosition() takes it.
- (void) warpMouse: (NSPoint) position;
// NO for a backend whose window system connection in CoreGraphics keeps the pointer's state itself (the cursor
// hide count, warping, the disassociated mouse, the deltas): CoreGraphics' pointer functions do not reach the display.
- (BOOL) usesPointerController;
- (BOOL) cursorIsVisible;
// YES disassociates the mouse from the cursor, as
// CGAssociateMouseAndMouseCursorPosition(false) does: the cursor stays where it
// is and mouse motion only produces event deltas. NO restores normal operation.
- (void) grabMouse: (BOOL) doGrab;

// Mouse motion, in points with y growing downwards, that the backend has
// reported since the last call; each call takes what has built up. Backends
// report motion with -accumulateMouseDeltaX:y: when they produce a motion
// event, from any thread. CGGetLastMouseDelta() reads it.
- (void) accumulateMouseDeltaX: (CGFloat) dx y: (CGFloat) dy;
- (void) takeMouseDeltaX: (int32_t *) dx y: (int32_t *) dy;

@end
