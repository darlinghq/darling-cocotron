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

#import "X11Display.h"
#import <AppKit/NSPasteboard.h>
#import <X11/Xlib.h>

@interface X11Pasteboard : NSPasteboard {
    NSPasteboardName _name;
    Display *_display;
    Window _window;
    Atom _selectionName;

    NSMutableDictionary<NSPasteboardType, NSData *> *_typeToData;
    NSMutableDictionary<NSPasteboardType, id<NSPasteboardTypeOwner>>
            *_typeToOwner;
    NSInteger _changeCount;

    Atom _receivingProperty;
    Atom _incrAtom;
    Atom _targetsAtom;
    Atom _awaitingTarget;
    NSArray<NSPasteboardType> *_remoteTypes;
    Window _remoteOwner;
    NSMutableDictionary<NSNumber *, id> *_incrTransfers;
    enum { WAITING, SUCCESS, NONE } _selectionNotifyResult;

    // Set while a read is in flight. -propertyNotify: records that the owner
    // wrote the receiving property, which is the only thing an INCR transfer
    // waits for between chunks.
    BOOL _readingProperty;
    BOOL _propertyWritten;
}

- (instancetype) initWithName: (NSPasteboardName) name;

// The unmapped window that owns this pasteboard's selection and answers the
// SelectionRequests for it. A drag publishes it as its XDND source window, so
// the properties the target reads and the data it converts come from one window.
- (Window) windowHandle;

// The X selection this pasteboard owns, which for a drag is the XdndSelection
// the target is told to convert.
- (Atom) selectionAtom;

// The X selection target names one NSPasteboardType converts to. XDND's type
// list is this mapping applied to the source's types, and a target asking for
// one of those names has to land on the type it came from, so the two uses
// cannot drift apart.
+ (NSArray<NSString *> *) targetsForType: (NSPasteboardType) type;
+ (NSPasteboardType) typeForTarget: (NSString *) target;

// An INCR transfer is paced by the receiver deleting the property, and that property
// lives on the receiver's window, which belongs to another client and so never reaches
// the window map. Whichever pasteboard is serving a transfer to that window is the one
// waiting for the deletion, so the display routes such an event here and this claims it.
// Returns YES if some pasteboard took the event.
+ (BOOL) dispatchPropertyNotify: (XPropertyEvent *) event;
// Sent by -[X11Display postXEvent:]
- (void) selectionNotify: (XSelectionEvent *) event;
- (void) selectionRequest: (XSelectionRequestEvent *) event;
- (void) selectionClear: (XSelectionClearEvent *) event;
- (void) propertyNotify: (XPropertyEvent *) event;

@end
