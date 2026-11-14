/* Copyright (C) 2026 Lubos Dolezel

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#import <AppKit/NSDisplay.h>

// The part of a display backend that does not depend on the windowing system:
// the system colours, the fontconfig font enumeration, the metrics and the
// click counting state. The X11 and Wayland backends are both subclasses of it,
// so neither has to be built on the other. A backend subclass connects to its
// own server in -init (after calling this class's) and overrides everything
// that needs the connection.
@interface DarlingDisplay : NSDisplay {
    // Per button, so the state of one button cannot make the next click of
    // another look like a double click.
    NSMutableDictionary *_buttonClickCounts;
    NSInteger _clickCount;
}
- (CGFloat) doubleClickInterval;
@end
