/*
 This file is part of Darling.

 Copyright (C) 2020 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/
#include <pthread.h>
#import <CoreGraphics/CGSConnection.h>
#import <CoreGraphics/CGSWindow.h>
#import <Foundation/NSRaise.h>
#import <CoreGraphics/CGWindow.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSValue.h>

const CFStringRef kCGSWindowTitle = CFSTR("WindowTitle");

@implementation CGSWindow
@synthesize windowId = _windowId;

- (instancetype) initWithRegion: (CGSRegionRef) region
                     connection: (CGSConnection *) connection
                       windowID: (CGSWindowID) windowID
{
    _connection = connection;
    _nextSurfaceId = 1;
    _surfaces = [[NSMutableDictionary alloc] initWithCapacity: 1];
    _windowId = windowID;
    return self;
}

- (void) dealloc {
    CGContextRelease(_contents);
    [_surfaces release];
    [super dealloc];
}

- (CGSSurface *) surfaceForId: (CGSSurfaceID) surfaceId {
    CGSSurface *rv;
    @synchronized(_surfaces) {
        rv = [_surfaces objectForKey: [NSNumber numberWithInt: surfaceId]];
    }
    return rv;
}

- (void) _surfaceInvalidated: (CGSSurfaceID) surfaceId {
    @synchronized(_surfaces) {
        [_surfaces removeObjectForKey: [NSNumber numberWithInt: surfaceId]];
    }
}

- (void) invalidate {
    [_connection _windowInvalidated: _windowId];
}

- (CGError) orderWindow: (CGSWindowOrderingMode) place
             relativeTo: (CGSWindow *) window
{
    NSInvalidAbstractInvocation();
}

- (CGError) moveTo: (const CGPoint *) point {
    NSInvalidAbstractInvocation();
}

- (CGError) setRegion: (CGSRegionRef) region {
    NSInvalidAbstractInvocation();
}

- (CGError) getRect: (CGRect *) outRect {
    NSInvalidAbstractInvocation();
}

- (CGError) setProperty: (CFStringRef) key value: (CFTypeRef) value {
    NSInvalidAbstractInvocation();
}

- (CGError) getProperty: (CFStringRef) key value: (CFTypeRef *) value {
    NSInvalidAbstractInvocation();
}

- (CGError) becomeDisplayOverlay: (void **) drawable {
    return kCGErrorNotImplemented;
}

- (CGError) recreateToplevelWithAttributes: (const CGSToplevelAttributes *) attributes {
    return kCGErrorNotImplemented;
}

- (CGError) setToplevelFrame: (CGRect) frame {
    return kCGErrorNotImplemented;
}

- (CGError) setToplevelMinimumSize: (CGSize) minimum maximumSize: (CGSize) maximum {
    return kCGErrorNotImplemented;
}

- (CGError) setToplevelAlpha: (CGFloat) alpha {
    return kCGErrorNotImplemented;
}

- (CGSSurface *) createSurface {
    NSInvalidAbstractInvocation();
}

- (void *) nativeWindow {
    NSInvalidAbstractInvocation();
}

#pragma mark - Contents

@synthesize styleFlags = _styleFlags;

- (CGError) setStyle: (uint32_t) styleFlags {
    _styleFlags = styleFlags;
    return kCGSErrorSuccess;
}

@synthesize level = _level;

- (CGError) setLevel: (CGWindowLevel) level {
    _level = level;
    return kCGSErrorSuccess;
}

- (void) presentRect: (CGRect) rect {
}

// A bitmap of 8 bits per component, little-endian 32-bit pixels with the alpha first (BGRA in
// memory), premultiplied: the layout both X11 (24-bit TrueColor) and wl_shm's ARGB8888 take.
static CGContextRef createContents(size_t width, size_t height) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(
            NULL, width, height, 8, 0, space,
            kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(space);
    return context;
}

- (void) resizeContentsTo: (CGSize) size {
    size_t width = (size_t) size.width, height = (size_t) size.height;
    if (width < 1 || height < 1)
        return;
    @synchronized(self) {
        if (_contents == NULL && _contentsSize.width == 0) {
            // Nothing drawn yet: the contents are made by the first drawing
            return;
        }
        if (size.width == _contentsSize.width && size.height == _contentsSize.height)
            return;
        CGContextRef bigger = createContents(width, height);
        if (bigger == NULL)
            return;
        if (_contents != NULL) {
            CGImageRef old = CGBitmapContextCreateImage(_contents);
            if (old != NULL) {
                CGContextSetBlendMode(bigger, kCGBlendModeCopy);
                // The origin of the bitmap is its bottom left corner: keep the top left
                CGContextDrawImage(bigger, CGRectMake(0, height - CGImageGetHeight(old),
                        CGImageGetWidth(old), CGImageGetHeight(old)), old);
                CGImageRelease(old);
            }
            CGContextRelease(_contents);
        }
        _contents = bigger;
        _contentsSize = CGSizeMake(width, height);
    }
}

- (CGError) drawImage: (CGImageRef) image atPoint: (CGPoint) origin {
    if (image == NULL)
        return kCGErrorIllegalArgument;

    CGRect frame;
    if ([self getRect: &frame] != kCGSErrorSuccess)
        return kCGErrorFailure;
    size_t width = (size_t) frame.size.width, height = (size_t) frame.size.height;
    if (width < 1 || height < 1)
        return kCGErrorFailure;

    CGRect dirty;
    @synchronized(self) {
        if (_contents == NULL) {
            _contents = createContents(width, height);
            if (_contents == NULL)
                return kCGErrorFailure;
            _contentsSize = CGSizeMake(width, height);
        } else if (_contentsSize.width != width || _contentsSize.height != height) {
            [self resizeContentsTo: CGSizeMake(width, height)];
        }

        CGFloat imageWidth = CGImageGetWidth(image), imageHeight = CGImageGetHeight(image);
        // Rows count from the top of the window, the bitmap's from its bottom
        CGRect target = CGRectMake(origin.x, _contentsSize.height - origin.y - imageHeight,
                imageWidth, imageHeight);
        CGContextSaveGState(_contents);
        CGContextSetBlendMode(_contents, kCGBlendModeCopy);
        CGContextClipToRect(_contents, CGRectMake(0, 0, _contentsSize.width, _contentsSize.height));
        CGContextDrawImage(_contents, target, image);
        CGContextRestoreGState(_contents);
        dirty = CGRectIntersection(CGRectMake(origin.x, origin.y, imageWidth, imageHeight),
                CGRectMake(0, 0, _contentsSize.width, _contentsSize.height));
    }
    if (!CGRectIsNull(dirty))
        [self presentRect: dirty];
    return kCGSErrorSuccess;
}

- (CGImageRef) copyContentsImage {
    @synchronized(self) {
        return _contents != NULL ? CGBitmapContextCreateImage(_contents) : NULL;
    }
}

- (BOOL) withContents: (void (^)(const void *, size_t, CGSize)) block {
    @synchronized(self) {
        if (_contents == NULL)
            return NO;
        block(CGBitmapContextGetData(_contents), CGBitmapContextGetBytesPerRow(_contents),
              _contentsSize);
    }
    return YES;
}


@end

CGError CGSSetWindowTitle(CGSConnectionID cid, CGSWindowID wid,
                          CFStringRef title)
{
    return CGSSetWindowProperty(cid, wid, kCGSWindowTitle, title);
}

static NSArray<NSDictionary *> *copyAllWindowDescriptions(void) {
    CGSConnection *connection = _CGSConnectionForID(CGSDefaultConnection);

    return connection ? [connection copyWindowDescriptions]
                      : [[NSArray alloc] init];
}

static CGWindowID windowNumberOf(NSDictionary *description) {
    return [[description objectForKey: (NSString *) kCGWindowNumber]
            unsignedIntValue];
}

// The descriptions the option and the reference window select, front to back.
static NSMutableArray<NSDictionary *> *
copySelectedWindowDescriptions(CGWindowListOption option,
                               CGWindowID relativeToWindow)
{
    NSArray<NSDictionary *> *all = copyAllWindowDescriptions();
    NSMutableArray<NSDictionary *> *selected = [[NSMutableArray alloc] init];
    NSUInteger referenceIndex = NSNotFound;
    BOOL above = (option & kCGWindowListOptionOnScreenAboveWindow) != 0;
    BOOL below = (option & kCGWindowListOptionOnScreenBelowWindow) != 0;
    BOOL including = (option & kCGWindowListOptionIncludingWindow) != 0;
    BOOL onScreenOnly =
            (option & kCGWindowListOptionOnScreenOnly) != 0 || above || below;

    if (relativeToWindow != kCGNullWindowID) {
        for (NSUInteger i = 0; i < [all count]; i++) {
            if (windowNumberOf([all objectAtIndex: i]) == relativeToWindow) {
                referenceIndex = i;
                break;
            }
        }
    }

    // With a reference window that does not exist, the relative options
    // select nothing.
    if ((above || below || including) && referenceIndex == NSNotFound) {
        [all release];
        return selected;
    }

    for (NSUInteger i = 0; i < [all count]; i++) {
        NSDictionary *window = [all objectAtIndex: i];
        BOOL isReference = i == referenceIndex;
        BOOL include;

        if (above)
            include = i < referenceIndex || (including && isReference);
        else if (below)
            include = i > referenceIndex || (including && isReference);
        else if (including)
            include = isReference;
        else
            include = YES;

        if (include && onScreenOnly && !isReference &&
            ![[window objectForKey: (NSString *) kCGWindowIsOnscreen] boolValue])
            include = NO;

        if (include)
            [selected addObject: window];
    }

    [all release];
    return selected;
}

CFArrayRef __nullable CGWindowListCopyWindowInfo(CGWindowListOption option,
                                                 CGWindowID relativeToWindow)
{
    return (CFArrayRef) copySelectedWindowDescriptions(option,
                                                       relativeToWindow);
}

CFArrayRef __nullable CGWindowListCreate(CGWindowListOption option, CGWindowID relativeToWindow)
{
    NSArray<NSDictionary *> *selected =
            copySelectedWindowDescriptions(option, relativeToWindow);
    CFMutableArrayRef numbers =
            CFArrayCreateMutable(NULL, [selected count], NULL);

    // Like the window server, a plain array of CGWindowID values.
    for (NSDictionary *window in selected)
        CFArrayAppendValue(numbers,
                           (const void *) (uintptr_t) windowNumberOf(window));

    [selected release];
    return numbers;
}

CFArrayRef __nullable CGWindowListCreateDescriptionFromArray(CFArrayRef windowArray)
{
    if (windowArray == NULL)
        return NULL;

    NSArray<NSDictionary *> *all = copyAllWindowDescriptions();
    NSMutableArray<NSDictionary *> *descriptions = [[NSMutableArray alloc] init];

    // The array holds CGWindowID values, as CGWindowListCreate() returns
    // them. Windows that no longer exist are left out.
    for (CFIndex i = 0; i < CFArrayGetCount(windowArray); i++) {
        CGWindowID number =
                (CGWindowID) (uintptr_t) CFArrayGetValueAtIndex(windowArray, i);

        for (NSDictionary *window in all) {
            if (windowNumberOf(window) == number) {
                [descriptions addObject: window];
                break;
            }
        }
    }

    [all release];
    return (CFArrayRef) descriptions;
}

CGImageRef __nullable CGWindowListCreateImageFromArray(CGRect screenBounds,
                                                       CFArrayRef windowArray,
                                                       CGWindowImageOption imageOption)
{
    // The image holds the listed windows composited over a transparent
    // background, in a bitmap of the bounds' size. Window contents cannot be
    // read back (there is no screen capture backend), so a list with windows
    // gives no image, as when screen recording is not permitted. An empty
    // list has nothing to composite and gives the transparent image.
    if (windowArray == NULL || CFArrayGetCount(windowArray) != 0 ||
        CGRectIsNull(screenBounds) || CGRectIsInfinite(screenBounds) ||
        CGRectIsEmpty(screenBounds))
        return NULL;

    size_t width = (size_t) ceil(screenBounds.size.width);
    size_t height = (size_t) ceil(screenBounds.size.height);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, space,
                                                 kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(space);
    if (context == NULL)
        return NULL;
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return image;
}

// The window of the process' default connection that the number names: the CGS window id, or the
// id of the native window of it, which is what the window lists give for a CGS window.
static CGSWindow *copyCGSWindowForNumber(CGWindowID number) {
    CGSConnection *connection = _CGSConnectionForID(CGSDefaultConnection);
    if (connection == nil || number == kCGNullWindowID)
        return nil;
    CGSWindow *found = [[connection windowForId: number] retain];
    if (found != nil)
        return found;
    NSArray *all = [connection copyAllWindows];
    for (CGSWindow *window in all) {
        if ((uintptr_t) [window nativeWindow] == number) {
            found = [window retain];
            break;
        }
    }
    [all release];
    return found;
}

CGImageRef __nullable CGWindowListCreateImage(CGRect screenBounds,
                                              CGWindowListOption listOption,
                                              CGWindowID windowID,
                                              CGWindowImageOption imageOption)
{
    // Only the contents of a single window of this process can be read: windows drawn into with
    // -[CGSWindow drawImage:atPoint:] keep their pixels. Anything else has no capture backend.
    if (!(listOption & kCGWindowListOptionIncludingWindow) ||
        (listOption & (kCGWindowListOptionOnScreenAboveWindow | kCGWindowListOptionOnScreenBelowWindow)))
        return NULL;

    CGSWindow *window = copyCGSWindowForNumber(windowID);
    if (window == nil)
        return NULL;
    CGImageRef image = [window copyContentsImage];
    [window release];
    if (image == NULL || CGRectIsNull(screenBounds) || CGRectIsInfinite(screenBounds))
        return image;

    // Bounds are in global coordinates: the part of the window they select
    CGRect frame;
    CGImageRef cropped = NULL;
    CGSWindow *again = copyCGSWindowForNumber(windowID);
    if (again != nil && [again getRect: &frame] == kCGSErrorSuccess) {
        CGRect part = CGRectOffset(screenBounds, -frame.origin.x, -frame.origin.y);
        cropped = CGImageCreateWithImageInRect(image, part);
    }
    [again release];
    CGImageRelease(image);
    return cropped;
}

CGError _CGSWindowDrawImage(CGSConnectionID cid, CGSWindowID wid, CGImageRef image, CGPoint origin)
{
    CGSConnection *connection = _CGSConnectionForID(cid);
    if (connection == nil)
        return kCGErrorInvalidConnection;
    CGSWindow *window = [[connection windowForId: wid] retain];
    if (window == nil)
        return kCGErrorIllegalArgument;
    CGError error = [window drawImage: image atPoint: origin];
    [window release];
    return error;
}

CGImageRef _CGSWindowCopyContents(CGSConnectionID cid, CGSWindowID wid)
{
    CGSConnection *connection = _CGSConnectionForID(cid);
    CGSWindow *window = [[connection windowForId: wid] retain];
    CGImageRef image = [window copyContentsImage];
    [window release];
    return image;
}

CGError _CGSWindowSetStyle(CGSConnectionID cid, CGSWindowID wid, uint32_t styleFlags)
{
    CGSConnection *connection = _CGSConnectionForID(cid);
    if (connection == nil)
        return kCGErrorInvalidConnection;
    CGSWindow *window = [[connection windowForId: wid] retain];
    if (window == nil)
        return kCGErrorIllegalArgument;
    CGError error = [window setStyle: styleFlags];
    [window release];
    return error;
}

CGError CGSSetWindowLevel(CGSConnectionID cid, CGSWindowID wid, CGWindowLevel level)
{
    CGSConnection *connection = _CGSConnectionForID(cid);
    if (connection == nil)
        return kCGErrorInvalidConnection;
    CGSWindow *window = [[connection windowForId: wid] retain];
    if (window == nil)
        return kCGErrorIllegalArgument;
    CGError error = [window setLevel: level];
    [window release];
    return error;
}

static pthread_mutex_t g_windowEventLock = PTHREAD_MUTEX_INITIALIZER;
static CGSWindowEventProc g_windowEventProc;
static void *g_windowEventInfo;

void _CGSSetWindowEventProc(CGSWindowEventProc proc, void *info)
{
    pthread_mutex_lock(&g_windowEventLock);
    g_windowEventProc = proc;
    g_windowEventInfo = info;
    pthread_mutex_unlock(&g_windowEventLock);
}

// For the backends
void _CGSPostWindowEvent(CGSWindowEventKind kind, CGSWindowID window, CGRect rect)
{
    pthread_mutex_lock(&g_windowEventLock);
    CGSWindowEventProc proc = g_windowEventProc;
    void *info = g_windowEventInfo;
    pthread_mutex_unlock(&g_windowEventLock);
    if (proc != NULL)
        proc(kind, window, rect, info);
}


// The window's bounds in global display coordinates, origin at the top left, as
// CGWindowListCopyWindowInfo() reports them. kCGErrorFailure and the null rect for a window that
// does not exist, as observed on macOS 26.7.3.
CGError CGSGetScreenRectForWindow(CGSConnectionID cid, CGSWindowID wid, CGRect *outRect)
{
    CGRect bounds = CGRectNull;
    BOOL found = NO;
    NSArray<NSDictionary *> *all = copyAllWindowDescriptions();

    for (NSDictionary *window in all) {
        if (windowNumberOf(window) == wid) {
            CFDictionaryRef dictionary = (CFDictionaryRef) [window objectForKey: (NSString *) kCGWindowBounds];
            found = dictionary != NULL && CGRectMakeWithDictionaryRepresentation(dictionary, &bounds);
            break;
        }
    }
    [all release];

    if (outRect != NULL)
        *outRect = found ? bounds : CGRectNull;
    return found ? kCGErrorSuccess : kCGErrorFailure;
}

// Window contents cannot be read back (there is no screen capture backend), so no images are
// given, as on macOS when the capture is not permitted.
CFArrayRef CGSHWCaptureWindowList(CGSConnectionID cid, CGSWindowID *windowList, uint32_t windowCount, uint32_t options)
{
    return NULL;
}
