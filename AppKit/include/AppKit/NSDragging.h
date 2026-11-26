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

#import <Foundation/Foundation.h>

@class NSPasteboard, NSWindow, NSImage, NSView, NSDraggingItem, NSDraggingSession, NSDictionary, NSArray, NSURL;

typedef NS_OPTIONS(NSUInteger, NSDragOperation) {
    NSDragOperationNone = 0x00,
    NSDragOperationCopy = 0x01,
    NSDragOperationLink = 0x02,
    NSDragOperationGeneric = 0x04,
    NSDragOperationPrivate = 0x08,
    NSDragOperationMove = 0x10,
    NSDragOperationDelete = 0x20,
    NSDragOperationEvery = NSUIntegerMax,
};

typedef NS_ENUM(NSInteger, NSDraggingFormation) {
    NSDraggingFormationDefault = 0,
    NSDraggingFormationNone,
    NSDraggingFormationPile,
    NSDraggingFormationList,
    NSDraggingFormationStack,
};

typedef NS_ENUM(NSInteger, NSDraggingContext) {
    NSDraggingContextOutsideApplication = 0,
    NSDraggingContextWithinApplication,
};

typedef NS_OPTIONS(NSUInteger, NSDraggingItemEnumerationOptions) {
    NSDraggingItemEnumerationConcurrent = 1,
    NSDraggingItemEnumerationClearNonenumeratedImages = (1UL << 16),
};

typedef NS_ENUM(NSInteger, NSSpringLoadingHighlight) {
    NSSpringLoadingHighlightNone = 0,
    NSSpringLoadingHighlightStandard,
    NSSpringLoadingHighlightEmphasized,
};

typedef NS_OPTIONS(NSUInteger, NSSpringLoadingOptions) {
    NSSpringLoadingDisabled = 0,
    NSSpringLoadingEnabled = 1UL << 0,
    NSSpringLoadingContinuousActivation = 1UL << 1,
    NSSpringLoadingNoHover = 1UL << 3,
};

@protocol NSDraggingInfo <NSObject>
- (NSPasteboard *) draggingPasteboard;
- (NSDragOperation) draggingSourceOperationMask;
- (NSPoint) draggingLocation;
- (NSImage *) draggedImage;
- (NSPoint) draggedImageLocation;
- (NSWindow *) draggingDestinationWindow;
- (id) draggingSource;
- (void) slideDraggedImageTo: (NSPoint) point;
- (NSInteger) draggingSequenceNumber;
- (NSArray *) namesOfPromisedFilesDroppedAtDestination: (NSURL *) destination;

// What a destination sees of the items, and may change for the rest of the drag
@property NSDraggingFormation draggingFormation;
@property BOOL animatesToDestination;
@property NSInteger numberOfValidItemsForDrop;
- (void) enumerateDraggingItemsWithOptions: (NSDraggingItemEnumerationOptions) enumOpts
                                   forView: (NSView *) view
                                   classes: (NSArray<Class> *) classArray
                             searchOptions: (NSDictionary *) searchOptions
                                usingBlock: (void (^)(NSDraggingItem *draggingItem, NSInteger idx, BOOL *stop)) block;
@property(readonly) NSSpringLoadingHighlight springLoadingHighlight;
- (void) resetSpringLoading;
@end

@protocol NSDraggingDestination <NSObject>
@optional
- (BOOL) prepareForDragOperation: (id<NSDraggingInfo>) sender;
- (BOOL) performDragOperation: (id<NSDraggingInfo>) sender;
- (void) concludeDragOperation: (id<NSDraggingInfo>) sender;

- (NSDragOperation) draggingEntered: (id<NSDraggingInfo>) sender;
- (void) draggingExited: (id<NSDraggingInfo>) sender;
- (NSDragOperation) draggingUpdated: (id<NSDraggingInfo>) sender;
- (void) draggingEnded: (id<NSDraggingInfo>) sender;

- (BOOL) wantsPeriodicDraggingUpdates;
@end

@protocol NSDraggingSource <NSObject>
- (NSDragOperation) draggingSession: (NSDraggingSession *) session
    sourceOperationMaskForDraggingContext: (NSDraggingContext) context;
@optional
- (void) draggingSession: (NSDraggingSession *) session willBeginAtPoint: (NSPoint) screenPoint;
- (void) draggingSession: (NSDraggingSession *) session movedToPoint: (NSPoint) screenPoint;
- (void) draggingSession: (NSDraggingSession *) session
            endedAtPoint: (NSPoint) screenPoint
               operation: (NSDragOperation) operation;
- (BOOL) ignoreModifierKeysForDraggingSession: (NSDraggingSession *) session;
@end

// The source methods of -dragImage:at:offset:event:pasteboard:source:slideBack:, which came before
// dragging sessions
@interface NSObject (NSDraggingSourceDeprecated)
- (BOOL) ignoreModifierKeysWhileDragging;
- (NSDragOperation) draggingSourceOperationMaskForLocal: (BOOL) flag;
- (void) draggedImage: (NSImage *) image beganAt: (NSPoint) point;
- (void) draggedImage: (NSImage *) image movedTo: (NSPoint) point;
- (void) draggedImage: (NSImage *) image
              endedAt: (NSPoint) point
            operation: (NSDragOperation) operation;
- (NSArray *) namesOfPromisedFilesDroppedAtDestination: (NSURL *) destination;
@end
