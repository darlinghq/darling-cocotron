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
    NSMutableArray *_eventQueue;
    NSRecursiveLock *_eventQueueLock;
    BOOL _cursorHiddenUntilMouseMoves;
    NSInteger _cursorHideCount;
    CFRunLoopSourceRef _eventSource;
}

+ (NSDisplay *) currentDisplay;

- (NSArray *) screens;

- (NSPasteboard *) pasteboardWithName: (NSPasteboardName) name;

- (NSDraggingManager *) draggingManager;

- (CGWindow *) newWindowWithDelegate: (NSWindow *) delegate;

- (NSColor *) colorWithName: (NSString *) colorName;
- (void) _addSystemColor: (NSColor *) result forName: (NSString *) colorName;

- (NSTimeInterval) textCaretBlinkInterval;

- (BOOL) activateProcessIdentifier: (pid_t) processIdentifier;

- (void) hideCursor;
- (void) unhideCursor;
// Counted hide and unhide, as on macOS: -hideCursor runs on the first hide and -unhideCursor
// when the last one is undone, so an explicit hide survives a pending hide-until-motion.
// +[NSCursor hide], CGDisplayHideCursor and -setCursorHiddenUntilMouseMoves: use these.
- (void) hideCursorCounted;
- (void) unhideCursorCounted;
// Hides the cursor until the pointer moves (+[NSCursor setHiddenUntilMouseMoves:]).
// The state is tracked here, so a backend reports motion with -pointerMoved.
- (void) setCursorHiddenUntilMouseMoves: (BOOL) flag;
- (void) pointerMoved;

- (id) cursorWithImage: (NSImage *) image hotSpot: (NSPoint) hotSpot;
- (id) cursorWithName: (NSString *) name;
- (void) setCursor: (id) cursor;

- (NSEvent *) nextEventMatchingMask: (NSEventMask) mask
                          untilDate: (NSDate *) untilDate
                             inMode: (NSRunLoopMode) mode
                            dequeue: (BOOL) dequeue;

- (void) discardEventsMatchingMask: (NSEventMask) mask
                       beforeEvent: (NSEvent *) event;

- (void) postEvent: (NSEvent *) event atStart: (BOOL) atStart;

- (BOOL) containsAndRemovePeriodicEvents;

- (NSEventModifierFlags) modifierForDefault: (NSString *) key
                                   standard: (NSEventModifierFlags) standard;

- (void) beep;

- (NSSet *) allFontFamilyNames;
- (NSArray<NSFontTypeface *> *) fontTypefacesForFamilyName: (NSString *) name;
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

- (int) savePanel: (NSSavePanel *) savePanel
        runModalForDirectory: (NSString *) directory
                        file: (NSString *) file;
- (int) openPanel: (NSOpenPanel *) openPanel
        runModalForDirectory: (NSString *) directory
                        file: (NSString *) file
                       types: (NSArray *) types;

// The pointer in Cocoa's global space: points, origin at the main screen's
// bottom-left corner, y up, like screen and window frames.
- (NSPoint) mouseLocation;
- (NSUInteger) currentModifierFlags;
// The buttons held down, as +[NSEvent pressedMouseButtons] reports them: bit 0
// is the left button, bit 1 the right one and bit n the button numbered n.
- (NSUInteger) pressedMouseButtons;

- (NSArray *) orderedWindowNumbers;

- (CGRect) insetRect: (CGRect) frame
        forNativeWindowBorderWithStyle: (NSUInteger) styleMask;
- (CGRect) outsetRect: (CGRect) frame
        forNativeWindowBorderWithStyle: (NSUInteger) styleMask;

- (NSArray *) modesForScreen: (int) screenIndex;
- (NSDictionary *) currentModeForScreen: (int) screenIndex;
- (BOOL) setMode: (NSDictionary *) mode forScreen: (int) screenIndex;

// Returned memory must be free()ed by the caller
- (UCKeyboardLayout *) keyboardLayout: (uint32_t *) byteLength;
// Returns an opaque number of the current keyboard layout.
// This is because apps tend to call TISCopyCurrentKeyboardLayoutInputSource()
// repeatedly and expect to get the same pointer if layout hasn't changed.
- (int) keyboardLayoutId;
- (void) keyboardLayoutName: (NSString **) name
                   fullName: (NSString **) fullName;

// position is in CoreGraphics' global space (origin at the main screen's top-left
// corner, y down), as CGWarpMouseCursorPosition() takes it.
- (void) warpMouse: (NSPoint) position;
// YES disassociates the mouse from the cursor, as
// CGAssociateMouseAndMouseCursorPosition(false) does: the cursor stays where it
// is and mouse motion only produces event deltas. NO restores normal operation.
- (void) grabMouse: (BOOL) doGrab;

@end
