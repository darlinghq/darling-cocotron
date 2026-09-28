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

#import "X11Pasteboard.h"

@implementation X11Pasteboard

static NSMutableDictionary<NSPasteboardName, X11Pasteboard *> *nameToPboard;

static const NSTimeInterval SelectionTimeout = 5;

// The Wayland backend bounds its clipboard transfers the same way, so the two
// backends accept the same payloads.
static const NSUInteger TransferLimit = 16 * 1024 * 1024;

+ (X11Pasteboard *) pasteboardWithName: (NSPasteboardName) name {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      nameToPboard = [NSMutableDictionary new];
    });

    if ([name isEqual: NSGeneralPboard]) {
        name = @"CLIPBOARD";
    }

    if (nameToPboard[name] == nil) {
        nameToPboard[name] = [[X11Pasteboard alloc] initWithName: name];
    }

    return nameToPboard[name];
}

- (instancetype) initWithName: (NSPasteboardName) name {
    self = [super init];
    _name = [name retain];

    X11Display *x11Display = (X11Display *) [NSDisplay currentDisplay];

    _display = [x11Display display];
    _selectionName = XInternAtom(_display, [name UTF8String], False);
    _receivingProperty = XInternAtom(_display, "RECEIVING_PROPERTY", False);
    _incrAtom = XInternAtom(_display, "INCR", False);
    _targetsAtom = XInternAtom(_display, "TARGETS", False);

    int screen = DefaultScreen(_display);
    _window = XCreateSimpleWindow(_display, RootWindow(_display, screen), -10,
                                  -10, 1, 1, 0, 0, 0);
    XSelectInput(_display, _window,
                 SelectionClear | SelectionRequest | SelectionNotify |
                         PropertyNotify);

    [x11Display setWindow: self forID: _window];

    return self;
}

- (void) discardRemoteTypes {
    [_remoteTypes release];
    _remoteTypes = nil;
    _remoteOwner = None;
}

- (void) ensureSelectionOwner {
    if (_typeToData != nil) {
        // Already an owner.
        return;
    }

    XSetSelectionOwner(_display, _selectionName, _window,
                       CurrentTime); // FIXME: don't use CurrentTime
    XFlush(_display);

    _typeToData = [NSMutableDictionary new];
    _typeToOwner = [NSMutableDictionary new];
    [self discardRemoteTypes];

    _changeCount++;
}

 - (NSInteger) clearContents {
    [self ensureSelectionOwner];

    // Notify from a snapshot, after the table is already empty. A pasteboard owner is
    // client code and may write to the pasteboard from its own callback, which would
    // otherwise mutate _typeToOwner while -allValues is still iterating it.
    NSArray *owners = [_typeToOwner allValues];
    [_typeToOwner removeAllObjects];
    [_typeToData removeAllObjects];
    // Bump here rather than only in ensureSelectionOwner, which fires once per ownership
    // transition: clearing twice in a row used to leave -changeCount unchanged, so a
    // poller saw no change even though the contents were replaced.
    _changeCount++;

    for (id owner in owners) {
        [owner pasteboardChangedOwner: self];
    }

    return _changeCount;
}

- (void) giveUpSelectionOwner {
    // -clearContents below accounts for the change, and it runs either way.
    [self clearContents];

    [_typeToOwner release];
    _typeToOwner = nil;

    [_typeToData release];
    _typeToData = nil;

    [self discardRemoteTypes];
}

- (NSString *) name {
    return _name;
}

- (void) dealloc {
    // Give up the selection first: giveUpSelectionOwner calls clearContents, which calls
    // ensureSelectionOwner, which would re-arm the selection on _window - already destroyed
    // by then, so the X request fails with BadWindow.
    [self giveUpSelectionOwner];

    [(X11Display *) [NSDisplay currentDisplay] setWindow: nil forID: _window];
    XDestroyWindow(_display, _window);

    [self giveUpSelectionOwner];
    [_remoteTypes release];
    [_incrTransfers release];
    [_name release];
    [super dealloc];
}

- (NSInteger) changeCount {
    [self observeSelectionOwner];
    return _changeCount;
}

- (void) selectionClear: (XSelectionClearEvent *) event {
    [self giveUpSelectionOwner];
}

+ (NSArray<NSString *> *) targetsForType: (NSPasteboardType) type {
    if ([type isEqual: NSStringPboardType]) {
        return @[
            @"UTF8_STRING", @"STRING", @"TEXT", @"text/plain",
            @"text/plain;charset=utf-8"
        ];
    }
    // TODO...
    return @[ type ];
}

+ (NSPasteboardType) typeForTarget: (NSString *) target {
    if ([target isEqual: @"STRING"] || [target isEqual: @"TEXT"] ||
        [target isEqual: @"text/plain"] ||
        [target isEqual: @"text/plain;charset=utf-8"] ||
        [target isEqual: @"UTF8_STRING"]) {
        return NSStringPboardType;
    }
    // TODO...
    return target;
}

- (NSData *) readReceivingPropertyForTarget: (Atom) target format: (int) format {
    Atom type;
    int actualFormat;
    unsigned long num_items, remaining;
    unsigned char *propValue = NULL;

    XGetWindowProperty(_display, _window, _receivingProperty, 0, ~0L, True,
                       AnyPropertyType, &type, &actualFormat, &num_items,
                       &remaining, &propValue);

    if (type == None) {
        return nil;
    }

    if (actualFormat != format) {
        NSLog(@"X11 pasteboard: the selection owner answered with format %d, "
              "expected %d", actualFormat, format);
        XFree(propValue);
        return nil;
    }

    if (type != target) {
        // The bytes would be read as a flavour nobody asked for.
        NSLog(@"X11 pasteboard: the selection owner answered one target with the "
              "type of another");
    }

    NSData *data = [NSData dataWithBytes: propValue
                                  length: num_items * (format / 8)];
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

    XGetWindowProperty(_display, _window, _receivingProperty, 0, 0, False,
                       AnyPropertyType, &type, &actualFormat, &numItems,
                       &remaining, &value);
    if (value != NULL)
        XFree(value);

    return type;
}

// Pumps the run loop until the owner writes the receiving property, or the
// deadline passes. The deadline is the caller's and covers the whole read, so a
// stalled owner costs one timeout and not one per chunk, and an event that is
// none of the transfer's business (our own delete, another window) only costs
// one pass of the loop.
- (BOOL) waitForPropertyWriteUntil: (NSTimeInterval) deadline {
    while (!_propertyWritten) {
        NSTimeInterval remaining = deadline
                - [NSDate timeIntervalSinceReferenceDate];
        if (remaining <= 0)
            return NO;

        [[NSDisplay currentDisplay]
                nextEventMatchingMask: NSAnyEventMask
                            untilDate: [NSDate dateWithTimeIntervalSinceNow: remaining]
                               inMode: NSDefaultRunLoopMode
                              dequeue: NO];
    }

    return YES;
}

// ICCCM 2.7.2: an owner whose data does not fit in a single property write
// answers with a zero-length property of type INCR and then appends the data in
// chunks. The requestor pulls one chunk at a time, and every read also deletes
// the property - that delete is the acknowledgement the owner waits for, and
// the only thing that keeps the server from holding the whole transfer at once.
- (NSData *) receiveIncrementalDataForTarget: (Atom) target
                                    format: (int) format
                                  deadline: (NSTimeInterval) deadline
{
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

        if ([data length] + [chunk length] > TransferLimit) {
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
        NSLog(@"X11 pasteboard: discarding an incremental transfer of %@ after %lu "
              "bytes, %@", _name, (unsigned long) [data length], failure);
        return nil;
    }

    return data;
}

// An owner that is gone, or that ignores the request, never answers at all, so
// the wait is bounded by a deadline the caller shares across its attempts
// instead of hanging the caller forever.
 - (NSData *) receiveDataForTarget: (Atom) target
                          format: (int) format
                        deadline: (NSTimeInterval) deadline
{
    // This method pumps the whole run loop, so any other pasteboard read reached from a
    // run-loop callback would nest inside it. There is one receiving property and one
    // outstanding-reply slot per object, so a nested read would delete the property the
    // outer call is waiting on and leave the outer loop reading a reply state it did not
    // set - it could return the nested call's bytes as its own. Refuse instead, loudly,
    // rather than corrupt either call. Serving concurrent requests properly needs a
    // property per in-flight transfer, which is a design change to request correlation.
    if (_awaitingTarget != None) {
        char *rawTarget = XGetAtomName(_display, target);
        NSLog(@"X11 pasteboard: refusing a re-entrant request for target %s on %@, "
              "another transfer is already in flight",
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

    XConvertSelection(_display, _selectionName, target, _receivingProperty,
                      _window, CurrentTime); // FIXME: don't use CurrentTime
    XFlush(_display);

    while (_selectionNotifyResult == WAITING) {
        NSTimeInterval remaining = deadline
                - [NSDate timeIntervalSinceReferenceDate];
        if (remaining <= 0)
            break;

        [[NSDisplay currentDisplay]
                nextEventMatchingMask: NSAnyEventMask
                            untilDate: [NSDate dateWithTimeIntervalSinceNow: remaining]
                               inMode: NSDefaultRunLoopMode
                              dequeue: NO];
    }

    // _awaitingTarget stays claimed until the data is in hand: an INCR transfer
    // keeps reading the same receiving property, and a nested read would delete
    // it out from under this one.
    if (_selectionNotifyResult != SUCCESS) {
        _readingProperty = NO;
        _awaitingTarget = None;

        if (_selectionNotifyResult == WAITING) {
            char *rawTarget = XGetAtomName(_display, target);
            NSLog(@"X11 pasteboard: the owner of %@ did not answer a request for "
                  "target %s", _name, rawTarget ? rawTarget : "?");
            if (rawTarget != NULL)
                XFree(rawTarget);
        }
        return nil;
    }

    NSData *result;
    if ([self typeOfReceivingProperty] == _incrAtom) {
        result = [self receiveIncrementalDataForTarget: target
                                               format: format
                                             deadline: deadline];
    } else {
        result = [self readReceivingPropertyForTarget: target format: format];
    }

    _readingProperty = NO;
    _awaitingTarget = None;
    return result;
}

- (NSData *) dataForType: (NSPasteboardType) type {

    if (_typeToOwner != nil) {
        // We're the owner; just fetch the data directly.
        id<NSPasteboardTypeOwner> owner = _typeToOwner[type];
        [owner pasteboard: self provideDataForType: type];
        return _typeToData[type];
    }

    [self observeSelectionOwner];
    if (_remoteOwner == None)
        // No owner, no reply, and waiting for one would block the caller.
        return nil;

    NSTimeInterval deadline = [NSDate timeIntervalSinceReferenceDate]
            + SelectionTimeout;
    for (NSString *target in [X11Pasteboard targetsForType: type]) {
        Atom targetAtom = XInternAtom(_display, [target UTF8String], False);
        NSData *data = [self receiveDataForTarget: targetAtom format: 8
                                         deadline: deadline];
        if (data != nil)
            return data;
    }

    return nil;
}

- (NSString *) stringForType: (NSPasteboardType) type {
    NSData *data = [self dataForType: type];

    NSStringEncoding encoding = NSUnicodeStringEncoding;
    if ([type isEqual: NSStringPboardType]) {
        encoding = NSUTF8StringEncoding;
    }
    return [[[NSString alloc] initWithData: data
                                  encoding: encoding] autorelease];
}

- (NSInteger) addTypes: (NSArray<NSPasteboardType> *) types
                 owner: (id<NSPasteboardTypeOwner>) owner
{
    [self ensureSelectionOwner];
    for (NSPasteboardType type in types) {
        [_typeToData removeObjectForKey: type];
        _typeToOwner[type] = owner;
    }
    return _changeCount;
}

- (NSInteger) declareTypes: (NSArray<NSPasteboardType> *) types
                     owner: (id<NSPasteboardTypeOwner>) owner
{
    [self clearContents];
    return [self addTypes: types owner: owner];
}

- (BOOL) setData: (NSData *) data forType: (NSPasteboardType) type {
    [self ensureSelectionOwner];
    // Make sure to retain data before releasing the owner,
    // because it might be the owner that is providing us
    // with this data.
    _typeToData[type] = data;
    [_typeToOwner[type] pasteboardChangedOwner: self];
    [_typeToOwner removeObjectForKey: type];
    return YES;
}

- (BOOL) setString: (NSString *) string forType: (NSPasteboardType) type {
    NSStringEncoding encoding = NSUnicodeStringEncoding;
    if ([type isEqual: NSStringPboardType]) {
        encoding = NSUTF8StringEncoding;
    }
    NSData *data = [string dataUsingEncoding: encoding];
    return [self setData: data forType: type];
}

- (NSArray<NSPasteboardType> *) localTypes {
    NSMutableArray *types = [NSMutableArray array];
    [types addObjectsFromArray: [_typeToData allKeys]];
    [types addObjectsFromArray: [_typeToOwner allKeys]];
    return types;
}

// X11 sends no notification when the contents of a selection change, so the
// identity of the owner is the only signal a requestor can get.
- (void) observeSelectionOwner {
    if (_typeToOwner != nil)
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

- (NSArray<NSPasteboardType> *) remoteTypes {
    [self observeSelectionOwner];
    if (_remoteTypes != nil)
        return [[_remoteTypes copy] autorelease];

    NSMutableArray *types = [NSMutableArray array];

    // Nothing owns the selection, so no TARGETS reply is ever coming and asking
    // for one would block the caller for the whole timeout.
    NSData *targets = nil;
    if (_remoteOwner != None) {
        NSTimeInterval deadline = [NSDate timeIntervalSinceReferenceDate]
                + SelectionTimeout;
        targets = [self receiveDataForTarget: _targetsAtom format: 32
                                     deadline: deadline];
    }
    if (targets != nil) {
        NSArray *metaTargets = @[
            @"TARGETS", @"TIMESTAMP", @"MULTIPLE", @"SAVE_TARGETS", @"DELETE"
        ];
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

            NSPasteboardType type = [X11Pasteboard typeForTarget: target];
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

- (NSArray<NSPasteboardType> *) types {
    if (_typeToOwner != nil)
        return [self localTypes];

    return [self remoteTypes];
}

- (void) selectionNotify: (XSelectionEvent *) event {
    // The reply to a request we are waiting for is the only one that says so.
    if (event->selection != _selectionName || event->target != _awaitingTarget)
        return;

    _selectionNotifyResult = event->property == _receivingProperty
            ? SUCCESS : NONE;
}

- (void) selectionRequest: (XSelectionRequestEvent *) event {
    void (^reply)(BOOL success) = ^(BOOL success) {
      XEvent replyEvent;
      XSelectionEvent *re = &replyEvent.xselection;
      re->type = SelectionNotify;
      re->requestor = event->requestor;
      re->selection = event->selection;
      re->target = event->target;
      re->property = success ? event->property : None;
      re->time = event->time;
      XSendEvent(_display, event->requestor, True, NoEventMask, &replyEvent);
      XFlush(_display);
    };

    if (event->target == None) {
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
        NSArray<NSPasteboardType> *types = [self localTypes];
        size_t count = 1;
        for (NSPasteboardType type in types) {
            NSArray<NSString *> *ts = [X11Pasteboard targetsForType: type];
            count += [ts count];
        }
        // Format 32 properties travel as 4 bytes per element, so an Atom buffer (8 bytes on
        // LP64) reaches the client interleaved with zeroes: it would read TARGETS as
        // [atom0, 0, atom1, 0, ...] and fail to match any of its own target names.
        uint32_t targets[count];
        size_t i = 0;
        for (NSPasteboardType type in types) {
            NSArray<NSString *> *ts = [X11Pasteboard targetsForType: type];
            for (NSString *t in ts) {
                targets[i++] = XInternAtom(_display, [t UTF8String], False);
            }
        }
        targets[i++] = event->target; // TARGETS itself

        XChangeProperty(_display, event->requestor, event->property,
                        event->target, 32, PropModeReplace,
                        (unsigned char *) targets, count);
        reply(YES);
        return;
    }

    NSPasteboardType type = [X11Pasteboard typeForTarget: target];

    id<NSPasteboardTypeOwner> owner = _typeToOwner[type];
    [owner pasteboard: self provideDataForType: type];

    NSData *data = _typeToData[type];
    if (data == nil) {
        reply(NO);
        return;
    }

    // TODO: INCR

    XChangeProperty(_display, event->requestor, event->property, event->target,
                    8, PropModeReplace, [data bytes], [data length]);

    reply(YES);
}

- (void) propertyNotify: (XPropertyEvent *) event {
    // Only a write by the owner counts. Our own deletes generate notifications
    // too, and they are the requestor's half of the handshake, not a chunk.
    if (_readingProperty && event->window == _window
            && event->atom == _receivingProperty
            && event->state == PropertyNewValue)
        _propertyWritten = YES;

    // ICCCM paces an incremental transfer with property deletions: the receiver
    // reads a chunk and deletes the property to ask for the next one. The owner
    // learns the receiver is ready from that deletion alone.
    NSNumber *requestor = [NSNumber numberWithUnsignedLong: event->window];
    X11IncrTransfer *transfer = _incrTransfers[requestor];
    if (transfer == nil || event->state != PropertyDelete ||
        transfer->_property != event->atom)
        return;

    [_incrTransfers removeObjectForKey: requestor];
    NSUInteger left = [transfer->_data length] - transfer->_offset;
    NSUInteger chunk = left > X11IncrChunkSize ? X11IncrChunkSize : left;
    if (chunk == 0) {
        // The receiver has read everything there was, so the transfer ends with a
        // zero-length write. Deleting the property instead would be
        // indistinguishable from the receiver asking for another chunk, and a
        // receiver would wait for data that never comes.
        XChangeProperty(_display, event->window, event->atom, transfer->_type, 8,
                        PropModeReplace, NULL, 0);
    } else {
        XChangeProperty(_display, event->window, event->atom, transfer->_type, 8,
                        PropModeReplace, [transfer->_data bytes] + transfer->_offset,
                        chunk);
    }
    XFlush(_display);
    [transfer release];
}

- (Window) windowHandle {
    return _window;
}

- (Atom) selectionAtom {
    return _selectionName;
}

- (id) delegate {
    // To sook somewhat like an X11Window to X11Display.
    return nil;
}

@end
