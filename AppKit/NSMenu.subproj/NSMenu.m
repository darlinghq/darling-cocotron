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
#import <AppKit/NSKeyEquivalentMatching.h>
#import <AppKit/NSWindow.h>
#import <Foundation/NSKeyedArchiver.h>

const NSNotificationName NSMenuWillSendActionNotification = @"NSMenuWillSendActionNotification";
const NSNotificationName NSMenuDidSendActionNotification = @"NSMenuDidSendActionNotification";
const NSNotificationName NSMenuDidBeginTrackingNotification = @"NSMenuDidBeginTrackingNotification";
const NSNotificationName NSMenuDidEndTrackingNotification = @"NSMenuDidEndTrackingNotification";
const NSNotificationName NSMenuDidAddItemNotification = @"NSMenuDidAddItemNotification";
const NSNotificationName NSMenuDidRemoveItemNotification = @"NSMenuDidRemoveItemNotification";
const NSNotificationName NSMenuDidChangeItemNotification = @"NSMenuDidChangeItemNotification";
NSString *const _NSFontMenuName = @"Font";
NSString *const _NSHelpMenuName = @"Help";
NSString *const _NSMainMenuName = @"Application";
NSString *const _NSRecentDocumentsMenuName = @"Recents";
NSString *const _NSServicesMenuName = @"Services";
NSString *const _NSWindowsMenuName = @"Window";

@implementation NSMenu

NS_EXTRA_SYNTHESIZE_ASSIGN(NSMenu, showsStateColumn, _showsStateColumn, BOOL, showsStateColumn, setShowsStateColumn:)
NS_EXTRA_SYNTHESIZE_COPY(NSMenu, identifier, _identifier, NSUserInterfaceItemIdentifier, identifier, setIdentifier:)

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

        [menuWindow setReleasedWhenClosed: YES];
        [menuWindow setFrameTopLeftPoint: [window convertBaseToScreen: point]];
        [menuWindow orderFront: nil];

        item = [menuView trackForEvent: event];

        [menuWindow close];

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

+ (NSZone *) menuZone {
    return NSDefaultMallocZone();
}

- (void) encodeWithCoder: (NSCoder *) coder {
    [coder encodeObject: _title forKey: @"NSTitle"];
    [coder encodeObject: NS_EXTRA(NSMenu, self)->_name forKey: @"NSName"];
    [coder encodeObject: NS_EXTRA(NSMenu, self)->_itemArray forKey: @"NSMenuItems"];
    [coder encodeBool: !NS_EXTRA(NSMenu, self)->_autoenablesItems forKey: @"NSNoAutoenable"];
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
    NS_EXTRA_FREE(NSMenu, self);
    [super dealloc];
}

- copyWithZone: (NSZone *) zone {
    NSMenu *copy = NSCopyObject(self, 0, zone);
    NS_EXTRA_COPY(NSMenu, copy, self);

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

- (NSArray *) itemArray {
    return [NSArray arrayWithArray: NS_EXTRA(NSMenu, self)->_itemArray];
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

- (void) update {
    if ([NS_EXTRA(NSMenu, self)->_delegate respondsToSelector: @selector(menuNeedsUpdate:)]) {
        [NS_EXTRA(NSMenu, self)->_delegate menuNeedsUpdate: self];
    }

    NSInteger i, count = [NS_EXTRA(NSMenu, self)->_itemArray count];

    for (i = 0; i < count; i++) {
        NSMenuItem *item = [NS_EXTRA(NSMenu, self)->_itemArray objectAtIndex: i];

        if (NS_EXTRA(NSMenu, self)->_autoenablesItems) {
            BOOL enabled = itemIsEnabled(item) ? YES : NO;
            BOOL currentlyEnabled = [item isEnabled] ? YES : NO;

            if (enabled != currentlyEnabled &&
                ![item _binderForBinding: @"enabled" create: NO]) {
                [item setEnabled: enabled];
                [self itemChanged: item];
            }
        }

        [[item submenu] update];
    }
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

- (BOOL) performKeyEquivalent: (NSEvent *) event {
    NSInteger i, count = [NS_EXTRA(NSMenu, self)->_itemArray count];

    if (NS_EXTRA(NSMenu, self)->_autoenablesItems)
        [self update];

    for (i = 0; i < count; i++) {
        NSMenuItem *item = [NS_EXTRA(NSMenu, self)->_itemArray objectAtIndex: i];

        if (NSKeyEquivalentMatchesEvent([item keyEquivalent],
                                        [item keyEquivalentModifierMask], event)) {
            // With automatic enabling, -update above brought isEnabled in
            // line with validation. Without it only isEnabled counts and
            // validation is not consulted.
            BOOL enabled = [item isEnabled];
            if (enabled && NS_EXTRA(NSMenu, self)->_autoenablesItems)
                enabled = itemIsEnabled(item);
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
