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

    int screen = DefaultScreen(_display);
    _window = XCreateSimpleWindow(_display, RootWindow(_display, screen), -10,
                                  -10, 1, 1, 0, 0, 0);
    XSelectInput(_display, _window,
                 SelectionClear | SelectionRequest | SelectionNotify |
                         PropertyNotify);

    [x11Display setWindow: self forID: _window];

    return self;
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
    [self giveUpSelectionOwner];
    [_remoteTypes release];
    [_incrTransfers release];
    [_name release];
    [super dealloc];
}

- (NSInteger) changeCount {
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

- (NSData *) readDataFromReceivingProperty {
    Atom type;
    unsigned char *propValue = NULL;
    int format;
    unsigned long num_items, remaining;

    XGetWindowProperty(_display, _window, _receivingProperty, 0, ~0L, True,
                       AnyPropertyType, &type, &format, &num_items, &remaining,
                       &propValue);

    if (type == None) {
        return nil;
    }

    if (type == XInternAtom(_display, "INCR", False)) {
        NSLog(@"Unimplemented: INCR support");
        return nil;
    }

    if (format != 8) {
        // ???
        XFree(propValue);
        return nil;
    }

    NSData *data = [NSData dataWithBytes: propValue length: num_items];
    XFree(propValue);

    return data;
}

- (NSData *) dataForType: (NSPasteboardType) type {

    if (_typeToOwner != nil) {
        // We're the owner; just fetch the data directly.
        id<NSPasteboardTypeOwner> owner = _typeToOwner[type];
        [owner pasteboard: self provideDataForType: type];
        return _typeToData[type];
    }

    NSString *target = [X11Pasteboard targetsForType: type][0];
    Atom targetAtom = XInternAtom(_display, [target UTF8String], False);
    XConvertSelection(_display, _selectionName, targetAtom, _receivingProperty,
                      _window, CurrentTime); // FIXME: don't use CurrentTime

    _selectionNotifyResult = WAITING;
    while (_selectionNotifyResult == WAITING) {
        [[NSDisplay currentDisplay]
                nextEventMatchingMask: NSAnyEventMask
                            untilDate: [NSDate distantFuture]
                               inMode: NSDefaultRunLoopMode
                              dequeue: NO];
    }

    return [self readDataFromReceivingProperty];
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
    // NOT SENT: [_typeToOwner[type] pasteboardChangedOwner: self];
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

- (NSArray<NSPasteboardType> *) types {
    return [[_typeToData allKeys]
            arrayByAddingObjectsFromArray: [_typeToOwner allKeys]];
}

- (void) selectionNotify: (XSelectionEvent *) event {
    if (event->property == None) {
        _selectionNotifyResult = NONE;
    } else {
        _selectionNotifyResult = SUCCESS;
    }
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
        NSArray<NSPasteboardType> *types = [self types];
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
    // TODO
}

- (id) delegate {
    // To sook somewhat like an X11Window to X11Display.
    return nil;
}

@end
