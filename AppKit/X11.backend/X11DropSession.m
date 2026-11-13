/* Copyright (c) 2008 Johannes Fortmann

 Permission is hereby granted, free of charge, to any person obtaining a copy of
 this software and associated documentation files (the "Software"), to deal in
 the Software without restriction, including without limitation the rights to
 use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
 of the Software, and to permit persons to whom the Software is furnished to do
 so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE. */

#import "X11DropSession.h"
#import "X11FileURLs.h"
#import "X11Window.h"
#import "X11Display.h"
#import <AppKit/NSWindow-Drag.h>
#import <AppKit/NSWindow.h>

@implementation X11DropSession

- (id) initWithSource: (Window) source
      selectionName: (NSString *) selection
             target: (X11Window *) target
               types: (NSArray *) types
    sourceOperations: (NSDragOperation) operations
{
    if ((self = [super initWithName: selection])) {
        _xdpy = [(X11Display *) [NSDisplay currentDisplay] display];
        _targetWindow = [target retain];
        _destination = [[target delegate] retain];
        _source = source;
        _types = [types copy];
        _sourceOperations = operations;
        static int nextSequence = 0;
        _sequence = ++nextSequence;
    }
    return self;
}

- (void) dealloc {
    [_targetWindow release];
    [_destination release];
    [_receiver release];
    [_types release];
    [super dealloc];
}

- (BOOL) matchesSource: (Window) source {
    // XDND requires a target to ignore every message that is not part of the
    // drag it is currently holding.
    return !_invalidated && source != None && source == _source;
}

- (NSDragOperation) updateAtRootX: (int) rootX
                           rootY: (int) rootY
                 requestedActions: (NSDragOperation) actions
{
    if (_invalidated)
        return NSDragOperationNone;

    int windowX = 0, windowY = 0;
    Window child;
    // XDND positions are root-relative device pixels, while the receiver is
    // addressed in window coordinates. A reparenting window manager inserts
    // frames between the root and this window, so translate rather than subtract.
    if (!XTranslateCoordinates(_xdpy, DefaultRootWindow(_xdpy),
                               [_targetWindow windowHandle], rootX, rootY, &windowX,
                               &windowY, &child))
        return NSDragOperationNone;
    _point = [_targetWindow logicalPoint: NSMakePoint(windowX, windowY)];

    // A drop already being performed owns the outcome; the source keeps sending
    // positions while the receiver reads the selection, and those must not
    // renegotiate it.
    if (_dropAnnounced)
        return NSDragOperationNone;

    id receiver = [_targetWindow isMapped] ? [_destination _receiverForDragSession: self]
                                     : nil;
    NSDragOperation operation = NSDragOperationNone;
    if (receiver != _receiver) {
        _acceptedOperations = NSDragOperationNone;
        id old = _receiver;
        _receiver = [receiver retain];
        @try {
            [old draggingExited: self];
        } @finally {
            [old release];
        }
        operation = [_receiver draggingEntered: self];
    } else {
        operation = [_receiver draggingUpdated: self];
    }
    if (_invalidated)
        return NSDragOperationNone;

    // A source that leaves the action field empty is not refusing, it is just
    // older than the action negotiation, so fall back to everything it offers.
    if (actions == NSDragOperationNone)
        actions = _sourceOperations;

    NSDragOperation accepted = operation & _sourceOperations & actions;
    // One operation for the whole drag: the source draws its cursor from
    // XdndStatus and later reports one action in XdndFinished, so narrowing to a
    // single bit keeps the three in step.
    if (accepted & NSDragOperationCopy)
        accepted = NSDragOperationCopy;
    else if (accepted & NSDragOperationMove)
        accepted = NSDragOperationMove;
    else if (accepted & NSDragOperationLink)
        accepted = NSDragOperationLink;
    else
        accepted = NSDragOperationNone;
    _acceptedOperations = accepted;
    return accepted;
}

- (NSDragOperation) performDrop {
    _dropAnnounced = YES;

    NSDragOperation performed = NSDragOperationNone;
    if (!_invalidated && _acceptedOperations != NSDragOperationNone &&
        [_targetWindow isMapped] &&
        [_destination _receiverForDragSession: self] == _receiver) {
        // Each step re-checks the receiver: reading the selection pumps the X
        // connection, and a callback can move the drag somewhere else entirely.
        BOOL prepared = ![_receiver respondsToSelector: @selector(prepareForDragOperation:)] ||
                        [_receiver prepareForDragOperation: self];
        if (prepared && [_targetWindow isMapped] &&
            [_destination _receiverForDragSession: self] == _receiver &&
            [_receiver performDragOperation: self] && !_transferFailed)
            performed = _acceptedOperations;
    }
    if (performed != NSDragOperationNone)
        [_receiver concludeDragOperation: self];
    [self invalidate];
    return performed;
}

- (void) leave {
    // A source may send XdndLeave as soon as it sees XdndDrop, while the
    // transfer this session owns is still running.
    if (_dropAnnounced)
        return;
    [self invalidate];
    [_receiver draggingExited: self];
}

- (void) invalidate {
    _invalidated = YES;
}

// A drag pasteboard is read-only, so there is nothing to clear. Inheriting the
// pasteboard's own -clearContents would also make -dealloc take ownership of the
// drag selection on an already destroyed helper window.
- (NSInteger) clearContents {
    return _sequence;
}

#pragma mark NSPasteboard

- (NSString *) name {
    return NSDragPboard;
}

- (NSInteger) changeCount {
    return _sequence;
}

- (NSArray *) types {
    return _types;
}

- (NSData *) dataForType: (NSPasteboardType) type {
    // A source that never offered a type has not failed to send one, so this
    // must not be counted as a broken transfer.
    if (_invalidated || ![_types containsObject: type])
        return nil;
    // NSFilenamesPboardType is an AppKit type with no X counterpart; file
    // managers publish their files as text/uri-list.
    NSData *data = [super dataForType: [type isEqual: NSFilenamesPboardType]
                                          ? @"text/uri-list"
                                          : type];
    if (!data) {
        _transferFailed = YES;
        return nil;
    }
    if (![type isEqual: NSFilenamesPboardType])
        return data;
    NSArray *files = X11FilenamesFromURIList(data);
    if (!files) {
        _transferFailed = YES;
        return nil;
    }
    return [NSPropertyListSerialization dataFromPropertyList: files
                                                     format: NSPropertyListXMLFormat_v1_0
                                           errorDescription: NULL];
}

#pragma mark NSDraggingInfo

- (NSPasteboard *) draggingPasteboard {
    return self;
}

- (NSDragOperation) draggingSourceOperationMask {
    // Once dropped, report the operation this target chose; NSDraggingInfo has no
    // separate accessor for the selected operation.
    return _dropAnnounced ? _acceptedOperations : _sourceOperations;
}

- (NSPoint) draggingLocation {
    return _point;
}

- (NSWindow *) draggingDestinationWindow {
    return _destination;
}

- (NSImage *) draggedImage {
    return nil;
}

- (NSPoint) draggedImageLocation {
    return _point;
}

- (id) draggingSource {
    return nil; // XDND sources live in other clients.
}

- (int) draggingSequenceNumber {
    return _sequence;
}

- (void) slideDraggedImageTo: (NSPoint) point {
}

- (NSArray *) namesOfPromisedFilesDroppedAtDestination: (NSURL *) destination {
    return nil;
}

@end
