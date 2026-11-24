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

#import <AppKit/NSMenuView.h>

@interface NSSubmenuView : NSMenuView {
    // A menu taller than the room it has shows part of its rows and scrolls: the full height of the rows, and
    // how far the rows are scrolled up.
    CGFloat _contentHeight;
    CGFloat _scrollOffset;
}

- initWithMenu: (NSMenu *) menu;
// The area of the item at an index of the menu's item array, in this view's
// (flipped) coordinates, as -itemIndexAtPoint: lays the items out.
- (NSRect) rectForItemAtIndex: (NSUInteger) index;
// Makes the view at most this high (the menu then scrolls, with an arrow at each end that has more rows); a
// no-op for a menu that fits. Call before the view is put into a window.
- (void) limitHeightTo: (CGFloat) height;

@end
