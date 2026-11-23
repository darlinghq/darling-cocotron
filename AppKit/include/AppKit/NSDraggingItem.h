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

NS_ASSUME_NONNULL_BEGIN

typedef NSString *NSDraggingImageComponentKey NS_STRING_ENUM;

APPKIT_EXPORT NSDraggingImageComponentKey const NSDraggingImageComponentIconKey;
APPKIT_EXPORT NSDraggingImageComponentKey const NSDraggingImageComponentLabelKey;

// One layer of a dragging item's image: an image placed in the item's frame
@interface NSDraggingImageComponent : NSObject {
    // The original's ivars take 24 bytes on i386 (appkit-i386-ivar-layout)
    NSDraggingImageComponentKey _key;
    id _contents;
    NSRect _frame;
}

+ (instancetype) draggingImageComponentWithKey: (NSDraggingImageComponentKey) key;
- (instancetype) initWithKey: (NSDraggingImageComponentKey) key;

@property(copy) NSDraggingImageComponentKey key;
@property(retain, nullable) id contents;   // an NSImage or a CGImageRef
@property NSRect frame;                    // in the item's coordinates, its frame's origin at (0, 0)

@end

@interface NSDraggingItem : NSObject {
    // The original's ivars take 36 bytes on i386 (appkit-i386-ivar-layout)
    id _item;
    NSRect _draggingFrame;
    NSArray *_Nonnull (^_imageComponentsProvider)(void);
    NS_LEGACY_IVAR_PAD(_NSDraggingItemReserved, 12)
}

- (instancetype) initWithPasteboardWriter: (id<NSPasteboardWriting>) pasteboardWriter;

@property(readonly, retain) id item;
@property NSRect draggingFrame;
@property(copy, nullable) NSArray<NSDraggingImageComponent *> *_Nonnull (^imageComponentsProvider)(void);
@property(readonly, copy, nullable) NSArray<NSDraggingImageComponent *> *imageComponents;

// Sets the frame, and a provider of one icon component showing the contents over all of it
- (void) setDraggingFrame: (NSRect) frame contents: (nullable id) contents;

@end

NS_ASSUME_NONNULL_END
