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
#import <AppKit/NSDisplay.h>
#import <AppKit/NSScreen.h>
#import <CoreGraphics/CGDirectDisplay.h>
#import <CoreGraphics/CGError.h>
#import <IOKit/graphics/IOGraphicsLib.h>
#import <IOKit/graphics/IOGraphicsTypes.h>
#include <dlfcn.h>

// not sure what type or value this has
unsigned int kCGDisplayPixelHeight = kCGDisplayHeight;
unsigned int kCGDisplayPixelWidth = kCGDisplayWidth;

const CFStringRef kCGDisplayProductNameKey = CFSTR("kCGDisplayProductNameKey");

CGError CGCaptureAllDisplays(void) {
    return kCGErrorSuccess;
}

CGError CGReleaseAllDisplays(void) {
    return kCGErrorSuccess;
}

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

CGDirectDisplayID CGOpenGLDisplayMaskToDisplayID(CGOpenGLDisplayMask mask) {
    return CGMainDisplayID();
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

CGError CGDisplayCapture(CGDirectDisplayID display) {
    return kCGErrorSuccess;
}

CGError CGDisplayRelease(CGDirectDisplayID display) {
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

CFArrayRef CGDisplayAvailableModes(CGDirectDisplayID displayIndex) {
    NSDisplay *display = currentDisplay();
    if (!display)
        return NULL;
    return (CFArrayRef) [display modesForScreen: displayIndex - 1];
}

boolean_t CGDisplayIsInMirrorSet(CGDirectDisplayID display) {
    printf("STUB %s\n", __PRETTY_FUNCTION__);

    return FALSE;
}

Boolean CGDisplayIsMain(CGDirectDisplayID display) {
    return display != kCGNullDirectDisplay && display == CGMainDisplayID();
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

CGError CGDisplaySetDisplayMode(CGDirectDisplayID displayId,
                                CGDisplayModeRef mode, CFDictionaryRef options)
{
    NSDisplay *display = currentDisplay();
    if (!display)
        return kCGErrorInvalidConnection;
    BOOL result = [display setMode: mode forScreen: displayId - 1];

    return result ? kCGErrorSuccess : kCGErrorFailure;
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

CGError CGAssociateMouseAndMouseCursorPosition(boolean_t connected) {
    NSDisplay *display = currentDisplay();
    if (!display)
        return kCGErrorInvalidConnection;

    [display grabMouse: connected];
    return kCGErrorSuccess;
}

CFDictionaryRef CGDisplayBestModeForParametersAndRefreshRate(
        CGDirectDisplayID display, size_t bitsPerPixel, size_t width,
        size_t height, CGRefreshRate refreshRate, boolean_t *exactMatch)
{
    return nil;
}

boolean_t CGDisplayIsCaptured(CGDirectDisplayID display) {
    return FALSE;
}

CGError CGDisplaySwitchToMode(CGDirectDisplayID display, CFDictionaryRef mode) {
    return kCGErrorSuccess;
}

CFDictionaryRef CGDisplayCurrentMode(CGDirectDisplayID display) {
    return nil;
}

size_t CGDisplayModeGetPixelWidth(CGDisplayModeRef mode) {
    return 0;
}
