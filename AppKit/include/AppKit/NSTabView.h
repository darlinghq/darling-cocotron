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

#import <AppKit/NSCell.h>
#import <AppKit/NSView.h>

#import <AppKit/AppKitIvarLayout.h>
@class NSTabViewItem, NSFont;

typedef NS_ENUM(NSUInteger, NSTabViewType) {
    NSTabViewTypeTopTabsBezelBorder,
    NSTabViewTypeLeftTabsBezelBorder,
    NSTabViewTypeBottomTabsBezelBorder,
    NSTabViewTypeRightTabsBezelBorder,
    NSTabViewTypeNoTabsBezelBorder,
    NSTabViewTypeNoTabsLineBorder,
    NSTabViewTypeNoTabsNoBorder
};

// Names used before the modern spellings; plain constants, so Swift does not see them.
enum {
    NSTopTabsBezelBorder = NSTabViewTypeTopTabsBezelBorder,
    NSLeftTabsBezelBorder = NSTabViewTypeLeftTabsBezelBorder,
    NSBottomTabsBezelBorder = NSTabViewTypeBottomTabsBezelBorder,
    NSRightTabsBezelBorder = NSTabViewTypeRightTabsBezelBorder,
    NSNoTabsBezelBorder = NSTabViewTypeNoTabsBezelBorder,
    NSNoTabsLineBorder = NSTabViewTypeNoTabsLineBorder,
    NSNoTabsNoBorder = NSTabViewTypeNoTabsNoBorder,
};

typedef NS_ENUM(NSUInteger, NSTabPosition) {
    NSTabPositionNone,
    NSTabPositionTop,
    NSTabPositionLeft,
    NSTabPositionBottom,
    NSTabPositionRight
};

typedef NS_ENUM(NSUInteger, NSTabViewBorderType) {
    NSTabViewBorderTypeNone = 0,
    NSTabViewBorderTypeLine = 1,
    NSTabViewBorderTypeBezel = 2,
};

// Legacy ObjC ABI (i386): instance size must stay 0x94, Apple's; an
// application's subclass is laid out right after it. New state goes to a
// side structure, never to a larger ivar block.
@interface NSTabView : NSView {
    NSMutableArray *_items;
    NSTabViewItem *_selectedItem;
    NSFont *_font;
    NSTabViewType _type;
    BOOL _allowsTruncatedLabels;
    id _delegate;
    NS_LEGACY_IVAR_PAD(_NSTabViewReserved1, 1)
    BOOL _drawsBackground;
    NSTabPosition _position;
    NSControlSize _controlSize;
    NS_LEGACY_IVAR_PAD(_NSTabViewReserved2, 32)
}

- delegate;

- (NSSize) minimumSize;
- (NSRect) contentRect;

@property(nonatomic, retain) NSFont *font;
@property(nonatomic) NSControlSize controlSize;
@property(nonatomic) NSTabViewType tabViewType;
@property(nonatomic) NSTabPosition tabPosition;
@property(nonatomic) BOOL drawsBackground;
@property(nonatomic) BOOL allowsTruncatedLabels;

- (void) setDelegate: delegate;

- (NSInteger) numberOfTabViewItems;
- (NSArray *) tabViewItems;
- (NSTabViewItem *) tabViewItemAtIndex: (NSInteger) index;
- (NSTabViewItem *) tabViewItemAtPoint: (NSPoint) point;
- (NSInteger) indexOfTabViewItem: (NSTabViewItem *) item;
- (NSInteger) indexOfTabViewItemWithIdentifier: identifier;

- (void) addTabViewItem: (NSTabViewItem *) item;
- (void) removeTabViewItem: (NSTabViewItem *) item;
- (void) insertTabViewItem: (NSTabViewItem *) item atIndex: (NSInteger) index;

- (NSTabViewItem *) selectedTabViewItem;
- (void) selectTabViewItem: (NSTabViewItem *) item;
- (void) selectTabViewItemAtIndex: (NSInteger) index;
- (void) selectTabViewItemWithIdentifier: identifier;
- (void) selectFirstTabViewItem: sender;
- (void) selectLastTabViewItem: sender;
- (void) takeSelectedTabViewItemFromSender: sender;

- (void) _itemViewDidChange: (NSTabViewItem *) item;

@end

@protocol NSTabViewDelegate <NSObject>
- (void) tabViewDidChangeNumberOfTabViewItems: (NSTabView *) tabView;

- (BOOL) tabView: (NSTabView *) tabView
        shouldSelectTabViewItem: (NSTabViewItem *) item;
- (void) tabView: (NSTabView *) tabView
        willSelectTabViewItem: (NSTabViewItem *) item;
- (void) tabView: (NSTabView *) tabView
        didSelectTabViewItem: (NSTabViewItem *) item;
@end
