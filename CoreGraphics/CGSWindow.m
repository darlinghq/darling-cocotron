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
#include <stdbool.h>
#include <stdlib.h>
#include <time.h>
#include <string.h>

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
    _inputMethodCursorRect = CGRectNull;
    return self;
}

- (void) dealloc {
    CGContextRelease(_contents);
    [_surfaces release];
    [_dragDestination release];
    [_inputMethodSurroundingText release];
    [super dealloc];
}

- (void) setDragDestination: (id<CGSDragDestination>) destination {
    if (destination == _dragDestination)
        return;
    id<CGSDragDestination> old = _dragDestination;
    _dragDestination = [destination retain];
    [old release];
    [self dragDestinationChanged];
}

- (id<CGSDragDestination>) dragDestination {
    return _dragDestination;
}

- (void) dragDestinationChanged {
}

- (void) setInputMethodEnabled: (BOOL) enabled {
    if (enabled == _inputMethodEnabled)
        return;
    _inputMethodEnabled = enabled;
    [self inputMethodEnabledChanged];
}

- (BOOL) inputMethodEnabled {
    return _inputMethodEnabled;
}

- (void) setInputMethodCursorRect: (CGRect) rect {
    if (CGRectEqualToRect(rect, _inputMethodCursorRect))
        return;
    _inputMethodCursorRect = rect;
    [self inputMethodCursorRectChanged];
}

- (CGRect) inputMethodCursorRect {
    return _inputMethodCursorRect;
}

- (void) inputMethodEnabledChanged {
}

- (void) inputMethodCursorRectChanged {
}

- (void) setInputMethodSurroundingText: (NSString *) text selection: (CFRange) selection {
    if ((text == _inputMethodSurroundingText || [text isEqualToString: _inputMethodSurroundingText]) &&
        selection.location == _inputMethodSurroundingSelection.location &&
        selection.length == _inputMethodSurroundingSelection.length)
        return;
    NSString *old = _inputMethodSurroundingText;
    _inputMethodSurroundingText = [text copy];
    [old release];
    _inputMethodSurroundingSelection = selection;
    [self inputMethodSurroundingTextChanged];
}

- (NSString *) inputMethodSurroundingText {
    return _inputMethodSurroundingText;
}

- (CFRange) inputMethodSurroundingSelection {
    return _inputMethodSurroundingSelection;
}

- (void) setInputMethodContentHint: (uint32_t) hint purpose: (uint32_t) purpose {
    if (hint == _inputMethodContentHint && purpose == _inputMethodContentPurpose)
        return;
    _inputMethodContentHint = hint;
    _inputMethodContentPurpose = purpose;
    [self inputMethodContentTypeChanged];
}

- (uint32_t) inputMethodContentHint {
    return _inputMethodContentHint;
}

- (uint32_t) inputMethodContentPurpose {
    return _inputMethodContentPurpose;
}

- (void) inputMethodSurroundingTextChanged {
}

- (void) inputMethodContentTypeChanged {
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
    [self setToplevelEventProc: NULL info: NULL];
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

- (void) setToplevelEventProc: (CGSToplevelEventProc) proc info: (void *) info {
    @synchronized(self) {
        _toplevelEventProc = proc;
        _toplevelEventInfo = info;
    }
}

- (void) postToplevelEvent: (const CGSToplevelEvent *) event {
    CGSToplevelEventProc proc;
    void *info;
    @synchronized(self) {
        proc = _toplevelEventProc;
        info = _toplevelEventInfo;
    }
    if (proc != NULL)
        proc(self, event, info);
}

- (CGRect) toplevelFrame {
    return CGRectNull;
}

- (CGFloat) toplevelBackingScaleFactor {
    return 1;
}

- (CGRect) toplevelDeviceRectForFrame: (CGRect) frame {
    return frame;
}

- (CGSize) toplevelDeviceSizeForSize: (CGSize) size {
    return size;
}

- (CGRect) toplevelDeviceRectForRect: (CGRect) rect {
    return rect;
}

- (CGError) setToplevelHasShadow: (BOOL) hasShadow {
    return kCGErrorNotImplemented;
}

- (CGError) setToplevelContentsOpaque: (BOOL) opaque {
    return kCGErrorNotImplemented;
}

- (CGError) setToplevelCornerRadius: (CGFloat) radius {
    return kCGErrorNotImplemented;
}

- (CGError) setToplevelShapeEmpty: (BOOL) empty {
    return kCGErrorNotImplemented;
}

- (BOOL) toplevelWindowSystemComposites {
    return NO;
}

- (CGError) setToplevelIgnoresMouseEvents: (BOOL) ignores {
    return kCGErrorNotImplemented;
}

- (CGError) setToplevelDecorated: (BOOL) decorated {
    return kCGErrorNotImplemented;
}

- (CGError) setToplevelTitlebarKind: (CGSToplevelTitlebarKind) kind {
    return kCGErrorNotImplemented;
}

- (CGSToplevelTitlebarKind) toplevelTitlebarKind {
    return kCGSToplevelTitlebarNone;
}

- (CGError) setToplevelPrefersClientDecoration: (BOOL) prefers {
    return kCGErrorNotImplemented;
}

- (CGError) setToplevelClientDecorationLayout: (const CGSToplevelDecorationLayout *) layout {
    return kCGErrorNotImplemented;
}

- (BOOL) toplevelClientDecorationContainsPoint: (CGPoint) point {
    return NO;
}

- (CGError) beginToplevelMoveByWindowSystem {
    return kCGErrorNotImplemented;
}

- (CGError) setToplevelIcons: (NSArray<NSData *> *) icons {
    return kCGErrorNotImplemented;
}

- (CGError) setToplevelHints: (const CGSToplevelHints *) hints {
    return kCGErrorNotImplemented;
}

- (CGError) reserveToplevelDockStrip {
    return kCGErrorNotImplemented;
}

- (CGError) setToplevelLevel: (int) level {
    return kCGErrorNotImplemented;
}

- (CGError) setToplevelStacksByLevel: (BOOL) stacks {
    return kCGErrorNotImplemented;
}

- (CGError) setToplevelApplicationMenuServiceName: (NSString *) service objectPath: (NSString *) path {
    return kCGErrorNotImplemented;
}

- (CGError) setToplevelHoldsInputForMenu: (BOOL) holds {
    return kCGErrorNotImplemented;
}

- (CGError) orderToplevelAbove: (CGSWindow *) sibling {
    return kCGErrorNotImplemented;
}

- (CGError) orderToplevelBelow: (CGSWindow *) sibling {
    return kCGErrorNotImplemented;
}

- (CGError) restackToplevelForLevels {
    return kCGErrorNotImplemented;
}

- (CGError) requestToplevelKeyboardFocus {
    return kCGErrorNotImplemented;
}

- (BOOL) toplevelHoldsKeyboardFocus {
    return NO;
}

- (CGError) miniaturizeToplevel {
    return kCGErrorNotImplemented;
}

- (CGError) deminiaturizeToplevel {
    return kCGErrorNotImplemented;
}

- (BOOL) toplevelIsMiniaturized {
    return NO;
}

- (BOOL) toplevelFrameCoversDisplay: (CGRect) frame {
    return NO;
}

- (CGError) setToplevelFullscreen: (BOOL) fullscreen force: (BOOL) force {
    return kCGErrorNotImplemented;
}

- (BOOL) toplevelFullscreenRequested {
    return NO;
}

- (BOOL) toplevelIsFullscreen {
    return NO;
}

- (BOOL) toplevelIsOccluded {
    return NO;
}

- (void) cancelToplevelKeyboardFocusRequest {
}

- (CGError) setToplevelParent: (CGSWindow *) parent {
    return kCGErrorNotImplemented;
}

- (CGSWindow *) toplevelParent {
    return nil;
}

- (CGError) setToplevelHeldBack: (BOOL) heldBack {
    return kCGErrorNotImplemented;
}

- (BOOL) toplevelFullscreenSettling {
    return NO;
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

#if defined(HAVE_PIPEWIRE) && HAVE_PIPEWIRE
#include <screen_capture_backend.h>

struct darling_cg_window_capture_state {
    pthread_mutex_t mutex;
    pthread_cond_t cond;
    bool done;
    bool gotFrame;
    uint8_t *bytes;
    uint32_t width;
    uint32_t height;
    uint32_t stride;
};

static void darlingCGWindowCaptureFrame(const struct darling_screen_capture_frame *frame, void *userData)
{
    struct darling_cg_window_capture_state *state = userData;
    pthread_mutex_lock(&state->mutex);
    if (!state->done && frame && frame->width && frame->height) {
        state->bytes = calloc((size_t) state->height * state->stride, 1);
        if (state->bytes && darling_screen_capture_convert_bgra(frame, state->bytes, state->stride, state->width, state->height) == 0)
            state->gotFrame = true;
        else {
            free(state->bytes);
            state->bytes = NULL;
        }
    }
    state->done = true;
    pthread_cond_broadcast(&state->cond);
    pthread_mutex_unlock(&state->mutex);
}

static void darlingCGWindowCaptureError(int error, void *userData)
{
    struct darling_cg_window_capture_state *state = userData;
    (void) error;
    pthread_mutex_lock(&state->mutex);
    state->done = true;
    pthread_cond_broadcast(&state->cond);
    pthread_mutex_unlock(&state->mutex);
}
#endif

static CGRect darlingWindowBoundsFromDescription(NSDictionary *description)
{
    NSDictionary *bounds = [description objectForKey: (NSString *) kCGWindowBounds];
    CGRect rect = CGRectZero;
    if ([bounds isKindOfClass: [NSDictionary class]])
        CGRectMakeWithDictionaryRepresentation((CFDictionaryRef) bounds, &rect);
    return rect;
}

CGImageRef __nullable CGWindowListCreateImageFromArray(CGRect screenBounds,
                                                       CFArrayRef windowArray,
                                                       CGWindowImageOption imageOption)
{
    if (windowArray == NULL || CGRectIsNull(screenBounds) || CGRectIsEmpty(screenBounds))
        return NULL;

    bool shouldBeOpaque = (imageOption & kCGWindowImageShouldBeOpaque) != 0;
    bool onlyShadows = (imageOption & kCGWindowImageOnlyShadows) != 0;

    CGRect captureBounds = screenBounds;
    if (CGRectIsInfinite(captureBounds)) {
        CFArrayRef desc = CGWindowListCreateDescriptionFromArray(windowArray);
        CGRect unionRect = CGRectNull;
        if (desc) {
            for (CFIndex i = 0; i < CFArrayGetCount(desc); i++) {
                NSDictionary *d = (NSDictionary *) CFArrayGetValueAtIndex(desc, i);
                CGRect r = darlingWindowBoundsFromDescription(d);
                if (!CGRectIsEmpty(r))
                    unionRect = CGRectIsNull(unionRect) ? r : CGRectUnion(unionRect, r);
            }
            CFRelease(desc);
        }
        if (CGRectIsNull(unionRect) || CGRectIsEmpty(unionRect))
            captureBounds = CGDisplayBounds(CGMainDisplayID());
        else
            captureBounds = unionRect;
    }

    size_t width = (size_t) ceil(captureBounds.size.width);
    size_t height = (size_t) ceil(captureBounds.size.height);
    if (width == 0 || height == 0)
        return NULL;

#if defined(HAVE_PIPEWIRE) && HAVE_PIPEWIRE
    if (CFArrayGetCount(windowArray) != 0 && !onlyShadows) {
        struct darling_cg_window_capture_state state;
        struct darling_screen_capture_callbacks callbacks = {
            .frame = darlingCGWindowCaptureFrame,
            .error = darlingCGWindowCaptureError,
        };
        struct darling_screen_capture_stream *stream = NULL;
        CGImageRef image = NULL;

        pthread_mutex_init(&state.mutex, NULL);
        pthread_cond_init(&state.cond, NULL);
        state.done = false;
        state.gotFrame = false;
        state.width = (uint32_t) width;
        state.height = (uint32_t) height;
        state.stride = ((state.width * 4 + 15u) & ~15u);
        state.bytes = NULL;

        if (darling_screen_capture_open((int32_t) captureBounds.origin.x, (int32_t) captureBounds.origin.y,
                (uint32_t) width, (uint32_t) height, 0, darling_screen_capture_supports_hdr() ? 1 : 0,
                &callbacks, &state, &stream) == 0) {
            darling_screen_capture_start(stream, 1);
            pthread_mutex_lock(&state.mutex);
            for (int i = 0; i < 100 && !state.done; i++) {
                struct timespec ts;
                clock_gettime(CLOCK_REALTIME, &ts);
                ts.tv_nsec += 20 * 1000 * 1000;
                if (ts.tv_nsec >= 1000000000L) { ts.tv_sec++; ts.tv_nsec -= 1000000000L; }
                pthread_cond_timedwait(&state.cond, &state.mutex, &ts);
                pthread_mutex_unlock(&state.mutex);
                darling_screen_capture_wait(stream, 20);
                pthread_mutex_lock(&state.mutex);
            }
            pthread_mutex_unlock(&state.mutex);
            darling_screen_capture_close(stream);
        }

        if (state.gotFrame && state.bytes) {
            /* True per-window isolated content is unavailable through the
             * ScreenCast portal; we composite visible screen pixels for the
             * selected windows' bounds in back-to-front order. Occluded regions
             * therefore reflect what was visible on screen at capture time. */
            CFArrayRef desc = CGWindowListCreateDescriptionFromArray(windowArray);
            size_t canvasStride = ((width * 4 + 15u) & ~15u);
            uint8_t *canvas = calloc(canvasStride * height, 1);
            if (canvas) {
                if (shouldBeOpaque)
                    memset(canvas, 0xff, canvasStride * height);
                if (desc) {
                    for (CFIndex i = CFArrayGetCount(desc) - 1; i >= 0; i--) {
                        NSDictionary *d = (NSDictionary *) CFArrayGetValueAtIndex(desc, i);
                        CGRect r = darlingWindowBoundsFromDescription(d);
                        CGRect inter = CGRectIntersection(r, captureBounds);
                        if (CGRectIsEmpty(inter))
                            continue;
                        int x0 = (int) floor(inter.origin.x - captureBounds.origin.x);
                        int y0 = (int) floor(inter.origin.y - captureBounds.origin.y);
                        int x1 = (int) ceil(inter.origin.x + inter.size.width - captureBounds.origin.x);
                        int y1 = (int) ceil(inter.origin.y + inter.size.height - captureBounds.origin.y);
                        if (x0 < 0) x0 = 0; if (y0 < 0) y0 = 0;
                        if (x1 > (int) width) x1 = (int) width;
                        if (y1 > (int) height) y1 = (int) height;
                        for (int y = y0; y < y1; y++) {
                            uint8_t *dst = canvas + (size_t) y * canvasStride + (size_t) x0 * 4;
                            uint8_t *src = state.bytes + (size_t) y * state.stride + (size_t) x0 * 4;
                            memcpy(dst, src, (size_t) (x1 - x0) * 4);
                            if (shouldBeOpaque)
                                for (int x = x0; x < x1; x++) canvas[(size_t) y * canvasStride + (size_t) x * 4 + 3] = 0xff;
                        }
                    }
                    CFRelease(desc);
                }
                CFDataRef data = CFDataCreate(NULL, canvas, (CFIndex)(canvasStride * height));
                CGDataProviderRef provider = CGDataProviderCreateWithCFData(data);
                CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
                CGBitmapInfo info = shouldBeOpaque ? (kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst)
                    : (kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
                image = CGImageCreate(width, height, 8, 32, canvasStride, space, info, provider, NULL, false, kCGRenderingIntentDefault);
                CGColorSpaceRelease(space);
                CGDataProviderRelease(provider);
                CFRelease(data);
                free(canvas);
            }
        }
        free(state.bytes);
        pthread_cond_destroy(&state.cond);
        pthread_mutex_destroy(&state.mutex);
        if (image)
            return image;
        return NULL;
    }
#else
    if (CFArrayGetCount(windowArray) != 0)
        return NULL;
#endif

    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, space,
                                                 shouldBeOpaque ? kCGImageAlphaNoneSkipFirst : kCGImageAlphaPremultipliedFirst);
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
    // Prefer the pixels kept by a window of this process drawn with
    // -[CGSWindow drawImage:atPoint:]. The ScreenCast capture below is a
    // fallback for windows the process cannot read directly.
    if ((listOption & kCGWindowListOptionIncludingWindow) &&
        !(listOption & (kCGWindowListOptionOnScreenAboveWindow | kCGWindowListOptionOnScreenBelowWindow))) {
        CGSWindow *window = copyCGSWindowForNumber(windowID);
        if (window != nil) {
            CGImageRef image = [window copyContentsImage];
            [window release];
            if (image != NULL) {
                if (CGRectIsNull(screenBounds) || CGRectIsInfinite(screenBounds))
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
        }
    }

#if defined(HAVE_PIPEWIRE) && HAVE_PIPEWIRE
    {
        CFArrayRef windows = CGWindowListCreate(listOption, windowID);
        CGImageRef image = NULL;
        if (windows != NULL) {
            image = CGWindowListCreateImageFromArray(screenBounds, windows, imageOption);
            CFRelease(windows);
        }
        return image;
    }
#else
    return NULL;
#endif
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
