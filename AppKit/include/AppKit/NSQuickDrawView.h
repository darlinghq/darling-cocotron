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

#import <AppKit/NSView.h>
#import <AppKit/AppKitIvarLayout.h>

#ifndef __LP64__

// A view that owns a QuickDraw graphics port. 32-bit only, as on macOS.
//
// Legacy ObjC ABI (i386): instance size must stay 92, Apple's: the port
// pointer sits at offset 80 and the rest of Apple's footprint is padding.
// New state needs the extra-ivars machinery of AppKitIvarLayout.h
// (NS_SIDE_IVARS_END here: there is no room for a pointer).
@interface NSQuickDrawView : NSView {
  @private
    void *_qdPort;
    NS_LEGACY_IVAR_PAD(_NSQuickDrawViewReserved, 8)
}

// The view's QuickDraw port (a CGrafPtr), created on first use with the size of
// the view's bounds. NULL when the view has no area. The port keeps its size
// when the view is resized.
- (void *) qdPort;

@end

#endif
