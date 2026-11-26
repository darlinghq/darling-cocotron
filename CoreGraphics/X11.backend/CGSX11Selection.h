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

#import <CoreGraphics/CGSSelection.h>
#import "CGSConnectionX11.h"
#import <X11/Xlib.h>
#import <dispatch/dispatch.h>

@class CGSX11IncrTransfer;

// An X11 selection (ICCCM) as seen by this process, on the process' connection: one unmapped helper window of
// the process owns it, answers the requests for it (TARGETS, TIMESTAMP, the conversions to the types the source
// has, in one write or as an INCR transfer when it is large) and, when another client owns the selection, receives
// the conversions that read it. See CGSSelectionEndpoint for what the endpoint offers.
@interface CGSX11Selection : NSObject <CGSSelectionEndpoint> {
@private
    CGSConnectionX11 *_connection;
    NSString *_name;
    Display *_display;
    Window _window;
    Atom _selectionName;

    BOOL _owned;
    // The types in the order they were declared: TARGETS answers with them.
    NSMutableArray<NSString *> *_localTypes;
    NSInteger _changeCount;
    id<CGSSelectionSource> _source;

    Atom _receivingProperty;
    Atom _incrAtom;
    Atom _targetsAtom;
    Atom _textAtom;
    Atom _utf8StringAtom;
    // The property type of the last reply read, which for TEXT says what
    // encoding the owner chose.
    Atom _receivedType;
    Atom _awaitingTarget;
    NSArray<NSString *> *_remoteTypes;
    Window _remoteOwner;
    NSMutableDictionary<NSNumber *, CGSX11IncrTransfer *> *_incrTransfers;
    volatile enum { WAITING, SUCCESS, NONE } _selectionNotifyResult;

    // Set while a read is in flight. -propertyNotify: records that the owner
    // wrote the receiving property, which is the only thing an INCR transfer
    // waits for between chunks.
    BOOL _readingProperty;
    BOOL _propertyWritten;

    // X sends no event when another client takes a selection over, so the owner is polled.
    void (^_hostChangeHandler)(void);
    dispatch_source_t _hostWatcher;
    Window _watchedOwner;
}

- (instancetype) initWithConnection: (CGSConnectionX11 *) connection name: (NSString *) name;

@end

// Gives an event of the connection to the selections it belongs to. Returns YES when it was theirs (a request,
// a reply or a clear of a selection's helper window, a change of a property of the helper window, or a requestor's
// deletion of the property an INCR transfer goes through), so that the connection does not pass it on.
extern BOOL CGSX11SelectionHandleEvent(XEvent *event);

@interface CGSConnectionX11 (CGSX11SelectionEndpoints)
// Connects the general pasteboard with the CLIPBOARD selection (see _CGSHostClipboardStart()). Called once by
// the connection when it has been opened.
- (void) _startHostClipboard;
// A new endpoint of the selection with that name, owned by the caller.
- (id) newSelectionEndpointNamed: (NSString *) name;
@end
