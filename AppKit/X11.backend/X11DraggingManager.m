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
#import <Foundation/NSDate.h>
#import <X11/Xatom.h>

// Implemented in X11Pasteboard.m but not declared there, because so far only the
// pasteboard itself needed them. Reusing the mapping keeps XDND's MIME type names
// and the pasteboard's X selection targets from drifting apart.
@interface X11Pasteboard (XDNDTypes)
+ (NSPasteboardType) typeForTarget: (NSString *) target;
@end

// XDND version 5: XdndFinished gained the performed flag and its action field.
static const unsigned X11XdndVersion = 5;

// The events a drag consumes while it holds the pointer: the motion that follows
// it and the release that ends it. Everything else the application receives is
// left in the queue for when the drag is over.
static const NSEventMask X11XdndDragEventMask =
        NSLeftMouseUpMask | NSLeftMouseDraggedMask | NSMouseMovedMask;

// A drag's selection is a selection of its own, so a second drag started before
// the first target finished reading cannot be served the first one's data. That
// is the hole version 0 of the protocol leaves open, and a fresh selection for
// every drag closes it.
static unsigned X11DragCount;

// How long the source waits for the answer to the position it is dropping on, and
// for the target to finish with the data it asked for. Both are bounded: a target
// that never answers must not hang the drag, and a target that never says it is
// done must not keep the data alive for ever.
static const NSTimeInterval X11XdndStatusGrace = 0.5;
static const NSTimeInterval X11XdndFinishedGrace = 10.0;

static BOOL X11PointerInRoot(Display *xdpy, int *x, int *y) {
    Window root, child;
    int windowX, windowY;
    unsigned int mask;
    return XQueryPointer(xdpy, DefaultRootWindow(xdpy), &root, &child, x, y, &windowX,
                         &windowY, &mask);
}

static BOOL X11HasProperty(Display *xdpy, Window w, Atom prop, Atom type) {
    Atom actualType;
    int format;
    unsigned long count, remaining;
    unsigned char *data = NULL;
    BOOL present =
            XGetWindowProperty(xdpy, w, prop, 0, 1, False, type, &actualType, &format,
                               &count, &remaining, &data) == Success &&
            actualType == type && format == 32 && count >= 1;
    if (data)
        XFree(data);
    return present;
}

// An action is advertised by a property of its own name holding that action. The
// protocol's XdndActionList belongs to the XdndActionAsk dialog, which this
// source does not offer.
static void X11AdvertiseAction(Display *xdpy, Window w, Atom action) {
    XChangeProperty(xdpy, w, action, XA_ATOM, 32, PropModeReplace,
                    (unsigned char *) &action, 1);
}

// The selection a drag publishes is served from the pasteboard the application
// handed to -dragImage:..., read when a target asks for it. Nothing is copied up
// front, so a payload that does not fit in memory twice still drags.
@interface X11DragProvider : NSObject <NSPasteboardTypeOwner> {
    NSPasteboard *_pasteboard;
}

- (id) initWithPasteboard: (NSPasteboard *) pasteboard;

@end

@implementation X11DragProvider

- (id) initWithPasteboard: (NSPasteboard *) pasteboard {
    if ((self = [super init]))
        _pasteboard = [pasteboard retain];
    return self;
}

- (void) dealloc {
    [_pasteboard release];
    [super dealloc];
}

- (void) pasteboard: (NSPasteboard *) sender
    provideDataForType: (NSPasteboardType) type
{
    // A type the application promised but cannot produce is left unpublished: the
    // target then gets a refusal for that name instead of an empty answer it
    // would have to tell apart from a real value.
    NSData *data = [_pasteboard dataForType: type];
    if (data != nil)
        [sender setData: data forType: type];
}

- (void) pasteboardChangedOwner: (NSPasteboard *) sender {
}

@end

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
    // A drag is synchronous, so this is only reached if one was started and the
    // process tore down inside it, but the pasteboard owns an X window and has to
    // give it back rather than leak it into the server.
    [_dragPasteboard release];
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
#pragma mark Source

// The X selection target names each NSPasteboardType converts to, so this is
// both the type list a drag advertises and the set of names a target may ask for.
// Building it from the same table a SelectionRequest is answered with is what
// keeps an advertised name and the type behind it from drifting apart.
- (NSArray<NSString *> *) selectionTargetsForPasteboard: (NSPasteboard *) pasteboard {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSPasteboardType type in [pasteboard types])
        for (NSString *name in [X11Pasteboard targetsForType: type])
            if (![names containsObject: name])
                [names addObject: name];
    return names;
}

- (void) dragImage: (NSImage *) image
                at: (NSPoint) location
            offset: (NSSize) offset
             event: (NSEvent *) event
        pasteboard: (NSPasteboard *) pasteboard
            source: (id) source
         slideBack: (BOOL) slideBack
{
    if (_dragging) {
        NSLog(@"X11 backend: a drag is already running, this one never started");
        return;
    }

    // Only the three actions XDND has atoms for can be offered: a target names the
    // one it wants, and the rest could not be named on the wire.
    NSDragOperation operations = NSDragOperationCopy;
    if ([source respondsToSelector: @selector(draggingSourceOperationMaskForLocal:)])
        operations = [source draggingSourceOperationMaskForLocal: NO];
    operations &= NSDragOperationCopy | NSDragOperationMove | NSDragOperationLink;

    NSArray<NSString *> *names = [self selectionTargetsForPasteboard: pasteboard];
    if (operations == NSDragOperationNone || [names count] == 0) {
        NSLog(@"X11 backend: nothing to drag that XDND could describe");
        return;
    }

    // The grab goes on the window the drag started in, so its motion and button
    // events keep arriving as this backend's normal mouse events.
    X11Window *origin = (X11Window *) [[event window] platformWindow];
    if (origin == nil) {
        NSLog(@"X11 backend: the drag event has no window to grab the pointer on");
        return;
    }

    // The selection's helper window is the drag's source window: the target reads
    // the properties below from it and converts the selection it names, so one
    // window answers both and there is nothing to keep in step.
    X11Pasteboard *board = [[X11Pasteboard alloc] initWithName:
            [NSString stringWithFormat: @"COCOTRON_DRAG_SELECTION_%u", ++X11DragCount]];
    X11DragProvider *provider = [[X11DragProvider alloc] initWithPasteboard: pasteboard];
    [board addTypes: [pasteboard types] owner: provider];
    [provider release];

    Window sourceWindow = [board windowHandle];
    unsigned long version = X11XdndVersion;
    XChangeProperty(_xdpy, sourceWindow, _atom.aware, XA_ATOM, 32, PropModeReplace,
                    (unsigned char *) &version, 1);
    // XdndSelection names the selection to convert, and may carry a second atom
    // naming the property to receive it on. The conversion lands on the property
    // the target names in XConvertSelection whatever this says, so the second
    // atom is left out rather than guessed at by whatever reads it.
    Atom selection = [board selectionAtom];
    XChangeProperty(_xdpy, sourceWindow, _atom.selection, XA_ATOM, 32, PropModeReplace,
                    (unsigned char *) &selection, 1);
    if (operations & NSDragOperationCopy)
        X11AdvertiseAction(_xdpy, sourceWindow, _atom.actionCopy);
    if (operations & NSDragOperationMove)
        X11AdvertiseAction(_xdpy, sourceWindow, _atom.actionMove);
    if (operations & NSDragOperationLink)
        X11AdvertiseAction(_xdpy, sourceWindow, _atom.actionLink);
    _dragTypeCount = [names count];
    _dragTypes = malloc(sizeof(Atom) * _dragTypeCount);
    for (unsigned long i = 0; i < _dragTypeCount; i++)
        _dragTypes[i] = XInternAtom(_xdpy, [[names objectAtIndex: i] UTF8String], False);
    // The message has room for three names, and this drag has more, so a target has
    // to read this property to see the rest. Listing all of them here as well keeps
    // a target that only reads the message from missing a type it could have used.
    XChangeProperty(_xdpy, sourceWindow, _atom.typeList, XA_ATOM, 32, PropModeReplace,
                    (unsigned char *) _dragTypes, _dragTypeCount);

    if (XGrabPointer(_xdpy, [origin windowHandle], False,
                     ButtonReleaseMask | ButtonMotionMask | PointerMotionMask,
                     GrabModeAsync, GrabModeAsync, None, None,
                     CurrentTime) != GrabSuccess) {
        NSLog(@"X11 backend: cannot grab the pointer, the drag never started");
        [self releaseDragState];
        return;
    }

    NSImage *heldImage = [image retain];
    id heldSource = [source retain];
    NSDragOperation result = NSDragOperationNone;
    BOOL began = NO;
    _dragging = YES;
    _dragPasteboard = board;
    _dragWindow = sourceWindow;
    _offeredOperations = operations;
    @try {
        int rootX = 0, rootY = 0;
        X11PointerInRoot(_xdpy, &rootX, &rootY);
        [self sendPositionAtRootX: rootX rootY: rootY];
        began = YES;
        if ([heldSource respondsToSelector: @selector(draggedImage:beganAt:)])
            [heldSource draggedImage: heldImage beganAt: location];

        int lastX = rootX, lastY = rootY;
        while (!_dropFinished) {
            NSEvent *next = [[NSDisplay currentDisplay]
                    nextEventMatchingMask: X11XdndDragEventMask
                              untilDate: [NSDate dateWithTimeIntervalSinceNow: 0.01]
                                 inMode: NSDefaultRunLoopMode
                                dequeue: YES];
            if (next != nil) {
                // The release is the drag's end. Any other event that reaches here
                // is the pointer the drag is holding; the application's own events
                // are not in the mask and stay queued for when it is over.
                if (next.type == NSLeftMouseUp)
                    break;
                continue;
            }
            // One position at a time. The answer to a position says which action
            // the target would take there, so a drag that outran its target would
            // be deciding on an answer to a place the pointer has left.
            if (!_awaitingStatus && X11PointerInRoot(_xdpy, &rootX, &rootY) &&
                (rootX != lastX || rootY != lastY)) {
                lastX = rootX;
                lastY = rootY;
                // A target's own rectangle says it needs no positions while the
                // pointer is inside it, unless it asked for them anyway.
                if (![self pointerInsideSuppressionRectAtRootX: rootX rootY: rootY])
                    [self sendPositionAtRootX: rootX rootY: rootY];
            }
        }

        // A release and the answer to the position it belongs to arrive over the
        // same connection and either can be read first, so the answer is waited
        // for before the drag decides what it did. A target that has already sent
        // XdndFinished is done with the drag and gets nothing further from it.
        if (_awaitingStatus && !_dropFinished)
            [self waitForStatusBefore:
                    [NSDate dateWithTimeIntervalSinceNow: X11XdndStatusGrace]];
        if (_targetAccepts && !_dropFinished) {
            [self sendDrop];
            [self waitForFinishedBefore:
                    [NSDate dateWithTimeIntervalSinceNow: X11XdndFinishedGrace]];
        } else {
            [self sendLeave];
        }
        // The target's own report of what it performed is the only thing that can
        // turn this drag into a result, and only an action this source offered
        // counts, so a target that performed nothing reports nothing.
        if (_dropAction != None)
            result = [self operationForAction: _dropAction] & _offeredOperations;
    } @finally {
        _dragging = NO;
        XUngrabPointer(_xdpy, CurrentTime);
        XSync(_xdpy, False);
        [self releaseDragState];
        @try {
            if (began && [heldSource respondsToSelector:
                                  @selector(draggedImage:endedAt:operation:)])
                [heldSource draggedImage: heldImage endedAt: location operation: result];
        } @finally {
            [heldSource release];
            [heldImage release];
        }
    }
}

// The drag is over as soon as the state is released: the selection is given up
// with the window that owns it, and the negotiated action with the negotiation.
- (void) releaseDragState {
    // Releasing the pasteboard destroys the source window, and a destroyed window
    // gives up every selection it owned. A target still converting gets a refusal
    // instead of the data, which is what the protocol promises it once the source
    // has heard XdndFinished.
    [_dragPasteboard release];
    _dragPasteboard = nil;
    _dragWindow = None;
    _targetWindow = None;
    _enteredWindow = None;
    _pointerWindow = None;
    _chosenOperations = _offeredOperations = NSDragOperationNone;
    _dropAction = None;
    _suppressionRect = NSZeroRect;
    _targetAccepts = _suppressionWanted = _awaitingStatus = _dropFinished = NO;
    free(_dragTypes);
    _dragTypes = NULL;
    _dragTypeCount = 0;
}

// ----------------------------------------------------------------- replies

- (void) handleXdndSourceMessage: (XClientMessageEvent *) message {
    if (!_dragging || message->format != 32)
        return;

    if (message->message_type == _atom.status) {
        // data.l[0] names the window in which the pointer was, which for a target
        // reached through XdndProxy is the frame rather than the proxy that answers.
        Window target = (Window) message->data.l[0];
        if (target == None)
            return;
        // A target the pointer has already left keeps answering positions it was
        // sent before the pointer moved on, and its answer describes a place that
        // no longer has anything to do with where the drop would land. Accepting it
        // would let a stale target claim the drag, or clear the acceptance the
        // target under the pointer had already given.
        if (target != _enteredWindow && target != _pointerWindow) {
            [self sendLeaveTo: target];
            return;
        }
        _targetWindow = _enteredWindow != None ? _enteredWindow : target;
        _awaitingStatus = NO;
        if (message->data.l[1] & 1) {
            Atom action = (Atom) message->data.l[4];
            // A target older than version 2 accepts with an empty action field,
            // and the protocol's default action is copy.
            _chosenOperations = action != None
                    ? [self operationForAction: action]
                    : (_offeredOperations & NSDragOperationCopy);
        } else {
            _chosenOperations = NSDragOperationNone;
        }
        // A target that reports an action this source never offered has agreed to
        // nothing, and agreeing to that would be the one way a refusal could turn
        // into a reported success.
        _chosenOperations &= _offeredOperations;
        _targetAccepts = _chosenOperations != NSDragOperationNone;
        long origin = message->data.l[2], size = message->data.l[3];
        _suppressionRect = NSMakeRect((origin >> 16) & 0xFFFF, origin & 0xFFFF,
                                      (size >> 16) & 0xFFFF, size & 0xFFFF);
        // Bit 1 asks for positions inside the rectangle as well, which is what a
        // receiver that draws its own feedback needs to stay in step.
        _suppressionWanted = (message->data.l[1] & 2) != 0;
    } else if (message->message_type == _atom.finished) {
        // Version 5 added both fields read here. A target that rejects the drop
        // sends neither, and reading a success out of an answer without them
        // would report a drop that never happened.
        _dropAction = (message->data.l[1] & 1) ? (Atom) message->data.l[2] : None;
        _dropFinished = YES;
    }
}

- (void) handlePropertyChange: (XPropertyEvent *) event {
    [_dragPasteboard propertyNotify: event];
}

// ----------------------------------------------------------------- sending

- (void) sendXdndMessage: (Atom) type
             destination: (Window) destination
                   fields: (const long *) fields
{
    if (destination == None)
        return;
    XEvent event = {0};
    event.xclient.type = ClientMessage;
    // The window field names the window the message is about. Under a reparenting
    // window manager that is the window that carries XdndProxy, which is also the
    // one the message is sent to, since it is the client that created it.
    event.xclient.window = destination;
    event.xclient.message_type = type;
    event.xclient.format = 32;
    for (int i = 0; i < 5; i++)
        event.xclient.data.l[i] = fields[i];
    // An empty event mask sends the message to the client that created the
    // destination window, which is the only one that can act on it.
    XSendEvent(_xdpy, destination, False, NoEventMask, &event);
    XFlush(_xdpy);
}

- (void) sendEnterTo: (Window) target {
    if (target == None)
        return;
    _enteredWindow = target;
    long fields[5] = { (long) _dragWindow, 1 | ((long) X11XdndVersion << 24), 0, 0, 0 };
    for (unsigned long i = 0; i < _dragTypeCount && i < 3; i++)
        fields[2 + i] = (long) _dragTypes[i];
    [self sendXdndMessage: _atom.enter destination: target fields: fields];
}

- (void) sendPositionAtRootX: (int) rootX rootY: (int) rootY {
    // A target is told about the drag when the pointer enters its window, so
    // sending a position to a new one has to tell it first: a target that was
    // never sent an XdndEnter does not know a drag is happening at all.
    Window target = [self xdndAwareWindowAtRootX: rootX rootY: rootY];
    if (target != _enteredWindow) {
        [self sendLeaveTo: _enteredWindow];
        [self sendEnterTo: target];
    }
    // The position is the root-relative pointer location packed into two 16-bit
    // halves of one word, the x coordinate in the high half and y in the low half.
    // The time is the one the target must convert the selection with, and zero
    // means the current time, which is the best this backend has: its events carry
    // no X timestamp, and a drag's selection is a window and an atom of its own, so
    // a time could not tell this drag from the next one either.
    long fields[5] = { (long) _dragWindow, 0,
                       ((long) (rootX & 0xFFFF) << 16) | (rootY & 0xFFFF), 0,
                       (long) X11ActionsFromOperations(_offeredOperations) };
    [self sendXdndMessage: _atom.position destination: target fields: fields];
    _awaitingStatus = YES;
}

- (void) sendDrop {
    // The drop goes to the target the pointer is over, which is the one whose
    // XdndStatus said it would take the drop: sending it anywhere else would
    // offer a window that never agreed to anything.
    if (_targetWindow == None)
        return;
    // The time is the one the target converts the selection with, and zero means
    // the current time, which is when the selection was taken.
    long fields[5] = { (long) _dragWindow, 0, 0, 0, 0 };
    [self sendXdndMessage: _atom.drop destination: _targetWindow fields: fields];
}

- (void) sendLeave {
    [self sendLeaveTo: _enteredWindow];
}

// XdndLeave goes to the window the message is about, and names the source in
// data.l[0], which is how the target tells this apart from another client's drag.
- (void) sendLeaveTo: (Window) target {
    if (target == None || target == _dragWindow)
        return;
    long fields[5] = { (long) _dragWindow, 0, 0, 0, 0 };
    [self sendXdndMessage: _atom.leave destination: target fields: fields];
}

- (NSDragOperation) operationForAction: (Atom) action {
    if (action == _atom.actionCopy)
        return NSDragOperationCopy;
    if (action == _atom.actionMove)
        return NSDragOperationMove;
    if (action == _atom.actionLink)
        return NSDragOperationLink;
    // XdndActionAsk and XdndActionPrivate name actions only both ends understand,
    // and this source offers neither, so there is no operation to map them to.
    return NSDragOperationNone;
}

- (BOOL) pointerInsideSuppressionRectAtRootX: (int) rootX rootY: (int) rootY {
    // An empty rectangle is the protocol's way of saying "no suppression", and a
    // target that wants a position for every move says so with the flag instead.
    return !_suppressionWanted && !NSIsEmptyRect(_suppressionRect) &&
            NSPointInRect(NSMakePoint(rootX, rootY), _suppressionRect);
}

// The window a message is about: the one under the pointer that carries
// XdndAware, following XdndProxy so that a reparenting window manager's frame
// resolves to the window inside it.
- (Window) xdndAwareWindowAtRootX: (int) rootX rootY: (int) rootY {
    Window root, child;
    int windowX, windowY;
    unsigned int mask;
    if (!XQueryPointer(_xdpy, DefaultRootWindow(_xdpy), &root, &child, &rootX, &rootY,
                       &windowX, &windowY, &mask))
        return None;
    // A target answers with the window the pointer is in, which under a
    // reparenting window manager is the frame rather than the window inside it.
    _pointerWindow = child;
    if (X11HasProperty(_xdpy, child, _atom.aware, XA_ATOM))
        return child;

    // The pointer is over the frame a reparenting window manager put around the
    // window, so the frame's XdndProxy is where the drop is really going.
    Atom proxy;
    int format;
    unsigned long count, remaining;
    unsigned char *data = NULL;
    if (XGetWindowProperty(_xdpy, child, _atom.proxy, 0, 1, False, XA_ATOM, &proxy,
                           &format, &count, &remaining, &data) != Success ||
        proxy == None) {
        if (data)
            XFree(data);
        return None;
    }
    if (data)
        XFree(data);
    // The specification says to ignore an XdndProxy left behind by a crashed
    // client: it has to point at itself, and the window it names has to still
    // exist. An XID that has since been reused would otherwise hand the whole drag
    // to an unrelated client.
    if (!X11HasProperty(_xdpy, proxy, _atom.proxy, XA_ATOM))
        return None;
    XWindowAttributes attributes;
    if (!XGetWindowAttributes(_xdpy, proxy, &attributes))
        return None;
    return X11HasProperty(_xdpy, proxy, _atom.aware, XA_ATOM) ? proxy : None;
}

// The drag holds the pointer, so the replies a target sends arrive as X events
// that -[X11Display nextEventMatchingMask:...] turns into messages on the source
// window. Waiting has to keep pumping for them, and for the SelectionRequests the
// target sends while it reads the data, which land on the same pasteboard.
- (void) pumpDragEventsBefore: (NSDate *) deadline {
    @autoreleasepool {
        [[NSDisplay currentDisplay] nextEventMatchingMask: X11XdndDragEventMask
                                              untilDate: deadline
                                                 inMode: NSDefaultRunLoopMode
                                                dequeue: YES];
    }
}

- (void) waitForStatusBefore: (NSDate *) deadline {
    while (_awaitingStatus && [deadline timeIntervalSinceNow] > 0)
        [self pumpDragEventsBefore: deadline];
}

- (void) waitForFinishedBefore: (NSDate *) deadline {
    while (!_dropFinished && [deadline timeIntervalSinceNow] > 0)
        [self pumpDragEventsBefore: deadline];
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
    // XDND type names are MIME types. File managers publish dragged files as
    // text/uri-list, which is the X11 spelling of NSFilenamesPboardType; the
    // pasteboard's own mapping already covers the string types.
    if ([name isEqualToString: @"text/uri-list"])
        return NSFilenamesPboardType;
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
