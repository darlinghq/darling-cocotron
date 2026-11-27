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

#import <AppKit/AppKitIvarLayout.h>
#import <AppKit/NSEvent.h>
#import <Foundation/Foundation.h>

@class NSMenu, NSUndoManager, NSTouchBar;

@class NSEvent;

NS_ASSUME_NONNULL_BEGIN

#define _NS_SIDE_NSResponder 0, 1,
// Legacy ObjC ABI (i386): instance size must stay 0x8, Apple's (only
// _nextResponder, at 0x4). Add new state to the extra struct, never as an ivar.
@interface NSResponder : NSObject <NSCoding> {
    id _nextResponder;
    NS_EXTRA_IVARS_BEGIN(NSResponder)
        NSTouchBar *_touchBar;
        NSUserActivity *_userActivity;
    NS_SIDE_IVARS_END(NSResponder)
}

@property (nullable, weak) NSResponder *nextResponder;

@property(nullable, retain) NSTouchBar *touchBar;
- (nullable NSTouchBar *) makeTouchBar;

@property(nullable, nonatomic, retain) NSMenu *menu;
- (nullable NSUndoManager *) undoManager;


- (nullable id) validRequestorForSendType: (null_unspecified NSString *) sendType
                 returnType: (null_unspecified NSString *) returnType;

- (void) interpretKeyEvents: (NSArray<NSEvent *> *) events;
- (BOOL) performKeyEquivalent: (NSEvent *) event;
- (BOOL) tryToPerform: (SEL) action with: (nullable id) object;
- (nullable id) supplementalTargetForAction: (SEL) action sender: (nullable id) sender;
- (void) noResponderFor: (SEL) action;

- (BOOL) acceptsFirstResponder;
- (BOOL) becomeFirstResponder;
- (BOOL) resignFirstResponder;

- (void) flagsChanged: (NSEvent *) event NS_SWIFT_NAME(flagsChanged(with:));

- (NSError *) willPresentError: (NSError *) error;
- (BOOL) presentError: (NSError *) error;
- (void) presentError: (NSError *) error
            modalForWindow: (NSWindow *) window
                  delegate: (nullable id) delegate
        didPresentSelector: (nullable SEL) selector
               contextInfo: (nullable void *) info;

- (void) keyUp: (NSEvent *) event NS_SWIFT_NAME(keyUp(with:));
- (void) keyDown: (NSEvent *) event NS_SWIFT_NAME(keyDown(with:));

- (void) cursorUpdate: (NSEvent *) event NS_SWIFT_NAME(cursorUpdate(with:));
- (void) scrollWheel: (NSEvent *) event NS_SWIFT_NAME(scrollWheel(with:));
- (void) magnifyWithEvent: (NSEvent *) event NS_SWIFT_NAME(magnify(with:));
- (void) rotateWithEvent: (NSEvent *) event NS_SWIFT_NAME(rotate(with:));
- (void) swipeWithEvent: (NSEvent *) event NS_SWIFT_NAME(swipe(with:));
- (void) beginGestureWithEvent: (NSEvent *) event NS_SWIFT_NAME(beginGesture(with:));
- (void) endGestureWithEvent: (NSEvent *) event NS_SWIFT_NAME(endGesture(with:));
- (void) pressureChangeWithEvent: (NSEvent *) event NS_SWIFT_NAME(pressureChange(with:));
- (void) tabletPoint: (NSEvent *) event NS_SWIFT_NAME(tabletPoint(with:));
- (void) tabletProximity: (NSEvent *) event NS_SWIFT_NAME(tabletProximity(with:));
- (void) touchesBeganWithEvent: (NSEvent *) event;
- (void) touchesMovedWithEvent: (NSEvent *) event;
- (void) touchesEndedWithEvent: (NSEvent *) event;
- (void) touchesCancelledWithEvent: (NSEvent *) event;

- (void) mouseUp: (NSEvent *) event NS_SWIFT_NAME(mouseUp(with:));
- (void) mouseDown: (NSEvent *) event NS_SWIFT_NAME(mouseDown(with:));
- (void) mouseMoved: (NSEvent *) event NS_SWIFT_NAME(mouseMoved(with:));
- (void) mouseEntered: (NSEvent *) event NS_SWIFT_NAME(mouseEntered(with:));
- (void) mouseExited: (NSEvent *) event NS_SWIFT_NAME(mouseExited(with:));
- (void) mouseDragged: (NSEvent *) event NS_SWIFT_NAME(mouseDragged(with:));

- (void) rightMouseUp: (NSEvent *) event NS_SWIFT_NAME(rightMouseUp(with:));
- (void) rightMouseDown: (NSEvent *) event NS_SWIFT_NAME(rightMouseDown(with:));
- (void) rightMouseDragged: (NSEvent *) event NS_SWIFT_NAME(rightMouseDragged(with:));
- (void) otherMouseUp: (NSEvent *) event NS_SWIFT_NAME(otherMouseUp(with:));
- (void) otherMouseDown: (NSEvent *) event NS_SWIFT_NAME(otherMouseDown(with:));
- (void) otherMouseDragged: (NSEvent *) event NS_SWIFT_NAME(otherMouseDragged(with:));

// State restoration hooks. AppKit itself declares no restorable key paths, and the
// base implementations encode and restore nothing.
@property(class, readonly, copy) NSArray<NSString *> *restorableStateKeyPaths;
- (void) encodeRestorableStateWithCoder: (NSCoder *) coder;
- (void) encodeRestorableStateWithCoder: (NSCoder *) coder backgroundQueue: (NSOperationQueue *) queue;
- (void) restoreStateWithCoder: (NSCoder *) coder;
- (void) invalidateRestorableState;
// Stored only: this AppKit does not make it current or update it.
@property(nullable, retain) NSUserActivity *userActivity;
- (void) updateUserActivityState: (NSUserActivity *) userActivity;
- (void) restoreUserActivityState: (NSUserActivity *) userActivity;

@end

@interface NSResponder (NSResponder_keyBindings)

- (void) doCommandBySelector: (SEL) selector;

- (void) insertText: (null_unspecified NSString *) text;
- (void) insertNewline: (nullable id) sender;
- (void) insertNewlineIgnoringFieldEditor: (nullable id) sender;
- (void) insertTab: (nullable id) sender;
- (void) insertTabIgnoringFieldEditor: (nullable id) sender;
- (void) insertBacktab: (nullable id) sender;
- (void) insertParagraphSeparator: (nullable id) sender;

- (void) deleteForward: (nullable id) sender;
- (void) deleteBackward: (nullable id) sender;
- (void) deleteWordForward: (nullable id) sender;
- (void) deleteWordBackward: (nullable id) sender;
- (void) deleteToBeginningOfLine: (nullable id) sender;
- (void) deleteToEndOfLine: (nullable id) sender;
- (void) deleteToBeginningOfParagraph: (nullable id) sender;
- (void) deleteToEndOfParagraph: (nullable id) sender;

- (void) transpose: (nullable id) sender;
- (void) transposeWords: (nullable id) sender;

- (void) indent: (nullable id) sender;
- (void) complete: (nullable id) sender;
- (void) yank: (nullable id) sender;

- (void) cancelOperation: (nullable id) sender;
- (void) uppercaseWord: (nullable id) sender;
- (void) lowercaseWord: (nullable id) sender;
- (void) capitalizeWord: (nullable id) sender;
- (void) changeCaseOfLetter: (nullable id) sender;

- (void) setMark: (nullable id) sender;
- (void) deleteToMark: (nullable id) sender;
- (void) selectToMark: (nullable id) sender;
- (void) swapWithMark: (nullable id) sender;

- (void) selectWord: (nullable id) sender;
- (void) selectLine: (nullable id) sender;
- (void) selectParagraph: (nullable id) sender;
- (void) selectAll: (null_unspecified id) sender;
- (void) centerSelectionInVisibleArea: (nullable id) sender;

- (void) moveUpAndModifySelection: (nullable id) sender;
- (void) moveDownAndModifySelection: (nullable id) sender;

- (void) moveForwardAndModifySelection: (nullable id) sender;
- (void) moveBackwardAndModifySelection: (nullable id) sender;
- (void) moveRightAndModifySelection: (nullable id) sender;
- (void) moveLeftAndModifySelection: (nullable id) sender;

- (void) moveWordForwardAndModifySelection: (nullable id) sender;
- (void) moveWordBackwardAndModifySelection: (nullable id) sender;
- (void) moveWordRightAndModifySelection: (nullable id) sender;
- (void) moveWordLeftAndModifySelection: (nullable id) sender;

- (void) moveUp: (nullable id) sender;
- (void) moveDown: (nullable id) sender;
- (void) moveLeft: (nullable id) sender;
- (void) moveRight: (nullable id) sender;
- (void) moveForward: (nullable id) sender;
- (void) moveBackward: (nullable id) sender;

- (void) moveWordForward: (nullable id) sender;
- (void) moveWordBackward: (nullable id) sender;
- (void) moveWordRight: (nullable id) sender;
- (void) moveWordLeft: (nullable id) sender;

- (void) moveToBeginningOfLine: (nullable id) sender;
- (void) moveToEndOfLine: (nullable id) sender;

- (void) moveToBeginningOfParagraph: (nullable id) sender;
- (void) moveToEndOfParagraph: (nullable id) sender;

- (void) moveToBeginningOfDocument: (nullable id) sender;
- (void) moveToEndOfDocument: (nullable id) sender;

- (void) pageUp: (nullable id) sender;
- (void) pageDown: (nullable id) sender;

- (void) scrollPageUp: (nullable id) sender;
- (void) scrollPageDown: (nullable id) sender;
- (void) scrollLineUp: (nullable id) sender;
- (void) scrollLineDown: (nullable id) sender;

- (void) scrollToBeginningOfDocument: (nullable id) sender;
- (void) scrollToEndOfDocument: (nullable id) sender;

- (void) noop: (null_unspecified id) sender;

- (void) moveToEndOfDocumentAndModifySelection: (nullable id) sender; // n.b.:
- (void) moveToBeginningOfDocumentAndModifySelection:
        (nullable id) sender; // these aren't in OSX (can't hurt)

@end

NS_ASSUME_NONNULL_END
