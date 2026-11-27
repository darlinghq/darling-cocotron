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

#import "CGDisplayGeometry.h"
#import "CGDisplayReconfiguration.h"
#import <CoreGraphics/CGSConnection.h>
#import <CoreGraphics/CGSPointerController.h>
#import <CoreGraphics/CGSScreen.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#import <CoreGraphics/CGDirectDisplay.h>
#import <CoreGraphics/CGError.h>
#import <IOKit/graphics/IOGraphicsLib.h>
#import <IOKit/graphics/IOGraphicsTypes.h>
#include <dlfcn.h>
#include <dispatch/dispatch.h>
#include <math.h>
#include <pthread.h>
#include <stdlib.h>
#include <sys/mman.h>
#if defined(HAVE_PIPEWIRE) && HAVE_PIPEWIRE
#include <screen_capture_backend.h>
#endif

// not sure what type or value this has
unsigned int kCGDisplayPixelHeight = 8200;
unsigned int kCGDisplayPixelWidth = 8200;

const CFStringRef kCGDisplayProductNameKey = CFSTR("kCGDisplayProductNameKey");
const CFStringRef kCGDisplayShowDuplicateLowResolutionModes = CFSTR("kCGDisplayShowDuplicateLowResolutionModes");

// The displays are the ones the window system connection of this process reports (see
// -[CGSConnection createScreens]); CoreGraphics knows nothing of the frameworks above it.
static CGSConnection *displayConnection(void) {
    CGSConnectionID connectionID = CGSMainConnectionID();
    return connectionID != 0 ? _CGSConnectionForID(connectionID) : nil;
}

// The active displays, the main display first, autoreleased. *connected says whether the
// process has a connection at all: a connection can report no display.
static NSArray<CGSScreen *> *activeScreens(BOOL *connected) {
    CGSConnection *connection = displayConnection();
    if (connected != NULL)
        *connected = connection != nil;
    return [[connection createScreens] autorelease];
}

static CGSScreen *screenForDisplayID(NSArray<CGSScreen *> *screens,
                                     CGDirectDisplayID displayID)
{
    for (CGSScreen *screen in screens) {
        if ([screen displayID] == displayID)
            return screen;
    }
    return nil;
}

// What owns the pointer in this process, when something has registered (see
// CGSPointerController.h).
static void *volatile gPointerController;

void _CGSSetPointerController(id<CGSPointerController> controller) {
    __atomic_store_n(&gPointerController, (void *) controller, __ATOMIC_RELEASE);
}

static id<CGSPointerController> pointerController(void) {
    return (id<CGSPointerController>) __atomic_load_n(&gPointerController, __ATOMIC_ACQUIRE);
}

CGDirectDisplayID CGMainDisplayID(void) {
    NSArray<CGSScreen *> *screens = activeScreens(NULL);

    return [screens count] > 0 ? [[screens objectAtIndex: 0] displayID]
                               : kCGNullDirectDisplay;
}

// Hands the display IDs found to the caller as the display list functions
// document: an array that is NULL (or has no room) is not written and the count
// is of all the displays; with an array the count is of the IDs written, at
// most maxDisplays. The count pointer is optional here.
static void deliverDisplayIDs(const CGDirectDisplayID *ids, uint32_t total,
                              uint32_t maxDisplays, CGDirectDisplayID *out,
                              uint32_t *count)
{
    BOOL wantsIDs = out != NULL && maxDisplays > 0;
    uint32_t written = wantsIDs ? MIN(total, maxDisplays) : total;

    for (uint32_t i = 0; wantsIDs && i < written; i++)
        out[i] = ids[i];
    if (count != NULL)
        *count = written;
}

// The online displays are the active ones: the backends list only outputs that show something.
static CGError listDisplays(uint32_t maxDisplays, CGDirectDisplayID *out, uint32_t *count) {
    BOOL connected;
    NSArray<CGSScreen *> *screens = activeScreens(&connected);
    if (!connected)
        return kCGErrorInvalidConnection;

    NSMutableData *storage = [NSMutableData
            dataWithLength: ([screens count] + 1) * sizeof(CGDirectDisplayID)];
    CGDirectDisplayID *ids = [storage mutableBytes];
    uint32_t total = 0;

    for (CGSScreen *screen in screens)
        ids[total++] = [screen displayID];

    deliverDisplayIDs(ids, total, maxDisplays, out, count);
    return kCGErrorSuccess;
}

CGError CGGetOnlineDisplayList(uint32_t maxDisplays,
                               CGDirectDisplayID *onlineDisplays,
                               uint32_t *displayCount)
{
    return listDisplays(maxDisplays, onlineDisplays, displayCount);
}

size_t CGDisplayPixelsHigh(CGDirectDisplayID displayIndex) {
    return (size_t) CGDisplayBounds(displayIndex).size.height;
}

size_t CGDisplayPixelsWide(CGDirectDisplayID displayIndex) {
    return (size_t) CGDisplayBounds(displayIndex).size.width;
}

CGError CGGetActiveDisplayList(uint32_t maxDisplays,
                               CGDirectDisplayID *activeDisplays,
                               uint32_t *displayCount)
{
    return listDisplays(maxDisplays, activeDisplays, displayCount);
}

CGError CGGetDisplaysWithOpenGLDisplayMask(CGOpenGLDisplayMask mask,
                                           uint32_t maxDisplays,
                                           CGDirectDisplayID *displays,
                                           uint32_t *matchingDisplayCount)
{
    return CGGetOnlineDisplayList(maxDisplays, displays, matchingDisplayCount);
}

// An OpenGL display mask has one bit per online display, the main display
// (first in the online list) being bit 0.
CGOpenGLDisplayMask CGDisplayIDToOpenGLDisplayMask(CGDirectDisplayID display) {
    CGDirectDisplayID online[32];
    uint32_t count = 0;
    if (display == kCGNullDirectDisplay ||
        CGGetOnlineDisplayList(32, online, &count) != kCGErrorSuccess)
        return 0;
    for (uint32_t i = 0; i < count && i < 32; i++) {
        if (online[i] == display)
            return (CGOpenGLDisplayMask) 1 << i;
    }
    return 0;
}

CGDirectDisplayID CGOpenGLDisplayMaskToDisplayID(CGOpenGLDisplayMask mask) {
    CGDirectDisplayID online[32];
    uint32_t count = 0;
    if (mask == 0 || CGGetOnlineDisplayList(32, online, &count) != kCGErrorSuccess)
        return kCGNullDirectDisplay;
    for (uint32_t i = 0; i < count && i < 32; i++) {
        if (mask & ((CGOpenGLDisplayMask) 1 << i))
            return online[i];
    }
    return kCGNullDirectDisplay;
}

// The displays a point or a rectangle falls on. As documented, the array may
// be NULL (or of no room): the count is then of all the displays that match;
// with an array it is of the IDs written, at most maxDisplays.
static CGError displaysMatching(CGPoint point, CGRect rect, BOOL isPoint,
                                uint32_t maxDisplays, CGDirectDisplayID *displays,
                                uint32_t *matchingDisplayCount)
{
    BOOL connected;
    NSArray<CGSScreen *> *screens = activeScreens(&connected);
    if (!connected)
        return kCGErrorInvalidConnection;

    NSMutableData *storage = [NSMutableData
            dataWithLength: ([screens count] + 1) * sizeof(CGDirectDisplayID)];
    CGDirectDisplayID *ids = [storage mutableBytes];
    uint32_t total = 0;

    for (CGSScreen *screen in screens) {
        CGRect screenRect = [screen bounds];
        BOOL hit = isPoint ? CGRectContainsPoint(screenRect, point)
                           : CGRectIntersectsRect(rect, screenRect);
        if (hit)
            ids[total++] = [screen displayID];
    }

    deliverDisplayIDs(ids, total, maxDisplays, displays, matchingDisplayCount);
    return kCGErrorSuccess;
}

CGError CGGetDisplaysWithPoint(CGPoint point, uint32_t maxDisplays,
                               CGDirectDisplayID *displays,
                               uint32_t *matchingDisplayCount)
{
    return displaysMatching(point, CGRectZero, YES, maxDisplays, displays,
                            matchingDisplayCount);
}

CGError CGGetDisplaysWithRect(CGRect rect, uint32_t maxDisplays,
                              CGDirectDisplayID *displays,
                              uint32_t *matchingDisplayCount)
{
    return displaysMatching(CGPointZero, rect, NO, maxDisplays, displays,
                            matchingDisplayCount);
}

CGRect CGDisplayBounds(CGDirectDisplayID displayIndex) {
    CGSScreen *screen = screenForDisplayID(activeScreens(NULL), displayIndex);

    return screen != nil ? [screen bounds] : CGRectZero;
}

// The pointer's state is kept by the window system connection where the backend decodes the pointer itself
// (X11); otherwise by what owns the pointer in this process (see CGSPointerController.h). A process with
// neither has no cursor of its own to hide.
static CGSConnection *pointerConnection(void) {
    CGSConnection *connection = displayConnection();

    return [connection managesPointer] ? connection : nil;
}

// Hides the cursor once more; each call is undone by one CGDisplayShowCursor(). The count is the
// process', not the display's.
CGError CGDisplayHideCursor(CGDirectDisplayID displayIndex) {
    CGSConnection *connection = pointerConnection();

    if (connection != nil)
        [connection hideCursor];
    else
        [pointerController() hideCursor];
    return kCGErrorSuccess;
}

CGError CGDisplayShowCursor(CGDirectDisplayID displayIndex) {
    CGSConnection *connection = pointerConnection();

    if (connection != nil)
        [connection unhideCursor];
    else
        [pointerController() unhideCursor];
    return kCGErrorSuccess;
}

// Whether the cursor is visible: no hide is pending. A process with no pointer of its own has nothing hiding it.
boolean_t CGCursorIsVisible(void) {
    CGSConnection *connection = pointerConnection();

    if (connection != nil)
        return [connection cursorIsVisible];
    id<CGSPointerController> controller = pointerController();
    if ([controller respondsToSelector: @selector(cursorIsVisible)])
        return [controller cursorIsVisible];
    return true;
}

// Callers pass the connection id and nothing else, and do not use a result;
// the function returns nothing on macOS. Seen in use around
// CGDisplayHideCursor()/CGDisplayShowCursor() pairs, which fits "show the
// cursor whatever the hide count was". The effect itself is not observable
// from outside; this is the minimal reading of the name.
// Test: coregraphics-cgs-force-show-cursor.m.
void CGSForceShowCursor(CGSConnectionID cid) {
    CGSConnection *connection = pointerConnection();

    if (connection != nil)
        [connection forceShowCursor];
    else
        [pointerController() forceShowCursor];
}

// The image of a cursor the window server has registered under a name (for
// example the one currently shown, "com.apple.coregraphics.GlobalCurrent"), with
// its hot spot in outHotspot. A name that is not registered gives NULL and leaves
// the hot spot alone, and so does any name here: the backends do not tell what
// cursor the window system shows and cannot read its image, in line with
// CGDisplayCreateImageForRect(), which has no pixels to return either. Callers
// that draw a cursor onto a capture skip it when they get NULL.
// Seen: the call takes the connection id, the name and an optional hot spot
// pointer, and returns a new CGImage that the caller releases.
// Test: coregraphics-registered-cursor-image.c.
CGImageRef CGSCreateRegisteredCursorImage(CGSConnectionID cid, const char *cursorName, CGPoint *outHotspot) {
    return NULL;
}

boolean_t CGDisplayIsInMirrorSet(CGDirectDisplayID display) {
    return CGDisplayMirrorsDisplay(display) != kCGNullDirectDisplay;
}

Boolean CGDisplayIsMain(CGDirectDisplayID display) {
    return display != kCGNullDirectDisplay && display == CGMainDisplayID();
}

uint32_t CGDisplayUnitNumber(CGDirectDisplayID display) {
    return (display > 0) ? (display - 1) : 0;
}

boolean_t CGDisplayUsesOpenGLAcceleration(CGDirectDisplayID display) {
    return TRUE;
}

CGDirectDisplayID CGDisplayMirrorsDisplay(CGDirectDisplayID display) {
    // STUB!
    // TODO: Get this from XRandR
    return kCGNullDirectDisplay;
}

// NULL for a display that does not exist, as on macOS 10.14.4 and 26.7.3 (observed through the public API;
// tests/coregraphics-displays-without-appkit.m).
CGDisplayModeRef CGDisplayCopyDisplayMode(CGDirectDisplayID displayId) {
    CGSScreen *screen = screenForDisplayID(activeScreens(NULL), displayId);

    return (CGDisplayModeRef) [[screen currentModeDictionary] retain];
}

void CGDisplayModeRelease(CGDisplayModeRef mode) {
    if (mode != NULL)
        CFRelease(mode);
}

CGDisplayModeRef CGDisplayModeRetain(CGDisplayModeRef mode) {
    if (mode)
        CFRetain(mode);
    return mode;
}

size_t CGDisplayModeGetHeight(CGDisplayModeRef mode) {
    NSDictionary *dict = (NSDictionary *) mode;
    return [[dict valueForKey: @"Height"] unsignedIntValue];
}

size_t CGDisplayModeGetWidth(CGDisplayModeRef mode) {
    NSDictionary *dict = (NSDictionary *) mode;
    return [[dict valueForKey: @"Width"] unsignedIntValue];
}

double CGDisplayModeGetRefreshRate(CGDisplayModeRef mode) {
    NSDictionary *dict = (NSDictionary *) mode;
    return [[dict valueForKey: @"RefreshRate"] doubleValue];
}

CFStringRef CGDisplayModeCopyPixelEncoding(CGDisplayModeRef mode) {
    NSDictionary *dict = (NSDictionary *) mode;
    unsigned depth = [[dict valueForKey: @"Depth"] unsignedIntValue];

    switch (depth) {
    case 24:
    case 32:
        return CFSTR(IO32BitDirectPixels);
    case 16:
        return CFSTR(IO16BitDirectPixels);
    default:
        return CFSTR("");
    }
}

const CFStringRef kCGSDisplayColorPrimariesKey = CFSTR("Primaries");
const CFStringRef kCGSDisplayColorTransferFunctionKey = CFSTR("TransferFunction");
const CFStringRef kCGSDisplayColorMinLuminanceKey = CFSTR("MinLuminance");
const CFStringRef kCGSDisplayColorMaxLuminanceKey = CFSTR("MaxLuminance");
const CFStringRef kCGSDisplayColorReferenceLuminanceKey = CFSTR("ReferenceLuminance");
const CFStringRef kCGSDisplayColorTargetMinLuminanceKey = CFSTR("TargetMinLuminance");
const CFStringRef kCGSDisplayColorTargetMaxLuminanceKey = CFSTR("TargetMaxLuminance");
const CFStringRef kCGSDisplayColorICCProfileKey = CFSTR("ICCProfile");
const CFStringRef kCGSDisplayColorPrimariesChromaticityKey = CFSTR("PrimariesChromaticity");
const CFStringRef kCGSDisplayColorTargetPrimariesChromaticityKey = CFSTR("TargetPrimariesChromaticity");
const CFStringRef kCGSDisplayColorTransferFunctionPowerKey = CFSTR("TransferFunctionPower");
const CFStringRef kCGSDisplayColorTargetMaxCLLKey = CFSTR("TargetMaxCLL");
const CFStringRef kCGSDisplayColorTargetMaxFALLKey = CFSTR("TargetMaxFALL");

CFArrayRef CGDisplayCopyAllDisplayModes(CGDirectDisplayID displayIndex,
                                        CFDictionaryRef options)
{
    CGSScreen *screen = screenForDisplayID(activeScreens(NULL), displayIndex);

    return (CFArrayRef) [[screen modes] retain];
}

double _CGSDisplayBackingScaleFactor(CGDirectDisplayID display) {
    CGSScreen *screen = screenForDisplayID(activeScreens(NULL), display);
    CGFloat scale = [screen backingScale];

    return scale >= 1 ? scale : 1;
}

bool _CGSDisplayNativeFrame(CGDirectDisplayID display, CGRect *frame) {
    CGSScreen *screen = screenForDisplayID(activeScreens(NULL), display);

    if (screen == nil || ![screen hasNativeFrame] || frame == NULL)
        return false;
    *frame = [screen nativeFrame];
    return true;
}

CFDataRef _CGSDisplayCopyEDID(CGDirectDisplayID display) {
    CGSScreen *screen = screenForDisplayID(activeScreens(NULL), display);

    return (CFDataRef) [[screen edid] retain];
}

CFStringRef _CGSDisplayCopyOutputName(CGDirectDisplayID display) {
    CGSScreen *screen = screenForDisplayID(activeScreens(NULL), display);

    return (CFStringRef) [[screen name] retain];
}

CFDictionaryRef _CGSDisplayCopyColorInfo(CGDirectDisplayID display) {
    CGSScreen *screen = screenForDisplayID(activeScreens(NULL), display);

    return (CFDictionaryRef) [[screen colorInfo] retain];
}

static NSData *edidForDisplay(CGDirectDisplayID displayId) {
    CGSScreen *screen = screenForDisplayID(activeScreens(NULL), displayId);
    if (!screen)
        return nil;

    NSData *edid = [screen edid];
    if (edid && [edid length] >= 16)
        return edid;

    return nil;
}

// EDID 1.x, first 18-byte descriptor at offset 54. Returns the image size in mm
// from it when it is a detailed timing descriptor (non-zero pixel clock), else
// from the basic display parameters (maximum image size in cm). false when
// neither holds a size. Kept free of Objective-C so tests can compile it alone.
static bool screenSizeFromEDID(const uint8_t *bytes, size_t length,
                               double *widthMM, double *heightMM)
{
    if (length < 128)
        return false;

    double width = 0, height = 0;
    /* A display descriptor (pixel clock 0) holds text or range limits, not a size. */
    if (bytes[54] != 0 || bytes[55] != 0) {
        width = bytes[66] | ((bytes[68] & 0xf0) << 4);
        height = bytes[67] | ((bytes[68] & 0x0f) << 8);
    }
    /* DTV timings may encode only an aspect ratio in these fields. */
    bool aspectRatioOnly = (width == 16 && height == 9) ||
                           (width == 4 && height == 3);
    if (width <= 0 || height <= 0 || aspectRatioOnly) {
        width = bytes[21] * 10.0;
        height = bytes[22] * 10.0;
    }
    if (width <= 0 || height <= 0)
        return false;
    *widthMM = width;
    *heightMM = height;
    return true;
}

CGSize CGDisplayScreenSize(CGDirectDisplayID display) {
    /* Zero for an invalid display, as documented. Callers that divide by this
     * size must handle 0; an unknown id is not silently answered for the main
     * display. */
    CGSize pixels = CGDisplayBounds(display).size;
    if (pixels.width <= 0 || pixels.height <= 0)
        return CGSizeZero;

    NSData *edid = edidForDisplay(display);
    double width, height;
    if (edid && screenSizeFromEDID([edid bytes], [edid length], &width, &height))
        return (CGSize){.width = width, .height = height};

    /* No usable EDID size: estimate from the bounds at 72 dpi (2.835 pixels/mm),
     * as documented for CGDisplayScreenSize. */
    return (CGSize){.width = pixels.width * 25.4 / 72, .height = pixels.height * 25.4 / 72};
}

uint32_t CGDisplaySerialNumber(CGDirectDisplayID displayId) {
    NSData *edid = edidForDisplay(displayId);
    if (!edid)
        return displayId;

    return CFSwapInt32LittleToHost(*(uint32_t *) (&[edid bytes][12]));
}

uint32_t CGDisplayModelNumber(CGDirectDisplayID displayId) {
    NSData *edid = edidForDisplay(displayId);
    if (!edid)
        return kDisplayProductIDGeneric;

    return CFSwapInt16LittleToHost(*(uint16_t *) (&[edid bytes][10]));
}

uint32_t CGDisplayVendorNumber(CGDirectDisplayID displayId) {
    NSData *edid = edidForDisplay(displayId);
    if (!edid)
        return kDisplayVendorIDUnknown;

    return CFSwapInt16BigToHost(*(uint16_t *) (&[edid bytes][8]));
}

io_service_t CGDisplayIOServicePort(CGDirectDisplayID displayID) {
    // The code in this function is:
    // Copyright (c) 2002-2006 Marcus Geelnard
    // Copyright (c) 2006-2010 Camilla Berglund <elmindreda@elmindreda.org>
    // Taken from
    // https://github.com/glfw/glfw/blob/e0a6772e5e4c672179fc69a90bcda3369792ed1f/src/cocoa_monitor.m

    io_iterator_t iter;
    io_service_t serv, servicePort = 0;

    CFMutableDictionaryRef matching = IOServiceMatching("IODisplayConnect");

    // releases matching for us
    kern_return_t err =
            IOServiceGetMatchingServices(kIOMasterPortDefault, matching, &iter);
    if (err)
        return 0;

    while ((serv = IOIteratorNext(iter)) != 0) {
        CFDictionaryRef info;
        CFIndex vendorID, productID, serialNumber;
        CFNumberRef vendorIDRef, productIDRef, serialNumberRef;
        Boolean success;

        info = IODisplayCreateInfoDictionary(serv, kIODisplayOnlyPreferredName);

        vendorIDRef = CFDictionaryGetValue(info, CFSTR(kDisplayVendorID));
        productIDRef = CFDictionaryGetValue(info, CFSTR(kDisplayProductID));
        serialNumberRef =
                CFDictionaryGetValue(info, CFSTR(kDisplaySerialNumber));

        if (!vendorIDRef || !productIDRef || !serialNumberRef) {
            CFRelease(info);
            continue;
        }

        success =
                CFNumberGetValue(vendorIDRef, kCFNumberCFIndexType, &vendorID);
        success &= CFNumberGetValue(productIDRef, kCFNumberCFIndexType,
                                    &productID);
        success &= CFNumberGetValue(serialNumberRef, kCFNumberCFIndexType,
                                    &serialNumber);

        if (!success) {
            CFRelease(info);
            continue;
        }

        // If the vendor and product id along with the serial don't match
        // then we are not looking at the correct monitor.
        // NOTE: The serial number is important in cases where two monitors
        //       are the exact same.
        if (CGDisplayVendorNumber(displayID) != vendorID ||
            CGDisplayModelNumber(displayID) != productID ||
            CGDisplaySerialNumber(displayID) != serialNumber) {
            CFRelease(info);
            continue;
        }

        // The VendorID, Product ID, and the Serial Number all Match Up!
        // Therefore we have found the appropriate display io_service
        servicePort = serv;
        CFRelease(info);
        break;
    }

    IOObjectRelease(iter);
    return servicePort;
}

// The union of the active displays in CoreGraphics' global space.
static CGDisplayGeometryRect desktopBounds(NSArray<CGSScreen *> *screens) {
    CGDisplayGeometryRect desktop = {0, 0, 0, 0};
    for (CGSScreen *screen in screens) {
        CGRect rect = [screen bounds];
        if (CGRectIsEmpty(rect))
            continue;
        desktop = CGDisplayGeometryUnion(
                desktop, (CGDisplayGeometryRect){rect.origin.x, rect.origin.y,
                                                 rect.size.width, rect.size.height});
    }
    return desktop;
}

// QUIRK: a coordinate that is not a finite number (NaN, +infinity, -infinity) is taken as 0, on its own axis, and the
// warp succeeds: the cursor goes to 0 on that axis (and where it was asked to on the other one), it is not clamped to
// the far edge for +infinity and no error is returned. Not documented. Evidence (tier 2, black-box): the return code
// and the cursor position CGEventCreate(NULL) reports after CGWarpMouseCursorPosition and CGDisplayMoveCursorToPoint
// with NaN, +infinity and -infinity as x, y or both on macOS 26.7.3 and 10.14.4 (x86_64, main display at the origin):
// success every time, the position 0 on every non-finite axis. Probe: vd-upstream/mac-probes/937-b2c-warp-nonfinite.c.
// Test: coregraphics-warp-mouse-glue (non-finite coordinates).
static CGPoint warpTargetWithFiniteCoordinates(CGPoint point) {
    if (!isfinite(point.x))
        point.x = 0;
    if (!isfinite(point.y))
        point.y = 0;
    return point;
}

// The one place CoreGraphics' global point meets the window system's: clip it to the
// desktop and hand it on, in the same global space (the space CGEventGetLocation()
// reports). The rules are written down in CGDisplayGeometry.h.
static CGError warpToGlobalPoint(CGPoint point) {
    point = warpTargetWithFiniteCoordinates(point);

    BOOL connected;
    NSArray<CGSScreen *> *screens = activeScreens(&connected);
    if (!connected)
        return kCGErrorInvalidConnection;
    // No active output: the point has no desktop to land in.
    if ([screens count] == 0)
        return kCGErrorCannotComplete;

    CGFloat scale = [[screens objectAtIndex: 0] backingScale];
    if (!(scale >= 1))
        scale = 1;

    CGDisplayGeometryPoint clipped = CGDisplayGeometryClamp(
            desktopBounds(screens), scale,
            (CGDisplayGeometryPoint){point.x, point.y});
    CGPoint target = CGPointMake(clipped.x, clipped.y);

    // The connection moves the pointer when it keeps the pointer's state itself; otherwise what owns the
    // pointer state (the relative-mouse grab among it) is asked first, until this framework owns the
    // connection that has the windows on every backend.
    id<CGSPointerController> controller = [displayConnection() managesPointer] ? nil : pointerController();
    if (controller != nil) {
        [controller warpPointerToPoint: target];
        return kCGErrorSuccess;
    }
    return [displayConnection() warpPointerToPoint: target];
}

CGError CGWarpMouseCursorPosition(CGPoint newCursorPosition) {
    return warpToGlobalPoint(newCursorPosition);
}

CGError CGDisplayMoveCursorToPoint(CGDirectDisplayID displayID, CGPoint newCursorPosition) {
    // The point is relative to the upper-left corner of that display.
    CGSScreen *screen = screenForDisplayID(activeScreens(NULL), displayID);
    if (!screen || CGRectIsEmpty([screen bounds]))
        return kCGErrorIllegalArgument;

    CGRect bounds = [screen bounds];
    CGDisplayGeometryPoint global = CGDisplayGeometryDisplayToGlobal(
            (CGDisplayGeometryRect){bounds.origin.x, bounds.origin.y,
                                    bounds.size.width, bounds.size.height},
            (CGDisplayGeometryPoint){newCursorPosition.x, newCursorPosition.y});
    return warpToGlobalPoint(CGPointMake(global.x, global.y));
}

// The mouse motion reported since the previous call, in screen pixels. The deltas come
// from the input the window system delivers to the windows, so without a pointer
// controller there are none.
void CGGetLastMouseDelta(int32_t *deltaX, int32_t *deltaY) {
    int32_t dx = 0, dy = 0;
    CGSConnection *connection = pointerConnection();

    if (connection != nil)
        [connection takeMouseDeltaX: &dx y: &dy];
    else
        [pointerController() takeMouseDeltaX: &dx y: &dy];
    if (deltaX)
        *deltaX = dx;
    if (deltaY)
        *deltaY = dy;
}

CGError CGAssociateMouseAndMouseCursorPosition(boolean_t connected) {
    // Disconnecting the mouse from the cursor: the cursor stays put and the mouse only
    // produces deltas.
    CGSConnection *connection = pointerConnection();

    if (connection != nil)
        [connection setMouseAssociatedWithCursor: connected != 0];
    else
        [pointerController() setMouseAssociatedWithCursor: connected != 0];
    return kCGErrorSuccess;
}

#pragma mark - Legacy display modes (CFDictionary based)

// The legacy mode dictionaries are the backend's mode (Width, Height in
// points; Depth; RefreshRate; PixelWidth/PixelHeight) with the keys the
// legacy API documents added: BitsPerPixel (a 24-bit visual is a 32-bit pixel
// format), BitsPerSample, SamplesPerPixel, the framebuffer's pixel size and
// row size, the refresh rate (0 when the display reports none, as for flat
// panels) and the mode's index in the list CGDisplayAvailableModes returns.
static NSDictionary *legacyModeDictionary(NSDictionary *mode, NSUInteger index) {
    NSNumber *depthNumber = [mode objectForKey: @"Depth"];
    unsigned depth = depthNumber ? [depthNumber unsignedIntValue] : 24;
    unsigned bitsPerPixel = (depth == 24) ? 32 : depth;
    unsigned bitsPerSample = (bitsPerPixel >= 24) ? 8 : (bitsPerPixel == 16 ? 5 : bitsPerPixel);
    unsigned samplesPerPixel = (bitsPerPixel > 8) ? 3 : 1;
    unsigned width = [[mode objectForKey: @"Width"] unsignedIntValue];
    unsigned height = [[mode objectForKey: @"Height"] unsignedIntValue];
    NSNumber *pixelWidth = [mode objectForKey: @"PixelWidth"];
    NSNumber *pixelHeight = [mode objectForKey: @"PixelHeight"];
    unsigned pw = pixelWidth ? [pixelWidth unsignedIntValue] : width;
    unsigned ph = pixelHeight ? [pixelHeight unsignedIntValue] : height;

    NSMutableDictionary *legacy = [NSMutableDictionary dictionaryWithDictionary: mode];
    [legacy setObject: @(bitsPerPixel) forKey: (NSString *) kCGDisplayBitsPerPixel];
    [legacy setObject: @(bitsPerSample) forKey: (NSString *) kCGDisplayBitsPerSample];
    [legacy setObject: @(samplesPerPixel) forKey: (NSString *) kCGDisplaySamplesPerPixel];
    [legacy setObject: @(pw * bitsPerPixel / 8) forKey: (NSString *) kCGDisplayBytesPerRow];
    [legacy setObject: @(pw) forKey: @"kCGDisplayPixelsWide"];
    [legacy setObject: @(ph) forKey: @"kCGDisplayPixelsHigh"];
    [legacy setObject: @((unsigned) index) forKey: (NSString *) kCGDisplayMode];
    if ([legacy objectForKey: @"RefreshRate"] == nil)
        [legacy setObject: @0.0 forKey: (NSString *) kCGDisplayRefreshRate];
    return legacy;
}

// The display's modes, or its current mode alone when the backend lists none.
// nil for a display that does not exist.
static NSArray *backendModesForDisplay(CGDirectDisplayID displayID, NSUInteger *currentIndex) {
    if (displayID == kCGNullDirectDisplay)
        return nil;
    CGSScreen *screen = screenForDisplayID(activeScreens(NULL), displayID);
    if (!screen)
        return nil;

    NSArray *modes = [screen modes];
    NSDictionary *current = [screen currentModeDictionary];
    if ([modes count] == 0)
        modes = [current count] > 0 ? @[ current ] : nil;

    if (currentIndex) {
        *currentIndex = [screen currentMode] >= 0 && (NSUInteger) [screen currentMode] < [modes count]
                                ? (NSUInteger) [screen currentMode] : 0;
    }
    return modes;
}

static NSDictionary *legacyCurrentMode(CGDirectDisplayID displayID) {
    NSUInteger index = 0;
    NSArray *modes = backendModesForDisplay(displayID, &index);
    if ([modes count] == 0)
        return nil;
    return legacyModeDictionary([modes objectAtIndex: index], index);
}

// Dictionaries with the keys the legacy API documents; see legacyModeDictionary.
CFArrayRef CGDisplayAvailableModes(CGDirectDisplayID displayIndex) {
    NSArray *modes = backendModesForDisplay(displayIndex, NULL);
    if (!modes)
        return NULL;
    NSMutableArray *legacy = [NSMutableArray arrayWithCapacity: [modes count]];
    for (NSUInteger i = 0; i < [modes count]; i++)
        [legacy addObject: legacyModeDictionary([modes objectAtIndex: i], i)];
    return (CFArrayRef) legacy;
}

CFDictionaryRef CGDisplayCurrentMode(CGDirectDisplayID display) {
    return (CFDictionaryRef) legacyCurrentMode(display);
}

static size_t legacyModeNumber(CGDirectDisplayID display, CFStringRef key) {
    return [[legacyCurrentMode(display) objectForKey: (NSString *) key] unsignedLongValue];
}

size_t CGDisplayBitsPerPixel(CGDirectDisplayID display) {
    return legacyModeNumber(display, kCGDisplayBitsPerPixel);
}

size_t CGDisplayBitsPerSample(CGDirectDisplayID display) {
    return legacyModeNumber(display, kCGDisplayBitsPerSample);
}

size_t CGDisplaySamplesPerPixel(CGDirectDisplayID display) {
    return legacyModeNumber(display, kCGDisplaySamplesPerPixel);
}

size_t CGDisplayBytesPerRow(CGDirectDisplayID display) {
    return legacyModeNumber(display, kCGDisplayBytesPerRow);
}

// Closest mode to the request. A mode of the requested pixel depth is
// preferred, then the next deeper one, then the deepest shallower one; within
// that depth, the smallest mode that is at least as wide and as high as
// requested, or else the largest mode; among those of the chosen size, the one
// whose refresh rate is nearest the requested one (a rate of 0 on either side
// means unspecified). exactMatch is set when the depth and the size equal the
// request and the refresh rate matches.
CFDictionaryRef CGDisplayBestModeForParametersAndRefreshRate(
        CGDirectDisplayID display, size_t bitsPerPixel, size_t width,
        size_t height, CGRefreshRate refreshRate, boolean_t *exactMatch)
{
    NSArray *modes = backendModesForDisplay(display, NULL);
    if ([modes count] == 0)
        return NULL;

    NSMutableArray *legacy = [NSMutableArray arrayWithCapacity: [modes count]];
    for (NSUInteger i = 0; i < [modes count]; i++)
        [legacy addObject: legacyModeDictionary([modes objectAtIndex: i], i)];

    // Depth class.
    size_t chosenDepth = 0;
    BOOL haveDepth = NO;
    for (NSDictionary *mode in legacy) {
        size_t depth = [[mode objectForKey: (NSString *) kCGDisplayBitsPerPixel] unsignedLongValue];
        if (depth == bitsPerPixel) {
            chosenDepth = depth;
            haveDepth = YES;
            break;
        }
    }
    if (!haveDepth) {
        for (NSDictionary *mode in legacy) {
            size_t depth = [[mode objectForKey: (NSString *) kCGDisplayBitsPerPixel] unsignedLongValue];
            if (depth > bitsPerPixel && (!haveDepth || depth < chosenDepth)) {
                chosenDepth = depth;
                haveDepth = YES;
            }
        }
    }
    if (!haveDepth) {
        for (NSDictionary *mode in legacy) {
            size_t depth = [[mode objectForKey: (NSString *) kCGDisplayBitsPerPixel] unsignedLongValue];
            if (!haveDepth || depth > chosenDepth) {
                chosenDepth = depth;
                haveDepth = YES;
            }
        }
    }

    NSDictionary *best = nil;
    double bestScore = 0;
    for (NSDictionary *mode in legacy) {
        size_t depth = [[mode objectForKey: (NSString *) kCGDisplayBitsPerPixel] unsignedLongValue];
        if (depth != chosenDepth)
            continue;
        double w = [[mode objectForKey: (NSString *) kCGDisplayWidth] doubleValue];
        double h = [[mode objectForKey: (NSString *) kCGDisplayHeight] doubleValue];
        double rate = [[mode objectForKey: (NSString *) kCGDisplayRefreshRate] doubleValue];
        BOOL covers = w >= width && h >= height;
        // Lower scores are better: covering modes by their excess area, the
        // others (all modes are smaller) by their shortfall, after every covering mode.
        double score = covers ? (w * h - (double) width * height)
                              : 1e18 + ((double) width * height - w * h);
        if (refreshRate > 0 && rate > 0)
            score += fabs(rate - refreshRate) / 1000.0;
        if (!best || score < bestScore) {
            best = mode;
            bestScore = score;
        }
    }

    if (exactMatch) {
        double w = [[best objectForKey: (NSString *) kCGDisplayWidth] doubleValue];
        double h = [[best objectForKey: (NSString *) kCGDisplayHeight] doubleValue];
        double rate = [[best objectForKey: (NSString *) kCGDisplayRefreshRate] doubleValue];
        BOOL rateMatches = refreshRate <= 0 || rate <= 0 || round(rate) == round(refreshRate);
        *exactMatch = (chosenDepth == bitsPerPixel && w == width && h == height && rateMatches);
    }
    return (CFDictionaryRef) best;
}

CFDictionaryRef CGDisplayBestModeForParameters(CGDirectDisplayID display,
                                               size_t bitsPerPixel,
                                               size_t width, size_t height,
                                               boolean_t *exactMatch)
{
    return CGDisplayBestModeForParametersAndRefreshRate(display, bitsPerPixel,
                                                        width, height, 0,
                                                        exactMatch);
}

#pragma mark - Mode switching, capture and release

// A backend mode is identified by its size in device pixels (the point size
// when the backend reports none) and its refresh rate.
static BOOL sameBackendMode(NSDictionary *a, NSDictionary *b) {
    NSNumber *aw = [a objectForKey: @"PixelWidth"] ?: [a objectForKey: @"Width"];
    NSNumber *ah = [a objectForKey: @"PixelHeight"] ?: [a objectForKey: @"Height"];
    NSNumber *bw = [b objectForKey: @"PixelWidth"] ?: [b objectForKey: @"Width"];
    NSNumber *bh = [b objectForKey: @"PixelHeight"] ?: [b objectForKey: @"Height"];
    if (![aw isEqual: bw] || ![ah isEqual: bh])
        return NO;
    double ar = [[a objectForKey: @"RefreshRate"] doubleValue];
    double br = [[b objectForKey: @"RefreshRate"] doubleValue];
    return fabs(ar - br) < 0.01;
}

// The display's mode list entry a mode (a legacy dictionary or a
// CGDisplayModeRef) stands for, or NSNotFound. A legacy dictionary carries the
// index it had in CGDisplayAvailableModes; otherwise the size selects the
// mode (all the size keys the dictionary has must agree), and among modes of
// that size the nearest refresh rate does.
static NSUInteger indexOfMode(NSArray *modes, NSDictionary *wanted) {
    NSNumber *wantedIndex = [wanted objectForKey: (NSString *) kCGDisplayMode];
    if (wantedIndex && [wantedIndex unsignedIntegerValue] < [modes count]) {
        // The index names a mode only while the dictionary still describes it.
        NSDictionary *listed = [modes objectAtIndex: [wantedIndex unsignedIntegerValue]];
        NSNumber *width = [wanted objectForKey: @"Width"], *height = [wanted objectForKey: @"Height"];
        if ((width == nil || [width isEqual: [listed objectForKey: @"Width"]]) &&
            (height == nil || [height isEqual: [listed objectForKey: @"Height"]]))
            return [wantedIndex unsignedIntegerValue];
    }
    NSUInteger found = NSNotFound;
    double foundDistance = 0;
    double wantedRate = [[wanted objectForKey: @"RefreshRate"] doubleValue];
    // Every size key the dictionary carries has to match, so a dictionary
    // edited in any one of them names no listed mode.
    NSArray *sizeKeys = @[ @"Width", @"Height", @"PixelWidth", @"PixelHeight" ];
    for (NSUInteger i = 0; i < [modes count]; i++) {
        NSDictionary *candidate = [modes objectAtIndex: i];
        BOOL sameSize = YES;
        for (NSString *key in sizeKeys) {
            NSNumber *value = [wanted objectForKey: key], *listed = [candidate objectForKey: key];
            // A backend that reports no pixel size lists none to compare.
            if (value && listed && ![value isEqual: listed])
                sameSize = NO;
        }
        if (!sameSize)
            continue;
        double distance = fabs([[candidate objectForKey: @"RefreshRate"] doubleValue] - wantedRate);
        if (found == NSNotFound || distance < foundDistance) {
            found = i;
            foundDistance = distance;
        }
    }
    return found;
}

// Per display: whether the process captured it, and the mode it had before
// the first switch since it was last restored.
static NSMutableDictionary *gDisplayState;
static NSObject *gDisplayStateLock;
static dispatch_once_t gDisplayStateOnce;

static void restoreAllDisplayModes(void);

static void initDisplayState(void) {
    dispatch_once(&gDisplayStateOnce, ^{
        gDisplayState = [[NSMutableDictionary alloc] init];
        gDisplayStateLock = [[NSObject alloc] init];
        // The modes this process changed go back when it exits.
        atexit(restoreAllDisplayModes);
    });
}

static NSMutableDictionary *stateForDisplay(CGDirectDisplayID display) {
    NSNumber *key = @(display);
    NSMutableDictionary *state = [gDisplayState objectForKey: key];
    if (!state) {
        state = [NSMutableDictionary dictionary];
        [gDisplayState setObject: state forKey: key];
    }
    return state;
}

// Asks the backend for the mode, reporting the change to the registered
// reconfiguration callbacks. When remember is set, the mode the display had
// is kept so that a release restores it.
static CGError changeBackendMode(CGDirectDisplayID displayID, NSDictionary *mode, BOOL remember) {
    CGSConnection *connection = displayConnection();
    if (!connection)
        return kCGErrorInvalidConnection;
    NSDictionary *before = [screenForDisplayID(activeScreens(NULL), displayID) currentModeDictionary];
    if (sameBackendMode(before, mode))
        return kCGErrorSuccess;

    initDisplayState();
    CGDisplayPostReconfiguration(displayID, kCGDisplayBeginConfigurationFlag);
    BOOL changed = [connection changeMode: mode forScreen: displayID - 1];
    CGDisplayChangeSummaryFlags flags = 0;
    if (changed) {
        flags = kCGDisplaySetModeFlag;
        NSDictionary *after = [screenForDisplayID(activeScreens(NULL), displayID) currentModeDictionary];
        for (NSString *key in @[ @"Width", @"Height", @"PixelWidth", @"PixelHeight" ]) {
            if (![[before objectForKey: key] isEqual: [after objectForKey: key]])
                flags |= kCGDisplayDesktopShapeChangedFlag;
        }
        if (remember) {
            @synchronized(gDisplayStateLock) {
                NSMutableDictionary *state = stateForDisplay(displayID);
                if (![state objectForKey: @"original"])
                    [state setObject: before forKey: @"original"];
            }
        }
    }
    CGDisplayPostReconfiguration(displayID, flags);
    return changed ? kCGErrorSuccess : kCGErrorFailure;
}

// Puts the display back in the mode it had before this process changed it.
static void restoreDisplayMode(CGDirectDisplayID displayID) {
    NSDictionary *original = nil;
    @synchronized(gDisplayStateLock) {
        NSMutableDictionary *state = [gDisplayState objectForKey: @(displayID)];
        original = [[state objectForKey: @"original"] retain];
        [state removeObjectForKey: @"original"];
    }
    if (original) {
        changeBackendMode(displayID, original, NO);
        [original release];
    }
}

static void restoreAllDisplayModes(void) {
    NSArray *ids;
    @synchronized(gDisplayStateLock) {
        ids = [[gDisplayState allKeys] copy];
    }
    for (NSNumber *key in ids)
        restoreDisplayMode([key unsignedIntValue]);
    [ids release];
}

// The mode must be one the display lists (as the dictionaries the legacy
// calls return are). Switching to the mode the display is already in
// succeeds; any other is left to the display backend, which reports whether
// it could change the mode.
//
// The errors are kCGErrorFailure for a missing mode, a mode the display does not
// list and an unknown display (observed on macOS 10.14.4; pinned by
// tests/coregraphics-display-mode-switch.m).
CGError CGDisplaySwitchToMode(CGDirectDisplayID displayID, CFDictionaryRef mode) {
    if (mode == NULL)
        return kCGErrorFailure;
    NSUInteger currentIndex = 0;
    NSArray *modes = backendModesForDisplay(displayID, &currentIndex);
    if ([modes count] == 0)
        return kCGErrorFailure;

    NSUInteger index = indexOfMode(modes, (NSDictionary *) mode);
    if (index == NSNotFound)
        return kCGErrorFailure;
    return changeBackendMode(displayID, [modes objectAtIndex: index], YES);
}

CGError CGDisplaySetDisplayMode(CGDirectDisplayID displayID, CGDisplayModeRef mode, CFDictionaryRef options) {
    if (mode == NULL)
        return kCGErrorFailure;
    NSArray *modes = backendModesForDisplay(displayID, NULL);
    if ([modes count] == 0)
        return kCGErrorFailure;
    NSUInteger index = indexOfMode(modes, (NSDictionary *) mode);
    if (index == NSNotFound)
        return kCGErrorFailure;
    return changeBackendMode(displayID, [modes objectAtIndex: index], YES);
}

uint32_t CGDisplayGammaTableCapacity(CGDirectDisplayID display) {
    (void)display;
    return 256;
}

// QUIRK: capturing a display ID that is not a display succeeds (and captures
// nothing). Not documented. Evidence: black-box observation on macOS 10.14.4
// (tier 2). Test: coregraphics-display-mode-switch, check 12.
CGError CGDisplayCapture(CGDirectDisplayID display) {
    BOOL connected;
    NSArray<CGSScreen *> *screens = activeScreens(&connected);
    if (!connected)
        return kCGErrorInvalidConnection;
    if (!screenForDisplayID(screens, display))
        return kCGErrorSuccess;
    initDisplayState();
    @synchronized(gDisplayStateLock) {
        [stateForDisplay(display) setObject: @YES forKey: @"captured"];
    }
    return kCGErrorSuccess;
}

// Releasing a display puts back the mode this process switched it from. A
// display that is neither captured nor was switched by this process, and one
// that does not exist, give kCGErrorIllegalArgument (observed on macOS 10.14.4).
CGError CGDisplayRelease(CGDirectDisplayID display) {
    BOOL connected;
    NSArray<CGSScreen *> *screens = activeScreens(&connected);
    if (!connected)
        return kCGErrorInvalidConnection;
    if (!screenForDisplayID(screens, display))
        return kCGErrorIllegalArgument;
    initDisplayState();
    BOOL known;
    @synchronized(gDisplayStateLock) {
        NSMutableDictionary *state = [gDisplayState objectForKey: @(display)];
        known = [state objectForKey: @"captured"] != nil || [state objectForKey: @"original"] != nil;
        [state removeObjectForKey: @"captured"];
    }
    if (!known)
        return kCGErrorIllegalArgument;
    restoreDisplayMode(display);
    return kCGErrorSuccess;
}

CGError CGCaptureAllDisplays(void) {
    BOOL connected;
    NSArray<CGSScreen *> *screens = activeScreens(&connected);
    if (!connected)
        return kCGErrorInvalidConnection;
    for (CGSScreen *screen in screens)
        CGDisplayCapture([screen displayID]);
    return kCGErrorSuccess;
}

// kCGErrorFailure when nothing was captured or switched (observed on macOS 10.14.4).
CGError CGReleaseAllDisplays(void) {
    if (displayConnection() == nil)
        return kCGErrorInvalidConnection;
    initDisplayState();
    NSArray *ids;
    BOOL any = NO;
    @synchronized(gDisplayStateLock) {
        ids = [[gDisplayState allKeys] copy];
        for (NSNumber *key in ids) {
            NSMutableDictionary *state = [gDisplayState objectForKey: key];
            if ([state objectForKey: @"captured"] || [state objectForKey: @"original"])
                any = YES;
            [state removeObjectForKey: @"captured"];
        }
    }
    for (NSNumber *key in ids)
        restoreDisplayMode([key unsignedIntValue]);
    [ids release];
    return any ? kCGErrorSuccess : kCGErrorFailure;
}

boolean_t CGDisplayIsCaptured(CGDirectDisplayID display) {
    if (gDisplayState == nil)
        return FALSE;
    @synchronized(gDisplayStateLock) {
        return [[gDisplayState objectForKey: @(display)] objectForKey: @"captured"] != nil;
    }
}

#pragma mark - Framebuffer access and palettes

// Displays here are windows or X screens, composited by the window system:
// applications cannot map the framebuffer. A display's "framebuffer" is a
// private, zero-filled block of pixel memory of the current mode's size, the
// same for every query, so code that writes pixels through it works but shows
// nothing. It stays mapped for the life of the process.
typedef struct {
    CGDirectDisplayID display;
    void *memory;
    size_t length;
} DisplayFramebuffer;

static DisplayFramebuffer gFramebuffers[16];
static size_t gFramebufferCount;
static pthread_mutex_t gFramebufferLock = PTHREAD_MUTEX_INITIALIZER;

void *CGDisplayBaseAddress(CGDirectDisplayID display) {
    // Rows are counted in pixels, which are not points on a scaled display.
    NSDictionary *mode = legacyCurrentMode(display);
    size_t length = CGDisplayBytesPerRow(display) *
                    [[mode objectForKey: @"kCGDisplayPixelsHigh"] unsignedLongValue];
    if (length == 0)
        return NULL;

    void *result = NULL;
    pthread_mutex_lock(&gFramebufferLock);
    DisplayFramebuffer *entry = NULL;
    for (size_t i = 0; i < gFramebufferCount; i++) {
        if (gFramebuffers[i].display == display) {
            entry = &gFramebuffers[i];
            break;
        }
    }
    if (entry == NULL && gFramebufferCount < sizeof gFramebuffers / sizeof *gFramebuffers) {
        entry = &gFramebuffers[gFramebufferCount++];
        entry->display = display;
        entry->memory = NULL;
        entry->length = 0;
    }
    if (entry != NULL && entry->length < length) {
        // A larger mode needs a new block; the old one stays valid for code still using it.
        void *memory = mmap(NULL, length, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0);
        if (memory != MAP_FAILED) {
            entry->memory = memory;
            entry->length = length;
        }
    }
    if (entry != NULL && entry->length >= length)
        result = entry->memory;
    pthread_mutex_unlock(&gFramebufferLock);
    return result;
}

void *CGDisplayAddressForPosition(CGDirectDisplayID display, CGDisplayCoord x, CGDisplayCoord y) {
    NSDictionary *mode = legacyCurrentMode(display);
    unsigned width = [[mode objectForKey: @"kCGDisplayPixelsWide"] unsignedIntValue];
    unsigned height = [[mode objectForKey: @"kCGDisplayPixelsHigh"] unsignedIntValue];
    if (x < 0 || y < 0 || (unsigned) x >= width || (unsigned) y >= height)
        return NULL;
    char *base = CGDisplayBaseAddress(display);
    if (base == NULL)
        return NULL;
    size_t bytesPerPixel = [[mode objectForKey: (NSString *) kCGDisplayBitsPerPixel] unsignedLongValue] / 8;
    return base + (size_t) y * CGDisplayBytesPerRow(display) + (size_t) x * bytesPerPixel;
}

// There is no vertical retrace to observe: the position is always 0, as for
// a display without a scanning beam.
uint32_t CGDisplayBeamPosition(CGDirectDisplayID display) {
    return 0;
}

// Only displays with an indexed (8-bit) pixel format have a palette to set,
// and the modes here are all direct color.
boolean_t CGDisplayCanSetPalette(CGDirectDisplayID display) {
    return FALSE;
}

CGError CGDisplaySetPalette(CGDirectDisplayID display, const CGDirectPaletteRef palette) {
    return kCGErrorNoneAvailable;
}

size_t CGDisplayModeGetPixelWidth(CGDisplayModeRef mode) {
    NSDictionary *dict = (NSDictionary *) mode;
    NSNumber *pixelWidth = [dict valueForKey: @"PixelWidth"];
    if (pixelWidth)
        return [pixelWidth unsignedIntValue];
    return CGDisplayModeGetWidth(mode);
}

size_t CGDisplayModeGetPixelHeight(CGDisplayModeRef mode) {
    NSDictionary *dict = (NSDictionary *) mode;
    NSNumber *pixelHeight = [dict valueForKey: @"PixelHeight"];
    if (pixelHeight)
        return [pixelHeight unsignedIntValue];
    return CGDisplayModeGetHeight(mode);
}

uint32_t CGDisplayModeGetIOFlags(CGDisplayModeRef mode) {
    NSDictionary *dict = (NSDictionary *) mode;
    return [[dict valueForKey: @"IOFlags"] unsignedIntValue];
}

boolean_t CGDisplayModeIsUsableForDesktopGUI(CGDisplayModeRef mode) {
    NSDictionary *dict = (NSDictionary *) mode;
    NSNumber *usable = [dict valueForKey: @"UsableForDesktopGUI"];
    if (usable)
        return [usable boolValue];
    return TRUE;
}

// BuiltinDisplay (org.darlinghq.platform): whether the main display is reported as the built-in
// panel. X11 has no reliable notion of a built-in display, so by default none is, as on a Mac
// laptop running closed with external displays. Read once per process.
static bool mainDisplayIsBuiltin(void) {
    static dispatch_once_t once;
    static bool builtin = false;

    dispatch_once(&once, ^{
        CFPropertyListRef value = CFPreferencesCopyValue(
            CFSTR("BuiltinDisplay"), CFSTR("org.darlinghq.platform"),
            kCFPreferencesAnyUser, kCFPreferencesCurrentHost);
        if (!value)
            return;
        if (CFGetTypeID(value) == CFBooleanGetTypeID()) {
            builtin = CFBooleanGetValue((CFBooleanRef) value);
        } else if (CFGetTypeID(value) == CFNumberGetTypeID()) {
            int number = 0;
            builtin = CFNumberGetValue((CFNumberRef) value, kCFNumberIntType,
                                       &number) &&
                      number != 0;
        }
        CFRelease(value);
    });

    return builtin;
}

// The display backends report no display power state, and a display
// they list stays drawable, so no display is ever reported asleep.
boolean_t CGDisplayIsAsleep(CGDirectDisplayID display) {
    return false;
}

boolean_t CGDisplayIsBuiltin(CGDirectDisplayID display) {
    // A Mac has at most one built-in display.
    return display != kCGNullDirectDisplay && display == CGMainDisplayID() &&
           mainDisplayIsBuiltin();
}

double CGDisplayRotation(CGDirectDisplayID display) {
    // The backends present every display unrotated.
    return 0.0;
}

CGColorSpaceRef CGDisplayCopyColorSpace(CGDirectDisplayID display) {
    return CGColorSpaceCreateDeviceRGB();
}

#if defined(HAVE_PIPEWIRE) && HAVE_PIPEWIRE
// One captured frame, converted into the caller's pixels by the stream's frame callback.
typedef struct {
    pthread_mutex_t lock;
    pthread_cond_t cond;
    uint8_t *pixels;
    size_t width, height, bytesPerRow;
    CGRect captureRect, bounds;
    int done, converted;
} CGDisplayImageGrab;

static void CGDisplayImageGrabFrame(const struct darling_screen_capture_frame *frame, void *userData) {
    CGDisplayImageGrab *grab = userData;

    pthread_mutex_lock(&grab->lock);
    if (!grab->done) {
        grab->converted = darling_screen_capture_convert_bgra_rect(frame, grab->pixels, (uint32_t) grab->bytesPerRow,
            (uint32_t) grab->width, (uint32_t) grab->height,
            (int32_t) (grab->captureRect.origin.x - grab->bounds.origin.x),
            (int32_t) (grab->captureRect.origin.y - grab->bounds.origin.y),
            (uint32_t) grab->captureRect.size.width, (uint32_t) grab->captureRect.size.height,
            0, 0, (uint32_t) grab->width, (uint32_t) grab->height) == 0;
        grab->done = 1;
        pthread_cond_signal(&grab->cond);
    }
    pthread_mutex_unlock(&grab->lock);
}
#endif

CGImageRef CGDisplayCreateImageForRect(CGDirectDisplayID display, CGRect rect) {
#if defined(HAVE_PIPEWIRE) && HAVE_PIPEWIRE
    CGRect bounds = CGDisplayBounds(display);
    CGRect captureRect = CGRectIntersection(rect, bounds);
    struct darling_screen_capture_stream *stream = NULL;
    CGDisplayImageGrab grab;
    CGColorSpaceRef space = NULL;
    CGContextRef context = NULL;
    CGImageRef image = NULL;
    int result;

    if (CGRectIsNull(captureRect) || CGRectIsEmpty(captureRect))
        return NULL;
    memset(&grab, 0, sizeof(grab));
    grab.width = (size_t) captureRect.size.width;
    grab.height = (size_t) captureRect.size.height;
    grab.bytesPerRow = grab.width * 4;
    grab.captureRect = captureRect;
    grab.bounds = bounds;
    grab.pixels = calloc(1, grab.bytesPerRow * grab.height);
    if (grab.pixels == NULL)
        return NULL;
    pthread_mutex_init(&grab.lock, NULL);
    pthread_cond_init(&grab.cond, NULL);

    {
        struct darling_screen_capture_callbacks callbacks;
        memset(&callbacks, 0, sizeof(callbacks));
        callbacks.frame = CGDisplayImageGrabFrame;
        result = darling_screen_capture_open((int32_t) bounds.origin.x, (int32_t) bounds.origin.y,
            (uint32_t) bounds.size.width, (uint32_t) bounds.size.height, 1,
            darling_screen_capture_supports_hdr() ? 1 : 0, &callbacks, &grab, &stream);
    }
    if (result == 0 && stream != NULL) {
        if (darling_screen_capture_start(stream, 1) == 0 && darling_screen_capture_wait(stream, 5000) == 0) {
            // The stream is streaming before its first frame arrives; give the compositor a few seconds.
            struct timespec deadline;
            clock_gettime(CLOCK_REALTIME, &deadline);
            deadline.tv_sec += 3;
            pthread_mutex_lock(&grab.lock);
            while (!grab.done && pthread_cond_timedwait(&grab.cond, &grab.lock, &deadline) == 0)
                ;
            pthread_mutex_unlock(&grab.lock);
        }
        // Stopping the stream waits for a running frame callback, so grab is not touched afterwards.
        darling_screen_capture_start(stream, 0);
        darling_screen_capture_close(stream);
    }

    if (grab.done && grab.converted) {
        space = CGColorSpaceCreateDeviceRGB();
        context = CGBitmapContextCreate(grab.pixels, grab.width, grab.height, 8, grab.bytesPerRow, space,
            kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
        if (context != NULL)
            image = CGBitmapContextCreateImage(context);
    }
    if (context != NULL) CGContextRelease(context);
    if (space != NULL) CGColorSpaceRelease(space);
    free(grab.pixels);
    pthread_cond_destroy(&grab.cond);
    pthread_mutex_destroy(&grab.lock);
    return image;
#else
    return NULL;
#endif
}

CGImageRef CGDisplayCreateImage(CGDirectDisplayID displayID) {
    return CGDisplayCreateImageForRect(displayID, CGDisplayBounds(displayID));
}

boolean_t CGCursorIsDrawnInFramebuffer(void) {
    // The pointer is part of the display contents.
    return true;
}

bool CGDisplayUsesForceToGray(void) {
    // Displays are never forced to grayscale.
    return false;
}

bool CGPreflightScreenCaptureAccess(void) {
#if defined(HAVE_PIPEWIRE) && HAVE_PIPEWIRE
    return darling_screen_capture_permitted() != 0;
#else
    return false;
#endif
}

bool CGRequestScreenCaptureAccess(void) {
#if defined(HAVE_PIPEWIRE) && HAVE_PIPEWIRE
    return darling_screen_capture_request_access() == 0;
#else
    return false;
#endif
}

id CGDirectDisplayCopyCurrentMetalDevice(CGDirectDisplayID displayID) {
    if (!screenForDisplayID(activeScreens(NULL), displayID))
        return nil;

    // Every display is driven by the system default Metal device. CoreGraphics
    // does not link Metal, so look it up at run time.
    typedef id (*CreateDeviceFunction)(void);
    CreateDeviceFunction create = (CreateDeviceFunction) dlsym(
        RTLD_DEFAULT, "MTLCreateSystemDefaultDevice");
    if (!create) {
        void *metal = dlopen("/System/Library/Frameworks/Metal.framework/Metal",
                             RTLD_LAZY | RTLD_GLOBAL);
        if (metal)
            create = (CreateDeviceFunction) dlsym(
                metal, "MTLCreateSystemDefaultDevice");
    }
    return create ? create() : nil;
}
