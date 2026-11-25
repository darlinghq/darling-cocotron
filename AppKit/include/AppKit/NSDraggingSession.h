/*
 This file is part of Darling.

 Copyright (C) 2026 Lubos Dolezel

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
#import <AppKit/NSDragging.h>
#import <AppKit/NSPasteboard.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSObject.h>

@class NSArray, NSDictionary, NSDraggingItem, NSView;

// A drag begun with -[NSView beginDraggingSessionWithItems:event:source:].
// Its class has no instance variables of its own on the legacy ABI, where
// Apple's layout is not known; they are kept with the object instead.
#define _NS_SIDE_NSDraggingSession 0, 1,
@interface NSDraggingSession : NSObject {
    NS_EXTRA_IVARS_BEGIN(NSDraggingSession)
        NSArray<NSDraggingItem *> *_items;
        id _source;
        NSView *_view;
        NSPasteboard *_pasteboard;
        NSDraggingFormation _draggingFormation;
        BOOL _animatesToStartingPositionsOnCancelOrFail;
        NSInteger _draggingLeaderIndex;
        NSInteger _draggingSequenceNumber;
        NSPoint _draggingLocation;
        NSPoint _startLocation;
        NSArray *_startFrames;
    NS_SIDE_IVARS_END(NSDraggingSession)
}

@property NSDraggingFormation draggingFormation;
@property BOOL animatesToStartingPositionsOnCancelOrFail;
@property NSInteger draggingLeaderIndex;
@property(readonly) NSPasteboard *draggingPasteboard;
@property(readonly) NSInteger draggingSequenceNumber;
// in screen coordinates
@property(readonly) NSPoint draggingLocation;

// Calls the block with an item for each object of the drag the pasteboard
// can read as one of the classes, in the coordinates of the view (of the
// screen when nil).
- (void) enumerateDraggingItemsWithOptions: (NSDraggingItemEnumerationOptions) options
                                   forView: (NSView *) view
                                   classes: (NSArray<Class> *) classArray
                             searchOptions: (NSDictionary<NSPasteboardReadingOptionKey, id> *) searchOptions
                                usingBlock: (void (^)(NSDraggingItem *draggingItem, NSInteger idx, BOOL *stop)) block;

@end
