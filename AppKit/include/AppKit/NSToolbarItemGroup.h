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
#import <Foundation/NSArray.h>

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

NS_ASSUME_NONNULL_BEGIN

#define _NS_SIDE_NSToolbarItemGroup 0, 1,
// Legacy ObjC ABI (i386): the instance size must stay 0x54, Apple's. New state goes to the side struct, never
// to an ivar of its own.
@interface NSToolbarItemGroup : NSToolbarItem {
    NSArray *_subitems;
    NS_LEGACY_IVAR_PAD(_NSToolbarItemGroupReserved, 8)
    NS_EXTRA_IVARS_BEGIN(NSToolbarItemGroup)
        NSToolbarItemGroupSelectionMode _selectionMode;
        NSToolbarItemGroupControlRepresentation _controlRepresentation;
    NS_SIDE_IVARS_END(NSToolbarItemGroup)
}

// Makes a group with one subitem per image. The subitems take the image and, when there is one at the same
// position, the label (also as palette label); the target and action are the group's own. The result is an
// NSToolbarItemGroup whichever class the message is sent to. The selection mode is stored.
+ (instancetype) groupWithItemIdentifier: (NSToolbarItemIdentifier) itemIdentifier
                                  images: (NSArray<NSImage *> *) images
                           selectionMode: (NSToolbarItemGroupSelectionMode) selectionMode
                                  labels: (nullable NSArray<NSString *> *) labels
                                  target: (nullable id) target
                                  action: (nullable SEL) action API_AVAILABLE(macos(10.15));

@property(nonatomic) NSToolbarItemGroupSelectionMode selectionMode API_AVAILABLE(macos(10.15));
// How the toolbar displays the group; stored only. The default is automatic.
@property(nonatomic) NSToolbarItemGroupControlRepresentation controlRepresentation API_AVAILABLE(macos(10.15));

- (NSArray *) subitems;
- (void) setSubitems: (NSArray *) subitems;

@end

NS_ASSUME_NONNULL_END
