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
#import <AppKit/NSDisplay.h>
#import <AppKit/NSScreen.h>
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

// not sure what type or value this has
unsigned int kCGDisplayPixelHeight = 8200;
unsigned int kCGDisplayPixelWidth = 8200;

const CFStringRef kCGDisplayProductNameKey = CFSTR("kCGDisplayProductNameKey");
const CFStringRef kCGDisplayShowDuplicateLowResolutionModes = CFSTR("kCGDisplayShowDuplicateLowResolutionModes");

// Our platform abstraction is in AppKit
static NSDisplay *currentDisplay(void) {
    Class cls = NSClassFromString(@"NSDisplay");

    if (!cls) {
        if (dlopen("/System/Library/Frameworks/AppKit.framework/Versions/C/"
                   "AppKit",
                   RTLD_LAZY | RTLD_GLOBAL) != NULL)
            cls = NSClassFromString(@"NSDisplay");
    }

    return [cls currentDisplay];
}

// A display's ID belongs to the screen (the backend ties it to the output it
// drives), and [NSScreen screens] lists the main screen first, so an array
// position is not an ID.
static NSScreen *screenForDisplayID(NSArray<NSScreen *> *screens,
                                    CGDirectDisplayID displayID)
{
    for (NSScreen *screen in screens) {
        if ([screen cgDirectDisplayID] == displayID)
            return screen;
    }
    return nil;
}

// NSScreen frames are in Cocoa's global space (origin at the main screen's
// bottom-left corner, y up, like window frames); CoreGraphics' global space has its
// origin at the main screen's top-left corner and y down, so a display above the main
// one has a negative y, as on macOS. [NSScreen screens] lists the main screen first.
static CGRect globalRectForFrame(NSArray<NSScreen *> *screens, NSRect frame) {
    if (NSIsEmptyRect(frame) || [screens count] == 0)
        return frame;
    CGFloat mainHeight = NSHeight([[screens objectAtIndex: 0] frame]);
    return CGRectMake(frame.origin.x,
                      mainHeight - frame.origin.y - frame.size.height,
                      frame.size.width, frame.size.height);
}

CGDirectDisplayID CGMainDisplayID(void) {
    NSDisplay *display = currentDisplay();
    if (!display)
        return kCGErrorInvalidConnection;

    NSArray<NSScreen *> *screens = [display screens];

    for (NSScreen *screen in screens) {
        if (!NSIsEmptyRect([screen frame])) {
            return [screen cgDirectDisplayID];
        }
    }

    return kCGNullDirectDisplay;
}

CGError CGGetOnlineDisplayList(uint32_t maxDisplays,
                               CGDirectDisplayID *onlineDisplays,
                               uint32_t *displayCount)
{
    NSDisplay *display = currentDisplay();
    if (!display)
        return kCGErrorInvalidConnection;

    NSArray<NSScreen *> *screens = [display screens];
    const CGDirectDisplayID mainDisplay = CGMainDisplayID();

    *displayCount = 0;

    // Main display should be the first returned
    if (mainDisplay != kCGNullDirectDisplay) {
        (*displayCount)++;
        if (maxDisplays > 0)
            onlineDisplays[0] = mainDisplay;
    }

    for (NSScreen *screen in screens) {
        CGDirectDisplayID displayID = [screen cgDirectDisplayID];
        if (displayID != mainDisplay) {
            if (*displayCount < maxDisplays && onlineDisplays)
                onlineDisplays[*displayCount] = displayID;
            (*displayCount)++;
        }
    }

    return kCGErrorSuccess;
}

size_t CGDisplayPixelsHigh(CGDirectDisplayID displayIndex) {
    NSDisplay *display = currentDisplay();
    if (!display)
        return kCGErrorInvalidConnection;

    NSScreen *screen = screenForDisplayID([display screens], displayIndex);
    if (!screen)
        return 0;

    return NSHeight([screen frame]);
}

size_t CGDisplayPixelsWide(CGDirectDisplayID displayIndex) {
    NSDisplay *display = currentDisplay();
    if (!display)
        return kCGErrorInvalidConnection;

    NSScreen *screen = screenForDisplayID([display screens], displayIndex);
    if (!screen)
        return 0;

    return NSWidth([screen frame]);
}

CGError CGGetActiveDisplayList(uint32_t maxDisplays,
                               CGDirectDisplayID *activeDisplays,
                               uint32_t *displayCount)
{
    NSDisplay *display = currentDisplay();
    if (!display)
        return kCGErrorInvalidConnection;

    NSArray<NSScreen *> *screens = [display screens];

    *displayCount = 0;
    for (NSScreen *screen in screens) {
        if (!NSIsEmptyRect([screen frame])) {
            if (*displayCount < maxDisplays && activeDisplays)
                activeDisplays[*displayCount] = [screen cgDirectDisplayID];
            (*displayCount)++;
        }
    }

    return kCGErrorSuccess;
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

CGError CGGetDisplaysWithPoint(CGPoint point, uint32_t maxDisplays,
                               CGDirectDisplayID *displays,
                               uint32_t *matchingDisplayCount)
{
    NSDisplay *display = currentDisplay();
    if (!display)
        return kCGErrorInvalidConnection;

    NSArray<NSScreen *> *screens = [display screens];
    *matchingDisplayCount = 0;

    for (NSScreen *screen in screens) {
        NSRect rect = globalRectForFrame(screens, [screen frame]);
        if (NSPointInRect(point, rect)) {
            if (*matchingDisplayCount < maxDisplays)
                displays[*matchingDisplayCount] = [screen cgDirectDisplayID];
            (*matchingDisplayCount)++;
        }
    }

    return kCGErrorSuccess;
}

CGError CGGetDisplaysWithRect(CGRect rect, uint32_t maxDisplays,
                              CGDirectDisplayID *displays,
                              uint32_t *matchingDisplayCount)
{
    NSDisplay *display = currentDisplay();
    if (!display)
        return kCGErrorInvalidConnection;

    NSArray<NSScreen *> *screens = [display screens];
    *matchingDisplayCount = 0;

    for (NSScreen *screen in screens) {
        NSRect screenRect = globalRectForFrame(screens, [screen frame]);
        if (NSIntersectsRect(rect, screenRect)) {
            if (*matchingDisplayCount < maxDisplays)
                displays[*matchingDisplayCount] = [screen cgDirectDisplayID];
            (*matchingDisplayCount)++;
        }
    }

    return kCGErrorSuccess;
}

CGRect CGDisplayBounds(CGDirectDisplayID displayIndex) {
    NSDisplay *display = currentDisplay();
    if (!display)
        return NSZeroRect;

    NSArray<NSScreen *> *screens = [display screens];
    NSScreen *screen = screenForDisplayID(screens, displayIndex);
    if (!screen)
        return CGRectZero;

    return globalRectForFrame(screens, [screen frame]);
}

CGError CGDisplayHideCursor(CGDirectDisplayID displayIndex) {
    NSDisplay *display = currentDisplay();
    if (!display)
        return kCGErrorInvalidConnection;

    [display hideCursorCounted];
    return kCGErrorSuccess;
}

CGError CGDisplayShowCursor(CGDirectDisplayID displayIndex) {
    NSDisplay *display = currentDisplay();
    if (!display)
        return kCGErrorInvalidConnection;

    [display unhideCursorCounted];
    return kCGErrorSuccess;
}

// Callers pass the connection id and nothing else, and do not use a result;
// the function returns nothing on macOS. Seen in use around
// CGDisplayHideCursor()/CGDisplayShowCursor() pairs, which fits "show the
// cursor whatever the hide count was". The effect itself is not observable
// from outside; this is the minimal reading of the name.
// Test: coregraphics-cgs-force-show-cursor.m.
void CGSForceShowCursor(CGSConnectionID cid) {
    [currentDisplay() forceShowCursor];
}

boolean_t CGDisplayIsInMirrorSet(CGDirectDisplayID display) {
    printf("STUB %s\n", __PRETTY_FUNCTION__);

    return FALSE;
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

CGDisplayModeRef CGDisplayCopyDisplayMode(CGDirectDisplayID displayId) {
    NSDisplay *display = currentDisplay();
    if (!display)
        return NULL;

    NSDictionary *dict = [[display currentModeForScreen: displayId - 1] retain];

    return (CGDisplayModeRef) dict;
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

CFArrayRef CGDisplayCopyAllDisplayModes(CGDirectDisplayID displayIndex,
                                        CFDictionaryRef options)
{
    NSDisplay *display = currentDisplay();
    if (!display)
        return NULL;
    return (CFArrayRef)[[display modesForScreen: displayIndex - 1] retain];
}

static NSData *edidForDisplay(CGDirectDisplayID displayId) {
    NSDisplay *display = currentDisplay();
    if (!display)
        return nil;

    NSScreen *screen = screenForDisplayID([display screens], displayId);
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
static CGDisplayGeometryRect desktopBounds(NSArray<NSScreen *> *screens) {
    CGDisplayGeometryRect desktop = {0, 0, 0, 0};
    for (NSScreen *screen in screens) {
        if (NSIsEmptyRect([screen frame]))
            continue;
        CGRect rect = globalRectForFrame(screens, [screen frame]);
        desktop = CGDisplayGeometryUnion(
                desktop, (CGDisplayGeometryRect){rect.origin.x, rect.origin.y,
                                                 rect.size.width, rect.size.height});
    }
    return desktop;
}

// The one place CoreGraphics' global point meets the backend's: clip it to the
// desktop and hand it to -warpMouse:, which takes CoreGraphics' global space (the
// space CGEventGetLocation() reports). The rules are written down in
// CGDisplayGeometry.h.
static CGError warpToGlobalPoint(NSDisplay *display, CGPoint point) {
    if (!isfinite(point.x) || !isfinite(point.y))
        return kCGErrorIllegalArgument;

    NSArray<NSScreen *> *screens = [display screens];
    if ([screens count] == 0)
        return kCGErrorCannotComplete;

    NSScreen *main = [screens objectAtIndex: 0];
    // No active output: the point has no desktop to land in.
    if (NSIsEmptyRect([main frame]))
        return kCGErrorCannotComplete;
    CGFloat scale = [main backingScaleFactor];
    if (!(scale >= 1))
        scale = 1;

    CGDisplayGeometryPoint clipped = CGDisplayGeometryClamp(
            desktopBounds(screens), scale,
            (CGDisplayGeometryPoint){point.x, point.y});

    [display warpMouse: NSMakePoint(clipped.x, clipped.y)];
    return kCGErrorSuccess;
}

CGError CGWarpMouseCursorPosition(CGPoint newCursorPosition) {
    NSDisplay *display = currentDisplay();
    if (!display)
        return kCGErrorInvalidConnection;
    return warpToGlobalPoint(display, newCursorPosition);
}

CGError CGDisplayMoveCursorToPoint(CGDirectDisplayID displayID, CGPoint newCursorPosition) {
    NSDisplay *display = currentDisplay();
    if (!display)
        return kCGErrorInvalidConnection;

    // The point is relative to the upper-left corner of that display.
    NSArray<NSScreen *> *screens = [display screens];
    NSScreen *screen = screenForDisplayID(screens, displayID);
    if (!screen || NSIsEmptyRect([screen frame]))
        return kCGErrorIllegalArgument;

    CGRect bounds = globalRectForFrame(screens, [screen frame]);
    CGDisplayGeometryPoint global = CGDisplayGeometryDisplayToGlobal(
            (CGDisplayGeometryRect){bounds.origin.x, bounds.origin.y,
                                    bounds.size.width, bounds.size.height},
            (CGDisplayGeometryPoint){newCursorPosition.x, newCursorPosition.y});
    return warpToGlobalPoint(display, CGPointMake(global.x, global.y));
}

// The mouse motion reported since the previous call, in screen pixels.
void CGGetLastMouseDelta(int32_t *deltaX, int32_t *deltaY) {
    NSDisplay *display = currentDisplay();
    int32_t dx = 0, dy = 0;
    if (display)
        [display takeMouseDeltaX: &dx y: &dy];
    if (deltaX)
        *deltaX = dx;
    if (deltaY)
        *deltaY = dy;
}

CGError CGAssociateMouseAndMouseCursorPosition(boolean_t connected) {
    NSDisplay *display = currentDisplay();
    if (!display)
        return kCGErrorInvalidConnection;

    // Disconnecting the mouse from the cursor is what -grabMouse: YES does:
    // the cursor stays put and the mouse only produces deltas.
    [display grabMouse: !connected];
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
    NSDisplay *display = currentDisplay();
    if (!display || displayID == kCGNullDirectDisplay)
        return nil;
    NSScreen *screen = screenForDisplayID([display screens], displayID);
    if (!screen)
        return nil;

    NSArray *modes = [display modesForScreen: displayID - 1];
    NSDictionary *current = [display currentModeForScreen: displayID - 1];
    if ([modes count] == 0)
        modes = [current count] > 0 ? @[ current ] : nil;

    if (currentIndex) {
        *currentIndex = 0;
        for (NSUInteger i = 0; i < [modes count]; i++) {
            NSDictionary *mode = [modes objectAtIndex: i];
            if ([[mode objectForKey: @"Width"] isEqual: [current objectForKey: @"Width"]] &&
                [[mode objectForKey: @"Height"] isEqual: [current objectForKey: @"Height"]] &&
                [[mode objectForKey: @"PixelWidth"] isEqual: [current objectForKey: @"PixelWidth"]]) {
                *currentIndex = i;
                break;
            }
        }
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
    NSDisplay *display = currentDisplay();
    if (!display)
        return kCGErrorInvalidConnection;
    NSDictionary *before = [display currentModeForScreen: displayID - 1];
    if (sameBackendMode(before, mode))
        return kCGErrorSuccess;

    initDisplayState();
    CGDisplayPostReconfiguration(displayID, kCGDisplayBeginConfigurationFlag);
    BOOL changed = [display setMode: mode forScreen: displayID - 1];
    CGDisplayChangeSummaryFlags flags = 0;
    if (changed) {
        flags = kCGDisplaySetModeFlag;
        NSDictionary *after = [display currentModeForScreen: displayID - 1];
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

// QUIRK: capturing a display ID that is not a display succeeds (and captures
// nothing). Not documented. Evidence: black-box observation on macOS 10.14.4
// (tier 2). Test: coregraphics-display-mode-switch, check 12.
CGError CGDisplayCapture(CGDirectDisplayID display) {
    NSDisplay *backend = currentDisplay();
    if (!backend)
        return kCGErrorInvalidConnection;
    if (!screenForDisplayID([backend screens], display))
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
    NSDisplay *backend = currentDisplay();
    if (!backend)
        return kCGErrorInvalidConnection;
    if (!screenForDisplayID([backend screens], display))
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
    NSDisplay *backend = currentDisplay();
    if (!backend)
        return kCGErrorInvalidConnection;
    for (NSScreen *screen in [backend screens])
        CGDisplayCapture([screen cgDirectDisplayID]);
    return kCGErrorSuccess;
}

// kCGErrorFailure when nothing was captured or switched (observed on macOS 10.14.4).
CGError CGReleaseAllDisplays(void) {
    NSDisplay *backend = currentDisplay();
    if (!backend)
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

CGImageRef CGDisplayCreateImageForRect(CGDirectDisplayID display, CGRect rect) {
    // Only an existing display and a non-empty part of it can be captured.
    NSDisplay *host = currentDisplay();
    if (!host || !screenForDisplayID([host screens], display) ||
        CGRectIsEmpty(rect) || CGRectIsNull(rect) ||
        !CGRectIntersectsRect(rect, CGDisplayBounds(display)))
        return NULL;

    // Reading the display's contents is a screen capture. No backend can read
    // pixels back, so the function returns NULL, as it does on a Mac where
    // screen recording is not permitted (see CGPreflightScreenCaptureAccess).
    return NULL;
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
    // Without screen capture, access is never granted.
    return false;
}

bool CGRequestScreenCaptureAccess(void) {
    return false;
}

id CGDirectDisplayCopyCurrentMetalDevice(CGDirectDisplayID displayID) {
    NSDisplay *display = currentDisplay();
    if (!display || !screenForDisplayID([display screens], displayID))
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
