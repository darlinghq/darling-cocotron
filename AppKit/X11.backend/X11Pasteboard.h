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
    enum { WAITING, SUCCESS, NONE } _selectionNotifyResult;
}

- (instancetype) initWithName: (NSPasteboardName) name;

// Sent by -[X11Display postXEvent:]
- (void) selectionNotify: (XSelectionEvent *) event;
- (void) selectionRequest: (XSelectionRequestEvent *) event;
- (void) selectionClear: (XSelectionClearEvent *) event;
- (void) propertyNotify: (XPropertyEvent *) event;

@end
