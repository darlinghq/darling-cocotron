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

#import <AppKit/NSApplication.h>
#import <AppKit/NSEvent.h>
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenu+Private.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSMenuView.h>
#import <AppKit/NSMenuWindow.h>
#import <AppKit/NSSubmenuView.h>
#import <AppKit/NSKeyEquivalentMatching.h>
#import <AppKit/NSWindow.h>
#import <AppKit/NSScreen.h>
#import <Foundation/NSProcessInfo.h>
#import <Foundation/NSKeyedArchiver.h>

const NSNotificationName NSMenuWillSendActionNotification = @"NSMenuWillSendActionNotification";
const NSNotificationName NSMenuDidSendActionNotification = @"NSMenuDidSendActionNotification";
const NSNotificationName NSMenuDidBeginTrackingNotification = @"NSMenuDidBeginTrackingNotification";
const NSNotificationName NSMenuDidEndTrackingNotification = @"NSMenuDidEndTrackingNotification";
const NSNotificationName NSMenuDidAddItemNotification = @"NSMenuDidAddItemNotification";
const NSNotificationName NSMenuDidRemoveItemNotification = @"NSMenuDidRemoveItemNotification";
const NSNotificationName NSMenuDidChangeItemNotification = @"NSMenuDidChangeItemNotification";

// Not declared in a public header.
APPKIT_EXPORT const NSNotificationName NSMenuDidCompleteInteractionNotification;
const NSNotificationName NSMenuDidCompleteInteractionNotification = @"NSMenuDidCompleteInteractionNotification";
NSString *const _NSFontMenuName = @"Font";
NSString *const _NSHelpMenuName = @"Help";
NSString *const _NSMainMenuName = @"Application";
NSString *const _NSRecentDocumentsMenuName = @"Recents";
NSString *const _NSServicesMenuName = @"Services";
NSString *const _NSWindowsMenuName = @"Window";

// Private: keys of the options of a pop-up menu shown for a pop-up button
// that a client draws itself: the button's bounds on the screen (an NSValue
// of an NSRect), the offset of the label in it (an NSValue of an NSSize), its
// control size (an NSNumber) and the kind of button drawn (WebKit gives an
// empty string for a button styled by the page). The strings were read from
// the exported constants on macOS 26.7.3 and 10.14.4 (black-box observation).
NSString *const NSPopUpMenuPopupButtonBounds = @"NSPopUpMenuPopupButtonBounds";
NSString *const NSPopUpMenuPopupButtonLabelOffset = @"NSPopUpMenuPopupButtonLabelOffset";
NSString *const NSPopUpMenuPopupButtonSize = @"NSPopUpMenuPopupButtonSize";
NSString *const NSPopUpMenuPopupButtonWidget = @"NSPopUpMenuPopupButtonWidget";

// Defined in NSMenuView.m
extern void _NSMenuCancelTracking(NSMenu *menu);
extern id _NSMenuTrackingBegin(NSMenu *menu);
extern void _NSMenuTrackingEnd(id session);
extern BOOL _NSMenuTrackingCancelRequested(id session);

@implementation NSMenu

NS_EXTRA_SYNTHESIZE_ASSIGN(NSMenu, showsStateColumn, _showsStateColumn, BOOL, showsStateColumn, setShowsStateColumn:)

- (NSUserInterfaceLayoutDirection) userInterfaceLayoutDirection {
    return NS_EXTRA(NSMenu, self)->_hasExplicitUserInterfaceLayoutDirection
                   ? NS_EXTRA(NSMenu, self)->_userInterfaceLayoutDirection
                   : [NSApp userInterfaceLayoutDirection];
}

- (void) setUserInterfaceLayoutDirection: (NSUserInterfaceLayoutDirection) direction {
    NS_EXTRA(NSMenu, self)->_hasExplicitUserInterfaceLayoutDirection = YES;
    NS_EXTRA(NSMenu, self)->_userInterfaceLayoutDirection = direction;
}
NS_EXTRA_SYNTHESIZE_COPY(NSMenu, identifier, _identifier, NSUserInterfaceItemIdentifier, identifier, setIdentifier:)
NS_EXTRA_SYNTHESIZE_RETAIN(NSMenu, appearance, _appearance, NSAppearance *, appearance, setAppearance:)

+ (NSSet *) keyPathsForValuesAffectingEffectiveAppearance {
    return [NSSet setWithObject: @"appearance"];
}

// NSAppearanceCustomization: the menu's own appearance, else the one it
// inherits. Observed on macOS 26.7.3: the application's for a menu that has no
// supermenu and is not attached to anything. GUESS: a submenu or a menu of a
// view or window inherits from its supermenu, view or window first; the
// reference says "the nearest ancestor that has set an appearance" and the
// probe did not reach those cases. Menu views do not
// draw from it yet, and a change of the application's appearance is not
// reported to observers of a menu that has none.
// https://developer.apple.com/documentation/appkit/nsappearancecustomization
- (NSAppearance *) effectiveAppearance {
    NSAppearance *own = [self appearance];

    return own != nil ? own : [NSApp effectiveAppearance];
}

+ (void) popUpContextMenu: (NSMenu *) menu
                withEvent: (NSEvent *) event
                  forView: (NSView *) view
{
    [menu update];
    if ([[menu itemArray] count] > 0) {
        NSPoint point = [event locationInWindow];
        NSWindow *window = [event window];
        NSMenuWindow *menuWindow = [[NSMenuWindow alloc] initWithMenu: menu];
        NSMenuView *menuView = [menuWindow menuView];
        NSMenuItem *item;

        // The view whose contextual menu this is gets told when it opens and
        // when it has closed, before the chosen item's action is sent.
        [view willOpenMenu: menu withEvent: event];

        [menuWindow setReleasedWhenClosed: YES];
        [menuWindow setFrameTopLeftPoint: [window convertBaseToScreen: point]];
        [menuWindow orderFront: nil];

        item = [menuView trackForEvent: event];

        [menuWindow close];

        [view didCloseMenu: menu withEvent: event];

        if (item != nil) {
            NSMenu *owner = [item menu] != nil ? [item menu] : menu;
            NSInteger index = [owner indexOfItem: item];

            if (index != NSNotFound)
                [owner performActionForItemAtIndex: index];
            else
                [NSApp sendAction: [item action] to: [item target] from: item];
        }
    }
}

// Shows the menu as a pop-up menu and tracks it until an item is chosen or
// the menu is dismissed. The top left corner of `item` (which must belong to
// the menu), or of the menu's content when `item` is nil, goes to `location`,
// given in `view`'s coordinates, or in screen coordinates when `view` is nil;
// the menu is then moved as little as needed to keep it on that screen. The
// chosen item's action is sent before this returns. YES when an item was
// chosen, NO when tracking was cancelled.
- (BOOL) popUpMenuPositioningItem: (NSMenuItem *) item
                       atLocation: (NSPoint) location
                           inView: (NSView *) view
{
    NSInteger itemIndex = item == nil ? NSNotFound : [self indexOfItem: item];

    if (item != nil && itemIndex == NSNotFound)
        return NO;

    // As on macOS: the begin notification, then -menuNeedsUpdate:, then
    // -menuWillOpen:, all before the menu is shown; -menuDidClose: and the end
    // notification come from the tracking that follows.
    id session = _NSMenuTrackingBegin(self);

    [[NSNotificationCenter defaultCenter]
            postNotificationName: NSMenuDidBeginTrackingNotification
                          object: self];
    [self _updateWithoutSubmenus];
    if ([self numberOfItems] == 0) {
        _NSMenuTrackingEnd(session);
        [[NSNotificationCenter defaultCenter]
                postNotificationName: NSMenuDidEndTrackingNotification
                              object: self];
        return NO;
    }

    NSPoint screenPoint = location;
    if (view != nil) {
        screenPoint = [view convertPoint: location toView: nil];
        screenPoint = [[view window] convertBaseToScreen: screenPoint];
    }

    NSMenuWindow *menuWindow = [[NSMenuWindow alloc] initWithMenu: self];
    NSMenuView *menuView = [menuWindow menuView];
    NSSize size = [menuWindow frame].size;
    // Where the anchor (the item's top left, or the menu's) is in the window,
    // measured from the window's top left corner.
    NSPoint anchor = NSZeroPoint;
    // The menu view counts the items it shows.
    if (itemIndex != NSNotFound)
        itemIndex = [[menuView itemArray] indexOfObjectIdenticalTo: item];
    if (itemIndex != NSNotFound) {
        NSRect itemRect = [(NSSubmenuView *) menuView rectForItemAtIndex: itemIndex];
        NSPoint topLeft = [menuView convertPoint: itemRect.origin toView: nil];

        anchor = NSMakePoint(topLeft.x, size.height - topLeft.y);
    }
    NSRect frame = NSMakeRect(screenPoint.x - anchor.x, screenPoint.y + anchor.y - size.height, size.width, size.height);

    NSScreen *screen = nil;
    for (NSScreen *candidate in [NSScreen screens])
        if (NSPointInRect(screenPoint, [candidate frame])) {
            screen = candidate;
            break;
        }
    if (screen == nil)
        screen = [NSScreen mainScreen];
    if (screen != nil) {
        NSRect visible = [screen visibleFrame];

        if (NSMaxX(frame) > NSMaxX(visible))
            frame.origin.x = NSMaxX(visible) - frame.size.width;
        if (NSMinX(frame) < NSMinX(visible))
            frame.origin.x = NSMinX(visible);
        if (NSMinY(frame) < NSMinY(visible))
            frame.origin.y = NSMinY(visible);
        if (NSMaxY(frame) > NSMaxY(visible))
            frame.origin.y = NSMaxY(visible) - frame.size.height;
    }

    id<NSMenuDelegate> delegate = [self delegate];
    if ([delegate respondsToSelector: @selector(menuWillOpen:)])
        [delegate menuWillOpen: self];

    // Cancelled from the delegate: nothing was shown.
    if (_NSMenuTrackingCancelRequested(session)) {
        [menuWindow release];
        _NSMenuTrackingEnd(session);
        [[NSNotificationCenter defaultCenter]
                postNotificationName: NSMenuDidEndTrackingNotification
                              object: self];
        return NO;
    }

    [menuWindow setReleasedWhenClosed: YES];
    [menuWindow setFrame: frame display: NO];
    [menuWindow orderFront: nil];

    // Tracking starts from the event that made the menu appear when that was a
    // button press, so that releasing the button over an item chooses it;
    // otherwise (a key press, a timer) from the pointer's current position.
    NSEvent *current = [NSApp currentEvent];
    NSEventType type = NSLeftMouseDown;
    NSTimeInterval timestamp = [[NSProcessInfo processInfo] systemUptime];
    switch ([current type]) {
    case NSLeftMouseDown:
    case NSRightMouseDown:
    case NSOtherMouseDown:
        type = [current type];
        timestamp = [current timestamp];
        break;
    default:
        break;
    }
    NSEvent *start = [NSEvent mouseEventWithType: type
                                        location: [menuWindow convertScreenToBase: [NSEvent mouseLocation]]
                                   modifierFlags: 0
                                       timestamp: timestamp
                                    windowNumber: [menuWindow windowNumber]
                                         context: nil
                                     eventNumber: 0
                                      clickCount: 1
                                        pressure: 0];

    NSMenuItem *chosen = [menuView _trackForEvent: start session: session];

    [menuWindow close];

    if (chosen == nil)
        return NO;

    NSMenu *owner = [chosen menu] != nil ? [chosen menu] : self;
    NSInteger index = [owner indexOfItem: chosen];

    if (index != NSNotFound)
        [owner performActionForItemAtIndex: index];
    else
        [NSApp sendAction: [chosen action] to: [chosen target] from: chosen];
    return YES;
}

// Ends the tracking of this menu, when it is the menu being tracked (a pop-up
// menu, or the menu bar), as if the user had dismissed it: no item is chosen,
// so a pop-up menu's popUpMenuPositioningItem:atLocation:inView: returns NO,
// and NSMenuDidEndTrackingNotification is posted. Animations do not exist
// here, so both variants end the tracking the same way.
- (void) cancelTracking {
    _NSMenuCancelTracking(self);
}

- (void) cancelTrackingWithoutAnimation {
    _NSMenuCancelTracking(self);
}

// The menu bar is visible unless the application's presentation options hide
// it (or auto-hide it).
+ (BOOL) menuBarVisible {
    NSApplicationPresentationOptions options = [NSApp presentationOptions];

    return (options & (NSApplicationPresentationHideMenuBar |
                       NSApplicationPresentationAutoHideMenuBar)) == 0;
}

// The visibility is the presentation options: NO replaces them all with a
// hidden Dock and menu bar (the options require the Dock to be hidden too),
// YES replaces them with the default ones, as on macOS.
+ (void) setMenuBarVisible: (BOOL) visible {
    [NSApp setPresentationOptions: visible ? NSApplicationPresentationDefault
                                           : (NSApplicationPresentationHideDock |
                                              NSApplicationPresentationHideMenuBar)];
}

+ (NSZone *) menuZone {
    return NSDefaultMallocZone();
}

- (void) encodeWithCoder: (NSCoder *) coder {
    [coder encodeObject: _title forKey: @"NSTitle"];
    [coder encodeObject: NS_EXTRA(NSMenu, self)->_name forKey: @"NSName"];
    [coder encodeObject: NS_EXTRA(NSMenu, self)->_itemArray forKey: @"NSMenuItems"];
    [coder encodeBool: !NS_EXTRA(NSMenu, self)->_autoenablesItems forKey: @"NSNoAutoenable"];
    if (NS_EXTRA(NSMenu, self)->_identifier != nil)
        [coder encodeObject: NS_EXTRA(NSMenu, self)->_identifier forKey: @"NSMenuIdentifier"];
}

- (void) setMenuChangedMessagesEnabled: (BOOL) flag {
    NSLog(@"-[NSMenu setMenuChangedMessagesEnabled not implemented]");
}

- initWithCoder: (NSCoder *) coder {
    NS_EXTRA(NSMenu, self)->_showsStateColumn = YES;

    if ([coder allowsKeyedCoding]) {
        NSKeyedUnarchiver *keyed = (NSKeyedUnarchiver *) coder;

        _supermenu = [keyed decodeObjectForKey: @"NSMenu"];
        _title = [[keyed decodeObjectForKey: @"NSTitle"] copy];
        NS_EXTRA(NSMenu, self)->_name = [[keyed decodeObjectForKey: @"NSName"] copy];

        NS_EXTRA(NSMenu, self)->_itemArray = [[NSMutableArray alloc]
                initWithArray: [keyed decodeObjectForKey: @"NSMenuItems"]];
        NS_EXTRA(NSMenu, self)->_autoenablesItems = ![keyed decodeBoolForKey: @"NSNoAutoenable"];
        // The identifier applications look their menus up by (nibs and archives
        // store it under this key on macOS).
        NS_EXTRA(NSMenu, self)->_identifier = [[keyed decodeObjectForKey: @"NSMenuIdentifier"] copy];
    } else {
        // One layout for every class version, as recorded from Mac archives: a flag word
        // (bit 31: no automatic enabling of items, bit 29: no state column), the title,
        // the item array and the name.
        int flags;

        [coder decodeValuesOfObjCTypes: "i@@@", &flags, &_title, &NS_EXTRA(NSMenu, self)->_itemArray, &NS_EXTRA(NSMenu, self)->_name];

        NS_EXTRA(NSMenu, self)->_autoenablesItems = !(flags & 0x80000000);
        NS_EXTRA(NSMenu, self)->_showsStateColumn = !(flags & 0x20000000);

        NSMutableArray *items = [NS_EXTRA(NSMenu, self)->_itemArray isKindOfClass: [NSArray class]] ? [NS_EXTRA(NSMenu, self)->_itemArray mutableCopy]
                                                                           : [[NSMutableArray alloc] init];
        [NS_EXTRA(NSMenu, self)->_itemArray release];
        NS_EXTRA(NSMenu, self)->_itemArray = items;
    }
    // The items do not archive their menu (a nib does not store it either): the menu that
    // decoded them is the one they belong to, as if they had been added to it.
    for (NSMenuItem *item in NS_EXTRA(NSMenu, self)->_itemArray) {
        [item performSelector: @selector(_setMenu:) withObject: self];
        [[item submenu] setSupermenu: self];
    }
    return self;
}

- initWithTitle: (NSString *) title {
    _title = [title copy];
    NS_EXTRA(NSMenu, self)->_itemArray = [NSMutableArray new];
    NS_EXTRA(NSMenu, self)->_autoenablesItems = YES;
    NS_EXTRA(NSMenu, self)->_showsStateColumn = YES;
    return self;
}

- init {
    return [self initWithTitle: @""];
}

- (void) dealloc {
    [_title release];
    [NS_EXTRA(NSMenu, self)->_name release];
    [NS_EXTRA(NSMenu, self)->_itemArray makeObjectsPerformSelector: @selector(_setMenu:)
                                withObject: nil];
    [NS_EXTRA(NSMenu, self)->_itemArray release];
    [NS_EXTRA(NSMenu, self)->_identifier release];
    [NS_EXTRA(NSMenu, self)->_appearance release];
    NS_EXTRA_FREE(NSMenu, self);
    [super dealloc];
}

- copyWithZone: (NSZone *) zone {
    NSMenu *copy = NSCopyObject(self, 0, zone);
    NS_EXTRA_COPY(NSMenu, copy, self);
    NS_EXTRA(NSMenu, copy)->_identifier =
        [NS_EXTRA(NSMenu, self)->_identifier copyWithZone: zone];
    // Observed on macOS 26.7.3: a copy keeps the appearance, as it keeps the identifier.
    [NS_EXTRA(NSMenu, copy)->_appearance retain];
    // QUIRK: a copy of a submenu has no supermenu. Not documented. Evidence: black-box observation on macOS
    // 26.7.3 (tier 2): the supermenu of a copy of a submenu, and of a copy of a menu with a supermenu, was nil.
    // Test: appkit-menu-appearance (test_copy_of_a_hierarchy)
    copy->_supermenu = nil;

    copy->_title = [_title copyWithZone: zone];
    NS_EXTRA(NSMenu, copy)->_name = [NS_EXTRA(NSMenu, self)->_name copyWithZone: zone];
    NS_EXTRA(NSMenu, copy)->_itemArray = [[NSMutableArray alloc] init];
    for (NSMenuItem *item in NS_EXTRA(NSMenu, self)->_itemArray) {
        [copy addItem: [[item copyWithZone: zone] autorelease]];
    }

    return copy;
}

- (NSMenu *) supermenu {
    return _supermenu;
}

- (NSString *) title {
    return _title;
}

- (NSInteger) numberOfItems {
    return [NS_EXTRA(NSMenu, self)->_itemArray count];
}

// The size of the pop-up form of the menu: the one its view lays out for the visible items.
- (NSSize) size {
    NSSubmenuView *view = [[NSSubmenuView alloc] initWithMenu: self];
    NSSize result = [view frame].size;

    [view release];
    return result;
}

- (NSArray *) itemArray {
    return [NSArray arrayWithArray: NS_EXTRA(NSMenu, self)->_itemArray];
}

- (void) setItemArray: (NSArray *) itemArray {
    for (NSMenuItem *item in itemArray)
        if ([item menu] != nil && [item menu] != self)
            [NSException raise: NSInternalInconsistencyException
                        format: @"Item to be inserted into menu already is in another menu: %@", item];
    NSArray *items = [[itemArray copy] autorelease];
    [self removeAllItems];
    for (NSMenuItem *item in items)
        [self addItem: item];
}

- (void) _setItemArray: itemArray {
    if (NS_EXTRA(NSMenu, self)->_itemArray != itemArray) {
        [NS_EXTRA(NSMenu, self)->_itemArray release];
        NS_EXTRA(NSMenu, self)->_itemArray = [itemArray retain];
    }
}

- (BOOL) autoenablesItems {
    return NS_EXTRA(NSMenu, self)->_autoenablesItems;
}

- (NSMenuItem *) itemAtIndex: (NSInteger) index {
    return [NS_EXTRA(NSMenu, self)->_itemArray objectAtIndex: index];
}

- (NSMenuItem *) itemWithTag: (NSInteger) tag {
    NSInteger i, count = [NS_EXTRA(NSMenu, self)->_itemArray count];

    for (i = 0; i < count; i++) {
        NSMenuItem *item = [NS_EXTRA(NSMenu, self)->_itemArray objectAtIndex: i];

        if ([item tag] == tag)
            return item;
    }

    return nil;
}

- (NSMenuItem *) itemWithTitle: (NSString *) title {
    NSInteger i, count = [NS_EXTRA(NSMenu, self)->_itemArray count];

    for (i = 0; i < count; i++) {
        NSMenuItem *item = [NS_EXTRA(NSMenu, self)->_itemArray objectAtIndex: i];

        if ([[item title] isEqualToString: title])
            return item;
    }

    return nil;
}

- (NSInteger) indexOfItem: (NSMenuItem *) item {
    return [NS_EXTRA(NSMenu, self)->_itemArray indexOfObjectIdenticalTo: item];
}

- (NSInteger) indexOfItemWithTag: (NSInteger) tag {
    NSInteger i, count = [NS_EXTRA(NSMenu, self)->_itemArray count];

    for (i = 0; i < count; ++i)
        if ([[NS_EXTRA(NSMenu, self)->_itemArray objectAtIndex: i] tag] == tag)
            return i;

    return -1;
}

- (NSInteger) indexOfItemWithTitle: (NSString *) title {
    NSInteger i, count = [NS_EXTRA(NSMenu, self)->_itemArray count];

    for (i = 0; i < count; i++)
        if ([[[NS_EXTRA(NSMenu, self)->_itemArray objectAtIndex: i] title] isEqualToString: title])
            return i;

    return -1;
}

- (NSInteger) indexOfItemWithRepresentedObject: object {
    NSInteger i, count = [NS_EXTRA(NSMenu, self)->_itemArray count];

    for (i = 0; i < count; i++)
        if ([[(NSMenuItem *) [NS_EXTRA(NSMenu, self)->_itemArray objectAtIndex: i] representedObject]
                    isEqual: object])
            return i;

    return -1;
}

// needed this for NSApplication windowsMenu stuff, so i did 'em all..
- (NSInteger) indexOfItemWithTarget: (id) target andAction: (SEL) action {
    NSInteger i, count = [NS_EXTRA(NSMenu, self)->_itemArray count];

    for (i = 0; i < count; ++i) {
        NSMenuItem *item = [NS_EXTRA(NSMenu, self)->_itemArray objectAtIndex: i];

        if ([item target] == target) {
            if (action == NULL)
                return i;
            else if ([item action] == action)
                return i;
        }
    }

    return -1;
}

- (NSInteger) indexOfItemWithSubmenu: (NSMenu *) submenu {
    NSInteger i, count = [NS_EXTRA(NSMenu, self)->_itemArray count];

    for (i = 0; i < count; ++i)
        if ([[NS_EXTRA(NSMenu, self)->_itemArray objectAtIndex: i] submenu] == submenu)
            return i;

    return -1;
}

- (void) setSupermenu: (NSMenu *) value {
    _supermenu = value;
}

- (void) setTitle: (NSString *) title {
    title = [title copy];
    [_title release];
    _title = title;
}

- (void) setAutoenablesItems: (BOOL) flag {
    NS_EXTRA(NSMenu, self)->_autoenablesItems = flag;
}

// Tells observers that the structure of the menu changed. The index is
// the position of the item concerned, as documented for the notifications.
- (void) _postItemNotification: (NSNotificationName) name
                       atIndex: (NSInteger) index
{
    [[NSNotificationCenter defaultCenter]
            postNotificationName: name
                          object: self
                        userInfo: @{
                            @"NSMenuItemIndex" : [NSNumber numberWithInteger: index]
                        }];
}

- (void) addItem: (NSMenuItem *) item {
    [item performSelector: @selector(_setMenu:) withObject: self];
    [NS_EXTRA(NSMenu, self)->_itemArray addObject: item];
    [self _postItemNotification: NSMenuDidAddItemNotification
                        atIndex: [NS_EXTRA(NSMenu, self)->_itemArray count] - 1];
}

- (NSMenuItem *) addItemWithTitle: (NSString *) title
                           action: (SEL) action
                    keyEquivalent: (NSString *) keyEquivalent
{
    NSMenuItem *item =
            [[[NSMenuItem alloc] initWithTitle: title
                                        action: action
                                 keyEquivalent: keyEquivalent] autorelease];

    [self addItem: item];

    return item;
}

- (void) removeAllItems {
    while ([NS_EXTRA(NSMenu, self)->_itemArray count] > 0)
        [self removeItem: [NS_EXTRA(NSMenu, self)->_itemArray lastObject]];
}

- (void) removeItem: (NSMenuItem *) item {
    NSInteger index = [NS_EXTRA(NSMenu, self)->_itemArray indexOfObjectIdenticalTo: item];

    [item performSelector: @selector(_setMenu:) withObject: nil];
    [NS_EXTRA(NSMenu, self)->_itemArray removeObjectIdenticalTo: item];
    if (index != NSNotFound)
        [self _postItemNotification: NSMenuDidRemoveItemNotification
                            atIndex: index];
}

- (void) removeItemAtIndex: (NSInteger) index {
    [self removeItem: [NS_EXTRA(NSMenu, self)->_itemArray objectAtIndex: index]];
}

- (void) insertItem: (NSMenuItem *) item atIndex: (NSInteger) index {
    [item performSelector: @selector(_setMenu:) withObject: self];
    [NS_EXTRA(NSMenu, self)->_itemArray insertObject: item atIndex: index];
    [self _postItemNotification: NSMenuDidAddItemNotification atIndex: index];
}

- (NSMenuItem *) insertItemWithTitle: (NSString *) title
                              action: (SEL) action
                       keyEquivalent: (NSString *) keyEquivalent
                             atIndex: (NSInteger) index
{
    NSMenuItem *item =
            [[[NSMenuItem alloc] initWithTitle: title
                                        action: action
                                 keyEquivalent: keyEquivalent] autorelease];

    [self insertItem: item atIndex: index];

    return item;
}

- (void) setSubmenu: (NSMenu *) submenu forItem: (NSMenuItem *) item {
    [item setSubmenu: submenu];
}

BOOL itemIsEnabled(NSMenuItem *item) {
    BOOL enabled = NO;

    if ([item action] != NULL) {
        id target = [item target];

        target = [NSApp targetForAction: [item action]
                                     to: [item target]
                                   from: nil];

        if ((target == nil) || ![target respondsToSelector: [item action]]) {
            enabled = NO;
        } else if ([target respondsToSelector: @selector(validateMenuItem:)]) {
            enabled = [target validateMenuItem: item];
        } else if ([target respondsToSelector: @selector
                           (validateUserInterfaceItem:)]) { // New validation
                                                            // scheme
            enabled = [target validateUserInterfaceItem: item];
        } else {
            enabled = YES;
        }
    }

    return enabled;
}

// QUIRK: -update validates the items of the menu and its submenus but does not send -menuNeedsUpdate: to the
// delegates; that message comes only when the menu is about to be shown (tracking, pop up). A delegate
// that calls -update on its menu from -menuNeedsUpdate: therefore does not recurse. Not documented.
// Evidence: black-box observation on macOS 26.7.3 and 10.14.4 (tier 2, x86_64 and i386, mac-probes p799): a
// menu and its submenu whose delegates count -menuNeedsUpdate: receive none through -update, also not
// as the main menu, nor through performKeyEquivalent: or a Command key event, while validateMenuItem: is
// sent by -update, and a delegate calling -update in -menuNeedsUpdate: is never re-entered.
// Test: appkit-menu-update-reentrancy
- (void) update {
    [self _validateItems];

    for (NSMenuItem *item in [NSArray arrayWithArray: NS_EXTRA(NSMenu, self)->_itemArray])
        [[item submenu] update];
}

// The delegate's -menuNeedsUpdate:, which may add, remove or change items.
static void askDelegateToUpdate(NSMenu *menu) {
    id delegate = NS_EXTRA(NSMenu, menu)->_delegate;

    if ([delegate respondsToSelector: @selector(menuNeedsUpdate:)])
        [delegate menuNeedsUpdate: menu];
}

// Brings the enabled state of one item in line with its validation, when the menu enables its items itself,
// and returns the result of the validation (the item's own state when the menu does not).
static BOOL validateItem(NSMenu *menu, NSMenuItem *item) {
    if (!NS_EXTRA(NSMenu, menu)->_autoenablesItems)
        return [item isEnabled];

    BOOL enabled = itemIsEnabled(item) ? YES : NO;
    BOOL currentlyEnabled = [item isEnabled] ? YES : NO;

    if (enabled != currentlyEnabled &&
        ![item _binderForBinding: @"enabled" create: NO]) {
        [item setEnabled: enabled];
        [menu itemChanged: item];
    }
    return enabled;
}

// The delegates -menuNeedsUpdate: and the validation of this menus own
// items; a submenu is brought up to date when it is shown.
- (void) _updateWithoutSubmenus {
    askDelegateToUpdate(self);
    [self _validateItems];
}

// The validation of this menus own items, without asking the delegate.
- (void) _validateItems {
    NSInteger i, count = [NS_EXTRA(NSMenu, self)->_itemArray count];

    for (i = 0; i < count; i++)
        validateItem(self, [NS_EXTRA(NSMenu, self)->_itemArray objectAtIndex: i]);
}

- (void) itemChanged: (NSMenuItem *) item {
    NSInteger index = [NS_EXTRA(NSMenu, self)->_itemArray indexOfObjectIdenticalTo: item];

    if (index != NSNotFound)
        [self _postItemNotification: NSMenuDidChangeItemNotification
                            atIndex: index];
}

// Sends the action of an enabled item the way a choice made in the menu does,
// without updating or validating the menu first. A disabled item does nothing.
- (void) performActionForItemAtIndex: (NSInteger) index {
    NSMenuItem *item = [self itemAtIndex: index];

    if (![item isEnabled])
        return;

    NSDictionary *userInfo = @{@"MenuItem" : item};
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

    [center postNotificationName: NSMenuWillSendActionNotification
                          object: self
                        userInfo: userInfo];
    [NSApp sendAction: [item action] to: [item target] from: item];
    [center postNotificationName: NSMenuDidSendActionNotification
                          object: self
                        userInfo: userInfo];
}

// Asks the delegate of this menu, then those of the submenus below it, in order, whether it has a key
// equivalent for the event of its own (-menuHasKeyEquivalent:forEvent:target:action:). The first to answer
// YES has its action sent to its target, from the menu it belongs to, and ends the search.
- (BOOL) _delegateHandlesKeyEquivalent: (NSEvent *) event {
    id delegate = NS_EXTRA(NSMenu, self)->_delegate;

    if ([delegate respondsToSelector: @selector(menuHasKeyEquivalent:forEvent:target:action:)]) {
        id target = nil;
        SEL action = NULL;

        if ([delegate menuHasKeyEquivalent: self forEvent: event target: &target action: &action]) {
            if (action != NULL)
                [NSApp sendAction: action to: target from: self];
            return YES;
        }
    }

    for (NSMenuItem *item in [NSArray arrayWithArray: NS_EXTRA(NSMenu, self)->_itemArray]) {
        if ([[item submenu] _delegateHandlesKeyEquivalent: event])
            return YES;
    }
    return NO;
}

// QUIRK: the search for a key equivalent never sends -menuNeedsUpdate: to the delegates. It asks them for
// -menuHasKeyEquivalent:forEvent:target:action: first (this menu's delegate and those below it, then again by each
// submenu that is searched), then validates the items of the menu that enables its items itself, then walks them
// in order, a submenu through its own -performKeyEquivalent:. So a delegate that changes the key equivalents of
// items when it updates has not done so yet. Not documented. Evidence: black-box observation on macOS 26.7.3
// (tier 2), 22 scenarios including delegates that rewrite a key and delegates that answer; the order of the calls
// is the one the scenarios of the test pin.
// Test: appkit-menu-key-equivalent-after-update (test_quirk_key_equivalent_search_*)
- (BOOL) performKeyEquivalent: (NSEvent *) event {
    if ([self _delegateHandlesKeyEquivalent: event])
        return YES;

    // The items are validated first, and an action or a validation may change the menu: the walk goes over a copy.
    NSArray *items = [NSArray arrayWithArray: NS_EXTRA(NSMenu, self)->_itemArray];

    NSMutableArray *validated = [NSMutableArray arrayWithCapacity: [items count]];

    for (NSMenuItem *item in items)
        [validated addObject: [NSNumber numberWithBool: validateItem(self, item)]];

    for (NSMenuItem *item in items) {
        if (NSKeyEquivalentMatchesEvent([item keyEquivalent],
                                        [item keyEquivalentModifierMask], event)) {
            // With automatic enabling the validation above brought isEnabled in line with it. Without it only
            // isEnabled counts and validation is not consulted.
            BOOL enabled = [item isEnabled];
            if (enabled && NS_EXTRA(NSMenu, self)->_autoenablesItems)
                enabled = [[validated objectAtIndex: [items indexOfObjectIdenticalTo: item]] boolValue];
            if (enabled)
                [NSApp sendAction: [item action]
                               to: [item target]
                             from: item];
            // QUIRK: a matching item consumes the key equivalent even when it
            // is disabled or has no target to perform the action; the
            // result is YES in every case. Not documented. Evidence:
            // black-box observation on macOS 27 (tier 2), recorded as
            // MC11.12 and MC11.13 of the upstreaming evidence notes.
            // Test: appkit-menu-key-equivalents.m
            // (disabled_matching_item_consumes_the_key)
            return YES;
        }

        if ([[item submenu] performKeyEquivalent: event])
            return YES;
    }

    return NO;
}

- (void) setDelegate: (id<NSMenuDelegate>) object {
    NS_EXTRA(NSMenu, self)->_delegate = object;
}

- (id<NSMenuDelegate>) delegate {
    return NS_EXTRA(NSMenu, self)->_delegate;
}

- (NSString *) _name {
    return NS_EXTRA(NSMenu, self)->_name;
}

- (void) _setMenuName: (NSString *) name {
    NSString* copied = [name copy];
    [NS_EXTRA(NSMenu, self)->_name release];
    NS_EXTRA(NSMenu, self)->_name = copied;
}

- (void) _setHasPadding: (BOOL) hasPadding onEdge: (NSInteger) edge {
}

- (NSMenu *) _menuWithName: (NSString *) name {
    if ([NS_EXTRA(NSMenu, self)->_name isEqual: name])
        return self;
    else {
        NSInteger i, count = [NS_EXTRA(NSMenu, self)->_itemArray count];

        for (i = 0; i < count; i++) {
            NSMenu *check = [[[NS_EXTRA(NSMenu, self)->_itemArray objectAtIndex: i] submenu]
                    _menuWithName: name];

            if (check != nil)
                return check;
        }
    }

    return nil;
}

@end

// An alternate goes with the item right before it in the menu when the two
// have the same key equivalent, letter case aside.
static BOOL isAlternateOfItem(NSMenuItem *item, NSMenuItem *previous) {
    return [item isAlternate] && previous != nil && ![previous isSeparatorItem] &&
           [[item keyEquivalent] caseInsensitiveCompare: [previous keyEquivalent]] == NSOrderedSame;
}

// The modifier keys an item's key equivalent needs: an upper-case key
// equivalent includes Shift.
static NSEventModifierFlags itemModifiers(NSMenuItem *item) {
    NSEventModifierFlags modifiers = NSCommandKeyMask | NSAlternateKeyMask |
                                     NSControlKeyMask | NSShiftKeyMask;
    NSEventModifierFlags mask = [item keyEquivalentModifierMask] & modifiers;
    NSString *key = [item keyEquivalent];

    if ([key length] > 0 && ![key isEqualToString: [key lowercaseString]])
        mask |= NSShiftKeyMask;
    return mask;
}

// Of an item and its alternates, the one for the modifier keys held: the
// first one shown unless one of the others is for exactly those keys, or for
// those keys added to the first one's.
static NSMenuItem *shownItemOfGroup(NSArray *group, NSEventModifierFlags flags) {
    NSMenuItem *first = nil;

    for (NSMenuItem *item in group)
        if (![item isHidden]) {
            first = item;
            break;
        }
    if (first == nil)
        return nil;

    NSEventModifierFlags held = flags & (NSCommandKeyMask | NSAlternateKeyMask |
                                         NSControlKeyMask | NSShiftKeyMask);
    if (held != 0) {
        NSEventModifierFlags withFirst = held | itemModifiers(first);
        for (NSMenuItem *item in group) {
            NSEventModifierFlags mask = itemModifiers(item);
            if (item != first && ![item isHidden] && (mask == held || mask == withFirst))
                return item;
        }
    }
    return first;
}

@implementation NSMenu (ShownItems)

- (NSArray *) _shownItemsWithModifierFlags: (NSEventModifierFlags) flags {
    NSMutableArray *shown = [NSMutableArray array];
    NSMutableArray *group = [NSMutableArray array];

    for (NSMenuItem *item in [self itemArray]) {
        if ([group count] > 0 && isAlternateOfItem(item, [group lastObject])) {
            [group addObject: item];
            continue;
        }
        if ([group count] > 0) {
            NSMenuItem *chosen = shownItemOfGroup(group, flags);
            if (chosen != nil)
                [shown addObject: chosen];
        }
        [group removeAllObjects];
        [group addObject: item];
    }
    if ([group count] > 0) {
        NSMenuItem *chosen = shownItemOfGroup(group, flags);
        if (chosen != nil)
            [shown addObject: chosen];
    }
    return shown;
}

@end
