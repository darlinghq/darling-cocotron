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
#import <AppKit/NSDragging.h>
#import "WaylandDisplay.h"

@class WaylandDragIcon;
extern NSString * const WaylandLocalDragMime;
@interface WaylandDraggingManager : NSDraggingManager {
    WaylandDisplay *_display; // Display owns manager.
    WaylandWindow *_origin;
    WaylandDragIcon *_icon;
    id _localSource;
    struct wl_proxy *_source;
    NSDictionary *_snapshot;
    BOOL _busy, _finished, _dropped, _nativeStarted, _localOnly;
    NSDictionary *_localSnapshot;
    NSString *_localMime;
    id _localSession; // Nonretained identity, revoked before session teardown.
    NSUInteger _localGeneration;
    uint32_t _completedLocalAction;
    uint32_t _action, _offeredActions;
    double _dropDeadline;
    NSDragOperation _localOperations;
}
- (id) initWithDisplay: (WaylandDisplay *) display;
- (NSDragOperation) localOperations;
- (NSDictionary *) localSnapshotForSession: (id) session mimes: (NSArray *) mimes
                               generation: (NSUInteger *) generation;
- (BOOL) permitsLocalSession: (id) session generation: (NSUInteger) generation;
- (void) revokeLocalSession: (id) session generation: (NSUInteger) generation;
- (BOOL) completeLocalSession: (id) session generation: (NSUInteger) generation
                       action: (uint32_t) action;
- (void) cancel;
- (void) outputRemoved: (struct wl_proxy *) output;
- (void) outputsChanged;
- (void) invalidate;
- (void) windowUnmapped: (WaylandWindow *) window;
- (void) handleEvent: (uint32_t) opcode kind: (WaylandObjectKind) kind
              proxy: (struct wl_proxy *) proxy arguments: (union wl_argument *) args;
@end
