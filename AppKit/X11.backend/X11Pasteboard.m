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
#import "NSPasteboardAliases.h"

@implementation X11Pasteboard

+ (NSArray<NSString *> *) targetsForType: (NSPasteboardType) type {
    return _CGSSelectionTargetsForType(NSPasteboardCanonicalType(type));
}

// The MIME types other X clients use for the types most pasteboards hold.
+ (NSString *) mimeTypeForType: (NSPasteboardType) type {
    return _CGSSelectionMimeTypeForType(NSPasteboardCanonicalType(type));
}

+ (NSPasteboardType) typeForTarget: (NSString *) target {
    return _CGSSelectionTypeForTarget(target);
}

- (instancetype) initWithName: (NSPasteboardName) name {
    return [self initWithName: name display: (X11Display *) [NSDisplay currentDisplay]];
}

- (instancetype) initWithName: (NSPasteboardName) name display: (X11Display *) x11Display {
    self = [super init];
    _name = [name retain];

    // The endpoint owns the helper window and reads the events of the connection that concern it.
    _selection = _CGSNativeConnectionNewSelection(name);
    if (_selection == nil) {
        [self release];
        return nil;
    }
    [_selection setSource: self];

    // The window is also the source window of a drag, which the target's replies are sent to.
    [x11Display setWindow: self forID: [_selection windowHandle]];

    return self;
}

- (void) ensureSelectionOwner {
    // Takes the selection unless this process owns it already.
    [_selection acquire];

    if (_typeToData == nil)
        _typeToData = [NSMutableDictionary new];
    if (_typeToOwner == nil)
        _typeToOwner = [NSMutableDictionary new];
    if (_typeOrder == nil)
        _typeOrder = [NSMutableArray new];
}

// What the selection offers is what this pasteboard holds, in the order it was declared.
- (void) publishTypes {
    [_selection setLocalTypes: _typeOrder != nil ? _typeOrder : @[]];
}

- (NSInteger) clearContents {
    [self ensureSelectionOwner];

    // Notify from a snapshot, after the table is already empty. A pasteboard owner is
    // client code and may write to the pasteboard from its own callback, which would
    // otherwise mutate _typeToOwner while -allValues is still iterating it.
    NSArray *owners = [_typeToOwner allValues];
    [_typeToOwner removeAllObjects];
    [_typeToData removeAllObjects];
    [_typeOrder removeAllObjects];
    [self publishTypes];
    // Bump here rather than only when ownership is taken, which fires once per ownership
    // transition: clearing twice in a row used to leave -changeCount unchanged, so a
    // poller saw no change even though the contents were replaced.
    [_selection bumpChangeCount];

    for (id owner in owners) {
        if ([owner respondsToSelector: @selector(pasteboardChangedOwner:)])
            [owner pasteboardChangedOwner: self];
    }

    return [_selection changeCount];
}

- (void) giveUpSelectionOwner {
    NSArray *owners = [_typeToOwner allValues];
    [_typeToOwner release];
    _typeToOwner = nil;

    [_typeToData release];
    _typeToData = nil;
    [_typeOrder release];
    _typeOrder = nil;

    for (id owner in owners) {
        if ([owner respondsToSelector: @selector(pasteboardChangedOwner:)])
            [owner pasteboardChangedOwner: self];
    }
}

- (NSString *) name {
    return _name;
}

- (void) dealloc {
    // Give up the selection before destroying the window so other clients and
    // clipboard managers are notified before the window becomes invalid.
    [_selection relinquish];
    [self giveUpSelectionOwner];
    [_selection setSource: nil];

    [(X11Display *) [NSDisplay currentDisplay] setWindow: nil forID: [_selection windowHandle]];
    [_selection release];

    [_name release];
    [super dealloc];
}

- (NSInteger) changeCount {
    return [_selection changeCount];
}

- (Window) windowHandle {
    return [_selection windowHandle];
}

- (Atom) selectionAtom {
    return [_selection selectionAtom];
}

#pragma mark CGSSelectionSource

// A client asks for a type of the selection this pasteboard owns.
- (NSData *) selectionDataForType: (NSPasteboardType) type {
    id<NSPasteboardTypeOwner> owner = _typeToOwner[type];
    [owner pasteboard: self provideDataForType: type];
    return _typeToData[type];
}

// Another client took the selection.
- (void) selectionLost {
    [self giveUpSelectionOwner];
}

#pragma mark NSPasteboard

- (NSData *) dataForType: (NSPasteboardType) type {
    type = NSPasteboardCanonicalType(type);

    if (_typeToOwner != nil) {
        // We're the owner; just fetch the data directly.
        NSData *data = [self selectionDataForType: type];
        return data != nil ? data : NSPasteboardDerivedDataForType(self, type);
    }

    NSData *data = [_selection remoteDataForType: type];
    return data != nil ? data : NSPasteboardDerivedDataForType(self, type);
}

- (NSString *) stringForType: (NSPasteboardType) type {
    NSData *data = [self dataForType: type];
    if (data == nil)
        return nil;

    // UTF-8 is what macOS reads strings of other clients' types as; data that is not valid UTF-8
    // (what -setString:forType: stores for a type other than the string type) is read as Unicode.
    NSString *string = [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease];
    if (string == nil && ![NSPasteboardCanonicalType(type) isEqual: NSPasteboardTypeString])
        string = [[[NSString alloc] initWithData: data encoding: NSUnicodeStringEncoding] autorelease];
    return string;
}

- (NSInteger) addTypes: (NSArray<NSPasteboardType> *) types
                 owner: (id<NSPasteboardTypeOwner>) owner
{
    [self ensureSelectionOwner];
    for (NSPasteboardType declared in types) {
        // Stored under the UTI spelling; the 10.0 name of the same type reaches it too.
        NSPasteboardType type = NSPasteboardCanonicalType(declared);
        if (![_typeOrder containsObject: type])
            [_typeOrder addObject: type];
        [_typeToData removeObjectForKey: type];
        // A nil owner is valid: an object that does not want pasteboardChangedOwner: callbacks
        // declares its types with none, which is what -[NSTextView copy:] does. Storing nil in
        // _typeToOwner would raise "Cannot set nil objects nor nil keys", so drop any stale
        // entry instead. The Wayland backend guards this the same way.
        if (owner != nil)
            _typeToOwner[type] = owner;
        else
            [_typeToOwner removeObjectForKey: type];
    }
    [self publishTypes];
    return [_selection changeCount];
}

- (NSInteger) declareTypes: (NSArray<NSPasteboardType> *) types
                     owner: (id<NSPasteboardTypeOwner>) owner
{
    [self clearContents];
    return [self addTypes: types owner: owner];
}

- (BOOL) setData: (NSData *) data forType: (NSPasteboardType) type {
    type = NSPasteboardCanonicalType(type);
    [self ensureSelectionOwner];
    if (![_typeOrder containsObject: type]) {
        [_typeOrder addObject: type];
        [self publishTypes];
    }
    // Make sure to retain data before releasing the owner,
    // because it might be the owner that is providing us
    // with this data.
    _typeToData[type] = data;
    id previousOwner = _typeToOwner[type];
    if ([previousOwner respondsToSelector: @selector(pasteboardChangedOwner:)])
        [previousOwner pasteboardChangedOwner: self];
    [_typeToOwner removeObjectForKey: type];
    return YES;
}

- (BOOL) setString: (NSString *) string forType: (NSPasteboardType) type {
    NSStringEncoding encoding = NSUnicodeStringEncoding;
    if ([NSPasteboardCanonicalType(type) isEqual: NSPasteboardTypeString]) {
        encoding = NSUTF8StringEncoding;
    }
    NSData *data = [string dataUsingEncoding: encoding];
    return [self setData: data forType: type];
}

- (NSArray<NSPasteboardType> *) localTypes {
    // Every declared type is listed, also one declared without an owner and not yet given data
    // (declareTypes:owner: with a nil owner)
    return [[_typeOrder copy] autorelease];
}

- (NSArray<NSPasteboardType> *) types {
    if (_typeToOwner != nil)
        return NSPasteboardTypesWithAliases([self localTypes]);

    return NSPasteboardTypesWithAliases([_selection remoteTypes]);
}

- (id) delegate {
    // To sook somewhat like an X11Window to X11Display.
    return nil;
}

@end
