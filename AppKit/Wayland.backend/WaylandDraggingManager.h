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

#import <AppKit/NSDraggingManager.h>
#import "WaylandDisplay.h"

@interface WaylandDraggingManager : NSDraggingManager {
    WaylandDisplay *_display; // Display owns manager.
    WaylandWindow *_origin;
    id _localSource;
    struct wl_proxy *_source;
    NSDictionary *_snapshot;
    BOOL _busy, _finished, _dropped;
    uint32_t _action;
    double _dropDeadline;
    BOOL _localCopyAllowed;
}
- (id) initWithDisplay: (WaylandDisplay *) display;
- (BOOL) localCopyAllowed;
- (void) cancel;
- (void) invalidate;
- (void) windowUnmapped: (WaylandWindow *) window;
- (void) handleEvent: (uint32_t) opcode kind: (WaylandObjectKind) kind
              proxy: (struct wl_proxy *) proxy arguments: (union wl_argument *) args;
@end
