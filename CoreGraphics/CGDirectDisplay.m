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

CGDirectDisplayID CGMainDisplayID(void) {
    NSDisplay *display = currentDisplay();
    if (!display)
        return kCGErrorInvalidConnection;

    NSArray<NSScreen *> *screens = [display screens];

    for (int i = 0; i < [screens count]; i++) {
        if (!NSIsEmptyRect([[screens objectAtIndex: i] frame])) {
            return i + 1;
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

    for (int i = 0; i < [screens count]; i++) {
        if ((i + 1) != mainDisplay) {
            if (*displayCount < maxDisplays)
                onlineDisplays[*displayCount] = i + 1;
            (*displayCount)++;
        }
    }

    return kCGErrorSuccess;
}

size_t CGDisplayPixelsHigh(CGDirectDisplayID displayIndex) {
    NSDisplay *display = currentDisplay();
    if (!display)
        return kCGErrorInvalidConnection;

    NSArray<NSScreen *> *screens = [display screens];
    if (displayIndex > [screens count] || displayIndex <= 0)
        return 0;

    return NSHeight([[screens objectAtIndex: displayIndex - 1] frame]);
}

size_t CGDisplayPixelsWide(CGDirectDisplayID displayIndex) {
    NSDisplay *display = currentDisplay();
    if (!display)
        return kCGErrorInvalidConnection;

    NSArray<NSScreen *> *screens = [display screens];
    if (displayIndex > [screens count] || displayIndex <= 0)
        return 0;

    return NSWidth([[screens objectAtIndex: displayIndex - 1] frame]);
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
    for (int i = 0; i < [screens count]; i++) {
        if (!NSIsEmptyRect([[screens objectAtIndex: i] frame])) {
            if (*displayCount < maxDisplays)
                activeDisplays[*displayCount] = i + 1;
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

    for (int i = 0; i < [screens count]; i++) {
        NSRect rect = [[screens objectAtIndex: i] frame];
        if (NSPointInRect(point, rect)) {
            if (*matchingDisplayCount < maxDisplays)
                displays[*matchingDisplayCount] = i + 1;
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

    for (int i = 0; i < [screens count]; i++) {
        NSRect screenRect = [[screens objectAtIndex: i] frame];
        if (NSIntersectsRect(rect, screenRect)) {
            if (*matchingDisplayCount < maxDisplays)
                displays[*matchingDisplayCount] = i + 1;
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
    if (displayIndex > [screens count] || displayIndex <= 0)
        return NSZeroRect;

    return [[screens objectAtIndex: displayIndex - 1] frame];
}

CGError CGDisplayHideCursor(CGDirectDisplayID displayIndex) {
    NSDisplay *display = currentDisplay();
    if (!display)
        return kCGErrorInvalidConnection;

    [display hideCursor];
    return kCGErrorSuccess;
}

CGError CGDisplayShowCursor(CGDirectDisplayID displayIndex) {
    NSDisplay *display = currentDisplay();
    if (!display)
        return kCGErrorInvalidConnection;

    [display unhideCursor];
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
    return display == 1;
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

    NSArray<NSScreen *> *screens = [display screens];
    if (displayId <= 0 || displayId > [screens count])
        return nil;

    NSScreen *screen = [screens objectAtIndex: displayId - 1];
    NSData *edid = [screen edid];
    if (edid && [edid length] >= 16)
        return edid;

    return nil;
}

CGSize CGDisplayScreenSize(CGDirectDisplayID display) {
    printf("STUB %s\n", __PRETTY_FUNCTION__);

    NSData *edid = edidForDisplay(display);

    if (!edid) {
        CGRect bounds = CGDisplayBounds(display);

        return bounds.size;
    }

    return (CGSize){.width = 0, .height = 0};
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

CGError CGWarpMouseCursorPosition(CGPoint newCursorPosition) {
    NSDisplay *display = currentDisplay();
    if (!display)
        return kCGErrorInvalidConnection;
    [display warpMouse: newCursorPosition];
    return kCGErrorSuccess;
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
