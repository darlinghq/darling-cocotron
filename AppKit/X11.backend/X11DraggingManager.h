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

#import <AppKit/NSDraggingManager.h>
#import <X11/Xlib.h>

@class X11DropSession, X11Window;

// Drop target half of XDND: advertises this backend's windows as drag targets,
// answers the ClientMessages a source sends them, and owns the one session in
// flight. Starting a drag (dragImage:at:offset:event:pasteboard:source:slideBack:)
// is not implemented yet.
@interface X11DraggingManager : NSDraggingManager {
    Display *_xdpy;
    struct {
        Atom aware, proxy, enter, position, status, leave, drop, finished;
        Atom selection, typeList, actionCopy, actionMove, actionLink;
    } _atom;
    X11DropSession *_session;
    BOOL _inDrop;
}

// One per display, like the display's pasteboards: the manager is reached through
// +[NSDraggingManager draggingManager] and has to outlive any single window.
+ (X11DraggingManager *) sharedManager;

- (void) windowReparented: (X11Window *) window intoParent: (Window) parent;
- (void) handleXdndMessage: (XClientMessageEvent *) message
                  toWindow: (X11Window *) window;

@end
