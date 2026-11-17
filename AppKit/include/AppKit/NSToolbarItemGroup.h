/* Copyright (c) 2009 Christopher J. W. Lloyd

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
#import <AppKit/NSToolbarItem.h>
#import <AppKit/AppKitIvarLayout.h>

@class NSArray;

typedef NS_ENUM(NSInteger, NSToolbarItemGroupSelectionMode) {
    NSToolbarItemGroupSelectionModeSelectOne = 0,
    NSToolbarItemGroupSelectionModeSelectAny = 1,
    NSToolbarItemGroupSelectionModeMomentary = 2,
};

typedef NS_ENUM(NSInteger, NSToolbarItemGroupControlRepresentation) {
    NSToolbarItemGroupControlRepresentationAutomatic,
    NSToolbarItemGroupControlRepresentationExpanded,
    NSToolbarItemGroupControlRepresentationCollapsed,
};

@interface NSToolbarItemGroup : NSToolbarItem {
    NSArray *_subitems;
    NS_LEGACY_IVAR_PAD(_NSToolbarItemGroupReserved, 8)
}

- (NSArray *) subitems;
- (void) setSubitems: (NSArray *) subitems;

@end
