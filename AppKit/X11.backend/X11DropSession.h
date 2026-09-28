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

#import "X11Pasteboard.h"
#import <AppKit/NSDragging.h>
#import <X11/Xlib.h>

@class X11Window;

// One incoming XDND offer. The pasteboard is an X11Pasteboard bound to the
// source's drag selection, so the data it serves never touches the clipboard.
// The wire methods are driven by X11DraggingManager; everything below them is
// the backend-neutral half that talks to views.
@interface X11DropSession : X11Pasteboard <NSDraggingInfo> {
    Display *_xdpy;
    X11Window *_targetWindow;
    NSWindow *_destination;
    Window _source;
    NSArray *_types;
    id _receiver;
    NSDragOperation _sourceOperations, _acceptedOperations;
    NSPoint _point;
    int _sequence;
    BOOL _dropAnnounced, _transferFailed, _invalidated;
}

// The selection is named rather than passed as an atom because X11Pasteboard
// derives its selection atom from the pasteboard name, and a drag's selection is
// only reachable through that one path.
- (id) initWithSource: (Window) source
      selectionName: (NSString *) selection
             target: (X11Window *) target
               types: (NSArray *) types
    sourceOperations: (NSDragOperation) operations;

- (BOOL) matchesSource: (Window) source;

// Returns the single operation the receiver accepted, NSDragOperationNone if it
// refused, so the manager can mirror it in XdndStatus.
- (NSDragOperation) updateAtRootX: (int) rootX
                           rootY: (int) rootY
                 requestedActions: (NSDragOperation) actions;

// Returns the operation actually performed, NSDragOperationNone if the drop was
// refused or failed.
- (NSDragOperation) performDrop;
- (void) leave;

@end
