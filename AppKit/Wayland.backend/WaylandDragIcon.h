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

#import "WaylandDisplay.h"
@class WaylandCursor;
@interface WaylandDragIcon : NSObject {
    WaylandDisplay *_display;
    WaylandCursor *_image;
    NSMutableSet *_outputs;
    struct wl_proxy *_surface, *_buffer, *_fractionalScale, *_viewport;
    NSPoint _offset;
    uint32_t _scale120, _preferredScale120, _initialScale120;
    int32_t _initialBufferScale;
    BOOL _shown, _positioned, _rendering, _scaleDirty, _scaleQueued;
}
- (id) initWithImage: (NSImage *) image display: (WaylandDisplay *) display
              scale120: (uint32_t) scale120 fallbackScale: (int32_t) fallbackScale offset: (NSPoint) offset;
- (struct wl_proxy *) surface;
- (void) show;
- (void) preferredScaleChanged: (uint32_t) scale120;
- (void) invalidate;
- (void) outputRemoved: (struct wl_proxy *) output;
- (void) scheduleScaleUpdate;
- (void) handleEvent: (uint32_t) opcode kind: (WaylandObjectKind) kind
              proxy: (struct wl_proxy *) proxy arguments: (union wl_argument *) args;
@end
