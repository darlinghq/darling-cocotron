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

// What AppKit's drag code shares about sessions: the drag managers run every
// drag the way -[NSView dragImage:...] does, and a drag begun as a session
// reaches its source through the methods here, which send the session's messages to
// a source that has them and the older ones otherwise.

#import <AppKit/NSDragging.h>
#import <AppKit/NSDraggingItem.h>
#import <AppKit/NSDraggingSession.h>
#import <AppKit/NSPasteboard.h>

@class NSImage, NSPasteboardItem;

@interface NSDraggingItem (NSDraggingPrivate)
- (instancetype) _initWithItem: (id) item;
@end

@interface NSPasteboard (NSDraggingItemReading)
- (id) _readObjectForClasses: (NSArray<Class> *) classArray
                     options: (NSDictionary<NSPasteboardReadingOptionKey, id> *) options
                    fromItem: (NSPasteboardItem *) item;
@end

// Methods rather than functions, so the backends (libraries of their own)
// reach them without AppKit exporting anything more.
@interface NSDraggingSession (NSDraggingPrivate)

// The operations the source allows, or defaultMask when it doesn't say.
+ (NSDragOperation) _operationMaskOfSource: (id) source
                                     local: (BOOL) local
                               defaultMask: (NSDragOperation) defaultMask;
// Points are in screen coordinates.
+ (void) _source: (id) source beganWithImage: (NSImage *) image at: (NSPoint) point;
+ (void) _source: (id) source movedWithImage: (NSImage *) image to: (NSPoint) point;
+ (void) _source: (id) source endedWithImage: (NSImage *) image at: (NSPoint) point
       operation: (NSDragOperation) operation;

// The parts of NSDraggingInfo that are the same for every kind of drop.
+ (NSDraggingFormation) _formationOfInfo: (id<NSDraggingInfo>) info;
+ (void) _setFormation: (NSDraggingFormation) formation ofInfo: (id<NSDraggingInfo>) info;
+ (BOOL) _animatesToDestinationOfInfo: (id<NSDraggingInfo>) info;
+ (void) _setAnimatesToDestination: (BOOL) animates ofInfo: (id<NSDraggingInfo>) info;
+ (NSInteger) _numberOfValidItemsOfInfo: (id<NSDraggingInfo>) info;
+ (void) _setNumberOfValidItems: (NSInteger) count ofInfo: (id<NSDraggingInfo>) info;
+ (void) _enumerateItemsOfInfo: (id<NSDraggingInfo>) info
                       options: (NSDraggingItemEnumerationOptions) options
                       forView: (NSView *) view
                       classes: (NSArray<Class> *) classArray
                 searchOptions: (NSDictionary<NSPasteboardReadingOptionKey, id> *) searchOptions
                    usingBlock: (void (^)(NSDraggingItem *draggingItem, NSInteger idx, BOOL *stop)) block;

@end

// The NSDraggingInfo methods a class gets from the functions above.
#define NS_DRAGGING_INFO_SHARED_METHODS                                                   \
    - (NSDraggingFormation) draggingFormation {                                           \
        return [NSDraggingSession _formationOfInfo: self];                                            \
    }                                                                                     \
    - (void) setDraggingFormation: (NSDraggingFormation) formation {                      \
        [NSDraggingSession _setFormation: formation ofInfo: self];                                     \
    }                                                                                     \
    - (BOOL) animatesToDestination {                                                      \
        return [NSDraggingSession _animatesToDestinationOfInfo: self];                                \
    }                                                                                     \
    - (void) setAnimatesToDestination: (BOOL) animates {                                  \
        [NSDraggingSession _setAnimatesToDestination: animates ofInfo: self];                          \
    }                                                                                     \
    - (NSInteger) numberOfValidItemsForDrop {                                             \
        return [NSDraggingSession _numberOfValidItemsOfInfo: self];                                   \
    }                                                                                     \
    - (void) setNumberOfValidItemsForDrop: (NSInteger) count {                            \
        [NSDraggingSession _setNumberOfValidItems: count ofInfo: self];                                \
    }                                                                                     \
    - (void) enumerateDraggingItemsWithOptions: (NSDraggingItemEnumerationOptions) options \
                                       forView: (NSView *) view                           \
                                       classes: (NSArray<Class> *) classArray             \
                                 searchOptions: (NSDictionary *) searchOptions            \
                                    usingBlock: (void (^)(NSDraggingItem *, NSInteger, BOOL *)) block \
    {                                                                                     \
        [NSDraggingSession _enumerateItemsOfInfo: self options: options forView: view classes: classArray searchOptions: searchOptions usingBlock: block]; \
    }                                                                                     \
    - (NSSpringLoadingHighlight) springLoadingHighlight {                                 \
        return NSSpringLoadingHighlightNone;                                              \
    }                                                                                     \
    - (void) resetSpringLoading {                                                         \
    }
