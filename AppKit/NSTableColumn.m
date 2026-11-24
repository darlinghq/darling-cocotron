/* Copyright (c) 2006-2007 Christopher J. W. Lloyd
   Copyright (c) 2007 Johannes Fortmann

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

#import <AppKit/AppKit.h>
#import <AppKit/NSObject+BindingSupport.h>
#import <Foundation/NSKeyedArchiver.h>

#import "NSKeyValueBinding/NSKVOBinder.h"
#import "NSKeyValueBinding/NSMultipleValueBinder.h"
#import <AppKit/NSRaise.h>

@interface NSTableView (private)
- (void) _establishBindingsWithDestinationIfUnbound: (id) dest;
@end

@implementation NSTableColumn

@synthesize identifier = _identifier;

- (void) encodeWithCoder: (NSCoder *) coder {
    NSUnimplementedMethod();
}

- initWithCoder: (NSCoder *) coder {
    if ([coder allowsKeyedCoding]) {
        NSKeyedUnarchiver *keyed = (NSKeyedUnarchiver *) coder;

        _identifier = [[keyed decodeObjectForKey: @"NSIdentifier"] retain];
        NS_EXTRA(NSTableColumn, self)->_headerCell = [[keyed decodeObjectForKey: @"NSHeaderCell"] retain];
        NS_EXTRA(NSTableColumn, self)->_dataCell = [[keyed decodeObjectForKey: @"NSDataCell"] retain];
        NS_EXTRA(NSTableColumn, self)->_width = [keyed decodeFloatForKey: @"NSWidth"];
        NS_EXTRA(NSTableColumn, self)->_minWidth = [keyed decodeFloatForKey: @"NSMinWidth"];
        NS_EXTRA(NSTableColumn, self)->_maxWidth = [keyed decodeFloatForKey: @"NSMaxWidth"];
        [self setResizable: [keyed decodeBoolForKey: @"NSIsResizeable"]];
        NS_EXTRA(NSTableColumn, self)->_isEditable = [keyed decodeBoolForKey: @"NSIsEditable"];
    } else {
        // One layout in every class version, as recorded from Mac archives: identifier,
        // width, minimum width, maximum width, header cell, data cell, resizable byte,
        // editable byte, then the table view (a back-reference, not retained).
        float width = 0, minWidth = 0, maxWidth = 0;
        char resizable = 0, editable = 0;
        id tableView = nil;

        [coder decodeValuesOfObjCTypes: "@fff@@cc", &_identifier, &width, &minWidth, &maxWidth, &NS_EXTRA(NSTableColumn, self)->_headerCell, &NS_EXTRA(NSTableColumn, self)->_dataCell,
                                        &resizable, &editable];
        tableView = [coder decodeObject];
        NS_EXTRA(NSTableColumn, self)->_width = width;
        NS_EXTRA(NSTableColumn, self)->_minWidth = minWidth;
        NS_EXTRA(NSTableColumn, self)->_maxWidth = maxWidth;
        [self setResizable: resizable != 0];
        NS_EXTRA(NSTableColumn, self)->_isEditable = editable != 0;
        NS_EXTRA(NSTableColumn, self)->_tableView = tableView;
    }

    return self;
}

// NSOutlineView needs to programmatically instantiated as IB/WOF4 doesn't have
// an editor for it.. also theoretically -dealloc could've crashed as the cell
// prototypes weren't initialized at all...
- (instancetype) initWithIdentifier: (NSUserInterfaceItemIdentifier) identifier {
    _identifier = [identifier retain];
    NS_EXTRA(NSTableColumn, self)->_width = 100.0;
    NS_EXTRA(NSTableColumn, self)->_minWidth = 10.0;
    NS_EXTRA(NSTableColumn, self)->_maxWidth = FLT_MAX; // Doc.s say MAXFLOAT, mingw doesnt have MAXFLOAT yet
    // A new column resizes with the table and by the user (macOS 26.7.3: resizingMask 3)
    [self setResizable: YES];

    NS_EXTRA(NSTableColumn, self)->_headerCell = [[NSTableHeaderCell alloc] initTextCell: @""];
    NS_EXTRA(NSTableColumn, self)->_dataCell = [[NSTextFieldCell alloc] initTextCell: @""];
    // A new column and its data cell are editable (macOS 10.14.4 and 26.7.3; test: appkit-tableview-edit-column.m)
    [self setEditable: YES];

    return self;
}

- (void) dealloc {
    [_identifier release];
    [NS_EXTRA(NSTableColumn, self)->_headerCell release];
    [NS_EXTRA(NSTableColumn, self)->_dataCell release];
    [NS_EXTRA(NSTableColumn, self)->_headerToolTip release];
    [NS_EXTRA(NSTableColumn, self)->_sortDescriptorPrototype release];

    NS_EXTRA_FREE(NSTableColumn, self);
    [super dealloc];
}

- (NSString *) description {
    return [NSString
            stringWithFormat:
                    @"<%@ 0x%08lx identifier: \"%@\" headerCell: %@ "
                    @"dataCell: %@ width: %f minWidth: %f maxWidth: %f>",
                    [self class], self, _identifier, NS_EXTRA(NSTableColumn, self)->_headerCell, NS_EXTRA(NSTableColumn, self)->_dataCell,
                    NS_EXTRA(NSTableColumn, self)->_width, NS_EXTRA(NSTableColumn, self)->_minWidth, NS_EXTRA(NSTableColumn, self)->_maxWidth];
}

- (NSTableView *) tableView {
    return NS_EXTRA(NSTableColumn, self)->_tableView;
}

- (NSString *) title {
    return [NS_EXTRA(NSTableColumn, self)->_headerCell stringValue];
}

- (id) headerCell {
    return NS_EXTRA(NSTableColumn, self)->_headerCell;
}

- (id) dataCell {
    return NS_EXTRA(NSTableColumn, self)->_dataCell;
}

- (NSString *) headerToolTip {
    return NS_EXTRA(NSTableColumn, self)->_headerToolTip;
}

- (CGFloat) width {
    return NS_EXTRA(NSTableColumn, self)->_width;
}

- (CGFloat) minWidth {
    return NS_EXTRA(NSTableColumn, self)->_minWidth;
}

- (CGFloat) maxWidth {
    return NS_EXTRA(NSTableColumn, self)->_maxWidth;
}

- (BOOL) isResizable {
    return (NS_EXTRA(NSTableColumn, self)->_resizingMask & NSTableColumnUserResizingMask) != 0;
}

- (BOOL) isEditable {
    return NS_EXTRA(NSTableColumn, self)->_isEditable;
}

- (NSUInteger) resizingMask {
    return NS_EXTRA(NSTableColumn, self)->_resizingMask;
}

- (void) setTableView: (NSTableView *) tableView {
    NS_EXTRA(NSTableColumn, self)->_tableView = tableView;
}

- (void) setTitle: (NSString *) title {
    [NS_EXTRA(NSTableColumn, self)->_headerCell setStringValue: title ?: @""];
}

- (void) setHeaderCell: (NSCell *) cell {
    cell = [cell retain];
    [NS_EXTRA(NSTableColumn, self)->_headerCell release];
    NS_EXTRA(NSTableColumn, self)->_headerCell = cell;
}

- (void) setDataCell: (NSCell *) cell {
    cell = [cell retain];
    [NS_EXTRA(NSTableColumn, self)->_dataCell release];
    NS_EXTRA(NSTableColumn, self)->_dataCell = cell;
}

- (void) setHeaderToolTip: (NSString *) value {
    value = [value copy];
    [NS_EXTRA(NSTableColumn, self)->_headerToolTip release];
    NS_EXTRA(NSTableColumn, self)->_headerToolTip = value;
}

- (void) setWidth: (CGFloat) width {
    if (width > NS_EXTRA(NSTableColumn, self)->_maxWidth)
        width = NS_EXTRA(NSTableColumn, self)->_maxWidth;
    else if (width < NS_EXTRA(NSTableColumn, self)->_minWidth)
        width = NS_EXTRA(NSTableColumn, self)->_minWidth;

    NS_EXTRA(NSTableColumn, self)->_width = width;
}

// A hidden column is still in tableColumns and in the count; only the layout of the table and of its header
// leaves it out. Changing the flag lays the table out again.
- (BOOL) isHidden {
    return NS_EXTRA(NSTableColumn, self)->_hidden;
}

- (void) setHidden: (BOOL) hidden {
    if (hidden == NS_EXTRA(NSTableColumn, self)->_hidden)
        return;
    NS_EXTRA(NSTableColumn, self)->_hidden = hidden;
    [NS_EXTRA(NSTableColumn, self)->_tableView tile];
}

- (void) setMinWidth: (CGFloat) width {
    NS_EXTRA(NSTableColumn, self)->_minWidth = width;
}

- (void) setMaxWidth: (CGFloat) width {
    NS_EXTRA(NSTableColumn, self)->_maxWidth = width;
}

- (void) setResizable: (BOOL) flag {
    // macOS 26.7.3: setResizable:YES sets the mask to auto plus user resizing, NO clears it
    NS_EXTRA(NSTableColumn, self)->_resizingMask = flag ? (NSTableColumnAutoresizingMask | NSTableColumnUserResizingMask) : NSTableColumnNoResizing;
    NS_EXTRA(NSTableColumn, self)->_isResizable = flag;
}

- (void) setEditable: (BOOL) flag {
    NS_EXTRA(NSTableColumn, self)->_isEditable = flag;
    [NS_EXTRA(NSTableColumn, self)->_dataCell setEditable: flag];
}

- (void) setResizingMask: (NSUInteger) value {
    NS_EXTRA(NSTableColumn, self)->_resizingMask = value;
}

// The documentation gives the contract: the width becomes that of the header cell, widening a maximum that is
// narrower and narrowing a minimum that is wider, so the width never has to be clamped, and the table view
// is marked as needing display when the width changes.
// Observed on macOS 26.7.3 and Mac OS X 10.14.4 (black-box, x86_64 and i386, identical; probe sizetofit.m):
// the header cell's width is that of -cellSize, unrounded; the limits and the width are changed through
// -setMaxWidth:, -setMinWidth: and -setWidth: (a subclass's overrides are called, the limit first); the cell is
// the stored header cell, not what an override of -headerCell returns; the table view is marked as needing
// display when the width changes (26.7.3). A column cannot have no header cell on macOS (-setHeaderCell: raises
// for nil); the nil check below only guards what this implementation lets through.
- (void) sizeToFit {
    NSCell *headerCell = NS_EXTRA(NSTableColumn, self)->_headerCell;
    if (headerCell == nil)
        return;

    CGFloat headerWidth = [headerCell cellSize].width;
    CGFloat oldWidth = [self width];

    if ([self maxWidth] < headerWidth)
        [self setMaxWidth: headerWidth];
    if ([self minWidth] > headerWidth)
        [self setMinWidth: headerWidth];
    [self setWidth: headerWidth];

    if ([self width] != oldWidth)
        [[self tableView] setNeedsDisplay: YES];
}

- (NSCell *) dataCellForRow: (NSInteger) row {
    return [self dataCell];
}

- (void) _boundValuesChanged {
}

- (void) prepareCell: (id) cell inRow: (NSInteger) row {
    id binders = [self _allUsedBinders];
    NSInteger count = [binders count];
    int i;
    for (i = 0; i < count; i++) {
        id binder = [binders objectAtIndex: i];
        if ([binder isKindOfClass: [_NSMultipleValueBinder class]]) {
            [binder applyToCell: cell inRow: row];
        }
    }
}

- (void) _establishBindingsWithDestinationIfUnbound: (id) dest {
    [[self tableView] _establishBindingsWithDestinationIfUnbound: dest];
}

- (NSSortDescriptor *) sortDescriptorPrototype {
    return [[NS_EXTRA(NSTableColumn, self)->_sortDescriptorPrototype retain] autorelease];
}

- (void) setSortDescriptorPrototype: (NSSortDescriptor *) value {
    if (NS_EXTRA(NSTableColumn, self)->_sortDescriptorPrototype != value) {
        [NS_EXTRA(NSTableColumn, self)->_sortDescriptorPrototype release];
        NS_EXTRA(NSTableColumn, self)->_sortDescriptorPrototype = [value copy];
    }
}

- (void) _sort {
    id newDescriptor = [self sortDescriptorPrototype];
    if (!newDescriptor)
        return;

    id allDescs = [[[NS_EXTRA(NSTableColumn, self)->_tableView sortDescriptors] mutableCopy] autorelease];
    NSInteger i;

    for (i = 0; i < [allDescs count]; i++) {
        id desc = [allDescs objectAtIndex: i];
        if ([[newDescriptor key] isEqual: [desc key]]) {
            if (i == 0)
                newDescriptor = [desc reversedSortDescriptor];

            // Removed by position, before the insert: removeObject: takes every element that isEqual: the
            // old descriptor, and that includes the new one when both are the column's own prototype.
            [allDescs removeObjectAtIndex: i];
            [allDescs insertObject: newDescriptor atIndex: 0];
            [NS_EXTRA(NSTableColumn, self)->_tableView setSortDescriptors: allDescs];
            return;
        }
    }

    [allDescs insertObject: newDescriptor atIndex: 0];
    [NS_EXTRA(NSTableColumn, self)->_tableView setSortDescriptors: allDescs];
}

@end

@implementation NSTableColumn (Bindings)

+ (Class) _binderClassForBinding: (id) binding {
    if ([binding isEqual: @"headerTitle"] || [binding isEqual: @"maxWidth"] ||
        [binding isEqual: @"minWidth"] || [binding isEqual: @"width"])
        return [_NSKVOBinder class];
    return [_NSMultipleValueBinder class];
}

- (NSString *) _headerTitle {
    return [NS_EXTRA(NSTableColumn, self)->_headerCell title];
}
- (void) _setHeaderTitle: (NSString *) title {
    return [NS_EXTRA(NSTableColumn, self)->_headerCell setTitle: title];
}

@end
