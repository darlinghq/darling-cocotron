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

#import <AppKit/NSMainMenuView.h>
#import <AppKit/NSMenu+Private.h>
#import <AppKit/NSMenuView.h>
#import <AppKit/NSMenuWindow.h>
#import <AppKit/NSRaise.h>

enum {
    kNSMenuKeyboardNavigationNone,
    kNSMenuKeyboardNavigationUp,
    kNSMenuKeyboardNavigationDown,
    kNSMenuKeyboardNavigationLeft,
    kNSMenuKeyboardNavigationRight,
    kNSMenuKeyboardNavigationLetter
};

// The tracking sessions that are running, for -[NSMenu cancelTracking]. Each
// is identified by the menu it tracks (the menu that was popped up, or the menu
// bar); cancelling is a request that the session's event loop looks at after
// every event, and a private event wakes the loop up when it is waiting.
enum { _NSMenuTrackingCancelSubtype = 0x4d43 };

@interface _NSMenuTrackingSession : NSObject {
@public
    NSMenu *menu; // not retained: the session ends before the menu can go
    volatile BOOL cancelRequested;
}
@end

@implementation _NSMenuTrackingSession
@end

static NSLock *trackingSessionsLock;
static NSMutableArray *trackingSessions;

static void _NSMenuTrackingInit(void) {
    static dispatch_once_t once;

    dispatch_once(&once, ^{
        trackingSessionsLock = [[NSLock alloc] init];
        trackingSessions = [[NSMutableArray alloc] init];
    });
}

// Also used by -[NSMenu popUpMenuPositioningItem:atLocation:inView:], which begins its session before
// the menu is updated and shown.
_NSMenuTrackingSession *_NSMenuTrackingBegin(NSMenu *menu) {
    _NSMenuTrackingSession *session = [[_NSMenuTrackingSession alloc] init];

    _NSMenuTrackingInit();
    session->menu = menu;
    [trackingSessionsLock lock];
    [trackingSessions addObject: session];
    [trackingSessionsLock unlock];
    return session;
}

void _NSMenuTrackingEnd(_NSMenuTrackingSession *session) {
    [trackingSessionsLock lock];
    [trackingSessions removeObjectIdenticalTo: session];
    [trackingSessionsLock unlock];
    [session release];
}

BOOL _NSMenuTrackingCancelRequested(_NSMenuTrackingSession *session) {
    return session->cancelRequested;
}

// Ends the tracking of `menu`, if it is being tracked; callable from any
// thread. Nothing happens for a menu that is not being tracked.
void _NSMenuCancelTracking(NSMenu *menu) {
    BOOL found = NO;

    _NSMenuTrackingInit();
    [trackingSessionsLock lock];
    for (_NSMenuTrackingSession *session in trackingSessions) {
        if (session->menu == menu) {
            session->cancelRequested = YES;
            found = YES;
        }
    }
    [trackingSessionsLock unlock];
    if (!found)
        return;

    NSEvent *wake = [NSEvent otherEventWithType: NSAppKitDefined
                                       location: NSZeroPoint
                                  modifierFlags: 0
                                      timestamp: [[NSProcessInfo processInfo] systemUptime]
                                   windowNumber: 0
                                        context: nil
                                        subtype: _NSMenuTrackingCancelSubtype
                                          data1: 0
                                          data2: 0];
    [NSApp postEvent: wake atStart: YES];
}

@implementation NSMenuView

- (void) dealloc {
    [_visibleArray release];
    [super dealloc];
}

- (NSUInteger) itemIndexAtPoint: (NSPoint) point {
    NSInvalidAbstractInvocation();
    return NSNotFound;
}

- (NSUInteger) itemIndexAtPoint: (NSPoint) point rect: (NSRect*) rect {
    NSInvalidAbstractInvocation();
    return NSNotFound;
}

- (NSUInteger) selectedItemIndex {
    return _selectedItemIndex;
}

// Tells the menu's delegate which item is about to be highlighted, nil for none. The index counts the items
// shown. The method is optional.
// https://developer.apple.com/documentation/appkit/nsmenudelegate/menu(_:willhighlight:)
// Shape of the call (delegate lookup, item or nil by index) taken after the SiliconForest cocoa patches, MIT,
// see THIRD-PARTY-NOTICES.md.
- (void) _delegateWillHighlightItemAtIndex: (NSUInteger) itemIndex {
    id delegate = [[self menu] delegate];

    if ([delegate respondsToSelector: @selector(menu:willHighlightItem:)]) {
        NSArray *items = [self visibleItemArray];
        [delegate menu: [self menu]
                willHighlightItem: itemIndex < [items count] ? [items objectAtIndex: itemIndex] : nil];
    }
}

- (void) setSelectedItemIndex: (NSUInteger) itemIndex {
    if (_selectedItemIndex != itemIndex) {
        // The delegate hears of the change before it happens, for the menu bar as for any menu.
        [self _delegateWillHighlightItemAtIndex: itemIndex];
        _selectedItemIndex = itemIndex;
        [self setNeedsDisplay: YES];
        [self displayIfNeeded];
    }
}

// The items as shown, in the order of the selected item index.
- (NSArray *) itemArray {
    return [NSArray arrayWithArray: [self visibleItemArray]];
}

// The items shown: not hidden, and of an item and its alternates only the one
// for the modifier keys held now.
- (NSArray *) visibleItemArray {
    if (_visibleArray == NULL)
        _visibleArray = [[NSMutableArray alloc] init];

    [_visibleArray setArray: [[self menu] _shownItemsWithModifierFlags: [NSEvent modifierFlags]]];
    return _visibleArray;
}

- (NSMenuItem *) itemAtSelectedIndex {
    NSArray *items = [self visibleItemArray];

    if (_selectedItemIndex < [items count])
        return [items objectAtIndex: _selectedItemIndex];

    return nil;
}

- (NSMenuView *) viewAtSelectedIndexPositionOnScreen: (NSScreen *) screen {
    NSInvalidAbstractInvocation();
    return nil;
}

- (void) rightMouseDown: (NSEvent *) event {
    // do nothing
}

- (NSScreen *) _screenForPoint: (NSPoint) point {
    NSArray *screens = [NSScreen screens];
    int i, count = [screens count];

    for (i = 0; i < count; i++) {
        NSScreen *check = [screens objectAtIndex: i];

        if (NSPointInRect(point, [check frame]))
            return check;
    }

    return [screens objectAtIndex: 0]; // should not happen
}

#if 0
#define MENUDEBUG(...) NSLog(__VA_ARGS__)
#else
#define MENUDEBUG(...)
#endif

// This threshold is not really applicable with regular
// menus - but in the event that the popup and regular menu
// logic is merged the behaviour as been replicated here.
// If a user clicks and releases on a menu it should remain
// visible. If a user clicks and holds for a period and then releases
// the current item should be reselected. This threshold is the dividing
// line between those two behaviours.
const NSTimeInterval kMenuInitialClickThreshold = .3f;
const NSTimeInterval kMouseMovementThreshold = .001f;

// The index of the item of this view under the point of a mouse event, or
// NSNotFound if the event is not over this view.
- (NSUInteger) _itemIndexAtEvent: (NSEvent *) event {
    NSPoint point = [[event window] convertBaseToScreen: [event locationInWindow]];
    point = [self convertPoint: [[self window] convertScreenToBase: point]
                      fromView: nil];

    NSRect rect;

    if (!NSMouseInRect(point, [self bounds], [self isFlipped]))
        return NSNotFound;
    return [self itemIndexAtPoint: point rect: &rect];
}

// The menu delegate and notification calls of a tracking session: the menu
// tracking started in this view gets NSMenuDidBeginTrackingNotification and
// NSMenuDidEndTrackingNotification; each menu shown, other than the menu bar
// itself, gets -menuWillOpen: and -menuDidClose: on its delegate.
- (BOOL) _isMenuBar {
    return [self isKindOfClass: [NSMainMenuView class]];
}

// The calls that start a tracking session, in the order macOS makes them:
// the begin notification, then -menuNeedsUpdate: (only for the menu itself:
// a submenu is updated when it opens), then -menuWillOpen:.
- (void) _willBeginTracking {
    NSMenu *menu = [self menu];

    [[NSNotificationCenter defaultCenter]
            postNotificationName: NSMenuDidBeginTrackingNotification
                          object: menu];
    [menu _updateWithoutSubmenus];
    if (![self _isMenuBar] &&
        [[menu delegate] respondsToSelector: @selector(menuWillOpen:)])
        [[menu delegate] menuWillOpen: menu];
}

- (void) _didEndTracking {
    NSMenu *menu = [self menu];

    if (![self _isMenuBar] &&
        [[menu delegate] respondsToSelector: @selector(menuDidClose:)])
        [[menu delegate] menuDidClose: menu];
    [[NSNotificationCenter defaultCenter]
            postNotificationName: NSMenuDidEndTrackingNotification
                          object: menu];
}

- (void) _pushBranch: (NSMenuView *) branch onto: (NSMutableArray *) stack {
    NSMenu *menu = [branch menu];

    [stack addObject: branch];
    if ([[menu delegate] respondsToSelector: @selector(menuWillOpen:)])
        [[menu delegate] menuWillOpen: menu];
}

- (void) _popBranch: (NSMutableArray *) stack {
    NSMenuView *branch = [stack lastObject];
    NSMenu *menu = [branch menu];

    [[branch window] close];
    [stack removeLastObject];
    if ([[menu delegate] respondsToSelector: @selector(menuDidClose:)])
        [[menu delegate] menuDidClose: menu];
}

// Left or Right in the menu opened from a title of the bar closes it and
// opens the menu of the next title that way, wrapping around. NO when that
// title has no menu: the caller then ends the tracking, as a bar tracking with
// no menu open would take the next click.
- (BOOL) _openAdjacentBarMenu: (NSInteger) step
                   onto: (NSMutableArray *) stack
                 screen: (NSScreen *) screen {
    NSUInteger count = [[self itemArray] count];

    [self _popBranch: stack];
    if (count == 0)
        return NO;
    NSUInteger index = [self selectedItemIndex];
    index = index == NSNotFound ? 0 : (index + count + step) % count;
    [self setSelectedItemIndex: index];

    NSMenuView *branch = [self viewAtSelectedIndexPositionOnScreen: screen];
    if (branch == nil)
        return NO;
    [self _pushBranch: branch onto: stack];
    return YES;
}

- (NSMenuItem *) trackForEvent: (NSEvent *) event {
    return [self _trackForEvent: event session: nil];
}

// With a session, the caller has already begun tracking (begin notification,
// update, -menuWillOpen:) and made it cancellable; this ends it.
- (NSMenuItem *) _trackForEvent: (NSEvent *) event session: (_NSMenuTrackingSession *) session {
    NSMenuItem *item = nil;

    enum {
        STATE_FIRSTMOUSEDOWN,
        STATE_MOUSEDOWN,
        STATE_MOUSEUP,
        STATE_EXIT
    } state = STATE_FIRSTMOUSEDOWN;

    // Get the menu management ball rolling
    NSPoint point = [event locationInWindow];
    NSPoint firstPoint = point;
    NSTimeInterval firstTimestamp = [event timestamp];

    // Cascading menus we manage will be pushed and popped on the viewStack
    __block NSMutableArray *viewStack = [NSMutableArray array];

    // Make sure we can put things back the way we found them
    BOOL oldAcceptsMouseMovedEvents = [[self window] acceptsMouseMovedEvents];

    // But while we're dealing with menus we want to track the mouse...
    [[self window] setAcceptsMouseMovedEvents: YES];

    if (session == nil) {
        session = _NSMenuTrackingBegin([self menu]);
        [self _willBeginTracking];
    }

    // And we, of course, are first on the stack
    [viewStack addObject: self];

    [event retain];

    int keyboardNavigationAction = kNSMenuKeyboardNavigationNone;

    BOOL cancelled = NO;
    // Set when a press lands on the title of the item whose menu is open
    // while the menu is sticky; the release over the same title closes the
    // menu.
    NSUInteger titlePressedIndex = NSNotFound;
    NSTimer* delaySubmenu = nil;
    NSRect lastRect = NSMakeRect(0,0,0,0);
    // The view whose coordinate space lastRect is expressed in.
    NSMenuView *lastRectView = nil;

    MENUDEBUG(@"entering outer loop");

    // Start tracking the mouse movements and clicks
    do {
        // Lots of objects are going to come and go as we track the mouse
        // so a tactical autorelease pool keeps a lid on things
        NSAutoreleasePool *pool = [NSAutoreleasePool new];
        int count = [viewStack count];
        NSScreen *screen = [self
                _screenForPoint: [[event window] convertBaseToScreen: point]];

        point = [[event window] convertBaseToScreen: point];

        // We've not pushed any views yet so the screen is where our window is
        if (count == 1) {
            screen = [self _screenForPoint: point];
        }

        if (keyboardNavigationAction == kNSMenuKeyboardNavigationNone) {
            // We're not current dealing with a keyboard event
            // Take a look at the visible menu stack (we're within a big loop so
            // views can come and go and the mouse can wander all over) deepest
            // first
            while (--count >= 0) {

                // get the deepest one
                NSMenuView *checkView = [viewStack objectAtIndex: count];

                // And find out where the mouse is relative to it
                NSPoint checkPoint =
                        [[checkView window] convertScreenToBase: point];

                checkPoint = [checkView convertPoint: checkPoint fromView: nil];

                // If it's inside the menu view
                if (NSMouseInRect(checkPoint, [checkView bounds],
                                  [checkView isFlipped])) {

                    MENUDEBUG(@"found a menu: %@", checkView);

                    // Performance optimization - break if we're still in the same
                    // menu item rect as last time. lastRect is expressed in the
                    // coordinate space of the view that produced it, so it says
                    // nothing about a view we have not measured: without the
                    // check, moving from the menu bar into a submenu keeps
                    // hitting the stale bar rect and breaks out before
                    // itemIndexAtPoint: runs, leaving the submenu with no
                    // selected item.
                    if (checkView == lastRectView &&
                        NSMouseInRect(checkPoint, lastRect, [checkView isFlipped]))
                        break;

                    // Which item is the cursor on top of?
                    NSUInteger itemIndex =
                            [checkView itemIndexAtPoint: checkPoint rect: &lastRect];
                    // A miss can leave lastRect unchanged. Only cache a view
                    // when its hit test actually supplied an item's rectangle.
                    lastRectView = itemIndex == NSNotFound ? nil : checkView;

                    MENUDEBUG(@"found an item index: %u", itemIndex);

                    // The menu bar keeps its open menu while the pointer is over a part of
                    // the bar that has no title: only another title switches menus.
                    if (itemIndex == NSNotFound && [checkView _isMenuBar] &&
                        [checkView selectedItemIndex] != NSNotFound)
                        break;

                    // If it's not the currently selected item
                    if (itemIndex != [checkView selectedItemIndex]) {

                        // This looks like it's dealing with pushed cascading
                        // menu views that are no longer needed because the user
                        // has moved on - so pop them all off.
                        while (count + 1 < [viewStack count]) {
                            NSView *view = [viewStack lastObject];
                            MENUDEBUG(@"popping cascading view: %@", view);
                            [self _popBranch: viewStack];
                        }

                        // And now select the new item
                        [checkView setSelectedItemIndex: itemIndex];

                        if (delaySubmenu) {
                            [delaySubmenu invalidate];
                            [delaySubmenu release];
                            delaySubmenu = nil;
                        }

                        // If it's got a cascading menu then push that on the
                        // stack
                        // Do this with a delay to improve performance - this is what toolkits commonly do
                        double delay = (count == 0) ? 0 : 0.5;
                        delaySubmenu = [[NSTimer timerWithTimeInterval: delay repeats: NO block: ^(NSTimer* timer){

                            NSMenuView *branch;

                            if ((branch = [checkView
                                        viewAtSelectedIndexPositionOnScreen:
                                                screen]) != nil) {
                                MENUDEBUG(@"adding a new cascading view: %@",
                                        branch);
                                [self _pushBranch: branch onto: viewStack];
                            }
                        }] retain];
                        [[NSRunLoop currentRunLoop] addTimer: delaySubmenu
                                                     forMode: NSEventTrackingRunLoopMode];
                    }
                    // And bail out of the while loop - we're in the right place
                    break;
                } else {
                    if (delaySubmenu) {
                        [delaySubmenu invalidate];
                        [delaySubmenu release];
                        delaySubmenu = nil;
                    }

                    lastRect = NSMakeRect(0,0,0,0);
                    lastRectView = nil;
                    
                    // We've wandered off the menu so don't show anything
                    // selected if it's the deepest visible view
                    if (checkView == [viewStack lastObject]) {
                        MENUDEBUG(@"clearing selection in view: %@", checkView);
                        // The mouse is outside of the top menu - be sure no
                        // item is selected anymore
                        [checkView setSelectedItemIndex: NSNotFound];
                    }
                }
            }

            // Looks like we've popped everything so nothing can be selected
            if (count < 0) {
                MENUDEBUG(@"clearing all selection");
                [[viewStack lastObject] setSelectedItemIndex: NSNotFound];
            }
        }

        [event release];

        // Let's take a look at what's come in on the event queue.
        // NSLeftMouseDown has to be in the mask: clicking an item in an
        // already-open menu without moving the pointer produces no motion event,
        // so without the press the hit test never re-runs at the item's
        // coordinates. The state machine below already handles a mouse down.
        event = [[self window]
                nextEventMatchingMask: NSLeftMouseUpMask | NSMouseMovedMask |
                                       NSLeftMouseDraggedMask | NSKeyDownMask |
                                       NSLeftMouseDownMask | NSAppKitDefinedMask |
                                       NSFlagsChangedMask];
        [event retain];

        // -[NSMenu cancelTracking] was called; it also posted an event, so
        // this is reached even while the loop was waiting.
        if (session->cancelRequested) {
            cancelled = YES;
            [pool release];
            break;
        }

        // The modifier keys held choose which of an item and its alternates
        // is shown. The pointer stays where it was: keep the hit test working
        // from its position in the event's window.
        if ([event type] == NSFlagsChanged) {
            point = [event locationInWindow];
            for (NSMenuView *view in viewStack)
                [view setNeedsDisplay: YES];
        }

        if (keyboardNavigationAction != kNSMenuKeyboardNavigationNone) {
            // We didn't enter the mouse handling loop that predecrements count
            // - so do it here...
            count--;
        }
        // Reset the keyboard navigation state
        keyboardNavigationAction = kNSMenuKeyboardNavigationNone;

        // Sometimes we can get key events with no characters (if the user
        // has invoked an accelerator while the menu is open for example)
        if ([event type] == NSKeyDown && [[event characters] length] > 0) {

            NSString *chars = [event characters];
            unichar ch = [chars characterAtIndex: 0];
            switch (ch) {
            case NSUpArrowFunctionKey:
                keyboardNavigationAction = kNSMenuKeyboardNavigationUp;
                break;
            case NSDownArrowFunctionKey:
                keyboardNavigationAction = kNSMenuKeyboardNavigationDown;
                break;
            case NSLeftArrowFunctionKey:
                keyboardNavigationAction = kNSMenuKeyboardNavigationLeft;
                break;
            case NSRightArrowFunctionKey:
                keyboardNavigationAction = kNSMenuKeyboardNavigationRight;
                break;

            case '\r': // Return = select the current item and exit the loop
                MENUDEBUG(@"Selecting current item and exit");
                // The item remembered so far is the one under the pointer
                // before its latest move; the highlighted item of the
                // deepest open menu, picked after the loop, is the one meant.
                item = nil;
                state = STATE_EXIT;
                break;
            case 27: // Escape = pop unless we're done then it's cancel
            {
                // A bar left tracking with no menu open would take the next
                // click: the menu of its title is the outermost one.
                NSUInteger outermost = [self _isMenuBar] ? 2 : 1;

                if ([viewStack count] > outermost) {
                    NSView *view = [viewStack lastObject];
                    MENUDEBUG(@"popping cascading view: %@", view);
                    [self _popBranch: viewStack];
                } else {
                    MENUDEBUG(@"Cancelling");
                    cancelled = YES;
                }
            } break;
            default:
                keyboardNavigationAction = kNSMenuKeyboardNavigationLetter;
                break;
            }

            NSMenuView *activeMenuView = [viewStack lastObject];

            BOOL ignoreEnabledState = NO;
            if ([viewStack count] == 1 &&
                [activeMenuView isKindOfClass: [NSMainMenuView class]]) {
                // For some reason main menu items are disabled - even though
                // they work fine...
                ignoreEnabledState = YES;
                // we're navigating the top menu which has opposite semantics
                // than a regular menu
                switch (keyboardNavigationAction) {
                case kNSMenuKeyboardNavigationDown:
                    keyboardNavigationAction = kNSMenuKeyboardNavigationRight;
                    break;
                case kNSMenuKeyboardNavigationUp:
                    keyboardNavigationAction = kNSMenuKeyboardNavigationLeft;
                    break;
                case kNSMenuKeyboardNavigationLeft:
                    keyboardNavigationAction = kNSMenuKeyboardNavigationUp;
                    break;
                case kNSMenuKeyboardNavigationRight:
                    keyboardNavigationAction = kNSMenuKeyboardNavigationDown;
                    break;
                }
            }

            switch (keyboardNavigationAction) {
            case kNSMenuKeyboardNavigationUp: {
                MENUDEBUG(@"Up...");

                NSUInteger oldIndex = [activeMenuView selectedItemIndex];
                NSArray *items = [activeMenuView itemArray];
                // Look for the next enabled item by search up and wrapping
                // around the bottom
                NSUInteger newIndex = 0;
                if (oldIndex != NSNotFound) {
                    newIndex = oldIndex == 0 ? [items count] - 1 : oldIndex - 1;
                }
                MENUDEBUG(@"oldIndex = %u", oldIndex);
                MENUDEBUG(@"newIndex = %u", newIndex);
                BOOL found = NO;
                while (!found && newIndex != oldIndex) {
                    // Make sure we stop eventually
                    if (oldIndex == NSNotFound) {
                        oldIndex = 0;
                    }
                    // Try and find a new item to select
                    NSMenuItem *item = [items objectAtIndex: newIndex];
                    if ([item isSeparatorItem] == NO &&
                        ((ignoreEnabledState || [item isEnabled]) ||
                         [item hasSubmenu])) {
                        MENUDEBUG(@"selecting item = %@", item);
                        [activeMenuView setSelectedItemIndex: newIndex];
                        found = YES;
                    } else {
                        MENUDEBUG(@"skipping item: %@", item);
                        if (newIndex == 0) {
                            newIndex = [items count] - 1;
                        } else {
                            newIndex--;
                        }
                    }
                }
            } break;
            case kNSMenuKeyboardNavigationDown: {
                MENUDEBUG(@"Down...");
                NSUInteger oldIndex = [activeMenuView selectedItemIndex];
                NSArray *items = [activeMenuView itemArray];
                // Look for the next enabled item by search down and wrapping
                // around to the top
                NSUInteger newIndex = 0;
                if (oldIndex != NSNotFound) {
                    newIndex = oldIndex == [items count] - 1 ? 0 : oldIndex + 1;
                }

                MENUDEBUG(@"oldIndex = %u", oldIndex);
                MENUDEBUG(@"newIndex = %u", newIndex);
                BOOL found = NO;
                while (!found && newIndex != oldIndex) {
                    // Make sure we stop eventually
                    if (oldIndex == NSNotFound) {
                        oldIndex = 0;
                    }
                    // Try and find a new item to select
                    NSMenuItem *item = [items objectAtIndex: newIndex];
                    if ([item isSeparatorItem] == NO &&
                        ((ignoreEnabledState || [item isEnabled]) ||
                         [item hasSubmenu])) {
                        MENUDEBUG(@"selecting item: %u", item);
                        [activeMenuView setSelectedItemIndex: newIndex];
                        found = YES;
                    } else {
                        MENUDEBUG(@"skipping item: %@", item);
                        if (newIndex == [items count] - 1) {
                            newIndex = 0;
                        } else {
                            newIndex++;
                        }
                    }
                }
            } break;
            case kNSMenuKeyboardNavigationLeft:
                MENUDEBUG(@"Left...");
                if ([self _isMenuBar] && [viewStack count] == 2) {
                    if (![self _openAdjacentBarMenu: -1 onto: viewStack screen: screen])
                        cancelled = YES;
                } else if ([viewStack count] > 1) {
                    NSView *view = [viewStack lastObject];
                    MENUDEBUG(@"popping cascading view: %@", view);
                    [self _popBranch: viewStack];
                }
                break;
            case kNSMenuKeyboardNavigationRight: {
                MENUDEBUG(@"Right...");
                NSMenuView *branch = nil;
                // If there's a submenu at the current  selected index
                if ((branch = [activeMenuView
                             viewAtSelectedIndexPositionOnScreen: screen]) !=
                    nil) {
                    MENUDEBUG(@"adding a new cascading view: %@", branch);
                    [self _pushBranch: branch onto: viewStack];
                } else if ([self _isMenuBar] && [viewStack count] == 2) {
                    if (![self _openAdjacentBarMenu: 1 onto: viewStack screen: screen])
                        cancelled = YES;
                } else {
                    // We'll pop it - they're trying to navigate to the next
                    // menu most likely
                    if ([viewStack count] > 1) {
                        NSView *view = [viewStack lastObject];
                        MENUDEBUG(@"popping cascading view: %@", view);
                        [self _popBranch: viewStack];
                    }
                }
            } break;
            case kNSMenuKeyboardNavigationLetter: {
                MENUDEBUG(@"Letter...");
                NSString *letterString =
                        [[NSString stringWithCharacters: &ch
                                                 length: 1] uppercaseString];
                NSUInteger oldIndex = [activeMenuView selectedItemIndex];
                NSArray *items = [activeMenuView itemArray];
                // Look for the next enabled item by search down and wrapping
                // around to the top
                NSUInteger newIndex = 0;
                if (oldIndex != NSNotFound) {
                    newIndex = oldIndex == [items count] - 1 ? 0 : oldIndex + 1;
                }

                MENUDEBUG(@"oldIndex = %u", oldIndex);
                MENUDEBUG(@"newIndex = %u", newIndex);
                BOOL found = NO;
                while (!found && newIndex != oldIndex) {
                    // Make sure we stop eventually
                    if (oldIndex == NSNotFound) {
                        oldIndex = 0;
                    }
                    // Try and find a new item to select
                    NSMenuItem *item = [items objectAtIndex: newIndex];
                    if ((ignoreEnabledState || [item isEnabled] == YES) ||
                        [item hasSubmenu] == YES) {
                        NSRange range =
                                [[item title] rangeOfString: letterString];
                        if (range.location != NSNotFound) {
                            MENUDEBUG(@"selecting item: %u", item);
                            [activeMenuView setSelectedItemIndex: newIndex];
                            found = YES;
                        }
                    }
                    if (!found) {
                        MENUDEBUG(@"skipping item: %@", item);
                        if (newIndex == [items count] - 1) {
                            newIndex = 0;
                        } else {
                            newIndex++;
                        }
                    }
                }
            } break;
            }
        }
        // We use this special AppKitDefined event to let the menu respond to
        // the app deactivation - it *has* to be passed through the event
        // system, unfortunately
        if ([event type] == NSAppKitDefined) {
            if ([event subtype] == NSApplicationDeactivated) {
                MENUDEBUG(@"NSApplicationDeactivated");
                cancelled = YES;
            }
        }

        if (cancelled == NO && [event type] != NSAppKitDefined &&
            [event type] != NSKeyDown && [event type] != NSFlagsChanged) {

            // looks like we can keep rolling

            point = [event locationInWindow];
            // Don't test for "== 0." - we tend to receive some delta with some
            // .000000... values while the mouse doesn't move
            BOOL mouseMoved = ([event type] != NSAppKitDefined) &&
                              (fabs([event deltaX]) > kMouseMovementThreshold ||
                               fabs([event deltaY]) > kMouseMovementThreshold);

            NSMenuView *activeView = nil;

            // We may not have a menuview here - so be cautious - and we may
            // have added a cascading menu so lastObject is also not the right
            // thing to look at - we need to look at the menuview found in the
            // preceeding block (if there was one found - the user could have
            // moused somewhere else entirely remember)
            if (count >= 0) {
                activeView = [viewStack objectAtIndex: count];
            }

            switch (state) {
            case STATE_FIRSTMOUSEDOWN:
                // Let's take a look at the item under the cursor (if there is
                // one)
                item = [activeView itemAtSelectedIndex];

                if ([event type] == NSLeftMouseUp) {
                    // The menu is really active after a mouse up (which means
                    // the menu will stay sticky)... The timestamp is to avoid
                    // false clicks - make sure there's a delay so the user can
                    if ([event timestamp] - firstTimestamp >
                                kMenuInitialClickThreshold &&
                        [viewStack count] == 1 && [item isEnabled]) {
                        MENUDEBUG(@"Handling selected item - exiting");
                        state = STATE_EXIT;
                    } else {
                        MENUDEBUG(@"mouse up - continuing");
                        state = STATE_MOUSEUP;
                    }
                } else if ([event type] == NSLeftMouseDown || mouseMoved) {
                    // .. Or a mouse down (second click after the sticky menu)
                    // or a real move
                    state = STATE_MOUSEDOWN;
                }
                break;

            default:
                item = [activeView itemAtSelectedIndex];
                if ([event type] == NSLeftMouseDown) {
                    // Pressing the title of the open menu again, once the menu
                    // is sticky, closes the menu when the button is released
                    // over that title. A press on another title, or inside
                    // the menu, behaves as before.
                    NSUInteger pressed = [self _itemIndexAtEvent: event];
                    titlePressedIndex = NSNotFound;
                    if (state == STATE_MOUSEUP && pressed != NSNotFound &&
                        pressed == [self selectedItemIndex] &&
                        [viewStack count] > 1 &&
                        [[self itemAtSelectedIndex] hasSubmenu])
                        titlePressedIndex = pressed;
                } else if ([event type] == NSLeftMouseUp &&
                           titlePressedIndex != NSNotFound) {
                    NSUInteger released = [self _itemIndexAtEvent: event];
                    BOOL closes = (released == titlePressedIndex);

                    titlePressedIndex = NSNotFound;
                    if (closes) {
                        MENUDEBUG(@"title of the open menu clicked - closing");
                        cancelled = YES;
                        break;
                    }
                }
                if ([event type] == NSLeftMouseUp) {
                    MENUDEBUG(@"mouseUp on item: %@", item);
                    if (item == nil) {
                        BOOL insideAnyMenu = NO;
                        for (NSMenuView *v in viewStack) {
                            NSPoint p = [[v window] convertScreenToBase: point];
                            p = [v convertPoint: p fromView: nil];
                            if (NSMouseInRect(p, [v bounds], [v isFlipped])) {
                                insideAnyMenu = YES;
                                break;
                            }
                        }
                        if (!insideAnyMenu) {
                            state = STATE_EXIT;
                        } else {
                            state = STATE_MOUSEUP;
                        }
                    } else if ([item hasSubmenu]) {
                        state = STATE_MOUSEUP;
                    } else if ([item isEnabled] && ![item isSeparatorItem]) {
                        state = STATE_EXIT;
                    } else {
                        // Clicking a disabled (grayed out) item or separator does not dismiss the menu
                        state = STATE_MOUSEUP;
                    }
                }
                break;
            }
        }
        [pool release];
    } while (cancelled == NO && state != STATE_EXIT);
    [event release];

    if (delaySubmenu) {
        [delaySubmenu invalidate];
        [delaySubmenu release];
        delaySubmenu = nil;
    }

    MENUDEBUG(@"done with the event loop");

    // If we've got a menu still visible
    if (item == nil && [viewStack count] > 0) {
        // Get the selected item
        item = [[viewStack lastObject] itemAtSelectedIndex];
        MENUDEBUG(@"got the selected item at the top most menu view: %@", item);
    }

    MENUDEBUG(@"removing the visible menu views");
    while ([viewStack count] > 1) {
        [self _popBranch: viewStack];
    }
    [viewStack removeLastObject];
    _NSMenuTrackingEnd(session);
    // QUIRK: when tracking ends with an item highlighted, the delegate is sent -menu:willHighlightItem: with nil
    // after the submenus have closed and before -menuDidClose:. Not documented. Evidence: black-box observation
    // on macOS 26.7.3 (tier 2), a pop-up menu positioned on an item, with and without an open submenu. Whether a
    // call is made when nothing was highlighted was not observed, so none is.
    // Test: appkit-menu-will-highlight-item (test_quirk_highlight_cleared_before_did_close)
    if (_selectedItemIndex != NSNotFound)
        [self _delegateWillHighlightItemAtIndex: NSNotFound];
    [self _didEndTracking];

    _selectedItemIndex = NSNotFound;
    [[self window] setAcceptsMouseMovedEvents: oldAcceptsMouseMovedEvents];
    [self setNeedsDisplay: YES];

    return (!cancelled && [item isEnabled]) ? item : (NSMenuItem *) nil;
}

- (void) mouseDown: (NSEvent *) event {
    BOOL didAccept = [[self window] acceptsMouseMovedEvents];
    NSMenuItem *item;

    [[self window] setAcceptsMouseMovedEvents: YES];
    item = [self trackForEvent: event];
    [[self window] setAcceptsMouseMovedEvents: didAccept];

    if (item != nil) {
        NSMenu *menu = [item menu];
        NSInteger index = [menu indexOfItem: item];

        if (menu != nil && index != NSNotFound)
            [menu performActionForItemAtIndex: index];
        else
            [NSApp sendAction: [item action] to: [item target] from: item];
    }
}

@end
