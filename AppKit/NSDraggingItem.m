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

#import <AppKit/NSDraggingItem.h>
#import "NSDraggingSession-Private.h"
#import <Foundation/NSArray.h>
#import <Foundation/NSString.h>

NSDraggingImageComponentKey const NSDraggingImageComponentIconKey = @"icon";
NSDraggingImageComponentKey const NSDraggingImageComponentLabelKey = @"label";

@implementation NSDraggingImageComponent

NS_EXTRA_SYNTHESIZE_COPY(NSDraggingImageComponent, key, _key, NSDraggingImageComponentKey, key, setKey:)
NS_EXTRA_SYNTHESIZE_RETAIN(NSDraggingImageComponent, contents, _contents, id, contents, setContents:)
NS_EXTRA_SYNTHESIZE_ASSIGN(NSDraggingImageComponent, frame, _frame, NSRect, frame, setFrame:)

+ (NSDraggingImageComponent *) draggingImageComponentWithKey: (NSDraggingImageComponentKey) key {
    return [[[self alloc] initWithKey: key] autorelease];
}

- (instancetype) initWithKey: (NSDraggingImageComponentKey) key {
    self = [super init];
    if (self != nil)
        NS_EXTRA(NSDraggingImageComponent, self)->_key = [key copy];
    return self;
}

- (void) dealloc {
    if (NS_EXTRA_ALLOCATED(NSDraggingImageComponent, self)) {
        [NS_EXTRA(NSDraggingImageComponent, self)->_key release];
        [NS_EXTRA(NSDraggingImageComponent, self)->_contents release];
    }
    NS_EXTRA_FREE(NSDraggingImageComponent, self);
    [super dealloc];
}

@end

typedef NSArray<NSDraggingImageComponent *> * (^NSDraggingImageComponentsProvider)(void);

@implementation NSDraggingItem

NS_EXTRA_SYNTHESIZE_RETAIN(NSDraggingItem, item, _item, id, item, _setItem:)
NS_EXTRA_SYNTHESIZE_ASSIGN(NSDraggingItem, draggingFrame, _draggingFrame, NSRect, draggingFrame, setDraggingFrame:)
NS_EXTRA_SYNTHESIZE_COPY(NSDraggingItem, imageComponentsProvider, _imageComponentsProvider,
                         NSDraggingImageComponentsProvider, imageComponentsProvider,
                         setImageComponentsProvider:)

- (instancetype) initWithPasteboardWriter: (id<NSPasteboardWriting>) pasteboardWriter {
    return [self _initWithItem: pasteboardWriter];
}

- (instancetype) _initWithItem: (id) item {
    self = [super init];
    if (self != nil)
        NS_EXTRA(NSDraggingItem, self)->_item = [item retain];
    return self;
}

- (void) dealloc {
    if (NS_EXTRA_ALLOCATED(NSDraggingItem, self)) {
        [NS_EXTRA(NSDraggingItem, self)->_item release];
        [NS_EXTRA(NSDraggingItem, self)->_imageComponentsProvider release];
    }
    NS_EXTRA_FREE(NSDraggingItem, self);
    [super dealloc];
}

- (void) setDraggingFrame: (NSRect) frame contents: (id) contents {
    [self setDraggingFrame: frame];

    // The component fills the frame; the provider keeps it, so it is the same
    // one each time it is asked for (observed on macOS 26.7.3).
    NSDraggingImageComponent *icon =
            [NSDraggingImageComponent draggingImageComponentWithKey: NSDraggingImageComponentIconKey];
    [icon setContents: contents];
    [icon setFrame: NSMakeRect(0, 0, frame.size.width, frame.size.height)];
    NSArray<NSDraggingImageComponent *> *components = [NSArray arrayWithObject: icon];
    [self setImageComponentsProvider: ^NSArray<NSDraggingImageComponent *> *(void) {
        return components;
    }];
}

- (NSArray<NSDraggingImageComponent *> *) imageComponents {
    NSArray<NSDraggingImageComponent *> * (^provider)(void) = [self imageComponentsProvider];
    if (provider == nil)
        return nil;
    return provider();
}

@end
