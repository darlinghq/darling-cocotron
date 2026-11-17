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

// Display mode changes through wlr-output-management-unstable-v1 (wlroots
// compositors such as sway). The manager announces every output as a "head"
// with its modes and current state; a configuration that lists every head
// is tested and applied to change a head's mode. Compositors without the
// protocol (GNOME's Mutter, KDE's KWin) do not get a manager, and their
// modes stay as the wl_output events report them.

#import "WaylandDisplay.h"

@protocol WaylandOutputManagementEvents
- (void) handleEvent: (uint32_t) opcode
                kind: (WaylandObjectKind) kind
               proxy: (struct wl_proxy *) proxy
           arguments: (union wl_argument *) args;
@end

@interface WaylandOutputManager : NSObject <WaylandOutputManagementEvents> {
    struct wl_display *_display;
    struct wl_proxy *_proxy;
    NSMutableArray *_heads;
    uint32_t _serial;
    BOOL _stopped;
}

// manager is the bound zwlr_output_manager_v1. The caller routes its events
// (WaylandObjectOutputManager and the kinds below) to -handleEvent:.
- (instancetype) initWithDisplay: (struct wl_display *) display manager: (struct wl_proxy *) manager;

// The modes of the head that drives the wl_output at x, y with the given
// current size, as dictionaries like -modesForScreen: returns; nil when no
// head is known for it.
- (NSArray *) modesForOutputAtX: (int) x y: (int) y width: (int) width height: (int) height;

// Changes the mode of that output's head to the listed mode of the given
// size whose refresh rate (in mHz) is nearest. Returns whether the compositor
// applied it.
- (BOOL) setModeWidth: (int) width height: (int) height refresh: (int) refresh
        forOutputAtX: (int) x y: (int) y currentWidth: (int) currentWidth currentHeight: (int) currentHeight;

// Destroys the protocol objects.
- (void) stop;
@end
