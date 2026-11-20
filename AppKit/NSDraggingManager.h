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

#import <Foundation/NSGeometry.h>
#import <Foundation/NSObject.h>

@class NSWindow, NSImage, NSEvent, NSPasteboard, NSArray, NSView, NSDraggingItem;

@interface NSDraggingManager : NSObject

+ (NSDraggingManager *) draggingManager;

- (void) registerWindow: (NSWindow *) window dragTypes: (NSArray *) types;
- (void) unregisterWindow: (NSWindow *) window;

- (id) localDraggingSource;

- (void) dragImage: (NSImage *) image
                at: (NSPoint) location
            offset: (NSSize) offset
             event: (NSEvent *) event
        pasteboard: (NSPasteboard *) pasteboard
            source: (id) source
         slideBack: (BOOL) slideBack;

@end

#import <AppKit/NSDraggingSession.h>

@protocol NSDraggingInfo;

// What the dragging managers and the NSDraggingInfo implementations share
@interface NSDraggingSession (NSDraggingManager)

// A session dragging items whose data is already on pasteboard, from view, which the mouse event began; it starts
// on the next pass of the run loop
- (instancetype) _initWithItems: (NSArray<NSDraggingItem *> *) items
                           view: (NSView *) view
                          event: (NSEvent *) event
                         source: (id<NSDraggingSource>) source
                     pasteboard: (NSPasteboard *) pasteboard;
- (void) _scheduleStart;

// The object a drag's destination sees as its source: a session's source, or the source given to
// -dragImage:at:offset:event:pasteboard:source:slideBack:
+ (id) _sourceForDestination: (id) dragSource;

// The mask a destination is offered, narrowed by the modifier keys held now
+ (NSDragOperation) _operationMask: (NSDragOperation) mask narrowedForSource: (id) dragSource;

// -[NSDraggingInfo enumerateDraggingItemsWithOptions:forView:classes:searchOptions:usingBlock:], for a drag
// whose source is dragSource (nil when it comes from another application)
+ (void) _enumerateItemsOfDraggingInfo: (id<NSDraggingInfo>) info
                                source: (id) dragSource
                               forView: (NSView *) view
                               classes: (NSArray<Class> *) classArray
                         searchOptions: (NSDictionary *) searchOptions
                            usingBlock: (void (^)(NSDraggingItem *item, NSInteger index, BOOL *stop)) block;

@end
