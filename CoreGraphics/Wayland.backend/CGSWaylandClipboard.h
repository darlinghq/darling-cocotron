/*
This file is part of Darling.

Copyright (C) 2026 Lubos Dolezel

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
#import "CGSConnectionWayland.h"
#import <Foundation/Foundation.h>

// The compositor's clipboard (the selection of a wl_data_device) as seen by this process. The device is the
// connection's own, made from the seat and the data device manager the connection binds: a clipboard needs no
// window. The data device of the framework that handles drag and drop is another one on the same seat; the
// compositor sends the selection to both.
@interface CGSWaylandClipboard : NSObject <CGSSelectionEndpoint> {
@private
    CGSConnectionWayland *_connection; // not retained: the connection owns the clipboard
    struct wl_proxy *_manager, *_device, *_source, *_selection;
    // The MIME types of every offer the device introduced, by wl_data_offer.
    NSMutableDictionary *_offers;
    NSMutableArray *_types;
    NSDictionary *_sourceData;
    NSInteger _changeCount;
    NSUInteger _selectionGeneration;
    uint32_t _changeSerial; // Serial of the input that made the pending change; 0 if none.
    BOOL _owned, _needsPublish, _publishQueued, _publishing;
    void (^_hostChangeHandler)(void);
    id<CGSSelectionSource> _delegateSource;
}

- (id) initWithConnection: (CGSConnectionWayland *) connection manager: (struct wl_proxy *) manager seat: (struct wl_proxy *) seat;
// Destroys the compositor objects; the connection calls this before it goes away.
- (void) invalidate;
// An input event of the seat that entitles the process to set the selection happened (a key press, a button press):
// what is waiting to be published is published, with the serial the connection holds.
- (void) inputAvailable;
- (void) handleEvent: (uint32_t) opcode
                kind: (CGSWaylandObjectKind) kind
               proxy: (struct wl_proxy *) proxy
           arguments: (union wl_argument *) args;

@end
