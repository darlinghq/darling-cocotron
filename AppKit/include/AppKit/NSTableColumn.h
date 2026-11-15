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
#import <Foundation/Foundation.h>
#import <AppKit/NSUserInterfaceItemIdentification.h>

@class NSTableView, NSCell;

typedef NS_OPTIONS(NSUInteger, NSTableColumnResizingOptions) {
    NSTableColumnNoResizing = 0x00,
    NSTableColumnAutoresizingMask = 0x01,
    NSTableColumnUserResizingMask = 0x02,
};

// Legacy ObjC ABI (i386): instance size must stay 0x28, Apple's; the ivars
// before the extras sit at Apple's offsets. Add new state to the extra
// struct, never as an ivar.
@interface NSTableColumn : NSObject <NSUserInterfaceItemIdentification> {
    NSUserInterfaceItemIdentifier _identifier;
    NS_LEGACY_IVAR_PAD(_NSTableColumnReserved1, 28)
    NS_EXTRA_IVARS_BEGIN(NSTableColumn)
        NSTableView *_tableView;
        NSCell *_headerCell;
        NSCell *_dataCell;
        NSString *_headerToolTip;
        CGFloat _width;
        CGFloat _minWidth;
        CGFloat _maxWidth;
        BOOL _isResizable;
        BOOL _isEditable;
        NSUInteger _resizingMask;
        BOOL _hidden;
        NSSortDescriptor *_sortDescriptorPrototype;
    NS_EXTRA_IVARS_END(NSTableColumn)
}

- (instancetype) initWithIdentifier: (NSUserInterfaceItemIdentifier) identifier;

@property(copy) NSString *title;

@property(nonatomic, retain) NSTableView *tableView;
- (NSString *) title;
@property(nonatomic, retain) id headerCell;
@property(nonatomic, retain) id dataCell;
@property(nonatomic, copy) NSString *headerToolTip;

@property(nonatomic, getter=isHidden) BOOL hidden;
@property(nonatomic) CGFloat width;
@property(nonatomic) CGFloat minWidth;
@property(nonatomic) CGFloat maxWidth;
@property(nonatomic, getter=isResizable) BOOL resizable;
@property(nonatomic, getter=isEditable) BOOL editable;
@property(nonatomic) NSUInteger resizingMask;

- (void) setTitle: (NSString *) title;


- (NSCell *) dataCellForRow: (NSInteger) row;

@property(nonatomic, retain) NSSortDescriptor *sortDescriptorPrototype;

// internal
- (void) prepareCell: (id) cell inRow: (NSInteger) row;
- (void) _boundValuesChanged;
- (void) _sort;

@end
