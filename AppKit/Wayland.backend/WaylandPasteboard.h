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

#import <AppKit/NSPasteboard.h>
#import "WaylandDisplay.h"

void WaylandSendData(WaylandDisplay *display, NSData *data, int fd);

// General pasteboard uses wl_data_device; other names are process-local.
@interface WaylandPasteboard : NSPasteboard {
    WaylandDisplay *_display; // display owns pasteboards
    NSString *_name;
    struct wl_proxy *_manager, *_device, *_source, *_selection, *_dragOffer;
    NSMutableDictionary *_offers, *_offerActions;
    id _dragSession;
    NSMutableArray *_types;
    NSMutableDictionary *_data, *_owners;
    NSDictionary *_sourceData;
    NSInteger _changeCount;
    NSUInteger _selectionGeneration;
    BOOL _owned, _needsPublish, _publishQueued, _publishing;
}
- (id) initWithName: (NSString *) name display: (WaylandDisplay *) display
           manager: (struct wl_proxy *) manager seat: (struct wl_proxy *) seat;
- (struct wl_proxy *) dataDevice;
+ (NSArray *) mimeTypesForType: (NSString *) type;
+ (NSArray *) typesForMime: (NSString *) mime;
+ (NSData *) encodeData: (NSData *) data forType: (NSString *) type;
+ (NSData *) decodeData: (NSData *) data forType: (NSString *) type mime: (NSString *) mime;
- (void) invalidate;
- (void) inputAvailable;
- (void) handleEvent: (uint32_t) opcode kind: (WaylandObjectKind) kind
              proxy: (struct wl_proxy *) proxy arguments: (union wl_argument *) args;
@end
