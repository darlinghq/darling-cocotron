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

#import "X11DraggingManager.h"
#import "X11DragOperations.h"
#import "X11DropSession.h"
#import "X11Display.h"
#import "X11Window.h"
#import <AppKit/NSEvent.h>
#import <AppKit/NSWindow.h>
#import <X11/Xatom.h>

// Implemented in X11Pasteboard.m but not declared there, because so far only the
// pasteboard itself needed them. Reusing the mapping keeps XDND's MIME type names
// and the pasteboard's X selection targets from drifting apart.
@interface X11Pasteboard (XDNDTypes)
+ (NSPasteboardType) typeForTarget: (NSString *) target;
@end

// XDND version 5: XdndFinished gained the performed flag and its action field.
static const unsigned X11XdndVersion = 5;

static X11DraggingManager *X11SharedManager;

@implementation X11DraggingManager

+ (X11DraggingManager *) sharedManager {
    if (X11SharedManager == nil)
        X11SharedManager = [[X11DraggingManager alloc] init];
    return X11SharedManager;
}

- (instancetype) init {
    if ((self = [super init])) {
        _xdpy = [(X11Display *) [NSDisplay currentDisplay] display];
        if (_xdpy == NULL) {
            [self release];
            return nil;
        }
        _atom.aware = XInternAtom(_xdpy, "XdndAware", False);
        _atom.proxy = XInternAtom(_xdpy, "XdndProxy", False);
        _atom.enter = XInternAtom(_xdpy, "XdndEnter", False);
        _atom.position = XInternAtom(_xdpy, "XdndPosition", False);
        _atom.status = XInternAtom(_xdpy, "XdndStatus", False);
        _atom.leave = XInternAtom(_xdpy, "XdndLeave", False);
        _atom.drop = XInternAtom(_xdpy, "XdndDrop", False);
        _atom.finished = XInternAtom(_xdpy, "XdndFinished", False);
        _atom.selection = XInternAtom(_xdpy, "XdndSelection", False);
        _atom.typeList = XInternAtom(_xdpy, "XdndTypeList", False);
        _atom.actionCopy = XInternAtom(_xdpy, "XdndActionCopy", False);
        _atom.actionMove = XInternAtom(_xdpy, "XdndActionMove", False);
        _atom.actionLink = XInternAtom(_xdpy, "XdndActionLink", False);
    }
    return self;
}

- (void) dealloc {
    [_session release];
    [super dealloc];
}

#pragma mark Target registration

- (void) registerWindow: (NSWindow *) window dragTypes: (NSArray *) types {
    // XdndAware has to be on every top-level window that can accept a drop, and
    // carries the highest XDND version this target speaks.
    Window handle = [(X11Window *) [window platformWindow] windowHandle];
    if (handle != None) {
        unsigned long version = X11XdndVersion;
        XChangeProperty(_xdpy, handle, _atom.aware, XA_ATOM, 32,
                        PropModeReplace, (unsigned char *) &version, 1);
    }
}

// Starting a drag needs a pointer grab, motion tracking and ownership of the
// drag selection, none of which exists yet. Left as a no-op rather than the base
// class's NSInvalidAbstractInvocation, because +draggingManager now answers with
// this object and -[NSView dragImage:...] reaches it.
- (void) dragImage: (NSImage *) image
                at: (NSPoint) location
            offset: (NSSize) offset
             event: (NSEvent *) event
        pasteboard: (NSPasteboard *) pasteboard
            source: (id) source
         slideBack: (BOOL) slideBack
{
    NSLog(@"X11 backend: dragging is not implemented, drop this drag");
}

- (void) windowReparented: (X11Window *) window intoParent: (Window) parent {
    Window handle = [window windowHandle];
    if (handle == None || parent == None ||
        parent == DefaultRootWindow(_xdpy))
        return;
    // Under a reparenting window manager the pointer sits over the frame, which
    // belongs to the window manager and carries no XdndAware, so this is the only
    // way a source can find the window that is listening. The specification also
    // requires the proxy to point at itself.
    XChangeProperty(_xdpy, parent, _atom.proxy, XA_ATOM, 32, PropModeReplace,
                    (unsigned char *) &handle, 1);
    XChangeProperty(_xdpy, handle, _atom.proxy, XA_ATOM, 32, PropModeReplace,
                    (unsigned char *) &handle, 1);
}

#pragma mark Source properties

static NSString *X11PropertyAtomName(Display *xdpy, Atom atom) {
    char *name = XGetAtomName(xdpy, atom);
    if (name == NULL)
        return nil;
    NSString *result = [NSString stringWithUTF8String: name];
    XFree(name);
    return result;
}

- (NSString *) selectionNameFromSource: (Window) source {
    Atom type;
    int format;
    unsigned long count, remaining;
    unsigned char *data = NULL;
    // XdndSelection is a pair: the selection to convert, and the property the
    // target is asked to receive it on. X11Pasteboard always receives on its own
    // RECEIVING_PROPERTY, which every source honours because the X protocol has
    // the conversion write to whatever property the requestor named, so only the
    // selection half is needed here.
    if (XGetWindowProperty(_xdpy, source, _atom.selection, 0, 2, False, XA_ATOM,
                           &type, &format, &count, &remaining,
                           &data) == Success &&
        type == XA_ATOM && format == 32 && count >= 1) {
        NSString *name = X11PropertyAtomName(_xdpy, (Atom) ((long *) data)[0]);
        if (data)
            XFree(data);
        return name;
    }
    if (data)
        XFree(data);
    return nil;
}

- (NSString *) pasteboardTypeForAtom: (Atom) atom {
    NSString *name = X11PropertyAtomName(_xdpy, atom);
    if (name == nil)
        return nil;
    // XDND type names are MIME types, and the pasteboard already knows which of
    // them are the AppKit string type.
    return [X11Pasteboard typeForTarget: name];
}

- (NSArray *) typesFromEnter: (XClientMessageEvent *) message source: (Window) source {
    NSMutableArray *types = [NSMutableArray array];
    for (int i = 2; i <= 4; i++) {
        NSString *type = [self pasteboardTypeForAtom: (Atom) message->data.l[i]];
        if (type)
            [types addObject: type];
    }
    // Bit 0 of data.l[1] says the three inline slots did not hold every type.
    if (message->data.l[1] & 1) {
        Atom type;
        int format;
        unsigned long count, remaining;
        unsigned char *data = NULL;
        if (XGetWindowProperty(_xdpy, source, _atom.typeList, 0, 1024, False,
                               XA_ATOM, &type, &format, &count, &remaining,
                               &data) == Success &&
            type == XA_ATOM && format == 32) {
            for (unsigned long i = 0; i < count; i++) {
                NSString *pasteboardType =
                        [self pasteboardTypeForAtom: ((Atom *) data)[i]];
                if (pasteboardType)
                    [types addObject: pasteboardType];
            }
        }
        if (data)
            XFree(data);
    }
    return types;
}

- (BOOL) source: (Window) source advertises: (Atom) action {
    Atom type;
    int format;
    unsigned long count, remaining;
    unsigned char *data = NULL;
    BOOL present =
            XGetWindowProperty(_xdpy, source, action, 0, 1, False, XA_ATOM, &type,
                               &format, &count, &remaining, &data) == Success &&
            type != None;
    if (data)
        XFree(data);
    return present;
}

- (NSDragOperation) operationsFromSource: (Window) source version: (unsigned) version {
    // Versions 0 and 1 predate action negotiation, and their action is always copy.
    if (version < 2)
        return NSDragOperationCopy;
    NSDragOperation operations = NSDragOperationNone;
    if ([self source: source advertises: _atom.actionCopy])
        operations |= NSDragOperationCopy;
    if ([self source: source advertises: _atom.actionMove])
        operations |= NSDragOperationMove;
    if ([self source: source advertises: _atom.actionLink])
        operations |= NSDragOperationLink;
    // The specified default for a source that advertises no action at all.
    return operations != NSDragOperationNone ? operations : NSDragOperationCopy;
}

#pragma mark XDND messages

- (void) handleXdndMessage: (XClientMessageEvent *) message
                  toWindow: (X11Window *) window
{
    if (message->format != 32)
        return;
    Atom type = message->message_type;

    if (type == _atom.position) {
        [self handlePosition: message toWindow: window];
    } else if (type == _atom.drop) {
        [self handleDrop: message toWindow: window];
    } else if (type == _atom.enter) {
        [self handleEnter: message toWindow: window];
    } else if (type == _atom.leave) {
        // A target has to ignore messages from any source but the one it is
        // holding a session for.
        if ([_session matchesSource: (Window) message->data.l[0]])
            [_session leave];
    }
}

- (void) handleEnter: (XClientMessageEvent *) message toWindow: (X11Window *) window {
    Window source = (Window) message->data.l[0];
    unsigned version = (unsigned) (message->data.l[1] & 0xFF);
    // A version this target does not speak cannot be negotiated. A new offer is
    // also refused while a drop is being performed, because the receiver's own
    // callbacks can pump the X connection and the running session must survive.
    if (source == None || version > X11XdndVersion || _inDrop)
        return;

    NSString *selection = [self selectionNameFromSource: source];
    NSArray *types = selection ? [self typesFromEnter: message source: source] : nil;
    if (selection == nil || [types count] == 0)
        return;

    // A source that re-enters without leaving first would otherwise strand the
    // receiver it had already entered.
    [_session leave];
    [_session release];
    _session = [[X11DropSession alloc] initWithSource: source
                                        selectionName: selection
                                               target: window
                                                 types: types
                                      sourceOperations: [self operationsFromSource: source
                                                                            version: version]];
}

- (void) handlePosition: (XClientMessageEvent *) message toWindow: (X11Window *) window {
    Window source = (Window) message->data.l[0];
    NSDragOperation accepted = NSDragOperationNone;
    if ([_session matchesSource: source]) {
        // XdndPosition packs the root-relative pointer position into two 16-bit
        // halves of one word, x in the high half and y in the low half.
        long packed = message->data.l[2];
        accepted = [_session updateAtRootX: (int) ((packed >> 16) & 0xFFFF)
                                     rootY: (int) (packed & 0xFFFF)
                           requestedActions: X11OperationsFromActions(
                                   (uint32_t) message->data.l[4])];
    }
    [self sendStatusTo: window source: source operations: accepted];
}

- (void) handleDrop: (XClientMessageEvent *) message toWindow: (X11Window *) window {
    Window source = (Window) message->data.l[0];
    if (_inDrop)
        return;
    NSDragOperation performed = NSDragOperationNone;
    if ([_session matchesSource: source]) {
        _inDrop = YES;
        @try {
            performed = [_session performDrop];
        } @finally {
            _inDrop = NO;
        }
    }
    [self sendFinishedTo: window source: source operations: performed];
}

// Both replies are addressed to the source window, which is where the source
// reads them, but name this target in data.l[0] so it can match them against the
// session it started, which it may still be holding after XdndLeave.
- (void) sendStatusTo: (X11Window *) window source: (Window) source
            operations: (NSDragOperation) operations
{
    Window target = [window windowHandle];
    if (target == None || source == None)
        return;
    XEvent event = {0};
    event.xclient.type = ClientMessage;
    event.xclient.window = source;
    event.xclient.message_type = _atom.status;
    event.xclient.format = 32;
    event.xclient.data.l[0] = (long) target;
    event.xclient.data.l[1] = operations != NSDragOperationNone ? 1 : 0;
    // Bit 1 stays clear and the suppression rectangle is empty, which means "send
    // a position for every mouse move": a receiver has to keep draggingUpdated:
    // in step with the pointer to draw its drop feedback.
    event.xclient.data.l[2] = 0;
    event.xclient.data.l[3] = 0;
    event.xclient.data.l[4] = (long) X11ActionsFromOperations(operations);
    XSendEvent(_xdpy, source, False, NoEventMask, &event);
    XFlush(_xdpy);
}

- (void) sendFinishedTo: (X11Window *) window source: (Window) source
              operations: (NSDragOperation) operations
{
    Window target = [window windowHandle];
    if (target == None || source == None)
        return;
    XEvent event = {0};
    event.xclient.type = ClientMessage;
    event.xclient.window = source;
    event.xclient.message_type = _atom.finished;
    event.xclient.format = 32;
    event.xclient.data.l[0] = (long) target;
    // Version 5 added the performed flag. A source older than that assumes
    // success on any XdndFinished, so the flag only has to be truthful for a
    // peer that negotiated version 5.
    event.xclient.data.l[1] = operations != NSDragOperationNone ? 1 : 0;
    event.xclient.data.l[2] = (long) [self atomForOperations: operations];
    XSendEvent(_xdpy, source, False, NoEventMask, &event);
    XFlush(_xdpy);
}

- (Atom) atomForOperations: (NSDragOperation) operations {
    if (operations & NSDragOperationCopy)
        return _atom.actionCopy;
    if (operations & NSDragOperationMove)
        return _atom.actionMove;
    if (operations & NSDragOperationLink)
        return _atom.actionLink;
    return None;
}

@end
