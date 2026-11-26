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

#import <AppKit/NSDragging.h>
#import <AppKit/NSPasteboard.h>
#import <CoreGraphics/CGSDrag.h>

@class NSWindow;

// An incoming drag as the destinations of an AppKit window see it: the NSDraggingInfo of a CoreGraphics drop session
// (see CGSDrag.h), whose pasteboard is the source's data, read when a destination asks for it, and which never touches
// the clipboard. The window system's protocol is CoreGraphics'; everything here is the half that talks to views.
@interface NSCGSDropSession : NSPasteboard <NSDraggingInfo> {
    id<CGSDropSession> _session;
    NSWindow *_destination;
    NSArray *_types;
    id _receiver;
    NSDragOperation _sourceOperations, _acceptedOperations;
    NSPoint _point;
    int _sequence;
    id _localSource;          // the drag's source when it comes from this application
    NSInteger _validItems;    // -1 until a destination sets numberOfValidItemsForDrop
    NSDraggingFormation _formation;
    BOOL _animatesToDestination;
    BOOL _dropAnnounced, _transferFailed, _invalidated;
}

- (id) initWithSession: (id<CGSDropSession>) session window: (NSWindow *) window localSource: (id) source;

// The session this is the view of
- (id<CGSDropSession>) dropSession;

// The operations the receiver accepts at a position of the window (points from its top left corner, y down), from
// the mask the source was offered.
- (NSDragOperation) updateAtPoint: (CGPoint) point;
// The drop: returns the operation actually performed, NSDragOperationNone if the drop was refused or failed.
- (NSDragOperation) performDropWithOperation: (NSDragOperation) operation;
- (void) leave;

@end
