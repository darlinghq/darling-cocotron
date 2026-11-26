/* Permission is hereby granted, free of charge, to any person obtaining a copy of
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

#import <Foundation/Foundation.h>
#import "WaylandDisplay.h"

// Writes the data to the descriptor from a short-lived thread once the events being dispatched are handled.
void WaylandSendData(WaylandDisplay *display, NSData *data, int fd);

// The data device that handles drag and drop (the data of a drag arrives as offers on it). The compositor's
// clipboard is CoreGraphics' (see CGSSelection.h), which has a data device of its own on the same seat.
@interface WaylandDataDevice : NSObject {
    WaylandDisplay *_display; // display owns the data device
    struct wl_proxy *_manager, *_device, *_selection, *_dragOffer;
    NSMutableDictionary *_offers, *_offerActions;
    id _dragSession;
}
- (id) initWithDisplay: (WaylandDisplay *) display
               manager: (struct wl_proxy *) manager seat: (struct wl_proxy *) seat;
- (struct wl_proxy *) dataDevice;
- (void) invalidate;
- (void) handleEvent: (uint32_t) opcode kind: (WaylandObjectKind) kind
              proxy: (struct wl_proxy *) proxy arguments: (union wl_argument *) args;
@end
