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

#pragma once
#import <AppKit/NSDragging.h>
#include <stdint.h>

// XDND action bits, carried in the flags word of XdndPosition and XdndStatus
// since version 2. Unlike Wayland, XDND has a link action, so the mapping is a
// bijection rather than a truncation.
#define XdndActionCopy 1u
#define XdndActionMove 2u
#define XdndActionLink 4u

static inline uint32_t X11ActionsFromOperations(NSDragOperation operations) {
    return ((operations & NSDragOperationCopy) ? XdndActionCopy : 0u) |
           ((operations & NSDragOperationMove) ? XdndActionMove : 0u) |
           ((operations & NSDragOperationLink) ? XdndActionLink : 0u);
}

static inline NSDragOperation X11OperationsFromActions(uint32_t actions) {
    return ((actions & XdndActionCopy) ? NSDragOperationCopy : NSDragOperationNone) |
           ((actions & XdndActionMove) ? NSDragOperationMove : NSDragOperationNone) |
           ((actions & XdndActionLink) ? NSDragOperationLink : NSDragOperationNone);
}
