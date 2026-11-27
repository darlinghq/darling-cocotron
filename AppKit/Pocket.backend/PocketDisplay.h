/* AppKit's Pocket backend: the display of a phone host.

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

// One fullscreen screen whose size, scale and safe area the host gives, and
// the windows of the application drawn for it. The wire format is
// PocketProtocol.h.
//
// Selection: DARLING_POCKET_DISPLAY names the host's socket (a path inside
// the container). Without it, -init returns nil and NSDisplay goes on to the
// next backend. The display never opens a connection to an X server or a
// compositor, and CoreGraphics has no Pocket backend, so the screen is the
// host's and CoreGraphics' own display list is empty.

#import "../private-include/AppKit/DarlingDisplay.h"
#import "PocketProtocol.h"

@interface PocketDisplay : DarlingDisplay {
    int _socket;
    CFSocketRef _pocketSocket;
    CFRunLoopSourceRef _pocketSource;
    uint8_t _input[POCKET_MAX_MESSAGE * 4];
    size_t _inputLength;

    struct pocket_screen _screen;
    BOOL _haveScreen;
}

// Pixels per point.
- (CGFloat) scale;
// The screen in points, AppKit's way up.
- (NSRect) screenFrame;

// Messages to the host. A send that fails ends the app: its host is gone.
- (void) send: (uint32_t) type bytes: (const void *) bytes length: (size_t) length;

@end
