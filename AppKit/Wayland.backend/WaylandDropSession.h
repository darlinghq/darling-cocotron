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
#import <AppKit/NSDragging.h>
#import "WaylandDisplay.h"
@class WaylandWindow, WaylandDraggingManager;

// One incoming offer. Its pasteboard never touches the clipboard.
@interface WaylandDropSession : NSPasteboard <NSDraggingInfo> {
    WaylandDisplay *_display;
    WaylandWindow *_window;
    NSWindow *_destination;
    struct wl_proxy *_offer;
    NSArray *_mimes, *_types;
    NSMutableDictionary *_cache, *_wireCache;
    NSDictionary *_localSnapshot;
    WaylandDraggingManager *_localManager;
    NSUInteger _localGeneration;
    id _receiver, _localSource;
    NSDragOperation _localOperations;
    NSPoint _point;
    uint32_t _serial, _sourceActions, _action, _acceptedActions;
    BOOL _dropAnnounced, _dropped, _accepted, _transferFailed;
    int _sequence;
    NSUInteger _negotiationDepth, _motionGeneration;
}
- (id) initWithOffer: (struct wl_proxy *) offer types: (NSArray *) mimes
            display: (WaylandDisplay *) display window: (WaylandWindow *) window
             serial: (uint32_t) serial sourceActions: (uint32_t) actions;
- (void) motion: (CGPoint) point;
- (void) sourceActions: (uint32_t) actions;
- (void) selectedAction: (uint32_t) action;
- (void) markDropped;
- (void) drop;
- (void) willLeave;
- (void) leave;
- (void) invalidate;
@end
