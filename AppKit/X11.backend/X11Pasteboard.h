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
#import <CoreGraphics/CGSSelection.h>
#import <X11/Xlib.h>
#import <X11/Xatom.h>

// The X11 backend's pasteboards are selection endpoints: they own an X selection (or read the one another client
// owns) and answer for it. XdndSelection endpoints carry the data of a drag; the pasteboard an application gets
// from NSPasteboard is not one of them (the CLIPBOARD selection belongs to CoreGraphics, which connects it with the
// general pasteboard). The selection protocol itself (ownership, targets, conversions, INCR transfers, the events
// of the helper window) is CoreGraphics', behind its selection endpoint; this class gives it the NSPasteboard API.
@interface X11Pasteboard : NSPasteboard <CGSSelectionSource> {
    NSPasteboardName _name;
    id<CGSSelectionEndpoint> _selection;

    NSMutableDictionary<NSPasteboardType, NSData *> *_typeToData;
    NSMutableDictionary<NSPasteboardType, id<NSPasteboardTypeOwner>>
            *_typeToOwner;
    // The types in the order they were declared or written: -types answers in it.
    NSMutableArray<NSPasteboardType> *_typeOrder;
}

- (instancetype) initWithName: (NSPasteboardName) name;
- (instancetype) initWithName: (NSPasteboardName) name display: (X11Display *) display;

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
+ (NSString *) mimeTypeForType: (NSPasteboardType) type;

@end
