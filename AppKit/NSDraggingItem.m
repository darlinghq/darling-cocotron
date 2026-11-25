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
#import <Foundation/NSArray.h>
#import <Foundation/NSString.h>

NSDraggingImageComponentKey const NSDraggingImageComponentIconKey = @"icon";
NSDraggingImageComponentKey const NSDraggingImageComponentLabelKey = @"label";

@implementation NSDraggingImageComponent

@synthesize key = _key, contents = _contents, frame = _frame;

+ (instancetype) draggingImageComponentWithKey: (NSDraggingImageComponentKey) key {
    return [[[self alloc] initWithKey: key] autorelease];
}

- (instancetype) initWithKey: (NSDraggingImageComponentKey) key {
    if ((self = [super init]))
        _key = [key copy];
    return self;
}

- (void) dealloc {
    [_key release];
    [_contents release];
    [super dealloc];
}

@end

@implementation NSDraggingItem

@synthesize item = _item, draggingFrame = _draggingFrame, imageComponentsProvider = _imageComponentsProvider;

- (instancetype) initWithPasteboardWriter: (id<NSPasteboardWriting>) pasteboardWriter {
    if ((self = [super init]))
        _item = [(id) pasteboardWriter retain];
    return self;
}

- (void) dealloc {
    [_item release];
    [_imageComponentsProvider release];
    [super dealloc];
}

- (NSArray<NSDraggingImageComponent *> *) imageComponents {
    return _imageComponentsProvider != nil ? _imageComponentsProvider() : nil;
}

- (void) setDraggingFrame: (NSRect) frame contents: (id) contents {
    [self setDraggingFrame: frame];
    // The component fills the frame; the provider keeps it, so it is the same
    // one each time it is asked for (observed on macOS 26.7.3).
    NSDraggingImageComponent *icon = [NSDraggingImageComponent draggingImageComponentWithKey:
                                                                   NSDraggingImageComponentIconKey];
    [icon setContents: contents];
    [icon setFrame: NSMakeRect(0, 0, frame.size.width, frame.size.height)];
    NSArray *components = [NSArray arrayWithObject: icon];
    [self setImageComponentsProvider: ^NSArray * {
        return components;
    }];
}

@end
