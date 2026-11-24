/* AppKit's Pocket backend: a window.

 Permission is hereby granted, free of charge, to any person obtaining a copy of
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

#import <CoreGraphics/CGWindowPrivate.h>
#import <Onyx2D/O2Geometry.h>

@class NSWindow, O2Context, PocketDisplay;

// A window the host shows: Onyx2D draws it at the screen's scale, and each
// flush copies it into the shared buffer the host reads.
@interface PocketWindow : CGWindow {
    NSWindow *_delegate;
    PocketDisplay *_display;
    BOOL _invalidated;
    BOOL _visible;
    int _level;
    NSUInteger _styleMask;
    BOOL _isOpaque;
    O2Rect _frame; // AppKit screen coordinates, in points
    NSString *_title;
    O2Context *_context;
    NSMutableDictionary *_deviceDictionary;

    // The shared buffer.
    void *_pixels;
    size_t _bufferSize;
    uint32_t _bufferWidth, _bufferHeight;
    BOOL _busy;         // presented, and the host has not released it yet
    BOOL _needsPresent; // drawn since the last present
}

- (instancetype) initWithDelegate: (NSWindow *) delegate;
- (NSWindow *) delegate;
- (O2Rect) frame;
- (O2Context *) cgContext;
- (BOOL) isVisible;
- (int) level;
- (uint32_t) number;

// From the host.
- (void) bufferReleased;
- (void) screenChanged;

@end
