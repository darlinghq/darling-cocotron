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
#import <AppKit/NSButton.h>
#import <AppKit/NSMenuItem.h>

APPKIT_EXPORT NSString *const NSPopUpButtonWillPopUpNotification;

// Legacy ObjC ABI (i386): instance size must stay 0x60, Apple's; the ivars
// before the extras sit at Apple's offsets. Add new state to the extra
// struct, never as an ivar.
@interface NSPopUpButton : NSButton {
    NS_EXTRA_IVARS_BEGIN(NSPopUpButton)
        BOOL _observerAdded;
    NS_EXTRA_IVARS_END(NSPopUpButton)
}
- initWithFrame: (NSRect) frame pullsDown: (BOOL) pullsDown;

@property(nonatomic) BOOL pullsDown;
@property(nonatomic, retain) NSMenu *menu;
@property(nonatomic) BOOL autoenablesItems;
@property(nonatomic) NSRectEdge preferredEdge;

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
