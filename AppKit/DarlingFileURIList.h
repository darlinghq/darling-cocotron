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
#import <Foundation/Foundation.h>

// Conversion between an RFC 2483 text/uri-list and the guest-visible file paths an
// AppKit pasteboard (NSFilenamesPboardType) carries, shared by the window-system
// backends' clipboard and drag-and-drop code. Host paths are visible in the guest
// below /Volumes/SystemRoot. Both functions are pure, never touch the filesystem
// and are all-or-nothing: one entry that is not well formed rejects the whole list.

// The guest paths of a text/uri-list, or nil if the list is not entirely well formed.
NSArray *DarlingFilenamesFromURIList(NSData *data);

// A text/uri-list for guest paths below /Volumes/SystemRoot, or nil if any entry is
// not a host-visible absolute path (a path that exists only in the guest cannot be
// named to another process) or the list is empty or too large.
NSData *DarlingURIListFromFilenames(NSArray *filenames);
