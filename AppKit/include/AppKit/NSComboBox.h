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

#import <AppKit/NSTextField.h>
#import <AppKit/AppKitIvarLayout.h>

APPKIT_EXPORT NSString *const NSComboBoxSelectionDidChangeNotification;
APPKIT_EXPORT NSString *const NSComboBoxSelectionIsChangingNotification;
APPKIT_EXPORT NSString *const NSComboBoxWillDismissNotification;
APPKIT_EXPORT NSString *const NSComboBoxWillPopUpNotification;

// Legacy ObjC ABI (i386): instance size must stay 0x68, Apple's; an
// application's subclass is laid out right after it. New state goes to a
// side structure, never to a larger ivar block.
@interface NSComboBox : NSTextField {
    NS_LEGACY_IVAR_PAD(_NSComboBoxReserved1, 4)
}

- dataSource;
@property(nonatomic) BOOL usesDataSource;
@property(nonatomic, getter=isButtonBordered) BOOL buttonBordered;
@property(nonatomic) CGFloat itemHeight;
@property(nonatomic) BOOL hasVerticalScroller;
@property(nonatomic) NSSize intercellSpacing;
@property(nonatomic) BOOL completes;
@property(nonatomic) NSInteger numberOfVisibleItems;

- (void) setDataSource: value;

- (NSInteger) numberOfItems;
- (NSArray *) objectValues;
- itemObjectValueAtIndex: (NSInteger) index;
- (NSInteger) indexOfItemWithObjectValue: object;
- (void) addItemWithObjectValue: object;
- (void) addItemsWithObjectValues: (NSArray *) objects;
- (void) removeAllItems;
- (void) removeItemAtIndex: (NSInteger) index;
- (void) removeItemWithObjectValue: value;
- (void) insertItemWithObjectValue: value atIndex: (NSInteger) index;

- (NSInteger) indexOfSelectedItem;
- objectValueOfSelectedItem;
- (void) selectItemAtIndex: (NSInteger) index;
- (void) selectItemWithObjectValue: value;
- (void) deselectItemAtIndex: (NSInteger) index;

- (void) scrollItemAtIndexToTop: (NSInteger) index;
- (void) scrollItemAtIndexToVisible: (NSInteger) index;

- (void) noteNumberOfItemsChanged;
- (void) reloadData;

@end

@protocol NSComboBoxDelegate <NSObject>
- (void) comboBoxWillPopUp: (NSNotification *) note;
- (void) comboBoxWillDismiss: (NSNotification *) note;
- (void) comboBoxSelectionDidChange: (NSNotification *) note;
- (void) comboBoxSelectionIsChanging: (NSNotification *) note;
@end

@protocol NSComboBoxDataSource <NSObject>

// TODO

@end
