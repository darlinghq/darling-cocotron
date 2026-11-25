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

#import "NSDraggingSession-Private.h"
#import "NSDraggingManager.h"
#import <AppKit/NSEvent.h>
#import <AppKit/NSGraphicsContext.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSPasteboardItem.h>
#import <AppKit/NSView.h>
#import <AppKit/NSWindow.h>
#import <ApplicationServices/ApplicationServices.h>
#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSValue.h>
#import <objc/runtime.h>

// The session whose drag is running. Drags run on the main thread, one at a
// time, so there is never more than one.
static NSDraggingSession *currentSession;

@implementation NSDraggingSession

NS_EXTRA_SYNTHESIZE_ASSIGN(NSDraggingSession, draggingFormation, _draggingFormation,
                           NSDraggingFormation, draggingFormation, setDraggingFormation:)
NS_EXTRA_SYNTHESIZE_ASSIGN(NSDraggingSession, animatesToStartingPositionsOnCancelOrFail,
                           _animatesToStartingPositionsOnCancelOrFail, BOOL,
                           animatesToStartingPositionsOnCancelOrFail,
                           setAnimatesToStartingPositionsOnCancelOrFail:)
NS_EXTRA_SYNTHESIZE_ASSIGN(NSDraggingSession, draggingLeaderIndex, _draggingLeaderIndex,
                           NSInteger, draggingLeaderIndex, setDraggingLeaderIndex:)

- (instancetype) _initWithItems: (NSArray<NSDraggingItem *> *) items
                           view: (NSView *) view
                         source: (id) source
                     pasteboard: (NSPasteboard *) pasteboard
                 sequenceNumber: (NSInteger) sequenceNumber
                  startLocation: (NSPoint) startLocation
                    startFrames: (NSArray *) startFrames
                         leader: (NSInteger) leader
{
    self = [super init];
    if (self == nil)
        return nil;
    NS_EXTRA(NSDraggingSession, self)->_items = [items copy];
    NS_EXTRA(NSDraggingSession, self)->_view = [view retain];
    NS_EXTRA(NSDraggingSession, self)->_source = [source retain];
    NS_EXTRA(NSDraggingSession, self)->_pasteboard = [pasteboard retain];
    NS_EXTRA(NSDraggingSession, self)->_draggingSequenceNumber = sequenceNumber;
    NS_EXTRA(NSDraggingSession, self)->_draggingLocation = startLocation;
    NS_EXTRA(NSDraggingSession, self)->_startLocation = startLocation;
    NS_EXTRA(NSDraggingSession, self)->_startFrames = [startFrames copy];
    NS_EXTRA(NSDraggingSession, self)->_draggingLeaderIndex = leader;
    // The defaults the header documents.
    NS_EXTRA(NSDraggingSession, self)->_draggingFormation = NSDraggingFormationNone;
    NS_EXTRA(NSDraggingSession, self)->_animatesToStartingPositionsOnCancelOrFail = YES;
    return self;
}

- (void) dealloc {
    if (NS_EXTRA_ALLOCATED(NSDraggingSession, self)) {
        [NS_EXTRA(NSDraggingSession, self)->_items release];
        [NS_EXTRA(NSDraggingSession, self)->_view release];
        [NS_EXTRA(NSDraggingSession, self)->_source release];
        [NS_EXTRA(NSDraggingSession, self)->_pasteboard release];
        [NS_EXTRA(NSDraggingSession, self)->_startFrames release];
    }
    NS_EXTRA_FREE(NSDraggingSession, self);
    [super dealloc];
}

- (NSPasteboard *) draggingPasteboard {
    return NS_EXTRA(NSDraggingSession, self)->_pasteboard;
}

- (NSInteger) draggingSequenceNumber {
    return NS_EXTRA(NSDraggingSession, self)->_draggingSequenceNumber;
}

- (NSPoint) draggingLocation {
    return NS_EXTRA(NSDraggingSession, self)->_draggingLocation;
}

- (id) _source {
    return NS_EXTRA(NSDraggingSession, self)->_source;
}

- (void) _setDraggingLocation: (NSPoint) location {
    NS_EXTRA(NSDraggingSession, self)->_draggingLocation = location;
}

// Where an item is now, in screen coordinates: the items keep the place they
// had relative to the pointer when the drag began.
- (NSRect) _screenFrameOfItemAtIndex: (NSUInteger) index {
    NSRect frame = [[NS_EXTRA(NSDraggingSession, self)->_startFrames objectAtIndex: index] rectValue];
    NSPoint start = NS_EXTRA(NSDraggingSession, self)->_startLocation;
    NSPoint now = NS_EXTRA(NSDraggingSession, self)->_draggingLocation;
    frame.origin.x += now.x - start.x;
    frame.origin.y += now.y - start.y;
    return frame;
}

static NSRect screenRectToView(NSRect rect, NSView *view) {
    if (view == nil)
        return rect;
    NSWindow *window = [view window];
    if (window != nil)
        rect = [window convertRectFromScreen: rect];
    return [view convertRect: rect fromView: nil];
}

// The pasteboard has an item for each dragging item, in the same order, as
// -beginDraggingSessionWithItems:event:source: wrote them.
- (void) enumerateDraggingItemsWithOptions: (NSDraggingItemEnumerationOptions) options
                                   forView: (NSView *) view
                                   classes: (NSArray<Class> *) classArray
                             searchOptions: (NSDictionary<NSPasteboardReadingOptionKey, id> *) searchOptions
                                usingBlock: (void (^)(NSDraggingItem *draggingItem, NSInteger idx, BOOL *stop)) block
{
    NSArray<NSDraggingItem *> *items = NS_EXTRA(NSDraggingSession, self)->_items;
    NSPasteboard *pasteboard = NS_EXTRA(NSDraggingSession, self)->_pasteboard;
    NSArray *pasteboardItems = [pasteboard pasteboardItems];
    NSUInteger count = MIN([items count], [pasteboardItems count]);

    for (NSUInteger index = 0; index < count; index++) {
        id object = [pasteboard _readObjectForClasses: classArray
                                              options: searchOptions
                                             fromItem: [pasteboardItems objectAtIndex: index]];
        if (object == nil)
            continue;

        // A new item each time (observed on macOS 26.7.3), with the original's image.
        NSDraggingItem *original = [items objectAtIndex: index];
        NSDraggingItem *item = [[[NSDraggingItem alloc] _initWithItem: object] autorelease];
        [item setDraggingFrame: screenRectToView([self _screenFrameOfItemAtIndex: index], view)];
        [item setImageComponentsProvider: [original imageComponentsProvider]];

        BOOL stop = NO;
        block(item, (NSInteger) index, &stop);
        if (stop)
            break;
    }
}

@end

#pragma mark Beginning a session

static NSInteger lastSequenceNumber;
// A session was begun and its drag has not run yet.
static BOOL sessionPending;
// The source of the running session was told the drag ended.
static BOOL sessionEnded;

static void draggingSourceEnded(id source, NSImage *image, NSPoint point, NSDragOperation operation);

@interface NSWindow (NSDraggingInProcess)
- (void) _dragImageInProcess: (NSImage *) image
                          at: (NSPoint) imageLocation
                       event: (NSEvent *) event
                  pasteboard: (NSPasteboard *) pasteboard
                      source: (id) source;
@end

// Runs the drag the way -[NSView dragImage:...] does, without sending that
// message: a subclass's override of it is not part of a session's drag.
static void runDrag(NSWindow *window, NSImage *image, NSPoint locationInWindow, NSEvent *event,
                    NSPasteboard *pasteboard, id source, BOOL slideBack)
{
    NSDraggingManager *manager = [NSDraggingManager draggingManager];
    if (manager == nil) {
        [window _dragImageInProcess: image
                                 at: locationInWindow
                              event: event
                         pasteboard: pasteboard
                             source: source];
        return;
    }
    [manager dragImage: image
                    at: locationInWindow
                offset: NSZeroSize
                 event: event
            pasteboard: pasteboard
                source: source
             slideBack: slideBack];
}

static NSRect standardFrame(NSDraggingItem *item) {
    return NSRectFromCGRect(CGRectStandardize(NSRectToCGRect([item draggingFrame])));
}

// The rectangle all items cover, in the view's coordinates.
static NSRect unionOfFrames(NSArray<NSDraggingItem *> *items) {
    NSRect bounds = NSZeroRect;
    BOOL first = YES;
    for (NSDraggingItem *item in items) {
        NSRect frame = standardFrame(item);
        bounds = first ? frame : NSUnionRect(bounds, frame);
        first = NO;
    }
    return bounds;
}

static void drawComponentContents(id contents, NSRect rect) {
    if ([contents isKindOfClass: [NSImage class]]) {
        [(NSImage *) contents drawInRect: rect
                                fromRect: NSZeroRect
                               operation: NSCompositeSourceOver
                                fraction: 1.0];
        return;
    }
    if (contents != nil && CFGetTypeID((CFTypeRef) contents) == CGImageGetTypeID()) {
        CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];
        CGContextDrawImage(context, NSRectToCGRect(rect), (CGImageRef) contents);
    }
}

// One image of every item's components, laid out as the items are in the view.
static NSImage *compositeImage(NSArray<NSDraggingItem *> *items, NSRect bounds, BOOL flipped) {
    NSSize size = bounds.size;
    if (size.width < 1)
        size.width = 1;
    if (size.height < 1)
        size.height = 1;
    NSImage *image = [[[NSImage alloc] initWithSize: size] autorelease];

    [image lockFocus];
    for (NSDraggingItem *item in items) {
        NSRect frame = standardFrame(item);
        CGFloat x = frame.origin.x - bounds.origin.x;
        // The image is never flipped, so in a flipped view an item that is
        // lower in the view is lower in the image too.
        CGFloat y = flipped ? NSMaxY(bounds) - NSMaxY(frame) : frame.origin.y - bounds.origin.y;
        for (NSDraggingImageComponent *component in [item imageComponents]) {
            NSRect rect = [component frame];
            rect.origin.x += x;
            rect.origin.y += y;
            drawComponentContents([component contents], rect);
        }
    }
    [image unlockFocus];
    return image;
}

// The index of the item nearest to the point, the default leader.
static NSInteger nearestItem(NSArray<NSDraggingItem *> *items, NSPoint point) {
    NSInteger best = 0;
    CGFloat bestDistance = 0;
    NSInteger index = 0;
    for (NSDraggingItem *item in items) {
        NSRect frame = standardFrame(item);
        CGFloat dx = point.x < NSMinX(frame) ? NSMinX(frame) - point.x
                   : point.x > NSMaxX(frame) ? point.x - NSMaxX(frame) : 0;
        CGFloat dy = point.y < NSMinY(frame) ? NSMinY(frame) - point.y
                   : point.y > NSMaxY(frame) ? point.y - NSMaxY(frame) : 0;
        CGFloat distance = dx * dx + dy * dy;
        if (index == 0 || distance < bestDistance) {
            best = index;
            bestDistance = distance;
        }
        index++;
    }
    return best;
}

@implementation NSView (NSDrag)

- (NSDraggingSession *) beginDraggingSessionWithItems: (NSArray<NSDraggingItem *> *) items
                                                event: (NSEvent *) event
                                               source: (id<NSDraggingSource>) source
{
    // QUIRK: while a session is waiting to start or running, another one is
    // not started and nil is returned. Not documented. Evidence: black-box
    // observation on macOS 26.7.3 (tier 2): a second call made before the run
    // loop ran the first drag returns nil.
    // Test: tests/appkit-dragging-session.m, "a second session waits for none".
    if (sessionPending || currentSession != nil)
        return nil;

    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithName: NSPasteboardNameDrag];
    [pasteboard clearContents];
    NSMutableArray *writers = [NSMutableArray arrayWithCapacity: [items count]];
    for (NSDraggingItem *item in items)
        if ([item item] != nil)
            [writers addObject: [item item]];
    [pasteboard writeObjects: writers];

    NSWindow *window = [self window];
    NSPoint eventInView = [self convertPoint: [event locationInWindow] fromView: nil];
    NSPoint start = [NSEvent mouseLocation];

    NSMutableArray *startFrames = [NSMutableArray arrayWithCapacity: [items count]];
    for (NSDraggingItem *item in items) {
        NSRect frame = [self convertRect: standardFrame(item) toView: nil];
        if (window != nil)
            frame = [window convertRectToScreen: frame];
        // relative to where the pointer is now rather than to the event
        NSPoint eventOnScreen = window != nil ? [window convertBaseToScreen: [event locationInWindow]]
                                              : [event locationInWindow];
        frame.origin.x += start.x - eventOnScreen.x;
        frame.origin.y += start.y - eventOnScreen.y;
        [startFrames addObject: [NSValue valueWithRect: frame]];
    }

    NSDraggingSession *session = [[NSDraggingSession alloc]
            _initWithItems: items
                      view: self
                    source: source
                pasteboard: pasteboard
            sequenceNumber: ++lastSequenceNumber
             startLocation: start
               startFrames: startFrames
                    leader: nearestItem(items, eventInView)];

    // The drag runs once the caller has returned to the run loop, so it can
    // still set the session's properties (as on macOS, where this method
    // returns before the source hears of the drag).
    NSRect bounds = unionOfFrames(items);
    BOOL flipped = [self isFlipped];
    NSImage *image = [compositeImage(items, bounds, flipped) retain];
    NSPoint at = [self convertPoint: NSMakePoint(NSMinX(bounds), flipped ? NSMaxY(bounds) : NSMinY(bounds))
                             toView: nil];
    NSEvent *heldEvent = [event retain];
    NSWindow *heldWindow = [window retain];
    NSDraggingSession *heldSession = [session retain];

    CFRunLoopRef runLoop = CFRunLoopGetMain();
    sessionPending = YES;
    CFRunLoopPerformBlock(runLoop, kCFRunLoopCommonModes, ^{
        sessionPending = NO;
        currentSession = heldSession;
        sessionEnded = NO;
        @try {
            runDrag(heldWindow, image, at, heldEvent, pasteboard, source,
                    [heldSession animatesToStartingPositionsOnCancelOrFail]);
            // A drag the backend could not start still ends for the source.
            if (!sessionEnded)
                draggingSourceEnded(source, image, [NSEvent mouseLocation], NSDragOperationNone);
        } @finally {
            currentSession = nil;
            [heldSession release];
            [heldWindow release];
            [heldEvent release];
            [image release];
        }
    });
    CFRunLoopWakeUp(runLoop);

    return [session autorelease];
}

@end

#pragma mark Telling the source

static NSDraggingSession *sessionOfSource(id source) {
    if (currentSession != nil && [currentSession _source] == source)
        return currentSession;
    return nil;
}

static NSDragOperation draggingSourceOperationMask(id source, BOOL local, NSDragOperation defaultMask) {
    NSDraggingSession *session = sessionOfSource(source);
    if (session != nil &&
        [source respondsToSelector: @selector(draggingSession:sourceOperationMaskForDraggingContext:)])
        return [source draggingSession: session
                sourceOperationMaskForDraggingContext: local ? NSDraggingContextWithinApplication
                                                             : NSDraggingContextOutsideApplication];
    if ([source respondsToSelector: @selector(draggingSourceOperationMaskForLocal:)])
        return [source draggingSourceOperationMaskForLocal: local];
    return defaultMask;
}

static void draggingSourceBegan(id source, NSImage *image, NSPoint point) {
    NSDraggingSession *session = sessionOfSource(source);
    if (session != nil) {
        if ([source respondsToSelector: @selector(draggingSession:willBeginAtPoint:)])
            [source draggingSession: session willBeginAtPoint: point];
        return;
    }
    if ([source respondsToSelector: @selector(draggedImage:beganAt:)])
        [source draggedImage: image beganAt: point];
}

static void draggingSourceMoved(id source, NSImage *image, NSPoint point) {
    NSDraggingSession *session = sessionOfSource(source);
    if (session != nil) {
        [session _setDraggingLocation: [NSEvent mouseLocation]];
        if ([source respondsToSelector: @selector(draggingSession:movedToPoint:)])
            [source draggingSession: session movedToPoint: point];
        return;
    }
    if ([source respondsToSelector: @selector(draggedImage:movedTo:)])
        [source draggedImage: image movedTo: point];
}

static void draggingSourceEnded(id source, NSImage *image, NSPoint point, NSDragOperation operation) {
    NSDraggingSession *session = sessionOfSource(source);
    if (session != nil) {
        sessionEnded = YES;
        [session _setDraggingLocation: [NSEvent mouseLocation]];
        if ([source respondsToSelector: @selector(draggingSession:endedAtPoint:operation:)])
            [source draggingSession: session endedAtPoint: point operation: operation];
        return;
    }
    if ([source respondsToSelector: @selector(draggedImage:endedAt:operation:)])
        [source draggedImage: image endedAt: point operation: operation];
}

#pragma mark The destination's side

// What a destination set on the dragging info of a drop.
@interface NSDraggingInfoSettings : NSObject {
  @public
    NSDraggingFormation _formation;
    BOOL _animatesToDestination;
    NSInteger _numberOfValidItems;
    BOOL _hasNumberOfValidItems;
}
@end

@implementation NSDraggingInfoSettings
@end

static char kDraggingInfoSettingsKey;

static NSDraggingInfoSettings *settingsOf(id<NSDraggingInfo> info, BOOL create) {
    NSDraggingInfoSettings *settings = objc_getAssociatedObject(info, &kDraggingInfoSettingsKey);
    if (settings == nil && create) {
        settings = [[[NSDraggingInfoSettings alloc] init] autorelease];
        // the header: the current formation, the session's for a drag of this application
        NSDraggingSession *session = sessionOfSource([info draggingSource]);
        settings->_formation = session != nil ? [session draggingFormation] : NSDraggingFormationDefault;
        objc_setAssociatedObject(info, &kDraggingInfoSettingsKey, settings, OBJC_ASSOCIATION_RETAIN);
    }
    return settings;
}

static NSDraggingFormation draggingInfoFormation(id<NSDraggingInfo> info) {
    return settingsOf(info, YES)->_formation;
}

static void draggingInfoSetFormation(id<NSDraggingInfo> info, NSDraggingFormation formation) {
    settingsOf(info, YES)->_formation = formation;
}

static BOOL draggingInfoAnimatesToDestination(id<NSDraggingInfo> info) {
    return settingsOf(info, YES)->_animatesToDestination;
}

static void draggingInfoSetAnimatesToDestination(id<NSDraggingInfo> info, BOOL animates) {
    settingsOf(info, YES)->_animatesToDestination = animates;
}

// Until the destination sets it: every item of the drag. Inferred from the
// header, which has the destination lower it when it accepts only some.
static NSInteger draggingInfoNumberOfValidItems(id<NSDraggingInfo> info) {
    NSDraggingInfoSettings *settings = settingsOf(info, YES);
    if (settings->_hasNumberOfValidItems)
        return settings->_numberOfValidItems;
    return (NSInteger) [[[info draggingPasteboard] pasteboardItems] count];
}

static void draggingInfoSetNumberOfValidItems(id<NSDraggingInfo> info, NSInteger count) {
    NSDraggingInfoSettings *settings = settingsOf(info, YES);
    settings->_numberOfValidItems = count;
    settings->_hasNumberOfValidItems = YES;
}

static void draggingInfoEnumerateItems(id<NSDraggingInfo> info,
        NSDraggingItemEnumerationOptions options, NSView *view, NSArray<Class> *classArray,
        NSDictionary<NSPasteboardReadingOptionKey, id> *searchOptions,
        void (^block)(NSDraggingItem *draggingItem, NSInteger idx, BOOL *stop))
{
    NSPasteboard *pasteboard = [info draggingPasteboard];

    // A drag this application began knows where each of its items is.
    NSDraggingSession *session = sessionOfSource([info draggingSource]);
    if (session != nil && [[session draggingPasteboard] isEqual: pasteboard]) {
        [session enumerateDraggingItemsWithOptions: options
                                           forView: view
                                           classes: classArray
                                     searchOptions: searchOptions
                                        usingBlock: block];
        return;
    }

    // Otherwise the items are where the dragged image is, all of them.
    NSRect frame = NSZeroRect;
    frame.origin = [info draggedImageLocation];
    frame.size = [[info draggedImage] size];
    NSWindow *window = [info draggingDestinationWindow];
    if (view != nil)
        frame = [view convertRect: frame fromView: nil];
    else if (window != nil)
        frame = [window convertRectToScreen: frame];

    NSInteger index = 0;
    for (NSPasteboardItem *pasteboardItem in [pasteboard pasteboardItems]) {
        id object = [pasteboard _readObjectForClasses: classArray
                                              options: searchOptions
                                             fromItem: pasteboardItem];
        if (object != nil) {
            NSDraggingItem *item = [[[NSDraggingItem alloc] _initWithItem: object] autorelease];
            [item setDraggingFrame: frame];
            BOOL stop = NO;
            block(item, index, &stop);
            if (stop)
                break;
        }
        index++;
    }
}

@implementation NSDraggingSession (NSDraggingPrivate)

+ (NSDragOperation) _operationMaskOfSource: (id) source
                                     local: (BOOL) local
                               defaultMask: (NSDragOperation) defaultMask
{
    return draggingSourceOperationMask(source, local, defaultMask);
}

+ (void) _source: (id) source beganWithImage: (NSImage *) image at: (NSPoint) point {
    draggingSourceBegan(source, image, point);
}

+ (void) _source: (id) source movedWithImage: (NSImage *) image to: (NSPoint) point {
    draggingSourceMoved(source, image, point);
}

+ (void) _source: (id) source endedWithImage: (NSImage *) image at: (NSPoint) point
       operation: (NSDragOperation) operation
{
    draggingSourceEnded(source, image, point, operation);
}

+ (NSDraggingFormation) _formationOfInfo: (id<NSDraggingInfo>) info {
    return draggingInfoFormation(info);
}

+ (void) _setFormation: (NSDraggingFormation) formation ofInfo: (id<NSDraggingInfo>) info {
    draggingInfoSetFormation(info, formation);
}

+ (BOOL) _animatesToDestinationOfInfo: (id<NSDraggingInfo>) info {
    return draggingInfoAnimatesToDestination(info);
}

+ (void) _setAnimatesToDestination: (BOOL) animates ofInfo: (id<NSDraggingInfo>) info {
    draggingInfoSetAnimatesToDestination(info, animates);
}

+ (NSInteger) _numberOfValidItemsOfInfo: (id<NSDraggingInfo>) info {
    return draggingInfoNumberOfValidItems(info);
}

+ (void) _setNumberOfValidItems: (NSInteger) count ofInfo: (id<NSDraggingInfo>) info {
    draggingInfoSetNumberOfValidItems(info, count);
}

+ (void) _enumerateItemsOfInfo: (id<NSDraggingInfo>) info
                       options: (NSDraggingItemEnumerationOptions) options
                       forView: (NSView *) view
                       classes: (NSArray<Class> *) classArray
                 searchOptions: (NSDictionary<NSPasteboardReadingOptionKey, id> *) searchOptions
                    usingBlock: (void (^)(NSDraggingItem *draggingItem, NSInteger idx, BOOL *stop)) block
{
    draggingInfoEnumerateItems(info, options, view, classArray, searchOptions, block);
}

@end
