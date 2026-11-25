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

#import <AppKit/NSDragging.h>
#import <AppKit/NSDraggingItem.h>
#import <Foundation/NSGeometry.h>
#import <Foundation/NSObject.h>

@class NSPasteboard, NSView, NSEvent, NSImage, NSArray, NSDictionary, NSMutableArray;

NS_ASSUME_NONNULL_BEGIN

// A drag that -[NSView beginDraggingSessionWithItems:event:source:] started
@interface NSDraggingSession : NSObject {
    NSArray *_items;
    NSMutableArray *_screenFrames; // each item's dragging frame, in screen coordinates
    NSPasteboard *_pasteboard;
    id _source;
    NSView *_view;
    NSEvent *_event;
    NSDraggingFormation _formation;
    NSInteger _leaderIndex, _sequenceNumber;
    NSPoint _location;
    NSPoint _mouseInImage; // where the mouse is, from the bottom left corner of the dragged image
    BOOL _animates;
}

@property NSDraggingFormation draggingFormation;
@property BOOL animatesToStartingPositionsOnCancelOrFail;
@property NSInteger draggingLeaderIndex;
@property(readonly) NSPasteboard *draggingPasteboard;
@property(readonly) NSInteger draggingSequenceNumber;
@property(readonly) NSPoint draggingLocation;

- (void) enumerateDraggingItemsWithOptions: (NSDraggingItemEnumerationOptions) enumOpts
                                   forView: (nullable NSView *) view
                                   classes: (NSArray<Class> *) classArray
                             searchOptions: (NSDictionary *) searchOptions
                                usingBlock: (void (^)(NSDraggingItem *draggingItem, NSInteger idx, BOOL *stop)) block;

@end

NS_ASSUME_NONNULL_END
