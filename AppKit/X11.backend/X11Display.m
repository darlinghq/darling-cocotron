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

#import "X11Display.h"
#import "NSEvent_mouse.h"
#import "X11Cursor.h"
#import "X11Pasteboard.h"
#import "X11Window.h"
#import <AppKit/NSApplication.h>
#import <AppKit/NSScreen.h>
#import <Foundation/NSDebug.h>

#ifndef DARLING
#import <Foundation/NSSelectInputSource.h>
#import <Foundation/NSSocket_bsd.h>
#endif

#import <AppKit/NSColor.h>
#import <AppKit/NSCursor.h>
#import <AppKit/NSFontManager.h>
#import <AppKit/NSFontTypeface.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSRaise.h>
#import <AppKit/NSWindow.h>

#import <Onyx2D/O2Font_freetype.h>

#import <OpenGL/CGLInternal.h>

#import "CarbonKeys.h"
#import "X11KeySymToUCS.h"
#import "X11KeyEvent.h"
#import <X11/XKBlib.h>
#import <X11/Xutil.h>
#import <X11/extensions/XKBrules.h>
#import <X11/extensions/Xrandr.h>
#import "../../CoreGraphics/X11.backend/X11Monitors.h"
#import "../../CoreGraphics/X11.backend/X11RandR.h"
#import <X11/keysym.h>
#import <fcntl.h>
#import <fontconfig/fontconfig.h>
#import <stddef.h>

void NSColorSetCatalogColor(NSColorListName catalogName, NSColorName colorName, NSColor *color);

@implementation X11Display

static int errorHandler(Display *display, XErrorEvent *errorEvent) {
    return [(X11Display *) [X11Display currentDisplay] handleError: errorEvent];
}

#ifdef DARLING
static void socketCallback(CFSocketRef s, CFSocketCallBackType type,
                           CFDataRef address, const void *data, void *info)
{
    X11Display *self = info;
    [self processPendingEvents];
}
#endif

- init {
    if (self = [super init]) {
        // EGL also uses this Display from compositor threads, so Xlib has
        // to be made thread-safe before the first Xlib call.
        if (!XInitThreads()) {
            NSLog(@"X11Display: XInitThreads() failed");
            [self release];
            return nil;
        }

        _display = XOpenDisplay(NULL);

        if (_display == NULL) {
            _display = XOpenDisplay(":0");
        }

        if (_display == NULL) {
            // Failed to connect.
            [self release];
            return nil;
        }

        if (NSDebugEnabled)
            XSynchronize(_display, True);

        XSetErrorHandler(errorHandler);

        _fileDescriptor = ConnectionNumber(_display);
#ifndef DARLING
        _inputSource = [[NSSelectInputSource
                socketInputSourceWithSocket:
                        [NSSocket_bsd socketWithDescriptor: _fileDescriptor]]
                retain];
        [_inputSource setDelegate: self];
        [_inputSource setSelectEventMask: NSSelectReadEvent];
#else
        // There's no need to retain/release the display,
        // because the display is guaranteed to outlive
        // the socket.
        CFSocketContext context = {.version = 0,
                                   .info = self,
                                   .retain = NULL,
                                   .release = NULL,
                                   .copyDescription = NULL};
        _cfSocket = CFSocketCreateWithNative(
                kCFAllocatorDefault, _fileDescriptor, kCFSocketReadCallBack,
                socketCallback, &context);
        _source =
                CFSocketCreateRunLoopSource(kCFAllocatorDefault, _cfSocket, 0);
        CFRunLoopAddSource(CFRunLoopGetMain(), _source, kCFRunLoopCommonModes);

        CGLRegisterNativeDisplay(_display);
#endif

        _windowsByID = [NSMutableDictionary new];
        [self _enableDetectableAutoRepeat];

        XSetLocaleModifiers("");
        _xim = XOpenIM(_display, NULL, NULL, NULL);

        if (!_xim) {
            NSLog(@"Failed to open XIM, falling back to im=none\n");

            XSetLocaleModifiers("@im=none");
            _xim = XOpenIM(_display, NULL, NULL, NULL);
        }

        int errorBase;
        if (XRRQueryExtension(_display, &_rrEventBase, &errorBase)) {
            XRRSelectInput(_display, DefaultRootWindow(_display), X11_RANDR_EVENT_MASK);
        }

        int xwaylandOpcode, xwaylandEvent, xwaylandError;
        _isXwayland = XQueryExtension(_display, "XWAYLAND", &xwaylandOpcode,
                                      &xwaylandEvent, &xwaylandError);

        lastFocusedWindow = nil;
        _buttonClickCounts = [NSMutableDictionary new];
        _modifierFlags = 0;
    }
    return self;
}

- (void) dealloc {
    X11RelativeMouseEnd(&_relativeMouse);
    [_blankCursor release];
    [_defaultCursor release];

    // -init releases self when it cannot connect to the X server, so none of these may exist yet.
    if (_xim)
        XCloseIM(_xim);

    if (_display)
        XCloseDisplay(_display);
#ifdef DARLING
    if (_source != NULL) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), _source, kCFRunLoopCommonModes);
        CFRelease(_source);
    }
    if (_cfSocket != NULL)
        CFRelease(_cfSocket);
#endif

    [_windowsByID release];
    [_buttonClickCounts release];
    [super dealloc];
}

- (CGWindow *) newWindowWithDelegate: (NSWindow *) delegate {
    return [[X11Window alloc] initWithDelegate: delegate];
}

- (Display *) display {
    return _display;
}

- (void) _enableDetectableAutoRepeat {
    int major = XkbMajorVersion, minor = XkbMinorVersion;
    XkbStateRec state;

    if (!XkbLibraryVersion(&major, &minor))
        return;
    if (!XkbQueryExtension(_display, NULL, NULL, &major, &minor, NULL))
        return;
    
    Bool supported;
    XkbSetDetectableAutoRepeat(_display, TRUE, &supported);
}

- (void) _invalidateRRCache {
    _pointerKnown = NO;
    // The root may have shrunk or a monitor gone: the pointer's reachable
    // area, and with it a relative-mode grab's bounds, changed.
    [self resnapshotRelativeMouse];
    if (_lastScreens) {
        [_lastScreens release];
        _lastScreens = nil;
    }
    _primaryRootFrameValid = NO;
}

// The main monitor's rectangle in root coordinates, device pixels: the origin
// of the global coordinate space, as on macOS. With one monitor, or without
// RandR, it is the root window.
- (NSRect) primaryRootFrame {
    if (!_primaryRootFrameValid)
        [self screens];
    return _primaryRootFrame;
}

// The main monitor in root coordinates, in the unit of window frames.
- (X11Frame) primaryFrameInPoints {
    NSRect primary = [self primaryRootFrame];
    return (X11Frame){NSMinX(primary), NSMinY(primary),
                      NSWidth(primary), NSHeight(primary)};
}

- (NSPoint) cgPointFromRoot: (NSPoint) root {
    X11Point point = X11CGPointFromRoot([self primaryFrameInPoints],
                                        (X11Point){root.x, root.y});
    return NSMakePoint(point.x, point.y);
}

- (NSArray *) rootScreenFallback {
    int width = DisplayWidth(_display, DefaultScreen(_display));
    int height = DisplayHeight(_display, DefaultScreen(_display));
    _primaryRootFrame = NSMakeRect(0, 0, width, height);
    _primaryRootFrameValid = YES;
    NSRect frame = NSMakeRect(0, 0, width, height);
    NSScreen *screen = [[[NSScreen alloc] initWithFrame: frame
                                           visibleFrame: frame] autorelease];
    [screen setCgDirectDisplayID: 1];
    return [NSArray arrayWithObject: screen];
}

// [NSScreen screens] starts with the main monitor, as on macOS, and every
// frame is relative to that monitor's origin. A display's CGDirectDisplayID
// stays tied to its RandR output (index + 1), whatever its position in the
// array, because the mode functions address the output by that index.
- (NSArray *) screens {

    NSArray* last = [_lastScreens retain];
    if (last) {
        return [last autorelease];
    }

    int count = 0, primary = -1;
    X11Monitor *monitors = X11MonitorsCopy(_display, &count, &primary);
    // A server that lists no output at all still has a root window; an empty
    // screen list would make +[NSScreen mainScreen] throw.
    if (monitors == NULL || count == 0) {
        free(monitors);
        return [self rootScreenFallback];
    }

    // Without any active output the root window stands in, like without RandR.
    _primaryRootFrame =
            primary >= 0
                    ? NSMakeRect(monitors[primary].x, monitors[primary].y,
                                 monitors[primary].width, monitors[primary].height)
                    : NSMakeRect(0, 0, DisplayWidth(_display, DefaultScreen(_display)),
                                 DisplayHeight(_display, DefaultScreen(_display)));
    _primaryRootFrameValid = YES;
    int *order = calloc(count > 0 ? (size_t) count : 1, sizeof *order);
    if (order == NULL) {
        free(monitors);
        return [self rootScreenFallback];
    }
    X11MonitorsOrder(monitors, count, primary, order);

    NSMutableArray<NSScreen *> *retval =
            [NSMutableArray arrayWithCapacity: count];
    Atom edidAtom = XInternAtom(_display, "EDID", FALSE);

    for (int n = 0; n < count; n++) {
        int i = order[n];

        // An output without a CRTC and mode (a disconnected or switched-off
        // connector) shows nothing, so it is not a screen.
        if (!monitors[i].active)
            continue;

        // The frame is in Cocoa's global space, y up from the main
        // monitor's bottom-left corner, like window frames.
        X11Frame global = X11FrameFromRoot(
                [self primaryFrameInPoints],
                (X11Frame){monitors[i].x, monitors[i].y,
                           monitors[i].width, monitors[i].height});
        NSRect frame = NSMakeRect(global.x, global.y, global.width,
                                  global.height);

        NSScreen *nsscreen =
                [[[NSScreen alloc] initWithFrame: frame
                                    visibleFrame: frame] autorelease];

        Atom actualType;
        unsigned long nitems, bytesAfter;
        int actualFormat;
        unsigned char *prop = NULL;

        if (XRRGetOutputProperty(_display, monitors[i].output, edidAtom, 0,
                                 100, FALSE, FALSE, AnyPropertyType,
                                 &actualType, &actualFormat, &nitems,
                                 &bytesAfter, &prop) == Success) {
            if (prop && actualFormat == 8 && nitems > 0)
                [nsscreen setEdid: [NSData dataWithBytes: prop
                                                  length: nitems]];
        }
        if (prop)
            XFree(prop);
        [nsscreen setCgDirectDisplayID: X11MonitorDisplayID(i)];
        [retval addObject: nsscreen];
    }

    free(order);
    free(monitors);

    if ([retval count] == 0)
        return [self rootScreenFallback];

    NSArray* array = [NSArray arrayWithArray: retval];
    _lastScreens = [array retain];
    return array;
}

static NSDictionary *modeInfoToDictionary(const XRRModeInfo *mi, int depth) {
    double rate = 0;

    if (mi->hTotal && mi->vTotal)
        rate = (double) mi->dotClock /
               ((double) mi->hTotal * (double) mi->vTotal);

    return @{
        @"Width" : @(mi->width),
        @"Height" : @(mi->height),
        @"Depth" : @(depth),
        @"RefreshRate" : @(rate)
    };
}

- (NSArray *) modesForScreen: (int) screenIndex {
    int eventBase, errorBase;
    const int defaultDepth =
            XDefaultDepthOfScreen(XDefaultScreenOfDisplay(_display));

    if (!XRRQueryExtension(_display, &eventBase, &errorBase)) {
        Screen *defaultScreen = XDefaultScreenOfDisplay(_display);
        return @[ @{
            @"Width" : @(WidthOfScreen(defaultScreen)),
            @"Height" : @(HeightOfScreen(defaultScreen)),
            @"Depth" : @(defaultDepth)
        } ];
    } else {
        XRRScreenResources *screen = XRRGetScreenResourcesCurrent(
                _display, DefaultRootWindow(_display));
        if (screen == NULL)
            return nil;

        if (screenIndex < 0 || screenIndex >= screen->noutput) {
            XRRFreeScreenResources(screen);
            return nil;
        }

        XRROutputInfo *oinfo = XRRGetOutputInfo(_display, screen,
                                                screen->outputs[screenIndex]);

        NSMutableArray<NSDictionary *> *retval =
                [NSMutableArray arrayWithCapacity: oinfo->nmode];

        for (int i = 0; i < oinfo->nmode; i++) {
            XRRModeInfo *mode = NULL;
            for (int j = 0; j < screen->nmode; j++) {
                if (screen->modes[j].id == oinfo->modes[i]) {
                    mode = &screen->modes[j];
                    break;
                }
            }

            if (mode != NULL) {
                NSDictionary *dict = modeInfoToDictionary(mode, defaultDepth);
                [retval addObject: dict];
            }
        }

        XRRFreeOutputInfo(oinfo);
        XRRFreeScreenResources(screen);
        return [NSArray arrayWithArray: retval];
    }
}

- (BOOL) setMode: (NSDictionary *) mode forScreen: (int) screenIndex {
    int eventBase, errorBase;

    if (XRRQueryExtension(_display, &eventBase, &errorBase)) {
        // TODO: Use XRRSetCrtcConfig
        // https://cgit.freedesktop.org/xorg/lib/libXrandr/tree/include/X11/extensions/Xrandr.h#n283
    }

    return FALSE;
}

- (NSDictionary *) currentModeForScreen: (int) screenIndex {
    int eventBase, errorBase;
    NSDictionary *dict = @{};

    if (XRRQueryExtension(_display, &eventBase, &errorBase)) {
        XRRScreenResources *screen = XRRGetScreenResourcesCurrent(
                _display, DefaultRootWindow(_display));
        if (screen == NULL)
            return dict;

        if (screenIndex < 0 || screenIndex >= screen->noutput) {
            XRRFreeScreenResources(screen);
            return dict;
        }

        XRROutputInfo *oinfo = XRRGetOutputInfo(_display, screen,
                                                screen->outputs[screenIndex]);

        if (oinfo->crtc) {
            XRRCrtcInfo *crtc = XRRGetCrtcInfo(_display, screen, oinfo->crtc);

            for (int i = 0; i < screen->nmode; i++) {
                if (screen->modes[i].id == crtc->mode) {
                    const int defaultDepth = XDefaultDepthOfScreen(
                            XDefaultScreenOfDisplay(_display));
                    dict = modeInfoToDictionary(&screen->modes[i],
                                                defaultDepth);

                    break;
                }
            }

            XRRFreeCrtcInfo(crtc);
        }

        XRRFreeOutputInfo(oinfo);
        XRRFreeScreenResources(screen);
    }
    return dict;
}

- (int) keyboardLayoutId {
    int major = XkbMajorVersion, minor = XkbMinorVersion;
    XkbStateRec state;

    if (!XkbLibraryVersion(&major, &minor))
        return -1;
    if (!XkbQueryExtension(_display, NULL, NULL, &major, &minor, NULL))
        return -1;
    if (XkbGetState(_display, XkbUseCoreKbd, &state) == Success)
        return state.group;

    return -1;
}

- (void) keyboardLayoutName: (NSString **) name
                   fullName: (NSString **) fullName
{
    int major = XkbMajorVersion, minor = XkbMinorVersion;

    if (name)
        *name = @"?";
    if (fullName)
        *fullName = @"?";

    if (!XkbLibraryVersion(&major, &minor))
        return;
    if (!XkbQueryExtension(_display, NULL, NULL, &major, &minor, NULL))
        return;

    XkbStateRec state;
    if (XkbGetState(_display, XkbUseCoreKbd, &state) != Success)
        return;

    XkbDescPtr desc =
            XkbGetKeyboard(_display, XkbAllComponentsMask, XkbUseCoreKbd);
    if (!desc)
        return;

    if (fullName != NULL) {
        char *group = XGetAtomName(_display, desc->names->groups[state.group]);

        if (group != NULL) {
            *fullName = [NSString stringWithUTF8String: group];
            XFree(group);
        }
    }

    XkbRF_VarDefsRec vd;
    if (name != NULL && XkbRF_GetNamesProp(_display, NULL, &vd)) {
        char *saveptr;
        char *tok = strtok_r(vd.layout, ",", &saveptr);

        for (int i = 0; i < state.group; i++) {
            tok = strtok_r(NULL, ",", &saveptr);
            if (tok == NULL)
                break;
        }

        if (tok != NULL) {
            *name = [NSString stringWithUTF8String: tok];
        }
    }
}

- (UCKeyboardLayout *) keyboardLayout: (uint32_t *) byteLength {
    int major = XkbMajorVersion, minor = XkbMinorVersion;
    XkbDescPtr pKBDesc;
    unsigned char group = 0;
    XkbStateRec state;

    struct MyLayout {
        UCKeyboardLayout layout;
        UCKeyModifiersToTableNum modifierVariants;
        UInt8 secondTableNum, thirdTableNum;
        UCKeyToCharTableIndex tableIndex;
        UInt32 secontTableOffset;
        UCKeyOutput table1[128];
        UCKeyOutput table2[128];
    };

    if (byteLength)
        *byteLength = 0;

    if (!XkbLibraryVersion(&major, &minor))
        return NULL;
    if (!XkbQueryExtension(_display, NULL, NULL, &major, &minor, NULL))
        return NULL;

    pKBDesc = XkbGetMap(_display, XkbAllClientInfoMask, XkbUseCoreKbd);
    if (!pKBDesc)
        return NULL;

    if (XkbGetState(_display, XkbUseCoreKbd, &state) == Success)
        group = state.group;

    struct MyLayout *layout =
            (struct MyLayout *) malloc(sizeof(struct MyLayout));

    layout->layout.keyLayoutHeaderFormat = kUCKeyLayoutHeaderFormat;
    layout->layout.keyLayoutDataVersion = 0;
    layout->layout.keyLayoutFeatureInfoOffset = 0;
    layout->layout.keyboardTypeCount = 1;

    memset(layout->layout.keyboardTypeList, 0, sizeof(UCKeyboardTypeHeader));

    layout->layout.keyboardTypeList[0].keyModifiersToTableNumOffset =
            offsetof(struct MyLayout, modifierVariants);
    layout->layout.keyboardTypeList[0].keyToCharTableIndexOffset =
            offsetof(struct MyLayout, tableIndex);

    layout->modifierVariants.keyModifiersToTableNumFormat =
            kUCKeyModifiersToTableNumFormat;
    layout->modifierVariants.defaultTableNum = 0;
    layout->modifierVariants.modifiersCount = 3;
    layout->modifierVariants.tableNum[0] = 0;
    layout->modifierVariants.tableNum[1] = 0; // cmd key bit
    layout->modifierVariants.tableNum[2] = 1; // shift key bit

    layout->tableIndex.keyToCharTableIndexFormat = kUCKeyToCharTableIndexFormat;
    layout->tableIndex.keyToCharTableSize = 128;
    layout->tableIndex.keyToCharTableCount = 2;
    layout->tableIndex.keyToCharTableOffsets[0] =
            offsetof(struct MyLayout, table1);
    layout->tableIndex.keyToCharTableOffsets[1] =
            offsetof(struct MyLayout, table2);

    for (int shift = 0; shift <= 1; shift++) {
        UCKeyOutput *outTable = (shift == 0) ? layout->table1 : layout->table2;
        for (int i = 0; i < 128; i++) {
            // Reverse the operation we do in -postXEvent:
            const int x11KeyCode = carbonToX11[i];

            if (!x11KeyCode) {
                outTable[i] = 0;
                continue;
            }

            // NOTE: Not using the group here. It just works with 0 instead...
            KeySym sym = XkbKeycodeToKeysym(_display, x11KeyCode, 0, shift);

            if (sym != NoSymbol)
                outTable[i] = X11KeySymToUCS(sym);
            else
                outTable[i] = 0;
        }
    }

    XkbFreeClientMap(pKBDesc, XkbAllClientInfoMask, true);

    if (byteLength)
        *byteLength = sizeof(struct MyLayout);

    return &layout->layout;
}

- (NSUInteger) currentModifierFlags {
    XkbStateRec r;
    if (XkbGetState(_display, XkbUseCoreKbd, &r) != Success)
        return 0;

    return [self modifierFlagsForState: r.mods];
}

- (NSUInteger) pressedMouseButtons {
    Window root, child;
    int rootX, rootY, winX, winY;
    unsigned int mask = 0;

    if (!XQueryPointer(_display, DefaultRootWindow(_display), &root, &child,
                       &rootX, &rootY, &winX, &winY, &mask))
        return 0;

    // X numbers the buttons by position (1 left, 2 middle, 3 right); Cocoa
    // numbers them 0 left, 1 right, 2 middle. The core protocol only reports
    // the state of buttons 1 to 5, and 4 and 5 are the wheel.
    NSUInteger buttons = 0;
    if (mask & Button1Mask)
        buttons |= 1 << 0;
    if (mask & Button3Mask)
        buttons |= 1 << 1;
    if (mask & Button2Mask)
        buttons |= 1 << 2;
    return buttons;
}

- (NSPasteboard *) pasteboardWithName: (NSString *) name {
    return [X11Pasteboard pasteboardWithName: name];
}

- (NSDraggingManager *) draggingManager {
    //   NSUnimplementedMethod();
    return nil;
}

- (NSColor *) colorWithName: (NSString *) colorName {
    if ([colorName isEqual: @"controlColor"])
        return [NSColor colorWithCalibratedWhite: 0.93 alpha: 1.0];
    if ([colorName isEqual: @"disabledControlTextColor"])
        return [NSColor grayColor];
    if ([colorName isEqual: @"controlTextColor"])
        return [NSColor blackColor];
    if ([colorName isEqual: @"menuBackgroundColor"])
        return [NSColor colorWithCalibratedWhite: 0.9 alpha: 1.0];
    if ([colorName isEqual: @"mainMenuBarColor"])
        return [NSColor colorWithCalibratedWhite: 0.9 alpha: 1.0];
    if ([colorName isEqual: @"controlShadowColor"])
        return [NSColor darkGrayColor];
    if ([colorName isEqual: @"selectedControlColor"])
        return [NSColor blueColor];
    if ([colorName isEqual: @"controlBackgroundColor"])
        return [NSColor whiteColor];
    if ([colorName isEqual: @"controlLightHighlightColor"])
        return [NSColor lightGrayColor];
    if ([colorName isEqual: @"headerColor"])
        return [NSColor greenColor];
    if ([colorName isEqual: @"textBackgroundColor"])
        return [NSColor whiteColor];
    if ([colorName isEqual: @"textColor"])
        return [NSColor blackColor];
    if ([colorName isEqual: @"selectedTextColor"])
        return [NSColor whiteColor];
    if ([colorName isEqual: @"headerTextColor"])
        return [NSColor blackColor];
    if ([colorName isEqual: @"menuItemTextColor"])
        return [NSColor blackColor];
    if ([colorName isEqual: @"selectedMenuItemTextColor"])
        return [NSColor whiteColor];
    if ([colorName isEqual: @"selectedMenuItemColor"])
        return [NSColor blueColor];
    if ([colorName isEqual: @"selectedControlTextColor"])
        return [NSColor blackColor];
    if ([colorName isEqual: @"windowFrameColor"])
        return [NSColor lightGrayColor];
    if ([colorName isEqual: @"shadowColor"])
        return [NSColor colorWithGenericGamma22White: 0.0f alpha: 1.0f];
    if ([colorName isEqual: @"alternateSelectedControlTextColor"])
        return [NSColor colorWithGenericGamma22White: 1.0f alpha: 1.0f];
    if ([colorName isEqual: @"labelColor"])
        return [NSColor colorWithSRGBRed: 0.0f
                                   green: 0.0f
                                    blue: 0.0f
                                   alpha: 0.847059f];
    if ([colorName isEqual: @"linkColor"])
        return [NSColor colorWithSRGBRed: 0.0f
                                   green: 0.411765f
                                    blue: 0.850980f
                                   alpha: 1.0f];
    if ([colorName isEqual: @"unemphasizedSelectedTextColor"])
        return [NSColor
                colorWithGenericGamma22White: 0.0f /* 1.0f on dark mode */
                                               alpha: 1.0f];
    if ([colorName isEqual: @"selectedContentBackgroundColor"])
        return [NSColor colorWithSRGBRed: 0.0f
                                   green: 0.388235f /* 0.345098f on dark mode */
                                    blue: 0.882353f /* 0.815686f on dark mode */
                                   alpha: 1.0f];
    if ([colorName isEqual: @"unemphasizedSelectedContentBackgroundColor"])
        return [NSColor colorWithSRGBRed: 0.862745f /* 0.274510f on dark mode */
                                   green: 0.862745f /* 0.274510f on dark mode */
                                    blue: 0.862745f /* 0.274510f on dark mode */
                                   alpha: 1.0f];
    if ([colorName isEqual: @"alternatingContentBackgroundColor"])
        return [NSColor colorWithSRGBRed: 0.956863f
                                   green: 0.960784f
                                    blue: 0.960784f
                                   alpha: 1.0f];
    if ([colorName isEqual: @"selectedTextBackgroundColor"])
        return [NSColor colorWithCalibratedRed: 0.20f
                                         green: 0.55f
                                          blue: 1.00f
                                         alpha: 1.00f];
    if ([colorName isEqual: @"alternateSelectedControlColor"])
        return [NSColor colorWithSRGBRed: 0.0f
                                   green: 0.411765f
                                    blue: 0.850980f
                                    alpha: 1.0f];
    if ([colorName isEqual: @"controlDarkShadowColor"])
        return [NSColor colorWithCalibratedRed: 0.0f
                                         green: 0.0f
                                          blue: 0.0f
                                         alpha: 1.0f];
    if ([colorName isEqual: @"controlHighlightColor"])
        return [NSColor colorWithCalibratedRed: 0.890097f
                                         green: 0.890097f
                                          blue: 0.890097f
                                         alpha: 1.0f];
    if ([colorName isEqual: @"gridColor"])
        return [NSColor colorWithGenericGamma22White: 0.80f alpha: 1.0f];
    if ([colorName isEqual: @"highlightColor"])
        return [NSColor colorWithGenericGamma22White: 1.0f alpha: 1.0f];
    if ([colorName isEqual: @"keyboardFocusIndicatorColor"])
        return [NSColor colorWithSRGBRed: 0.231373f
                                   green: 0.60f
                                    blue: 0.988235f
                                    alpha: 1.0f];
    if ([colorName isEqual: @"knobColor"])
        return [NSColor colorWithSRGBRed: 0.60f
                                   green: 0.60f
                                    blue: 0.733333f
                                    alpha: 1.0f];
    if ([colorName isEqual: @"scrollBarColor"])
        return [NSColor colorWithSRGBRed: 0.666667f
                                   green: 0.666667f
                                    blue: 0.666667f
                                    alpha: 1.0f];
    if ([colorName isEqual: @"secondarySelectedControlColor"])
        return [NSColor colorWithSRGBRed: 0.862745f
                                   green: 0.862745f
                                    blue: 0.862745f
                                    alpha: 1.0f];
    if ([colorName isEqual: @"selectedKnobColor"])
        return [NSColor colorWithSRGBRed: 0.40f
                                   green: 0.40f
                                    blue: 0.60f
                                    alpha: 1.0f];

    NSLog(@"missing color for %@", colorName);
    return [NSColor redColor];
}

- (void) _addSystemColor: (NSColor *) result forName: (NSString *) colorName {
    NSColorSetCatalogColor(@"System", colorName, result);
}

- (NSTimeInterval) textCaretBlinkInterval {
    return 0.5;
}

- (void) hideCursor {
    if (!_blankCursor)
        _blankCursor = [[X11Cursor alloc] initBlank];
    [self setCursor: _blankCursor];
}

- (void) unhideCursor {
    NSCursor *current = [NSCursor currentCursor];
    if (current != nil) {
        [current push];
        [current pop];
    } else {
        if (!_defaultCursor)
            _defaultCursor = [[X11Cursor alloc] init];
        [self setCursor: _defaultCursor];
    }
}

// Arrow, IBeam, HorizontalResize, VerticalResize
- (id) cursorWithName: (NSString *) name {
    unsigned int shape = XC_left_ptr;
    const char *xname = "left_ptr";

    if ([name isEqualToString: @"arrowCursor"])
        xname = "left_ptr";
    else if ([name isEqualToString: @"closedHandCursor"])
        xname = "hand3";
    else if ([name isEqualToString: @"crosshairCursor"])
        xname = "crosshair";
    // else if([name isEqualToString:@"disappearingItemCursor"])
    // shape = XC_left_ptr;
    else if ([name isEqualToString: @"IBeamCursor"])
        xname = "xterm";
    else if ([name isEqualToString: @"openHandCursor"])
        xname = "fleur";
    else if ([name isEqualToString: @"pointingHandCursor"])
        xname = "hand";
    else if ([name isEqualToString: @"resizeDownCursor"])
        xname = "bottom_side";
    else if ([name isEqualToString: @"resizeLeftCursor"])
        xname = "left_side";
    else if ([name isEqualToString: @"resizeLeftRightCursor"])
        xname = "h_double_arrow";
    else if ([name isEqualToString: @"resizeRightCursor"])
        xname = "right_side";
    else if ([name isEqualToString: @"resizeUpCursor"])
        xname = "top_side";
    else if ([name isEqualToString: @"resizeUpDownCursor"])
        xname = "v_double_arrow";

    return [[[X11Cursor alloc] initWithName: xname] autorelease];
}

- (id) cursorWithImage: (NSImage *) image hotSpot: (NSPoint) hotSpot {
    return [[[X11Cursor alloc] initWithImage: image
                                    hotPoint: hotSpot] autorelease];
}

- (void) setCursor: (id) cursor {
    CGWindow *window = [[NSApp keyWindow] platformWindow];
    if (window != nil) {
        Window w = [(X11Window *) window windowHandle];
        Cursor c = ((X11Cursor *) cursor).cursor;

        XDefineCursor(_display, w, c);
        XSync(_display, False);
    }
    _cursorHidden = cursor != nil && cursor == _blankCursor;
}

- (void) beep {
    XBell(_display, 100);
}

- (NSSet *) allFontFamilyNames {
    FcPattern *pat = FcPatternCreate();
    FcObjectSet *props = FcObjectSetBuild(FC_FAMILY, NULL);

    FcFontSet *set = FcFontList(O2FontSharedFontConfig(), pat, props);
    NSMutableSet *ret = [NSMutableSet set];

    for (int i = 0; i < set->nfont; i++) {
        FcChar8 *family;
        if (FcPatternGetString(set->fonts[i], FC_FAMILY, 0, &family) ==
            FcResultMatch) {
            [ret addObject: [NSString stringWithUTF8String: (const char *)
                                                                    family]];
        }
    }

    FcPatternDestroy(pat);
    FcObjectSetDestroy(props);
    FcFontSetDestroy(set);
    return ret;
}

- (NSString *) substituteFamilyName: (NSString *) familyName {
    FcConfig *config = O2FontSharedFontConfig();

    FcPattern *pat = FcNameParse((FcChar8 *) [familyName UTF8String]);
    FcConfigSubstitute(config, pat, FcMatchPattern);
    FcDefaultSubstitute(pat);

    FcResult fcResult;
    FcPattern *match = FcFontMatch(config, pat, &fcResult);
    FcPatternDestroy(pat);
    if (match == NULL)
        return NULL;

    FcChar8 *rawRes = NULL;
    FcPatternGetString(match, FC_FAMILY, 0, &rawRes);

    NSString *res = nil;
    if (rawRes != NULL) {
        res = [NSString stringWithUTF8String: (char *) rawRes];
    }

    FcPatternDestroy(match);
    return res;
}

- (NSArray<NSFontTypeface *> *) fontTypefacesForFamilyName:
        (NSString *) familyName
{
    familyName = [self substituteFamilyName: familyName];
    if (familyName == nil) {
        return @[];
    }
    FcPattern *pat = FcPatternCreate();
    FcPatternAddString(pat, FC_FAMILY,
                       (unsigned char *) [familyName UTF8String]);
    FcObjectSet *props = FcObjectSetBuild(FC_FAMILY, FC_STYLE, FC_SLANT,
                                          FC_WIDTH, FC_WEIGHT, NULL);

    FcFontSet *set = FcFontList(O2FontSharedFontConfig(), pat, props);
    NSMutableArray *ret = [NSMutableArray array];

    for (int i = 0; i < set->nfont; i++) {
        FcChar8 *typeface;
        FcPattern *p = set->fonts[i];
        if (FcPatternGetString(p, FC_STYLE, 0, &typeface) == FcResultMatch) {
            NSString *traitName =
                    [NSString stringWithUTF8String: (const char *) typeface];
            FcChar8 *pattern = FcNameUnparse(p);
            NSString *name =
                    [NSString stringWithUTF8String: (const char *) pattern];
            FcStrFree(pattern);

            NSFontTraitMask traits = 0;
            int slant, width, weight;
            FcPatternGetInteger(p, FC_SLANT, FC_SLANT_ROMAN, &slant);
            FcPatternGetInteger(p, FC_WIDTH, FC_WIDTH_NORMAL, &width);
            FcPatternGetInteger(p, FC_WEIGHT, FC_WEIGHT_REGULAR, &weight);

            switch (slant) {
            case FC_SLANT_OBLIQUE:
            case FC_SLANT_ITALIC:
                traits |= NSItalicFontMask;
                break;
            default:
                traits |= NSUnitalicFontMask;
                break;
            }

            if (weight <= FC_WEIGHT_LIGHT)
                traits |= NSUnboldFontMask;
            else if (weight >= FC_WEIGHT_SEMIBOLD)
                traits |= NSBoldFontMask;

            if (width <= FC_WIDTH_SEMICONDENSED)
                traits |= NSNarrowFontMask;
            else if (width >= FC_WIDTH_SEMIEXPANDED)
                traits |= NSExpandedFontMask;

            NSFontTypeface *face =
                    [[NSFontTypeface alloc] initWithName: name
                                               traitName: traitName
                                                  traits: traits];
            [ret addObject: face];
            [face release];
        }
    }

    FcPatternDestroy(pat);
    FcObjectSetDestroy(props);
    FcFontSetDestroy(set);
    return ret;
}

- (CGFloat) scrollerWidth {
    return 15.0;
}

- (CGFloat) doubleClickInterval {
    return 1.0;
}

- (int) runModalPageLayoutWithPrintInfo: (NSPrintInfo *) printInfo {
    NSUnimplementedMethod();
    return 0;
}

- (int) runModalPrintPanelWithPrintInfoDictionary:
        (NSMutableDictionary *) attributes
{
    NSUnimplementedMethod();
    return 0;
}

- (O2Context *) graphicsPortForPrintOperationWithView: (NSView *) view
                                            printInfo: (NSPrintInfo *) printInfo
                                            pageRange: (NSRange) pageRange
{
    NSUnimplementedMethod();
    return nil;
}

- (int) savePanel: (NSSavePanel *) savePanel
        runModalForDirectory: (NSString *) directory
                        file: (NSString *) file
{
    NSUnimplementedMethod();
    return 0;
}

- (int) openPanel: (NSOpenPanel *) openPanel
        runModalForDirectory: (NSString *) directory
                        file: (NSString *) file
                       types: (NSArray *) types
{
    NSUnimplementedMethod();
    return 0;
}

- (BOOL) queryPointerRootX: (int *) x y: (int *) y state: (unsigned int *) state {
    if (_pointerKnown) {
        *x = _pointerRootX;
        *y = _pointerRootY;
        *state = _pointerState;
        return YES;
    }
    // Not known from the event stream: ask the server, and again next time.
    Window root, child;
    int winX, winY;
    return XQueryPointer(_display, DefaultRootWindow(_display), &root, &child,
                         x, y, &winX, &winY, state);
}

// Tracks the pointer from the event stream, so that asking for the mouse
// location, as applications do every frame, costs no round trip while the
// pointer moves over our windows. Motion over other clients' windows is not
// reported, which is why every event that can precede such motion forgets it.
- (void) trackPointerForEvent: (XEvent *) ev {
    switch (ev->type) {
    case MotionNotify:
        _pointerKnown = ev->xmotion.same_screen &&
                ev->xmotion.root == DefaultRootWindow(_display);
        _pointerRootX = ev->xmotion.x_root;
        _pointerRootY = ev->xmotion.y_root;
        _pointerState = ev->xmotion.state;
        break;
    case ButtonPress:
    case ButtonRelease:
    case KeyPress:
    case KeyRelease:
    case EnterNotify:
    case LeaveNotify:
    case FocusIn:
    case FocusOut:
    case KeymapNotify:
        _pointerKnown = NO;
        break;
    default:
        break;
    }
}

- (NSPoint) mouseLocation {
    int root_x = 0, root_y = 0;
    unsigned int mask;

    if (_relativeMouse.active) {
        // The cursor is disassociated: report the frozen (virtual) position, as macOS does.
        root_x = (int) _relativeMouse.virtualX;
        root_y = (int) _relativeMouse.virtualY;
    } else {
        [self queryPointerRootX: &root_x y: &root_y state: &mask];
    }
    // Cocoa's global space, as +[NSEvent mouseLocation] reports on macOS: points,
    // origin at the main monitor's bottom-left corner, y up, so the result can be
    // compared with window and screen frames. CGEventGetLocation() reports the same
    // point in CoreGraphics' y-down space (see CGSConnectionX11).
    // -[X11Window mouseLocationOutsideOfEventStream] is window-local.
    X11Point point = X11PointFromRoot([self primaryFrameInPoints],
                                      (X11Point){root_x, root_y});
    return NSMakePoint(point.x, point.y);
}

- (void) setWindow: (id) window forID: (XID) i {
    if (window)
        [_windowsByID
                setObject: window
                   forKey: [NSNumber
                                   numberWithUnsignedLong: (unsigned long) i]];
    else {
        [_windowsByID removeObjectForKey: [NSNumber numberWithUnsignedLong:
                                                            (unsigned long) i]];

        // if "lastFocusedWindow" is dying, drop it
        //
        // this is an ugly hack because we miss FocusOut events sometimes and
        // retaining the window causes it to keep popping back up endlessly even after dismissing it
        if (lastFocusedWindow && [[lastFocusedWindow platformWindow] windowHandle] == i)
            lastFocusedWindow = nil;
        // The server released a grab on a destroyed window.
        if (_relativeWindow == i)
            [self suspendRelativeMouse];
    }
}

- (id) windowForID: (XID) i {
    return [_windowsByID objectForKey: [NSNumber numberWithUnsignedLong: i]];
}

- (NSEvent *) nextEventMatchingMask: (NSEventMask) mask
                          untilDate: (NSDate *) untilDate
                             inMode: (NSRunLoopMode) mode
                            dequeue: (BOOL) dequeue
{
#ifndef DARLING
    [[NSRunLoop currentRunLoop] addInputSource: _inputSource forMode: mode];
#else
    [self processPendingEvents];
#endif

    NSEvent *result = [super nextEventMatchingMask: mask
                                         untilDate: untilDate
                                            inMode: mode
                                           dequeue: dequeue];

#ifndef DARLING
    [[NSRunLoop currentRunLoop] removeInputSource: _inputSource forMode: mode];
#endif

    return result;
}

- (NSEventModifierFlags) modifierFlagsForState: (unsigned int) state {
    NSEventModifierFlags ret = 0;
    if (state & ShiftMask)
        ret |= NSShiftKeyMask;
    if (state & ControlMask)
        ret |= NSControlKeyMask;
    // if (state & Mod2Mask) // Mod2Mask is numlock
    //   ret |= NSCommandKeyMask;
    if (state & LockMask)
        ret |= NSAlphaShiftKeyMask;
    if (state & Mod4Mask)
        ret |= NSCommandKeyMask;
    if (state & Mod1Mask)
        ret |= NSAlternateKeyMask;
    if (state & Mod5Mask) // AltGr
        ret |= NSFunctionKeyMask;

    return ret;
}

// A modifier key reaches AppKit as an NSFlagsChanged and never as a key down or
// up, so each modifier keysym is mapped to the virtual keycode the event must
// carry and the X mask bit it drives. `toggle` marks the lock keys, whose press
// flips the bit and whose release changes nothing. A carbon keycode of -1 means
// the keysym is not a modifier at all.
typedef struct {
    int carbonKeyCode;
    unsigned int xMask;
    BOOL toggle;
} X11ModifierKey;

static X11ModifierKey modifierKeyForKeysym(KeySym keySym) {
    X11ModifierKey notAModifier = {-1, 0, NO};
    switch (keySym) {
    case XK_Shift_L: return (X11ModifierKey){kVK_Shift, ShiftMask, NO};
    case XK_Shift_R: return (X11ModifierKey){kVK_RightShift, ShiftMask, NO};
    case XK_Control_L: return (X11ModifierKey){kVK_Control, ControlMask, NO};
    case XK_Control_R: return (X11ModifierKey){kVK_RightControl, ControlMask, NO};
    case XK_Alt_L: return (X11ModifierKey){kVK_Option, Mod1Mask, NO};
    case XK_Alt_R: return (X11ModifierKey){kVK_RightOption, Mod1Mask, NO};
    case XK_Super_L: case XK_Meta_L:
        return (X11ModifierKey){kVK_Command, Mod4Mask, NO};
    case XK_Super_R: case XK_Meta_R:
        return (X11ModifierKey){0x36, Mod4Mask, NO};
    case XK_ISO_Level3_Shift: case XK_Mode_switch:
        return (X11ModifierKey){kVK_Function, Mod5Mask, NO};
    case XK_Caps_Lock:
        return (X11ModifierKey){kVK_CapsLock, LockMask, YES};
    case XK_Num_Lock:
        return (X11ModifierKey){kVK_ANSI_KeypadClear, Mod2Mask, NO};
    default: return notAModifier;
    }
}

// The X server fills `state` with the modifier and button state as it was
// *before* the event, so the key's own contribution has to be applied to reach
// the state the event leaves behind. Verified against an Xvfb server: a
// Shift_L press carries state 0 and its release carries ShiftMask.
static unsigned int x11StateAfterKeyEvent(const X11ModifierKey *key,
                                          unsigned int state,
                                          BOOL pressed) {
    if (pressed)
        return key->toggle ? (state ^ key->xMask) : (state | key->xMask);
    if (key->toggle)
        return state;
    return state & ~key->xMask;
}

static BOOL isModifierKeyHeld(const unsigned char *held, unsigned int keycode) {
    return keycode < 256 && (held[keycode / 8] & (1 << (keycode % 8)));
}

static void setModifierKeyHeld(unsigned char *held, unsigned int keycode, BOOL down) {
    if (keycode >= 256)
        return;
    if (down)
        held[keycode / 8] |= 1 << (keycode % 8);
    else
        held[keycode / 8] &= ~(1 << (keycode % 8));
}

// The X masks still driven by held modifier keys other than `keycode`. A key
// event only carries the state from before it, so this is what tells whether
// releasing one Shift key leaves Shift down because the other one is held.
- (unsigned int) maskOfHeldModifierKeysExcept: (unsigned int) keycode {
    unsigned int mask = 0;
    for (unsigned int code = 0; code < 256; code++) {
        if (code == keycode || !isModifierKeyHeld(_heldModifierKeys, code))
            continue;
        X11ModifierKey key = modifierKeyForKeysym(XKeycodeToKeysym(_display, code, 0));
        if (key.carbonKeyCode >= 0 && !key.toggle)
            mask |= key.xMask;
    }
    return mask;
}

// Cocoa has no event for "a modifier's aggregate changed without a key": the
// same flagsChanged carries a sentinel keycode, which is what macOS sends when
// a modifier is released while another app holds the focus and the next key
// event is the first this process sees of the new mask.
- (void) postFlagsChanged: (unsigned short) keyCode
                    flags: (NSEventModifierFlags) flags
                 inWindow: (X11Window *) window {
    NSWindow *delegate = [window delegate];
    if (delegate == nil)
        return;
    [self postEvent: [NSEvent keyEventWithType: NSFlagsChanged
            location: [window mouseLocationOutsideOfEventStream]
            modifierFlags: flags
            timestamp: 0.0
            windowNumber: [delegate windowNumber]
            context: nil
            characters: @""
            charactersIgnoringModifiers: @""
            isARepeat: NO
            keyCode: keyCode]
             atStart: NO];
}

// Every input event carries the modifier state the server holds. A modifier
// that went up while another client had the keyboard, or whose release a
// compositor kept for itself, therefore shows up as a difference here, and
// is reported the way macOS reports it, with a flagsChanged that names no key.
- (void) resyncModifierFlagsWithState: (unsigned int) state
                               window: (X11Window *) window {
    NSEventModifierFlags flags = [self modifierFlagsForState: state];
    if (flags == _modifierFlags)
        return;

    for (unsigned int code = 0; code < 256; code++) {
        if (!isModifierKeyHeld(_heldModifierKeys, code))
            continue;
        X11ModifierKey key = modifierKeyForKeysym(XKeycodeToKeysym(_display, code, 0));
        if (key.carbonKeyCode < 0 || !(state & key.xMask))
            setModifierKeyHeld(_heldModifierKeys, code, NO);
    }

    _modifierFlags = flags;
    [self postFlagsChanged: 0xFFFF flags: flags inWindow: window];
}

// Keys pressed or released while another client had the focus never reached
// us, so on getting the focus back the held keys are read from the server.
- (void) resyncModifierKeysOnFocusIn: (X11Window *) window {
    char keys[32];
    Window root, child;
    int rootX, rootY, winX, winY;
    unsigned int state;

    XQueryKeymap(_display, keys);
    for (unsigned int code = 0; code < 256; code++) {
        BOOL down = (keys[code / 8] & (1 << (code % 8))) != 0;
        X11ModifierKey key = modifierKeyForKeysym(XKeycodeToKeysym(_display, code, 0));
        setModifierKeyHeld(_heldModifierKeys, code,
                           down && key.carbonKeyCode >= 0 && !key.toggle);
    }

    if (XQueryPointer(_display, DefaultRootWindow(_display), &root, &child,
                      &rootX, &rootY, &winX, &winY, &state))
        [self resyncModifierFlagsWithState: state window: window];
}

// Cocoa groups clicks only within its double-click interval and four logical
// points of the preceding press, and only for the same button in the same
// window. Without the button and the window, a left click followed by a right
// click inside the interval was reported as a double click; without the
// distance, a click on a far side of a window was too. The X server's own
// timestamp is used rather than the wall clock, which the client cannot
// compare against a server that may be a different machine, and its unsigned
// subtraction covers the 32-bit wrap.
- (NSInteger) countClickForButton: (unsigned int) button
                                  window: (XID) window
                                   point: (NSPoint) point
                                   time: (Time) time {
    CGFloat dx = point.x - _lastClickPoint.x;
    CGFloat dy = point.y - _lastClickPoint.y;
    if (_lastClickWindow == window && _lastClickButton == button &&
        (uint32_t) (time - _lastClickTime) < [self doubleClickInterval] * 1000 &&
        dx * dx + dy * dy <= 16 && _clickCount < NSIntegerMax)
        _clickCount++;
    else
        _clickCount = 1;
    _lastClickTime = time;
    _lastClickButton = button;
    _lastClickWindow = window;
    _lastClickPoint = point;
    [_buttonClickCounts setObject: @(_clickCount) forKey: @(button)];
    return _clickCount;
}

// Cocoa numbers the mouse buttons in press order from 0 (left), 1 (right) and
// 2 for everything else, so an app reading +[NSEvent buttonNumber] for the
// right button gets 3 and reads the middle button as the right one. X numbers
// them by position instead: 1 left, 3 right, 2 middle.
static NSInteger cocoaButtonNumber(unsigned int xButton) {
    switch (xButton) {
    case Button1: return 0;
    case Button3: return 1;
    case Button2: return 2;
    default:
        // X buttons 4 to 7 are the two wheels and never get here. The extra
        // buttons start at 8 (back) and 9 (forward), which Cocoa numbers 3
        // and 4, right after the middle button.
        return xButton >= 8 ? (NSInteger) xButton - 5 : (NSInteger) xButton;
    }
}

- (NSArray *) orderedWindowNumbers {
    NSMutableArray *result = [NSMutableArray array];

    for (NSWindow *win in [NSApp windows]) {
        [result addObject: @([win windowNumber])];
    }

    NSUnimplementedFunction(); // (Window numbers not even remotely ordered)

    return result;
}

// Xlib names only the first five buttons. 6 and 7 are conventionally the
// horizontal wheel, to the left and to the right.
enum {
    HorizontalScrollLeftButton = 6,
    HorizontalScrollRightButton = 7,
};
// While relative mode is active the cursor is the virtual one, not wherever the
// pointer physically is (it is put back under the cursor after each motion, but a
// click can arrive in between). Returns NO when the server cannot translate.
static BOOL relativeEventPoint(Display *dpy, X11Window *window, const X11RelativeMouse *mouse, NSPoint *point) {
    Window child;
    int winX, winY;
    if (dpy == NULL || window == nil ||
        !XTranslateCoordinates(dpy, DefaultRootWindow(dpy), [window windowHandle], (int) mouse->virtualX,
                               (int) mouse->virtualY, &winX, &winY, &child))
        return NO;
    *point = [window transformPoint: NSMakePoint(winX, winY)];
    return YES;
}

- (void) postXEvent: (XEvent *) ev {
    id event = nil;
    NSEventType type;
    X11Window* window = (X11Window*) [self windowForID: ev->xany.window];

    id delegate = [window delegate];

    // Events another client sent carry whatever state it chose.
    if (!ev->xany.send_event) {
        switch (ev->type) {
        case ButtonPress:
        case ButtonRelease:
            [self resyncModifierFlagsWithState: ev->xbutton.state window: window];
            break;
        case MotionNotify:
            [self resyncModifierFlagsWithState: ev->xmotion.state window: window];
            break;
        case EnterNotify:
        case LeaveNotify:
            [self resyncModifierFlagsWithState: ev->xcrossing.state window: window];
            break;
        }
    }
    [self trackPointerForEvent: ev];

    // Expected warp echoes are among the events queued when the warp was
    // synced; motion ages them itself.
    if (_relativeMouse.active && ev->type != MotionNotify)
        X11RelativeMouseTick(&_relativeMouse);

    switch (ev->type) {
    case KeyPress:
    case KeyRelease:;

        NSEventModifierFlags modifierFlags = [self modifierFlagsForState: ev->xkey.state];
        char buf[20] = {0};
        char *text = buf;
        KeySym keySym = NoSymbol;
        int strLen;

        // Ahead of the input method: a modifier is not text, and an IM filter
        // that swallows it would leave the reported flags permanently stale.
        // The aggregate mask is also corrected here for the same reason, with
        // the keycode macOS uses when no single key is responsible.
        {
            BOOL pressed = ev->type == KeyPress;
            unsigned int keycode = ev->xkey.keycode;
            X11ModifierKey modifier = modifierKeyForKeysym(
                    XKeycodeToKeysym(_display, keycode, 0));
            if (modifier.carbonKeyCode >= 0) {
                // A lock key changes the state on its press only.
                if (modifier.toggle && !pressed)
                    break;
                unsigned int after = x11StateAfterKeyEvent(&modifier, ev->xkey.state, pressed);
                if (!modifier.toggle) {
                    setModifierKeyHeld(_heldModifierKeys, keycode, pressed);
                    // The other key of a pair keeps the mask down.
                    if (!pressed)
                        after |= [self maskOfHeldModifierKeysExcept: keycode] & modifier.xMask;
                }
                _modifierFlags = [self modifierFlagsForState: after];
                [self postFlagsChanged: (unsigned short) modifier.carbonKeyCode
                                 flags: _modifierFlags
                              inWindow: window];
                break; // Modifiers are neither text nor repeatable keys.
            }
            if (!ev->xany.send_event)
                [self resyncModifierFlagsWithState: ev->xkey.state window: window];
        }

        if (XFilterEvent(ev, None)) // XIM processing
            break;

        // A window has no input context when the display couldn't open an input method or
        // XCreateIC() failed, and Xutf8LookupString() dereferences its XIC unconditionally.
        if (ev->type == KeyPress && window != nil && window->_xic != NULL) {
            Status status;
            strLen = Xutf8LookupString(window->_xic, (XKeyPressedEvent *) ev, buf, sizeof(buf) - 1, &keySym, &status);
            if (status == XBufferOverflow) {
                // Composed and input method text can be longer than buf. Nothing was copied and
                // strLen is the size needed; Xlib says to repeat the lookup with a large enough buffer.
                char *larger = malloc(strLen + 1);
                if (larger != NULL) {
                    text = larger;
                    strLen = Xutf8LookupString(window->_xic, (XKeyPressedEvent *) ev, text, strLen, &keySym, &status);
                }
            }
            // The text and keySym are only valid for the statuses that report them.
            if (status != XLookupChars && status != XLookupBoth)
                strLen = 0;
            if (status != XLookupKeySym && status != XLookupBoth)
                keySym = NoSymbol;
            text[strLen] = 0;
        } else {
            // Xutf8LookupString() may not be used with KeyRelease
            strLen = XLookupString((XKeyEvent*) ev, buf, sizeof(buf) - 1, &keySym, NULL);
            buf[strLen] = 0;
        }

        id str = [[NSString alloc] initWithCString: text
                                          encoding: NSUTF8StringEncoding];
        if (text != buf)
            free(text);
        NSPoint pos =
                [window transformPoint: NSMakePoint(ev->xkey.x, ev->xkey.y)];

        uint16_t ucsCode = (uint16_t) X11KeySymToUCS(keySym); // All defined codes in the table fit into 16 bits
        NSString* strIg = [NSString stringWithCharacters: &ucsCode length: 1];

        // The text above retains normal XIM/keyboard modifier behavior.
        // Shortcut characters ignore modifiers other than Shift.
        uint16_t shortcutCode = (uint16_t) X11KeySymToUCS(
                X11KeySymIgnoringModifiers(&ev->xkey));
        strIg = [NSString stringWithCharacters: &shortcutCode length: 1];

        // If there's an app that uses constants from HIToolbox/Events.h (e.g.
        // kVK_ANSI_A), this gives it a chance to work. x11ToCarbon is 256 wide
        // and the protocol's keycode is 8 bits, but the field is a full word.
        const int carbonKeyCode = ev->xkey.keycode < 256
                ? x11ToCarbon[ev->xkey.keycode] : 0;

        BOOL isARepeat = NO;

        if (ev->type == KeyPress) {
            isARepeat = _lastKeySym == keySym;
            _lastKeySym = keySym;
        } else {
            _lastKeySym = 0;
        }

        id event = [NSEvent keyEventWithType: ev->type == KeyPress ? NSKeyDown
                                                                   : NSKeyUp
                                    location: pos
                               modifierFlags: modifierFlags
                                   timestamp: 0.0
                                windowNumber: [delegate windowNumber]
                                     context: nil
                                  characters: str
                 charactersIgnoringModifiers: strIg
                                   isARepeat: isARepeat
                                     keyCode: carbonKeyCode];

        [self postEvent: event atStart: NO];

        [str release];
        break;

    case ButtonPress:;
        pos = [window
                transformPoint: NSMakePoint(ev->xbutton.x, ev->xbutton.y)];
        if (_relativeMouse.active)
            relativeEventPoint(_display, window, &_relativeMouse, &pos);

        // A wheel notch arrives as a press/release pair and belongs to exactly
        // one of them, or the notch scrolls twice. The press carries it: a
        // release the client never sees (a grab, an unmap, focus lost while
        // the button is held) then cannot swallow the scroll, and the press
        // has already been accepted by the server when we get it. A notch is
        // not a click, so it must not touch the click count either.
        if (ev->xbutton.button >= Button4 &&
            ev->xbutton.button <= HorizontalScrollRightButton) {
            // Buttons 4 and 5 are the vertical wheel, 6 and 7 the horizontal
            // one. -[NSView scrollWheel:] adds the delta to the document view's
            // bounds origin, so a positive delta scrolls towards the larger
            // coordinate on both axes: the up and right buttons are positive.
            CGFloat deltaX = 0.0, deltaY = 0.0;
            switch (ev->xbutton.button) {
            case Button4: deltaY = 1.0; break;
            case Button5: deltaY = -1.0; break;
            case HorizontalScrollLeftButton: deltaX = -1.0; break;
            case HorizontalScrollRightButton: deltaX = 1.0; break;
            }
            event = [NSEvent
                    mouseEventWithType: NSScrollWheel
                              location: pos
                         modifierFlags: [self modifierFlagsForState: ev->xbutton
                                                                             .state]
                               window: delegate
                           clickCount: 0
                               deltaX: deltaX
                               deltaY: deltaY];
            [self postEvent: event atStart: NO];
            break;
        }

        switch (ev->xbutton.button) {
        case Button1:
            type = NSLeftMouseDown;
            break;
        case Button3:
            type = NSRightMouseDown;
            break;
        default:
            type = NSOtherMouseDown;
        }

        event = [NSEvent
                mouseEventWithType: type
                          location: pos
                     modifierFlags: [self modifierFlagsForState: ev->xbutton
                                                                         .state]
                            window: delegate
                        clickCount: [self
                                    countClickForButton: ev->xbutton.button
                                                   window: ev->xany.window
                                                    point: pos
                                                    time: ev->xbutton.time]
                            deltaX: 0.0
                            deltaY: 0.0];
        [(NSEvent_mouse *) event
                _setButtonNumber: cocoaButtonNumber(ev->xbutton.button)];
        [self postEvent: event atStart: NO];
        break;

    case ButtonRelease:;
        // The wheel's other half of the pair; the press already scrolled.
        if (ev->xbutton.button >= Button4 &&
            ev->xbutton.button <= HorizontalScrollRightButton)
            break;

        pos = [window
                transformPoint: NSMakePoint(ev->xbutton.x, ev->xbutton.y)];
        if (_relativeMouse.active)
            relativeEventPoint(_display, window, &_relativeMouse, &pos);

        // The up of a click reports the count its down was given, so that a
        // double click's two downs are matched by their own ups. A release
        // with no press behind it (the app attached mid-drag) is a single
        // click: Cocoa never reports an up with a count of zero.
        NSNumber *upCount = [_buttonClickCounts objectForKey: @(ev->xbutton.button)];
        [_buttonClickCounts removeObjectForKey: @(ev->xbutton.button)];

        switch (ev->xbutton.button) {
        case Button1:
            type = NSLeftMouseUp;
            break;
        case Button3:
            type = NSRightMouseUp;
            break;
        default:
            type = NSOtherMouseUp;
        }

        event = [NSEvent
                mouseEventWithType: type
                          location: pos
                     modifierFlags: [self modifierFlagsForState: ev->xbutton
                                                                         .state]
                            window: delegate
                        clickCount: upCount ? [upCount integerValue] : 1
                            deltaX: 0.0
                            deltaY: 0.0];
        [(NSEvent_mouse *) event
                _setButtonNumber: cocoaButtonNumber(ev->xbutton.button)];
        [self postEvent: event atStart: NO];
        break;

    case MotionNotify:; {
            // NSLog(@"MotionNotify, x=%d, y=%d, xroot=%d, yroot=%d\n",
            // ev->xmotion.x, ev->xmotion.y, ev->xmotion.x_root,
            // ev->xmotion.y_root);

            CGPoint lastMotionPos = [window mouseLocationOutsideOfEventStream];
            pos = [window
                    transformPoint: NSMakePoint(ev->xmotion.x, ev->xmotion.y)];

            CGFloat deltaX, deltaY;

            if (_relativeMouse.active) {
                // The cursor is disassociated: physical motion only produces
                // deltas, the event reports the frozen cursor, and the pointer is
                // put back under it where the server honours warps. A warp's own
                // echo is not motion.
                bool recorded;
                X11RelativeMouseMotion relative = X11RelativeMouseMotionEvent(
                        _display, &_relativeMouse, &ev->xmotion,
                        [self warpsHonoured], &recorded);
                // An echo that could not be recorded would be taken for input.
                if (!recorded)
                    [self suspendRelativeMouse];
                if (!relative.post)
                    break;
                deltaX = relative.deltaX;
                deltaY = relative.deltaY;
                // The window's origin in root coordinates is (x_root - x, y_root - y).
                pos = [window transformPoint: NSMakePoint(
                        _relativeMouse.virtualX - (ev->xmotion.x_root - ev->xmotion.x),
                        _relativeMouse.virtualY - (ev->xmotion.y_root - ev->xmotion.y))];
            } else {
                // Mouse deltas are in screen orientation, y growing downwards
                // (as CGEvent's kCGMouseEventDeltaY), while pos is window-local
                // with y growing upwards; relative mode reports root deltas,
                // which already grow downwards.
                deltaX = pos.x - lastMotionPos.x;
                deltaY = lastMotionPos.y - pos.y;
            }
            [window setLastKnownCursorPosition: pos];

            // X11 numbers the right button 3 (Button3Mask); Button2Mask is
            // the middle button, whose drags are other-mouse drags.
            type = NSMouseMoved;

            if (ev->xmotion.state & Button1Mask) {
                type = NSLeftMouseDragged;
            } else if (ev->xmotion.state & Button3Mask) {
                type = NSRightMouseDragged;
            } else if (ev->xmotion.state & Button2Mask) {
                type = NSOtherMouseDragged;
            }

            // The pointer moved: a cursor hidden until then comes back, even
            // when the application does not want the mouse-moved event.
            [self pointerMoved];
            if (type == NSMouseMoved && ![delegate acceptsMouseMovedEvents])
                break;

            // Posting a drag discards the queued drags before it, and in
            // relative mode their deltas are all the application gets.
            if (_relativeMouse.active && type == NSLeftMouseDragged) {
                for (NSEvent *queued in _eventQueue) {
                    if ([queued type] == type) {
                        deltaX += [queued deltaX];
                        deltaY += [queued deltaY];
                    }
                }
            }

            event = [NSEvent
                    mouseEventWithType: type
                              location: pos
                         modifierFlags:
                                 [self modifierFlagsForState: ev->xmotion.state]
                                window: delegate
                            clickCount: 1
                                deltaX: deltaX
                                deltaY: deltaY];
            [self postEvent: event atStart: NO];
            [self discardEventsMatchingMask: NSLeftMouseDraggedMask
                                beforeEvent: event];

            [delegate platformWindowSetCursorEvent: window];
            break;
        }

    case EnterNotify:
        NSLog(@"EnterNotify");
        if (!_relativeMouse.active)
            [window setLastKnownCursorPosition:
                            [window transformPoint: NSMakePoint(
                                                            ev->xcrossing.x,
                                                            ev->xcrossing.y)]];
        break;

    case LeaveNotify:
        NSLog(@"LeaveNotify");
        break;

    case FocusIn:
        NSLog(@"FocusIn");
        // The server can still report FocusIn (detail NotifyPointer) for a
        // window we have unmapped; an ordered-out window must not become key.
        if (window != nil && ![window isMapped])
            break;
        if ([delegate attachedSheet]) {
            [[delegate attachedSheet] makeKeyAndOrderFront: delegate];
            break;
        }
        if (lastFocusedWindow) {
            [lastFocusedWindow platformWindowDeactivated: window
                                 checkForAppDeactivation: NO];
            lastFocusedWindow = nil;
        }
        if (window != nil)
            window->_receivingFocus = YES;
        [delegate platformWindowActivated: window displayIfNeeded: YES];
        if (window != nil)
            window->_receivingFocus = NO;
        lastFocusedWindow = delegate;
        if (window != nil)
            XSetICFocus(window->_xic);
        [self resyncModifierKeysOnFocusIn: window];
        // Losing the focus released the pointer grab; the application still
        // wants relative mode.
        if (_relativeRequested && !_relativeMouse.active)
            [self beginRelativeMouse];
        break;

    case FocusOut:
        NSLog(@"FocusOut");
        [delegate platformWindowDeactivated: window
                    checkForAppDeactivation: NO];
        lastFocusedWindow = nil;
        // Give the pointer back to other clients; relative mode stays requested
        // and resumes on FocusIn. A grab transition or the pointer crossing a
        // child leaves the focus where it was.
        if (ev->xfocus.mode != NotifyGrab && ev->xfocus.mode != NotifyUngrab &&
            ev->xfocus.detail != NotifyPointer &&
            ev->xfocus.detail != NotifyInferior)
            [self suspendRelativeMouse];
        // Unlike XSetICFocus(), XUnsetICFocus() doesn't accept a NULL XIC.
        if (window != nil && window->_xic != NULL)
            XUnsetICFocus(window->_xic);
        break;

    case KeymapNotify:
        NSLog(@"KeymapNotify");
        break;

    case Expose:;
        O2Rect rect = NSMakeRect(ev->xexpose.x, ev->xexpose.y,
                                 ev->xexpose.width, ev->xexpose.height);

        rect.origin.y =
                [window frame].size.height - rect.origin.y - rect.size.height;
        // rect=NSInsetRect(rect, -10, -10);
        // [_backingContext addToDirtyRect:rect];
        if (ev->xexpose.count == 0)
            [window flushBuffer];

        [delegate platformWindowExposed: window inRect: rect];
        break;

    case GraphicsExpose:
        NSLog(@"GraphicsExpose");
        break;

    case NoExpose:
        NSLog(@"NoExpose");
        break;

    case VisibilityNotify:
        NSLog(@"VisibilityNotify");
        break;

    case CreateNotify:
        NSLog(@"CreateNotify");
        break;

    case DestroyNotify:;
        // we should never get this message before the WM_DELETE_WINDOW
        // ClientNotify so normally, window should be nil here.
        [window invalidate];
        break;

    case UnmapNotify:
        NSLog(@"UnmapNotify");
        // The server released a grab whose window became unviewable.
        if (ev->xany.window == _relativeWindow)
            [self suspendRelativeMouse];
        break;

    case MapNotify:
        NSLog(@"MapNotify");
        [window mapNotified];
        break;

    case MapRequest:
        NSLog(@"MapRequest");
        break;

    case ReparentNotify:
        NSLog(@"ReparentNotify");
        break;

    case ConfigureNotify:
        if (_relativeMouse.active && ev->xconfigure.window == _relativeWindow)
            [self resnapshotRelativeMouse];
        [window frameChanged];
        [delegate platformWindow: window
                    frameChanged: [window frame]
                         didSize: YES];
        break;

    case ConfigureRequest:
        NSLog(@"ConfigureRequest");
        break;

    case GravityNotify:
        NSLog(@"GravityNotify");
        break;

    case ResizeRequest:
        NSLog(@"ResizeRequest");
        break;

    case CirculateNotify:
        NSLog(@"CirculateNotify");
        break;

    case CirculateRequest:
        NSLog(@"CirculateRequest");
        break;

    case PropertyNotify:
        if ([window respondsToSelector: @selector(propertyNotify:)]) {
            [window propertyNotify: &ev->xproperty];
        }
        // An INCR transfer a pasteboard serves is paced by the requestor
        // deleting a property on its own window, usually another client's,
        // which therefore is not in the window map.
        if (ev->xproperty.state == PropertyDelete &&
            (window == nil || [window isKindOfClass: [X11Pasteboard class]]))
            [X11Pasteboard dispatchPropertyNotify: &ev->xproperty];
        break;

    case SelectionClear:
        if ([window respondsToSelector: @selector(selectionClear:)]) {
            [window selectionClear: &ev->xselectionclear];
        }
        break;

    case SelectionRequest:
        if ([window respondsToSelector: @selector(selectionRequest:)]) {
            [window selectionRequest: &ev->xselectionrequest];
        }
        break;

    case SelectionNotify:
        if ([window respondsToSelector: @selector(selectionNotify:)]) {
            [window selectionNotify: &ev->xselection];
        }
        break;

    case ColormapNotify:
        NSLog(@"ColormapNotify");
        break;

    case ClientMessage:
        if (ev->xclient.format == 32 &&
            ev->xclient.data.l[0] ==
                    XInternAtom(_display, "WM_DELETE_WINDOW", False)) {
            NSLog(@"ClientMessage:WM_DELETE_WINDOW");
            [[NSRunLoop currentRunLoop] cancelPerformSelector: @selector(platformWindowWillClose:)
                                                       target: delegate
                                                     argument: window];
            [[NSRunLoop currentRunLoop] performSelector: @selector(platformWindowWillClose:)
                                                 target: delegate
                                               argument: window
                                                  order: 0
                                                  modes: @[
                                                        NSDefaultRunLoopMode, NSModalPanelRunLoopMode,
                                                        NSEventTrackingRunLoopMode
                                                    ]];
        }
        break;

    case MappingNotify:
        NSLog(@"MappingNotify");
        // Xlib caches the keyboard and modifier mappings, and the client has
        // to tell it when they change, or XLookupString() and
        // XKeycodeToKeysym() keep answering for the old layout.
        if (ev->xmapping.request == MappingKeyboard ||
            ev->xmapping.request == MappingModifier)
            XRefreshKeyboardMapping(&ev->xmapping);
        break;

    case GenericEvent:
        NSLog(@"GenericEvent");
        break;

    default:
        // RandR reports layout changes as plain extension events (see X11RandR.h).
        if (X11RandRHandleLayoutChange(ev, _rrEventBase)) {
            [self _invalidateRRCache];
            break;
        }
        NSLog(@"Unknown X11 event type %i", ev->type);
        break;
    }
}

#ifndef DARLING
- (void) selectInputSource: (NSSelectInputSource *) inputSource
               selectEvent: (NSUInteger) selectEvent
{
#else
- (void) processPendingEvents {
#endif
    int numEvents;

    while ((numEvents = XPending(_display)) > 0) {
        XEvent e;
        int error;

        if ((error = XNextEvent(_display, &e)) != 0)
            NSLog(@"XNextEvent returned %d", error);
        else
            [self postXEvent: &e];
    }
}

- (int) handleError: (XErrorEvent *) errorEvent {
    NSLog(@"************** X11 ERROR!");
    NSLog(@"Request code: %d:%d", errorEvent->request_code,
          errorEvent->minor_code);
    NSLog(@"Error code: %d", errorEvent->error_code);
    return 0;
}

void CGNativeBorderFrameWidthsForStyle(NSUInteger styleMask, CGFloat *top,
                                       CGFloat *left, CGFloat *bottom,
                                       CGFloat *right)
{
    *top = 0.0;
    *left = 0.0;
    *bottom = 0.0;
    *right = 0.0;
}

- (CGRect) insetRect: (CGRect) frame
        forNativeWindowBorderWithStyle: (NSUInteger) styleMask
{
    CGFloat top, left, bottom, right;

    CGNativeBorderFrameWidthsForStyle(styleMask, &top, &left, &bottom, &right);

    frame.origin.x += left;
    frame.origin.y += bottom;
    frame.size.width -= left + right;
    frame.size.height -= top + bottom;

    return frame;
}

- (CGRect) outsetRect: (CGRect) frame
        forNativeWindowBorderWithStyle: (NSUInteger) styleMask
{
    CGFloat top, left, bottom, right;

    CGNativeBorderFrameWidthsForStyle(styleMask, &top, &left, &bottom, &right);

    frame.origin.x -= left;
    frame.origin.y -= bottom;
    frame.size.width += left + right;
    frame.size.height += top + bottom;

    return frame;
}

// Takes CoreGraphics global points (origin at the main monitor's top-left corner,
// y down): CGWarpMouseCursorPosition hands its argument straight through, and on
// macOS that API is documented in that space. Internal callers that hold a root
// point convert it with -cgPointFromRoot:.
//
// The relative-mode state and Xlib are only used from the main thread (the one that
// pumps X events), and CGWarpMouseCursorPosition may be called from any thread, so a
// call from another thread is handed over. The warp produces no delta, so the caller
// need not wait.
- (void) warpMouse: (NSPoint) position {
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread: @selector(warpMouseOnMainThread:)
                               withObject: [NSValue valueWithPoint: position]
                            waitUntilDone: NO];
        return;
    }
    [self warpMouseOnMainThread: [NSValue valueWithPoint: position]];
}

- (void) warpMouseOnMainThread: (NSValue *) target {
    NSPoint position = [target pointValue];
    _pointerKnown = NO;
    X11Point root = X11CGPointToRoot([self primaryFrameInPoints],
                                     (X11Point){position.x, position.y});
    int root_x = (int) round(root.x);
    int root_y = (int) round(root.y);

    if (_relativeMouse.active) {
        // CGWarpMouseCursorPosition moves the disassociated cursor without
        // producing a delta; the warp's echo is dropped.
        if (!X11RelativeMouseApplicationWarp(_display, &_relativeMouse, root_x,
                                             root_y, [self warpsHonoured]))
            [self suspendRelativeMouse];
        return;
    }

    XWarpPointer(_display, None, DefaultRootWindow(_display), 0, 0, 0, 0,
                 root_x, root_y);
    XSync(_display, False);
    if (_relativeRequested) {
        // Suspended (focus lost, retry pending): the next grab must resume at
        // the application's target, not at the cursor frozen before.
        _relativeResumeValid = YES;
        _relativeResumeX = root_x;
        _relativeResumeY = root_y;
    }
}

- (BOOL) warpsHonoured {
    return !_isXwayland || _cursorHidden;
}

// Takes the relative-mode pointer grab on the key (else main, else first
// visible) window, starting the virtual cursor at the current pointer position.
// Without the keyboard focus nothing is grabbed (a grab would take the pointer
// from whichever client has it); FocusIn retries the preserved request.
- (void) beginRelativeMouse {
    NSWindow *nswin = [NSApp keyWindow];
    if (!nswin)
        nswin = [NSApp mainWindow];
    if (!nswin) {
        NSArray *windows = [NSApp windows];
        for (NSWindow *w in windows) {
            if ([w isVisible]) {
                nswin = w;
                break;
            }
        }
        if (!nswin && [windows count] > 0)
            nswin = [windows objectAtIndex: 0];
    }

    X11Window *xwin = (X11Window *) [nswin platformWindow];
    Window win = xwin ? [xwin windowHandle] : None;
    if (win == None) {
        NSLog(@"Relative mouse mode: no window to grab the pointer for\n");
        return;
    }
    if (_relativeMouse.active && _relativeWindow == win)
        return;
    [self suspendRelativeMouse];
    _pointerKnown = NO;

    int result = X11RelativeMouseGrab(_display, &_relativeMouse, win,
                                      [self warpsHonoured]);
    if (result == X11_RELATIVE_MOUSE_NOT_FOCUSED)
        return;
    if (result != GrabSuccess) {
        NSLog(@"XGrabPointer() failed with error %d for window %lu\n", result, win);
        return;
    }
    NSLog(@"XGrabPointer() succeeded for window %lu\n", win);
    _relativeWindow = win;
    if (_relativeResumeValid) {
        // The cursor stays where it froze, not where the pointer is now.
        X11RelativeMouseRestoreCursor(&_relativeMouse, _relativeResumeX,
                                      _relativeResumeY);
        _relativeResumeValid = NO;
    }

    // Absolute motion after the release is measured from where the cursor froze.
    Window child;
    int windowX, windowY;
    if (XTranslateCoordinates(_display, DefaultRootWindow(_display), win,
                              (int) _relativeMouse.virtualX,
                              (int) _relativeMouse.virtualY, &windowX, &windowY,
                              &child))
        [xwin setLastKnownCursorPosition:
                        [xwin transformPoint: NSMakePoint(windowX, windowY)]];
}

// A reconfiguration (the grab window moved or resized, the screen layout
// changed) can move a confined pointer by itself and changes where it can go:
// take a new snapshot and drop the old geometry's pending motion. The new grab
// can fail while the window manager is mid-operation (AlreadyGrabbed, or the
// focus check during a fullscreen transition) and FocusIn may never follow, so
// a failure is retried for a while.
- (void) resnapshotRelativeMouse {
    if (!_relativeMouse.active)
        return;
    [self suspendRelativeMouse];
    [self beginRelativeMouse];
    if (_relativeRequested && !_relativeMouse.active)
        [self scheduleRelativeMouseRetry];
}

- (void) scheduleRelativeMouseRetry {
    _relativeRetriesLeft = 10;
    [NSObject cancelPreviousPerformRequestsWithTarget: self
                                             selector: @selector(retryRelativeMouse)
                                               object: nil];
    [self performSelector: @selector(retryRelativeMouse)
               withObject: nil
               afterDelay: 0.1];
}

- (void) retryRelativeMouse {
    if (!_relativeRequested || _relativeMouse.active)
        return;
    [self beginRelativeMouse];
    if (_relativeRequested && !_relativeMouse.active && --_relativeRetriesLeft > 0)
        [self performSelector: @selector(retryRelativeMouse)
                   withObject: nil
                   afterDelay: 0.1];
}

// Releases the grab without cancelling the request (focus loss, window gone).
- (void) suspendRelativeMouse {
    if (!_relativeMouse.active)
        return;
    _pointerKnown = NO;
    _relativeResumeValid = YES;
    _relativeResumeX = _relativeMouse.virtualX;
    _relativeResumeY = _relativeMouse.virtualY;
    X11RelativeMouseRelease(_display, &_relativeMouse);
    _relativeWindow = None;
}

// CGAssociateMouseAndMouseCursorPosition(!doGrab).
- (void) grabMouse: (BOOL) doGrab {
    // Main thread only, like -warpMouse:.
    if (![NSThread isMainThread]) {
        [self performSelectorOnMainThread: @selector(grabMouseOnMainThread:)
                               withObject: [NSNumber numberWithBool: doGrab]
                            waitUntilDone: NO];
        return;
    }
    [self grabMouseOnMainThread: [NSNumber numberWithBool: doGrab]];
}

- (void) grabMouseOnMainThread: (NSNumber *) wanted {
    BOOL doGrab = [wanted boolValue];
    if (doGrab) {
        _relativeRequested = YES;
        [self beginRelativeMouse];
        // A failed first grab (AlreadyGrabbed while a window manager holds the
        // pointer) is retried for a while, like one after a reconfiguration.
        if (!_relativeMouse.active)
            [self scheduleRelativeMouseRetry];
    } else {
        _relativeRequested = NO;
        [self suspendRelativeMouse];
        _relativeResumeValid = NO;
    }
    XSync(_display, False);
}

@end

#import <AppKit/NSGraphicsStyle.h>

@implementation NSGraphicsStyle (Overrides)
- (void) drawMenuBranchArrowInRect: (NSRect) rect selected: (BOOL) selected {
    NSImage *arrow = [NSImage imageNamed: @"NSMenuArrow"];
    // ??? magic numbers
    rect.origin.y += 5;
    rect.origin.x -= 2;
    [arrow drawInRect: rect
             fromRect: NSZeroRect
            operation: NSCompositeSourceOver
             fraction: 1.0];
}

@end
