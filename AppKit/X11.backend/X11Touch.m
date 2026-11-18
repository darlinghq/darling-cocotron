/*
 This file is part of Darling.

 Copyright (C) 2026 Darling Team

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

#import "X11Touch.h"
#import "X11Display.h"
#import "X11Window.h"
#import <AppKit/NSTouch.h>
#import "../private-include/AppKit/NSTouchBackend.h"
#import <Foundation/Foundation.h>
#import <X11/extensions/XInput2.h>
#include <elfcalls.h>
#include <math.h>
#include <string.h>

extern struct elf_calls *_elfcalls;

static int (*sXISelectEvents)(Display *, Window, XIEventMask *, int);
static Status (*sXIQueryVersion)(Display *, int *, int *);
static int sOpcode = -1;

BOOL X11TouchInit(Display *display) {
    int event, error;
    if (!XQueryExtension(display, "XInputExtension", &sOpcode, &event, &error)) {
        sOpcode = -1;
        return NO;
    }
    if (_elfcalls == NULL) {
        sOpcode = -1;
        return NO;
    }
    void *library = _elfcalls->dlopen("libXi.so.6");
    if (library == NULL)
        library = _elfcalls->dlopen("libXi.so");
    if (library == NULL) {
        NSLog(@"X11 backend: no libXi, so no touch screen input");
        sOpcode = -1;
        return NO;
    }
    sXISelectEvents = _elfcalls->dlsym(library, "XISelectEvents");
    sXIQueryVersion = _elfcalls->dlsym(library, "XIQueryVersion");
    // Asking for a version also makes libXi decode its events for this display.
    int major = 2, minor = 2;
    if (sXISelectEvents == NULL || sXIQueryVersion == NULL || sXIQueryVersion(display, &major, &minor) != Success
        || major < 2 || (major == 2 && minor < 2)) {
        sOpcode = -1;
        return NO;
    }
    return YES;
}

void X11TouchSelectWindow(Display *display, Window window) {
    if (sOpcode < 0 || window == 0)
        return;
    unsigned char bits[XIMaskLen(XI_TouchEnd)];
    memset(bits, 0, sizeof(bits));
    XISetMask(bits, XI_TouchBegin);
    XISetMask(bits, XI_TouchUpdate);
    XISetMask(bits, XI_TouchEnd);
    XIEventMask mask = {.deviceid = XIAllMasterDevices, .mask_len = sizeof(bits), .mask = bits};
    sXISelectEvents(display, window, &mask, 1);
}

BOOL X11TouchHandleEvent(X11Display *x11, XEvent *ev) {
    if (sOpcode < 0 || ev->type != GenericEvent || ev->xcookie.extension != sOpcode)
        return NO;
    XGenericEventCookie *cookie = &ev->xcookie;
    if (cookie->evtype != XI_TouchBegin && cookie->evtype != XI_TouchUpdate && cookie->evtype != XI_TouchEnd)
        return YES;
    Display *display = [x11 display];
    if (!XGetEventData(display, cookie))
        return YES;
    XIDeviceEvent *touch = cookie->data;
    [x11 touchEventType: cookie->evtype
                 device: touch->deviceid
                 detail: touch->detail
                 window: touch->event
                      x: touch->event_x
                      y: touch->event_y
                  rootX: touch->root_x
                  rootY: touch->root_y];
    XFreeEventData(display, cookie);
    return YES;
}

@implementation X11Display (X11Touch)

- (void) touchEventType: (int) type
                 device: (int) deviceID
                 detail: (unsigned int) detail
                 window: (Window) eventWindow
                      x: (double) eventX
                      y: (double) eventY
                  rootX: (double) rootX
                  rootY: (double) rootY
{
    X11Window *window = (X11Window *) [self windowForID: eventWindow];
    if (window == nil)
        return;
    NSPoint device = NSMakePoint(eventX, eventY);
    // Selected on the frame window; a child reports its own coordinates.
    if (eventWindow != [window windowHandle]) {
        Display *display = [self display];
        int x, y;
        Window child;
        if (XTranslateCoordinates(display, DefaultRootWindow(display), [window windowHandle],
                                  (int) rootX, (int) rootY, &x, &y, &child))
            device = NSMakePoint(x, y);
    }
    NSTouchPhase phase = type == XI_TouchBegin ? NSTouchPhaseBegan
            : type == XI_TouchUpdate ? NSTouchPhaseMoved : NSTouchPhaseEnded;
    // Touch numbers are per device.
    long long identifier = ((long long) deviceID << 32) | (long long) detail;
    // As on Wayland, an end carries no position: the finger leaves where it last was.
    NSPoint location = phase == NSTouchPhaseEnded ? NSMakePoint(NAN, NAN) : [window logicalPoint: device];
    NSTouchPost([window delegate], identifier, phase, location, 0);
}

@end
