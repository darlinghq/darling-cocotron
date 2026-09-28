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
#import <AppKit/NSDraggingManager.h>
#import <Foundation/NSGeometry.h>
#import <X11/Xlib.h>

@class X11DropSession, X11Pasteboard, X11Window;

// XDND, both halves. The target half advertises this backend's windows as drag
// targets and answers the ClientMessages a source sends them. The source half
// runs the drag -dragImage:... was stubbed for: it owns the drag selection, grabs
// the pointer and sends XdndEnter, XdndPosition, XdndDrop and XdndLeave until the
// target it is talking to is done with it.
@interface X11DraggingManager : NSDraggingManager {
    Display *_xdpy;
    struct {
        Atom aware, proxy, enter, position, status, leave, drop, finished;
        Atom selection, typeList, actionCopy, actionMove, actionLink;
    } _atom;
    X11DropSession *_session;
    BOOL _inDrop;

    // One drag at a time. _dragPasteboard owns the drag selection, and its helper
    // window is the XDND source window, so the properties a target reads and the
    // data it converts are answered by one window.
    X11Pasteboard *_dragPasteboard;
    Window _dragWindow;
    // The window the last XdndEnter and XdndLeave went to, and the one whose
    // XdndStatus is the answer the drag is currently decided on.
    Window _enteredWindow, _targetWindow;
    // The window the pointer is actually over. Under a reparenting window manager
    // that is the frame, and a target reached through XdndProxy names it rather
    // than the proxy in its replies, so it is the other window a reply may name.
    Window _pointerWindow;
    Atom *_dragTypes;
    unsigned long _dragTypeCount;
    NSDragOperation _offeredOperations, _chosenOperations;
    NSRect _suppressionRect;
    Atom _dropAction;
    BOOL _dragging, _targetAccepts, _suppressionWanted, _awaitingStatus, _dropFinished;
}

// One per display, like the display's pasteboards: the manager is reached through
// +[NSDraggingManager draggingManager] and has to outlive any single window.
+ (X11DraggingManager *) sharedManager;

- (void) windowReparented: (X11Window *) window intoParent: (Window) parent;
- (void) handleXdndMessage: (XClientMessageEvent *) message
                  toWindow: (X11Window *) window;

// Sent by -[X11Display postXEvent:] for the replies a target addresses to a
// drag's source window, and for the property deletions that pace a transfer too
// large for one request, which arrive on the receiving window rather than on ours.
- (void) handleXdndSourceMessage: (XClientMessageEvent *) message;
- (void) handlePropertyChange: (XPropertyEvent *) event;

@end
