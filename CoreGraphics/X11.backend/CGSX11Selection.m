/*
This file is part of Darling.

Copyright (C) 2019 Lubos Dolezel

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

#import "CGSX11Selection.h"
#import <Foundation/Foundation.h>
#import "CGSConnectionX11.h"
#import <X11/Xatom.h>
#import <dispatch/dispatch.h>
#include <poll.h>

static const NSUInteger X11IncrChunkSize = 64 * 1024;
static const NSTimeInterval kSelectionPollInterval = 0.02;
static const NSTimeInterval SelectionTimeout = 5;

static NSString *const kTypeString = @"public.utf8-plain-text";

@interface CGSX11IncrTransfer : NSObject {
@public
    Atom _property;
    Atom _type;
    NSData *_data;
    NSUInteger _offset;
    // Whether this transfer made the process select property changes on the requestor's window (so it
    // is the one that takes the selection back).
    BOOL _selectedInput;
    long _previousMask;
}

- (id) initWithProperty: (Atom) property type: (Atom) type data: (NSData *) data;

@end

@implementation CGSX11IncrTransfer

- (id) initWithProperty: (Atom) property type: (Atom) type data: (NSData *) data {
    if ((self = [super init])) {
        _property = property;
        _type = type;
        _data = [data retain];
    }
    return self;
}

- (void) dealloc {
    [_data release];
    [super dealloc];
}

@end

// The largest property write this server will accept. BIG-REQUESTS raises it
// above the protocol minimum, and the answer differs per server, so ask rather
// than assume; 65535 is what the protocol guarantees without it.
static size_t MaximumPropertyBytes(Display *display) {
    long units = XExtendedMaxRequestSize(display);
    if (units <= 0)
        units = 65535;
    return (size_t) units * 4 / 2;
}

@interface CGSX11Selection ()
- (void) selectionRequest: (XSelectionRequestEvent *) event;
- (void) selectionNotify: (XSelectionEvent *) event;
- (void) selectionClear: (XSelectionClearEvent *) event;
- (void) propertyNotify: (XPropertyEvent *) event;
- (Window) windowHandleValue;
- (BOOL) servesTransferTo: (Window) requestor;
@end

// The selections of the process by their helper window, not retained. Events are routed with it, and an INCR transfer
// they serve is paced by events of another client's window that only they can claim.
static NSMutableDictionary<NSNumber *, NSValue *> *windowToSelection;
static NSLock *selectionsLock;

static void registerSelection(CGSX11Selection *selection, Window window) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      windowToSelection = [NSMutableDictionary new];
      selectionsLock = [NSLock new];
    });
    [selectionsLock lock];
    windowToSelection[@(window)] = [NSValue valueWithNonretainedObject: selection];
    [selectionsLock unlock];
}

static void unregisterSelection(Window window) {
    [selectionsLock lock];
    [windowToSelection removeObjectForKey: @(window)];
    [selectionsLock unlock];
}

// The selection for a helper window; the lookup retains it for the duration of the event.
static CGSX11Selection *selectionForWindow(Window window) {
    [selectionsLock lock];
    CGSX11Selection *selection = [[windowToSelection[@(window)] nonretainedObjectValue] retain];
    [selectionsLock unlock];
    return [selection autorelease];
}

static NSArray<CGSX11Selection *> *allSelections(void) {
    [selectionsLock lock];
    NSMutableArray *selections = [NSMutableArray array];
    for (NSValue *value in [windowToSelection allValues])
        [selections addObject: [value nonretainedObjectValue]];
    [selectionsLock unlock];
    return selections;
}

BOOL CGSX11SelectionHandleEvent(XEvent *event) {
    switch (event->type) {
    case SelectionClear: {
        CGSX11Selection *selection = selectionForWindow(event->xselectionclear.window);
        [selection selectionClear: &event->xselectionclear];
        return selection != nil;
    }
    case SelectionRequest: {
        CGSX11Selection *selection = selectionForWindow(event->xselectionrequest.owner);
        [selection selectionRequest: &event->xselectionrequest];
        return selection != nil;
    }
    case SelectionNotify: {
        CGSX11Selection *selection = selectionForWindow(event->xselection.requestor);
        [selection selectionNotify: &event->xselection];
        return selection != nil;
    }
    case PropertyNotify: {
        XPropertyEvent *property = &event->xproperty;
        CGSX11Selection *own = selectionForWindow(property->window);
        BOOL handled = own != nil;
        [own propertyNotify: property];
        // An INCR transfer is paced by the receiver deleting the property, and that property lives on the
        // receiver's window, which belongs to another client. Whichever selection is serving a transfer to
        // that window is the one waiting for the deletion.
        if (property->state == PropertyDelete) {
            for (CGSX11Selection *selection in allSelections()) {
                // The selection whose own window this is has already seen the event.
                if (selection == own)
                    continue;
                if ([selection servesTransferTo: property->window]) {
                    [selection propertyNotify: property];
                    return YES;
                }
            }
        }
        return handled;
    }
    default:
        return NO;
    }
}

@implementation CGSX11Selection

@synthesize source = _source;

- (instancetype) initWithConnection: (CGSConnectionX11 *) connection name: (NSString *) name {
    self = [super init];
    _connection = [connection retain];
    _name = [name retain];

    _display = connection->_display;
    _selectionName = XInternAtom(_display, [name UTF8String], False);
    _receivingProperty = XInternAtom(_display, "RECEIVING_PROPERTY", False);
    _incrAtom = XInternAtom(_display, "INCR", False);
    _targetsAtom = XInternAtom(_display, "TARGETS", False);
    _textAtom = XInternAtom(_display, "TEXT", False);
    _utf8StringAtom = XInternAtom(_display, "UTF8_STRING", False);
    _incrTransfers = [[NSMutableDictionary alloc] init];

    int screen = DefaultScreen(_display);
    _window = XCreateSimpleWindow(_display, RootWindow(_display, screen), -10, -10, 1, 1, 0, 0, 0);
    // XSelectInput() takes event masks, not event types. The selection events
    // are always delivered; PropertyNotify is what an INCR transfer into this
    // window waits for, and it needs PropertyChangeMask.
    XSelectInput(_display, _window, PropertyChangeMask);

    registerSelection(self, _window);

    return self;
}

- (void) discardRemoteTypes {
    [_remoteTypes release];
    _remoteTypes = nil;
    _remoteOwner = None;
}

- (void) acquire {
    if (_owned && XGetSelectionOwner(_display, _selectionName) == _window) {
        // Already an owner.
        return;
    }

    XSetSelectionOwner(_display, _selectionName, _window, CurrentTime); // FIXME: don't use CurrentTime
    XFlush(_display);

    _owned = YES;
    if (_localTypes == nil)
        _localTypes = [NSMutableArray new];
    [self discardRemoteTypes];

    _changeCount++;
}

- (void) setLocalTypes: (NSArray<NSString *> *) types {
    if (_localTypes == nil)
        _localTypes = [NSMutableArray new];
    [_localTypes setArray: types];
}

- (void) bumpChangeCount {
    _changeCount++;
}

// The process no longer owns the selection (another client took it, or the endpoint goes away).
- (void) giveUpSelectionOwner {
    _owned = NO;
    [_localTypes release];
    _localTypes = nil;

    [self discardRemoteTypes];
    _changeCount++;
}

- (void) relinquish {
    [self giveUpSelectionOwner];
}

- (BOOL) ownsSelection {
    return _owned;
}

- (void) dealloc {
    // Give up the selection before destroying the window so other clients and
    // clipboard managers are notified before _window becomes invalid.
    [self giveUpSelectionOwner];

    if (_hostWatcher != nil) {
        dispatch_source_cancel(_hostWatcher);
        dispatch_release(_hostWatcher);
    }
    [_hostChangeHandler release];

    unregisterSelection(_window);
    XDestroyWindow(_display, _window);
    XFlush(_display);

    [_remoteTypes release];
    [_incrTransfers release];
    [_name release];
    [_connection release];
    [super dealloc];
}

- (NSInteger) changeCount {
    [self observeSelectionOwner];
    return _changeCount;
}

- (void) selectionClear: (XSelectionClearEvent *) event {
    [self giveUpSelectionOwner];
    [_source selectionLost];
}

- (BOOL) servesTransferTo: (Window) requestor {
    return _incrTransfers[@(requestor)] != nil;
}

- (Window) windowHandleValue {
    return _window;
}

- (unsigned long) windowHandle {
    return _window;
}

- (unsigned long) selectionAtom {
    return _selectionName;
}

- (NSData *) readReceivingPropertyForTarget: (Atom) target format: (int) format {
    Atom type;
    int actualFormat;
    unsigned long num_items, remaining;
    unsigned char *propValue = NULL;

    XGetWindowProperty(_display, _window, _receivingProperty, 0, ~0L, True, AnyPropertyType, &type, &actualFormat,
                       &num_items, &remaining, &propValue);

    if (type == None) {
        return nil;
    }

    if (actualFormat != format) {
        NSLog(@"X11 selection: the owner of %@ answered with format %d, expected %d", _name, actualFormat, format);
        XFree(propValue);
        return nil;
    }

    // TEXT lets the owner pick the encoding, and the property type says which.
    _receivedType = type;
    if (type != target && !(target == _textAtom && (type == XA_STRING || type == _utf8StringAtom))) {
        // The bytes would be read as a flavour nobody asked for.
        NSLog(@"X11 selection: the owner of %@ answered one target with the type of another", _name);
    }

    // Xlib stores a format-32 reply as an array of long, so copying num_items * 4
    // bytes keeps only the first half of the items, each at an 8-byte stride.
    NSData *data;
    if (format == 32) {
        NSMutableData *packed = [NSMutableData dataWithLength: num_items * sizeof(uint32_t)];
        const long *items = (const long *) propValue;
        uint32_t *atoms = (uint32_t *) packed.mutableBytes;
        for (unsigned long n = 0; n < num_items; n++)
            atoms[n] = (uint32_t) items[n];
        data = packed;
    } else {
        data = [NSData dataWithBytes: propValue length: num_items * (format / 8)];
    }
    XFree(propValue);

    return data;
}

// The type of the receiving property, read without taking or deleting it: the
// reply to a conversion may be an INCR marker instead of the data, and that has
// to be known before the data is read.
- (Atom) typeOfReceivingProperty {
    Atom type = None;
    int actualFormat;
    unsigned long numItems, remaining;
    unsigned char *value = NULL;

    XGetWindowProperty(_display, _window, _receivingProperty, 0, 0, False, AnyPropertyType, &type, &actualFormat,
                       &numItems, &remaining, &value);
    if (value != NULL)
        XFree(value);

    return type;
}

// Handles the events the connection has, then waits up to a slice of time for more. The thread that reads a
// selection is not its connection's run loop: nothing but the connection's own events can complete the
// read, so those are all that is waited for.
- (void) pumpEventsFor: (NSTimeInterval) slice {
    [_connection processPendingEvents];
    struct pollfd ready = {.fd = ConnectionNumber(_display), .events = POLLIN};
    if (XPending(_display) == 0)
        poll(&ready, 1, (int) (slice * 1000));
    [_connection processPendingEvents];
}

// Pumps the events until the owner writes the receiving property, or the
// deadline passes. The deadline is the caller's and covers the whole read, so a
// stalled owner costs one timeout and not one per chunk, and an event that is
// none of the transfer's business (our own delete, another window) only costs
// one pass of the loop.
- (BOOL) waitForPropertyWriteUntil: (NSTimeInterval) deadline {
    while (!_propertyWritten) {
        NSTimeInterval remaining = deadline - [NSDate timeIntervalSinceReferenceDate];
        if (remaining <= 0)
            return NO;

        // Wait in short slices, so the next chunk is seen right away instead of after the whole remaining timeout.
        [self pumpEventsFor: MIN(kSelectionPollInterval, remaining)];
    }

    return YES;
}

// ICCCM 2.7.2: an owner whose data does not fit in a single property write
// answers with a zero-length property of type INCR and then appends the data in
// chunks. The requestor pulls one chunk at a time, and every read also deletes
// the property - that delete is the acknowledgement the owner waits for, and
// the only thing that keeps the server from holding the whole transfer at once.
- (NSData *) receiveIncrementalDataForTarget: (Atom) target format: (int) format deadline: (NSTimeInterval) deadline {
    NSMutableData *data = [NSMutableData data];
    NSString *failure = nil;

    // The INCR property is a marker, not data, and it has to be deleted before
    // anything else: that is what tells the owner to start sending. Its format
    // says nothing about the chunks that follow, so it is not validated.
    XDeleteProperty(_display, _window, _receivingProperty);
    XFlush(_display);

    BOOL complete = NO;
    while (failure == nil && [self waitForPropertyWriteUntil: deadline]) {
        // The property has now been looked at, so a notification from before this
        // read must not be taken for the chunk after it. Not the other way round:
        // a write that arrived while we were still reading the reply out of the
        // queue is the chunk this iteration is waiting for.
        _propertyWritten = NO;

        NSData *chunk = [self readReceivingPropertyForTarget: target format: format];
        if (chunk == nil) {
            // The property was already gone, so the notification was one of our
            // own deletes. That is not a chunk, and it is not the end either.
            continue;
        }

        if ([chunk length] == 0) {
            // A zero-length property of the target's type is the terminator: a
            // real chunk is never empty, because an empty one is what ends the
            // transfer.
            complete = YES;
            break;
        }

        if ([data length] + [chunk length] > CGSSelectionTransferLimit) {
            failure = @"it would exceed 16 MiB";
            break;
        }

        [data appendData: chunk];
    }

    if (failure == nil && !complete)
        failure = @"the owner stopped sending";
    if (failure != nil) {
        // A partial buffer is worse than none: the caller cannot tell it apart
        // from a complete transfer.
        NSLog(@"X11 selection: discarding an incremental transfer of %@ after %lu bytes, %@", _name,
              (unsigned long) [data length], failure);
        return nil;
    }

    return data;
}

// An owner that is gone, or that ignores the request, never answers at all, so
// the wait is bounded by a deadline the caller shares across its attempts
// instead of hanging the caller forever.
- (NSData *) receiveDataForTarget: (Atom) target format: (int) format deadline: (NSTimeInterval) deadline {
    // This method pumps the connection's events, so any other read reached from an event handler would nest
    // inside it. There is one receiving property and one outstanding-reply slot per object, so a nested read would
    // delete the property the outer call is waiting on and leave the outer loop reading a reply state it did not
    // set - it could return the nested call's bytes as its own. Refuse instead, loudly, rather than corrupt
    // either call. Serving concurrent requests properly needs a property per in-flight transfer, which is a
    // design change to request correlation.
    if (_awaitingTarget != None) {
        char *rawTarget = XGetAtomName(_display, target);
        NSLog(@"X11 selection: refusing a re-entrant request for target %s on %@, another transfer is already in "
              "flight",
              rawTarget ? rawTarget : "?", _name);
        if (rawTarget != NULL)
            XFree(rawTarget);
        return nil;
    }

    if ([NSDate timeIntervalSinceReferenceDate] >= deadline)
        return nil;

    XDeleteProperty(_display, _window, _receivingProperty);
    _awaitingTarget = target;
    _selectionNotifyResult = WAITING;
    // Start watching before the conversion is even sent: the owner can answer an
    // INCR request by writing the first chunk before the reply to it has been
    // read out of the queue, and that write is the chunk we are waiting for.
    _readingProperty = YES;
    _propertyWritten = NO;

    XConvertSelection(_display, _selectionName, target, _receivingProperty, _window,
                      CurrentTime); // FIXME: don't use CurrentTime
    XFlush(_display);

    while (_selectionNotifyResult == WAITING) {
        NSTimeInterval remaining = deadline - [NSDate timeIntervalSinceReferenceDate];
        if (remaining <= 0)
            break;

        [self pumpEventsFor: MIN(kSelectionPollInterval, remaining)];
    }

    // _awaitingTarget stays claimed until the data is in hand: an INCR transfer
    // keeps reading the same receiving property, and a nested read would delete
    // it out from under this one.
    if (_selectionNotifyResult != SUCCESS) {
        _readingProperty = NO;
        _awaitingTarget = None;

        if (_selectionNotifyResult == WAITING) {
            char *rawTarget = XGetAtomName(_display, target);
            NSLog(@"X11 selection: the owner of %@ did not answer a request for target %s", _name,
                  rawTarget ? rawTarget : "?");
            if (rawTarget != NULL)
                XFree(rawTarget);
        }
        return nil;
    }

    NSData *result;
    if ([self typeOfReceivingProperty] == _incrAtom) {
        result = [self receiveIncrementalDataForTarget: target format: format deadline: deadline];
    } else {
        result = [self readReceivingPropertyForTarget: target format: format];
    }

    _readingProperty = NO;
    _awaitingTarget = None;
    return result;
}

- (NSData *) remoteDataForType: (NSString *) type {
    if (_owned)
        return nil;

    [self observeSelectionOwner];
    if (_remoteOwner == None)
        // No owner, no reply, and waiting for one would block the caller.
        return nil;

    NSTimeInterval deadline = [NSDate timeIntervalSinceReferenceDate] + SelectionTimeout;
    for (NSString *target in _CGSSelectionTargetsForType(type)) {
        Atom targetAtom = XInternAtom(_display, [target UTF8String], False);
        _receivedType = None;
        NSData *data = [self receiveDataForTarget: targetAtom format: 8 deadline: deadline];
        if (data == nil)
            continue;
        if (![type isEqual: kTypeString])
            return data;
        // Text is kept as UTF-8. ICCCM's STRING is ISO Latin-1, and a TEXT
        // reply is in whichever encoding its type names.
        if (_receivedType == XA_STRING) {
            NSString *text = [[[NSString alloc] initWithData: data encoding: NSISOLatin1StringEncoding] autorelease];
            data = [text dataUsingEncoding: NSUTF8StringEncoding];
        } else if (targetAtom == _textAtom && _receivedType != _utf8StringAtom) {
            // COMPOUND_TEXT or something else we cannot decode.
            continue;
        }
        if (data != nil)
            return data;
    }

    return nil;
}

// X11 sends no notification when the contents of a selection change, so the
// identity of the owner is the only signal a requestor can get.
- (void) observeSelectionOwner {
    if (_owned)
        // We own the selection, so what we hold is the answer.
        return;

    Window owner = XGetSelectionOwner(_display, _selectionName);
    if (owner == _remoteOwner)
        return;

    _remoteOwner = owner;
    [_remoteTypes release];
    _remoteTypes = nil;
    // Whatever the previous owner held is gone, which is a change as far as a
    // caller watching -changeCount is concerned.
    _changeCount++;
}

- (NSArray<NSString *> *) remoteTypes {
    if (_owned)
        return @[];
    [self observeSelectionOwner];
    if (_remoteTypes != nil)
        return [[_remoteTypes copy] autorelease];

    NSMutableArray *types = [NSMutableArray array];

    // Nothing owns the selection, so no TARGETS reply is ever coming and asking
    // for one would block the caller for the whole timeout.
    NSData *targets = nil;
    if (_remoteOwner != None) {
        NSTimeInterval deadline = [NSDate timeIntervalSinceReferenceDate] + SelectionTimeout;
        targets = [self receiveDataForTarget: _targetsAtom format: 32 deadline: deadline];
    }
    if (targets != nil) {
        NSArray *metaTargets = @[ @"TARGETS", @"TIMESTAMP", @"MULTIPLE", @"SAVE_TARGETS", @"DELETE" ];
        // A 32-format property holds 32-bit items, one per atom.
        const uint32_t *atoms = (const uint32_t *) [targets bytes];
        for (size_t i = 0; i * sizeof(uint32_t) < [targets length]; i++) {
            if (atoms[i] == None)
                continue;
            char *rawTarget = XGetAtomName(_display, atoms[i]);
            if (rawTarget == NULL)
                continue;
            NSString *target = [NSString stringWithUTF8String: rawTarget];
            XFree(rawTarget);
            // The meta targets name a conversion mode, not a flavour.
            if (target == nil || [metaTargets containsObject: target])
                continue;

            NSString *type = _CGSSelectionTypeForTarget(target);
            if (![types containsObject: type])
                [types addObject: type];
        }
    }

    // Only a real answer is worth remembering: an owner that stayed silent this
    // time may answer the next.
    if (targets != nil || _remoteOwner == None)
        _remoteTypes = [types copy];

    return types;
}

- (void) selectionNotify: (XSelectionEvent *) event {
    // The reply to a request we are waiting for is the only one that says so.
    if (event->selection != _selectionName || event->target != _awaitingTarget)
        return;

    _selectionNotifyResult = event->property == _receivingProperty ? SUCCESS : NONE;
}

- (void) selectionRequest: (XSelectionRequestEvent *) event {
    void (^reply)(BOOL success) = ^(BOOL success) {
      XEvent replyEvent;
      XSelectionEvent *re = &replyEvent.xselection;
      re->type = SelectionNotify;
      re->requestor = event->requestor;
      re->selection = event->selection;
      re->target = event->target;
      re->property = success ? ((event->property == None) ? event->target : event->property) : None;
      re->time = event->time;
      // ICCCM 2.2: the SelectionNotify goes to the requestor alone (propagate False).
      XSendEvent(_display, event->requestor, False, NoEventMask, &replyEvent);
      XFlush(_display);
    };

    if (event->target == None || !_owned) {
        reply(NO);
        return;
    }

    char *rawTarget = XGetAtomName(_display, event->target);
    if (rawTarget == NULL) {
        // A client can name an atom that does not exist. +stringWithUTF8String: raises on
        // NULL, so a bogus target in a SelectionRequest would abort the process.
        reply(NO);
        return;
    }
    NSString *target = [NSString stringWithUTF8String: rawTarget];
    XFree(rawTarget);

    if ([target isEqual: @"TARGETS"]) {
        // Only what we hold can be served; asking the current owner instead
        // would nest one selection request inside another client's.
        NSArray<NSString *> *types = [[_localTypes copy] autorelease];
        size_t count = 2; // TARGETS + TIMESTAMP
        for (NSString *type in types)
            count += [_CGSSelectionTargetsForType(type) count];
        // Xlib takes format-32 data as one long per element, so a uint32_t buffer is
        // read at twice its size: every other atom, then half the reply off the stack.
        unsigned long targets[count];
        size_t i = 0;
        for (NSString *type in types) {
            for (NSString *t in _CGSSelectionTargetsForType(type))
                targets[i++] = XInternAtom(_display, [t UTF8String], False);
        }
        targets[i++] = event->target; // TARGETS itself
        targets[i++] = XInternAtom(_display, "TIMESTAMP", False);

        Atom targetProperty = (event->property == None) ? event->target : event->property;
        XChangeProperty(_display, event->requestor, targetProperty, XA_ATOM, 32, PropModeReplace,
                        (unsigned char *) targets, count);
        reply(YES);
        return;
    }

    if ([target isEqual: @"TIMESTAMP"]) {
        // ICCCM 2.6.2: TIMESTAMP returns the timestamp used to acquire the selection.
        Time timestamp = event->time ? event->time : CurrentTime;
        Atom targetProperty = (event->property == None) ? event->target : event->property;
        XChangeProperty(_display, event->requestor, targetProperty, XA_INTEGER, 32, PropModeReplace,
                        (unsigned char *) &timestamp, 1);
        reply(YES);
        return;
    }

    if ([target isEqual: @"SAVE_TARGETS"]) {
        // The selection is not handed to a clipboard manager; the request is acknowledged.
        reply(YES);
        return;
    }

    NSString *type = _CGSSelectionTypeForTarget(target);
    NSData *data = [_source selectionDataForType: type];
    if (data == nil) {
        reply(NO);
        return;
    }

    // Text is held as UTF-8. STRING promises ISO Latin-1, so text that does not
    // fit is refused and the requestor can ask for UTF8_STRING instead; TEXT
    // leaves the encoding to the owner, and the reply's type names it.
    Atom replyType = event->target;
    if ([type isEqual: kTypeString]) {
        if (event->target == XA_STRING) {
            NSString *text = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
            data = [text dataUsingEncoding: NSISOLatin1StringEncoding];
            if (data == nil) {
                reply(NO);
                return;
            }
        } else if (event->target == _textAtom) {
            replyType = _utf8StringAtom;
        }
    }

    if ([data length] > MaximumPropertyBytes(_display)) {
        // ICCCM 2.7.2: more than fits in one property write, so hand it over as
        // INCR. The marker and the reply go out now; -propertyNotify: paces the
        // chunks from the requestor's acknowledgements, so nothing here waits on
        // the peer.
        [self startIncrementalTransferForRequest: event type: replyType data: data];
        reply(YES);
        return;
    }

    Atom targetProperty = (event->property == None) ? event->target : event->property;
    if (targetProperty == None) {
        reply(NO);
        return;
    }
    XChangeProperty(_display, event->requestor, targetProperty, replyType, 8, PropModeReplace, [data bytes],
                    [data length]);

    reply(YES);
}

- (void) propertyNotify: (XPropertyEvent *) event {
    // Only a write by the owner counts. Our own deletes generate notifications
    // too, and they are the requestor's half of the handshake, not a chunk.
    if (_readingProperty && event->window == _window && event->atom == _receivingProperty &&
        event->state == PropertyNewValue)
        _propertyWritten = YES;

    // ICCCM paces an incremental transfer with property deletions: the receiver
    // reads a chunk and deletes the property to ask for the next one. The owner
    // learns the receiver is ready from that deletion alone.
    NSNumber *requestor = [NSNumber numberWithUnsignedLong: event->window];
    CGSX11IncrTransfer *transfer = _incrTransfers[requestor];
    if (transfer == nil || event->state != PropertyDelete || transfer->_property != event->atom)
        return;

    NSUInteger left = [transfer->_data length] - transfer->_offset;
    NSUInteger chunk = left > X11IncrChunkSize ? X11IncrChunkSize : left;
    if (chunk == 0) {
        // The receiver has read everything there was, so the transfer ends with a
        // zero-length write. Deleting the property instead would be
        // indistinguishable from the receiver asking for another chunk, and a
        // receiver would wait for data that never comes.
        XChangeProperty(_display, event->window, event->atom, transfer->_type, 8, PropModeReplace, NULL, 0);
        [self stopWatchingRequestor: event->window transfer: transfer];
        // Releases the transfer; nothing of it is used past this point.
        [_incrTransfers removeObjectForKey: requestor];
    } else {
        XChangeProperty(_display, event->window, event->atom, transfer->_type, 8, PropModeReplace,
                        [transfer->_data bytes] + transfer->_offset, chunk);
        // The transfer stays in the table until the terminator has been
        // written: every chunk is asked for by its own deletion.
        transfer->_offset += chunk;
    }
    XFlush(_display);
}

// The requestor's window is usually another client's, and XSelectInput() replaces the mask this client has on a
// window rather than adding to it. The mask the process already has there is kept, and put back when the transfer
// ends.
- (void) watchRequestor: (Window) requestor transfer: (CGSX11IncrTransfer *) transfer {
    XWindowAttributes attributes;
    long mask = 0;
    if (XGetWindowAttributes(_display, requestor, &attributes))
        mask = attributes.your_event_mask;
    if (mask & PropertyChangeMask)
        return;
    transfer->_previousMask = mask;
    transfer->_selectedInput = YES;
    XSelectInput(_display, requestor, mask | PropertyChangeMask);
}

- (void) stopWatchingRequestor: (Window) requestor transfer: (CGSX11IncrTransfer *) transfer {
    if (transfer->_selectedInput)
        XSelectInput(_display, requestor, transfer->_previousMask);
}

// Start handing a selection over as INCR, because it is larger than one property
// write. The continuation already lives in -propertyNotify:, keyed by the
// requestor's window; this only has to write the INCR marker the requestor is
// waiting for and subscribe to the deletions that pace it.
- (void) startIncrementalTransferForRequest: (XSelectionRequestEvent *) event type: (Atom) type data: (NSData *) data {
    // ICCCM 2.7.2: the owner writes the property with type INCR and the total
    // length as its value, and the requestor then deletes the property to say it
    // is ready for a chunk. The length is what lets the requestor size its read,
    // so it is the payload here, not the atom.
    // An obsolete requestor names no property; ICCCM 2.2 has the owner use the
    // target atom as the property name then.
    Atom property = (event->property == None) ? event->target : event->property;
    unsigned long length = (unsigned long) [data length];
    XChangeProperty(_display, event->requestor, property, _incrAtom, 32, PropModeReplace, (unsigned char *) &length, 1);

    NSNumber *requestor = [NSNumber numberWithUnsignedLong: event->requestor];
    CGSX11IncrTransfer *transfer = [[[CGSX11IncrTransfer alloc] initWithProperty: property type: type
                                                                            data: data] autorelease];
    // Deletions arrive as PropertyNotify on the requestor's window, which we do not necessarily select for.
    [self watchRequestor: event->requestor transfer: transfer];
    _incrTransfers[requestor] = transfer;

    XFlush(_display);
}

#pragma mark Another client taking the selection

- (void) setHostChangeHandler: (void (^)(void)) handler {
    [_hostChangeHandler release];
    _hostChangeHandler = [handler copy];
    if (_hostWatcher != nil || handler == nil)
        return;

    _hostWatcher = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(_hostWatcher, dispatch_time(DISPATCH_TIME_NOW, 0), 200 * NSEC_PER_MSEC,
                              50 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(_hostWatcher, ^{
      [self pollHostOwner];
    });
    dispatch_resume(_hostWatcher);
}

// Another client having taken the selection is noticed by its owner changing. The owner is not looked at
// while this endpoint believes it owns the selection: the X server's SelectionClear tells it first.
- (void) pollHostOwner {
    if (_owned)
        return;
    Window owner = XGetSelectionOwner(_display, _selectionName);
    if (owner == _watchedOwner)
        return;
    _watchedOwner = owner;
    if (owner == None || owner == _window)
        return;
    // Drops what was known about the previous owner and counts the change.
    [self observeSelectionOwner];
    if (_hostChangeHandler != nil)
        _hostChangeHandler();
}

@end

#pragma mark - The endpoints of the connection

@implementation CGSConnectionX11 (CGSX11SelectionEndpoints)

- (id) newSelectionEndpointNamed: (NSString *) name {
    return [[CGSX11Selection alloc] initWithConnection: self name: name];
}

- (void) _startHostClipboard {
    // The endpoint lives as long as the process: the pasteboard bridge registered with CoreFoundation cannot be
    // taken back.
    _CGSHostClipboardStart([[self newSelectionEndpointNamed: @"CLIPBOARD"] autorelease]);
}

@end
