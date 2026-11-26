/* Copyright (c) 2008 Johannes Fortmann

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

#import <AppKit/NSDraggingManager.h>
#import <AppKit/NSDragging.h>

// The dragging manager of a window system whose drag and drop CoreGraphics runs (see CGSDrag.h): it starts the drags
// of NSDraggingSession and -dragImage:..., and registers the windows as drag destinations. Everything the window
// system's protocol needs is CoreGraphics'.
@interface NSCGSDraggingManager : NSDraggingManager {
    // The source of the drag this manager is running, which a destination in this application sees
    id _localSource;
    BOOL _dragging;
}

// One per process, like the display's other managers: it is reached through +[NSDraggingManager draggingManager]
// and has to outlive any single window. nil when CoreGraphics' window system has no drag and drop.
+ (NSCGSDraggingManager *) sharedManager;

@end
