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

#import <AppKit/NSMenuItemCell.h>

#import <AppKit/AppKitIvarLayout.h>
@class NSMenuItem;

APPKIT_EXPORT NSNotificationName NSPopUpButtonCellWillPopUpNotification;

typedef NS_ENUM(NSUInteger, NSPopUpArrowPosition) {
    NSPopUpNoArrow = 0,
    NSPopUpArrowAtCenter = 1,
    NSPopUpArrowAtBottom = 2
};

// Legacy ObjC ABI (i386): instance size must stay 0x80, Apple's; an
// application's subclass is laid out right after it. New state goes to a
// side structure, never to a larger ivar block.
@interface NSPopUpButtonCell : NSMenuItemCell {
    NSMenu *_menu;
    NSInteger _selectedIndex;
    NS_EXTRA_IVARS_BEGIN(NSPopUpButtonCell)
        BOOL _pullsDown;
        BOOL _autoenablesItems;
        BOOL _usesItemFromMenu;
        NSPopUpArrowPosition _arrowPosition;
        NSRectEdge _preferredEdge;
        BOOL _syncTitleNeeded;
        BOOL _altersStateOfSelectedItem;
    NS_EXTRA_IVARS_END(NSPopUpButtonCell)
}

- initTextCell: (NSString *) string pullsDown: (BOOL) pullDown;

- (NSPopUpArrowPosition) arrowPosition;
- (BOOL) pullsDown;
- (NSMenu *) menu;
- (BOOL) autoenablesItems;
- (NSRectEdge) preferredEdge;
- (BOOL) usesItemFromMenu;
// Whether the selected item of a pop-up (not pull-down) menu is the one with the on state.
@property BOOL altersStateOfSelectedItem;

- (NSArray *) itemArray;
- (NSInteger) numberOfItems;

- (NSMenuItem *) itemAtIndex: (NSInteger) index;
- (NSMenuItem *) itemWithTitle: (NSString *) title;
- (NSMenuItem *) lastItem;

- (NSInteger) indexOfItem: (NSMenuItem *) item;
- (NSInteger) indexOfItemWithTitle: (NSString *) title;
- (NSInteger) indexOfItemWithTag: (NSInteger) tag;
- (NSInteger) indexOfItemWithRepresentedObject: object;
- (NSInteger) indexOfItemWithTarget: target andAction: (SEL) action;

- (NSMenuItem *) selectedItem;
- (NSString *) titleOfSelectedItem;
- (NSInteger) indexOfSelectedItem;

- (void) setArrowPosition: (NSPopUpArrowPosition) position;
- (void) setPullsDown: (BOOL) flag;
- (void) setMenu: (NSMenu *) menu;
- (void) setAutoenablesItems: (BOOL) value;
- (void) setPreferredEdge: (NSRectEdge) edge;
- (void) setUsesItemFromMenu: (BOOL) flag;

- (void) addItemWithTitle: (NSString *) title;
- (void) addItemsWithTitles: (NSArray *) titles;

- (void) removeAllItems;
- (void) removeItemAtIndex: (NSInteger) index;
- (void) removeItemWithTitle: (NSString *) title;

- (void) insertItemWithTitle: (NSString *) title atIndex: (NSInteger) index;

- (void) selectItem: (NSMenuItem *) item;
- (void) selectItemAtIndex: (NSInteger) index;
- (void) selectItemWithTitle: (NSString *) title;
- (BOOL) selectItemWithTag: (NSInteger) tag;

- (NSString *) itemTitleAtIndex: (NSInteger) index;
- (NSArray *) itemTitles;

- (void) synchronizeTitleAndSelectedItem;

@end
