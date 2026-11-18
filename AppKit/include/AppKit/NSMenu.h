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
#import <AppKit/AppKitExport.h>
#import <Foundation/Foundation.h>
#import <AppKit/NSUserInterfaceItemIdentification.h>

@class NSScreen, NSMenu, NSMenuItem, NSWindow, NSEvent, NSView;

@protocol NSMenuDelegate;

NS_ASSUME_NONNULL_BEGIN

APPKIT_EXPORT const NSNotificationName NSMenuWillSendActionNotification;
APPKIT_EXPORT const NSNotificationName NSMenuDidSendActionNotification;
APPKIT_EXPORT const NSNotificationName NSMenuDidBeginTrackingNotification;
APPKIT_EXPORT const NSNotificationName NSMenuDidEndTrackingNotification;
APPKIT_EXPORT const NSNotificationName NSMenuDidAddItemNotification;
APPKIT_EXPORT const NSNotificationName NSMenuDidRemoveItemNotification;
APPKIT_EXPORT const NSNotificationName NSMenuDidChangeItemNotification;

typedef NS_ENUM(NSInteger, NSMenuSelectionMode) {
    NSMenuSelectionModeAutomatic = 0,
    NSMenuSelectionModeSelectOne = 1,
    NSMenuSelectionModeSelectAny = 2,
};

typedef NS_OPTIONS(NSUInteger, NSMenuProperties) {
    NSMenuPropertyItemTitle = 1 << 0,
    NSMenuPropertyItemAttributedTitle = 1 << 1,
    NSMenuPropertyItemKeyEquivalent = 1 << 2,
    NSMenuPropertyItemImage = 1 << 3,
    NSMenuPropertyItemEnabled = 1 << 4,
    NSMenuPropertyItemAccessibilityDescription = 1 << 5,
};

// Legacy ObjC ABI (i386): instance size must stay 0x1c, Apple's; the ivars
// before the extras sit at Apple's offsets. Add new state to the extra
// struct, never as an ivar.
@interface NSMenu : NSObject <NSCopying, NSUserInterfaceItemIdentification> {
    NSMenu *_supermenu;
    NSString *_title;
    NS_LEGACY_IVAR_PAD(_NSMenuReserved1, 12)
    NS_EXTRA_IVARS_BEGIN(NSMenu)
        NSString *_name;
        NSMutableArray *_itemArray;
        BOOL _autoenablesItems;
        id<NSMenuDelegate> _delegate;
        BOOL _showsStateColumn;
        NSUserInterfaceItemIdentifier _identifier;
    NS_EXTRA_IVARS_END(NSMenu)
}

@property BOOL showsStateColumn;

+ (void) popUpContextMenu: (NSMenu*) menu
                withEvent: (NSEvent*) event
                  forView: (NSView*) view;

+ (null_unspecified NSZone *) menuZone;

- (instancetype) initWithTitle: (NSString *) title;

@property(nullable, nonatomic, retain) NSMenu *supermenu;
@property(nonatomic, copy) NSString *title;
@property(nonatomic, readonly) NSInteger numberOfItems;
- (NSArray<NSMenuItem *> *) itemArray;
@property(nonatomic) BOOL autoenablesItems;

- (nullable NSMenuItem *) itemAtIndex: (NSInteger) index;
- (nullable NSMenuItem *) itemWithTag: (NSInteger) tag;
- (nullable NSMenuItem *) itemWithTitle: (NSString *) title;

- (NSInteger) indexOfItem: (NSMenuItem *) item;
- (NSInteger) indexOfItemWithTag: (NSInteger) tag;
- (NSInteger) indexOfItemWithTitle: (NSString *) title;
- (NSInteger) indexOfItemWithRepresentedObject: (nullable id) object;
- (NSInteger) indexOfItemWithTarget: (nullable id) target andAction: (nullable SEL) action;
- (NSInteger) indexOfItemWithSubmenu: (nullable NSMenu *) menu;

- (void) setMenuChangedMessagesEnabled: (BOOL) flag;

- (void) addItem: (NSMenuItem *) item;
- (NSMenuItem *) addItemWithTitle: (NSString *) title
                           action: (nullable SEL) action
                    keyEquivalent: (NSString *) keyEquivalent;

- (void) removeAllItems; // private, don't use outside framework
- (void) removeItem: (NSMenuItem *) item;
- (void) removeItemAtIndex: (NSInteger) index;

- (void) insertItem: (NSMenuItem *) item atIndex: (NSInteger) index;
- (NSMenuItem *) insertItemWithTitle: (NSString *) title
                              action: (nullable SEL) action
                       keyEquivalent: (NSString *) keyEquivalent
                             atIndex: (NSInteger) index;

- (void) setSubmenu: (nullable NSMenu *) submenu forItem: (NSMenuItem *) item;

- (void) update;

- (void) itemChanged: (NSMenuItem *) item;
- (void) performActionForItemAtIndex: (NSInteger) index;

- (BOOL) performKeyEquivalent: (NSEvent *) event;

@property(nullable, nonatomic, assign) id<NSMenuDelegate> delegate;

// The size the menu has when it is shown as a pop-up, in points.
@property(readonly) NSSize size;

@end

@interface NSObject (NSMenu_validateItem)
- (BOOL) validateMenuItem: (NSMenuItem *) item;
@end

@protocol NSMenuDelegate <NSObject>

@optional

- (NSRect) confinementRectForMenu: (NSMenu *) menu
                         onScreen: (nullable NSScreen *) screen;
- (BOOL) menuHasKeyEquivalent: (NSMenu*) menu
                     forEvent: (NSEvent*) event
                       target: (_Nullable id* _Nonnull) target
                       action: (_Nullable SEL* _Nonnull) action;
- (void) menuNeedsUpdate: (NSMenu*) menu;
- (void) menuWillOpen: (NSMenu *) menu;
- (void) menuDidClose: (NSMenu *) menu;
- (NSInteger) numberOfItemsInMenu: (NSMenu*) menu;
- (void) menu: (NSMenu *) menu willHighlightItem: (nullable NSMenuItem *) item;
- (BOOL) menu: (NSMenu*) menu
          updateItem: (NSMenuItem*) item
             atIndex: (NSInteger) index
        shouldCancel: (BOOL) shouldCancel;

@end

NS_ASSUME_NONNULL_END
