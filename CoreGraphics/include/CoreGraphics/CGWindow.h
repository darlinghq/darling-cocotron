/* Copyright (c) 2006-2007 Christopher J. W. Lloyd

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

#ifndef COREGRAPHICS_CGWINDOW_H
#define COREGRAPHICS_CGWINDOW_H

// Keep this header CoreFoundation-only, as it is on macOS. The Cocotron window
// class and its delegate protocol live in CGWindowPrivate.h: pulling Foundation
// and OpenGL in here makes the CoreGraphics module re-enter Foundation mid-build.
#include <CoreFoundation/CoreFoundation.h>
#import <CoreGraphics/CGWindowLevel.h>
#import <CoreGraphics/CGImage.h>

extern const CFStringRef kCGWindowAlpha;
extern const CFStringRef kCGWindowBounds;
extern const CFStringRef kCGWindowLayer;
extern const CFStringRef kCGWindowName;
extern const CFStringRef kCGWindowIsOnscreen;
extern const CFStringRef kCGWindowOwnerName;
extern const CFStringRef kCGWindowOwnerPID;
extern const CFStringRef kCGWindowNumber;
extern const CFStringRef kCGWindowStoreType;
extern const CFStringRef kCGWindowSharingState;
extern const CFStringRef kCGWindowMemoryUsage;

typedef CF_ENUM(uint32_t, CGWindowSharingType) {
    kCGWindowSharingNone      = 0,
    kCGWindowSharingReadOnly  = 1,
    kCGWindowSharingReadWrite = 2,
};

typedef CF_ENUM(uint32_t, CGWindowBackingType) {
    kCGBackingStoreRetained    = 0,
    kCGBackingStoreNonretained = 1,
    kCGBackingStoreBuffered    = 2,
};

typedef CF_OPTIONS(uint32_t, CGWindowListOption) {
    kCGWindowListOptionAll                 = 0,
    kCGWindowListOptionOnScreenOnly        = (1 << 0),
    kCGWindowListOptionOnScreenAboveWindow = (1 << 1),
    kCGWindowListOptionOnScreenBelowWindow = (1 << 2),
    kCGWindowListOptionIncludingWindow     = (1 << 3),
    kCGWindowListExcludeDesktopElements    = (1 << 4),
};

typedef CF_OPTIONS(uint32_t, CGWindowImageOption) {
    kCGWindowImageDefault             = 0,
    kCGWindowImageBoundsIgnoreFraming = (1 << 0),
    kCGWindowImageShouldBeOpaque      = (1 << 1),
    kCGWindowImageOnlyShadows         = (1 << 2),
    kCGWindowImageBestResolution      = (1 << 3),
    kCGWindowImageNominalResolution   = (1 << 4),
};

typedef uint32_t CGWindowID;
#define kCGNullWindowID ((CGWindowID) 0)

CF_IMPLICIT_BRIDGING_ENABLED

COREGRAPHICS_EXPORT CFArrayRef CGWindowListCopyWindowInfo(CGWindowListOption option, CGWindowID relativeToWindow);
COREGRAPHICS_EXPORT CFArrayRef CGWindowListCreate(CGWindowListOption option, CGWindowID relativeToWindow);
COREGRAPHICS_EXPORT CFArrayRef CGWindowListCreateDescriptionFromArray(CFArrayRef windowArray);
COREGRAPHICS_EXPORT CGImageRef CGWindowListCreateImageFromArray(CGRect screenBounds, CFArrayRef  windowArray, CGWindowImageOption imageOption);

COREGRAPHICS_EXPORT CGImageRef CGWindowListCreateImage(CGRect screenBounds,
                                                       CGWindowListOption listOption,
                                                       CGWindowID windowID,
                                                       CGWindowImageOption imageOption);

CF_IMPLICIT_BRIDGING_DISABLED

#endif
