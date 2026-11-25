/*
 This file is part of Darling.

 Copyright (C) 2019 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

#import <AppKit/AppKitExport.h>
#import <AppKit/AppKitIvarLayout.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSObject.h>

@class NSArray, NSString;
@protocol NSPasteboardWriting;

typedef NSString *NSDraggingImageComponentKey NS_STRING_ENUM;

APPKIT_EXPORT NSDraggingImageComponentKey const NSDraggingImageComponentIconKey;
APPKIT_EXPORT NSDraggingImageComponentKey const NSDraggingImageComponentLabelKey;

// One part of the image of a dragging item: its contents (an NSImage or a
// CGImageRef) drawn in its frame, in the item's coordinates.
@interface NSDraggingImageComponent : NSObject {
    NS_LEGACY_IVAR_PAD(_NSDraggingImageComponentReserved, 20)
    NS_EXTRA_IVARS_BEGIN(NSDraggingImageComponent)
        NSDraggingImageComponentKey _key;
        id _contents;
        NSRect _frame;
    NS_EXTRA_IVARS_END(NSDraggingImageComponent)
}

+ (NSDraggingImageComponent *) draggingImageComponentWithKey: (NSDraggingImageComponentKey) key;

- (instancetype) initWithKey: (NSDraggingImageComponentKey) key;

@property(copy) NSDraggingImageComponentKey key;
@property(retain) id contents;
@property NSRect frame;

@end

// One of the things a drag carries: its object (written to the pasteboard
// when the drag begins) and how it is shown.
@interface NSDraggingItem : NSObject {
    NS_LEGACY_IVAR_PAD(_NSDraggingItemReserved, 32)
    NS_EXTRA_IVARS_BEGIN(NSDraggingItem)
        id _item;
        NSRect _draggingFrame;
        NSArray<NSDraggingImageComponent *> * (^_imageComponentsProvider)(void);
    NS_EXTRA_IVARS_END(NSDraggingItem)
}

- (instancetype) initWithPasteboardWriter: (id<NSPasteboardWriting>) pasteboardWriter;

@property(readonly, retain) id item;
// in the coordinates of the view the drag begins in, or of the destination's
@property NSRect draggingFrame;
@property(copy) NSArray<NSDraggingImageComponent *> * (^imageComponentsProvider)(void);

// Sets the frame and makes the image one icon component with the contents,
// filling the frame.
- (void) setDraggingFrame: (NSRect) frame contents: (id) contents;

// What the provider gives, or nil without one.
@property(readonly, copy) NSArray<NSDraggingImageComponent *> *imageComponents;

@end
