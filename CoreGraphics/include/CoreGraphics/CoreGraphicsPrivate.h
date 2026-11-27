#ifndef COREGRAPHICSPRIVATE_H
#define COREGRAPHICSPRIVATE_H
#include <CoreGraphics/CoreGraphics.h>
#include <IOKit/hidsystem/IOLLEvent.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_types.h>
#include <CoreGraphics/CGSServerSPI.h>

__BEGIN_DECLS

// References:
// https://github.com/koekeishiya/cglwindow/blob/master/src/cgl_window.c
// https://sourceforge.net/p/xnntp/SVN_Xnntp/1/tree/CGSPrivate.h

typedef int CGSSurfaceID;
typedef unsigned long CGSNotificationType;
typedef CFMutableDictionaryRef CGSDictionaryObj;
typedef CFTypeRef CGSRegionRef;

#define CGSDefaultConnection _CGSDefaultConnection()

enum
{
	kCGSErrorSuccess = 0,
};

typedef enum {
	kCGSOrderBelow = -1,
	kCGSOrderOut, /* hides the window */
	kCGSOrderAbove,
	kCGSOrderIn /* shows the window */
} CGSWindowOrderingMode;


typedef enum {
   kCGSBackingNonRetianed,
   kCGSBackingRetained,
   kCGSBackingBuffered,
} CGSBackingType;

extern void CGSInitialize(void);
extern CGError CGSNewConnection(_Nullable CGSDictionaryObj attribs, CGSConnectionID* connId);
extern CGError CGSReleaseConnection(CGSConnectionID connId);
extern CGSConnectionID _CGSDefaultConnection(void);
extern CGError CGSSetDenyWindowServerConnections(Boolean deny);
// Whether CGSSetDenyWindowServerConnections() denied the process connections to the window system.
extern Boolean _CGSWindowServerConnectionsDenied(void);
extern void CGSShutdownServerConnections(void);

// CGSRegion
extern CGError CGSNewRegionWithRect(const CGRect * rect, CGSRegionRef *newRegion);
extern void CGSRegionRelease(CGSRegionRef reg);
extern void CGSRegionRetain(CGSRegionRef reg);
extern void CGSRegionToRect(CGSRegionRef reg, CGRect* rect); // This is non-standard. We should support non-rectangular regions instead
extern bool CGSRegionIsRectangular(CGSRegionRef reg);

// CGRegion (the same region objects as CGSRegion)
typedef CGSRegionRef CGRegionRef;
extern CGRegionRef CGRegionCreateWithRect(CGRect rect);
extern void CGRegionRelease(CGRegionRef region);

// Global hot keys. Prototypes as in the CGSHotKeys.h of CGSInternal
// (https://github.com/NUIKit/CGSInternal, MIT license), declared here independently.
// The meaning of the arguments is not documented; what is implemented is inferred:
// uid is chosen by the caller and names the hot key, key is the virtual key code,
// options is ignored (the character the key produces, perhaps), modifierFlags are
// CGEventFlags modifier bits, exclusion is ignored. The setters return nothing, so a hot key
// that could not be set up (another client holds the combination) shows as
// CGSGetHotKey() returning false.
// A hot key's presses and releases are delivered as the window server does it: as events of
// type NX_SYSDEFINED, here to the procs registered with CGSRegisterNotifyProc() for
// CGSNotificationSingleEventType(NX_SYSDEFINED) (or kCGSNotificationAllEvents); the data is a
// CGSEventRecord whose data.compound.subType is kCGSHotKeyPressedSubtype or
// kCGSHotKeyReleasedSubtype, whose data.compound.misc.L[0] is the uid, and whose flags,
// location and time are those of the key event. The same event, made with
// CGEventCreateWithEventRecord(), goes through the event taps into the event stream of the process
// (_CGSEventStreamPost), where HIToolbox reads it; AppKit gets it from HIToolbox's queue as an
// NSEvent of type NSSystemDefined and hands it back to HIToolbox in -[NSApplication sendEvent:].
// QUIRK: system-defined subtype 6 is a hot key press, 9 a release, and the event's data1 names
// the hot key (the uid given when it was set). Not documented. Evidence: public write-ups of
// the observed event (The Register, 2009, https://www.theregister.co.uk/2009/02/24/hotkeys_framework2/;
// cocoa-dev 2011-10, https://lists.apple.com/archives/cocoa-dev/2011/Oct/msg00526.html, data1 is the
// hot key; cocoa-dev 2009-09, https://lists.apple.com/archives/cocoa-dev/2009/Sep/msg01824.html, on
// 64-bit data1 is not the EventHotKeyRef), tier 4. What data1 holds on 64-bit macOS is not verified;
// the uid is inference.
// Test: tests/src/carbon_hotkeys_appkit.m (subtype and data1 seen in -sendEvent:).
enum
{
	kCGSHotKeyPressedSubtype = 6,
	kCGSHotKeyReleasedSubtype = 9,
};
typedef uint32_t CGSModifierFlags;
extern void CGSSetHotKeyWithExclusion(CGSConnectionID cid, int uid, uint16_t options, uint16_t key, CGSModifierFlags modifierFlags, int exclusion);
extern void CGSSetHotKey(CGSConnectionID cid, int uid, uint16_t options, uint16_t key, CGSModifierFlags modifierFlags);
extern bool CGSGetHotKey(CGSConnectionID cid, int uid, uint16_t* options, uint16_t* key, CGSModifierFlags* modifierFlags);
extern void CGSRemoveHotKey(CGSConnectionID cid, int uid);
extern bool CGSIsHotKeyEnabled(CGSConnectionID cid, int uid);
extern void CGSSetHotKeyEnabled(CGSConnectionID cid, int uid, bool enabled);
extern CGError CGSGetGlobalHotKeyOperatingMode(CGSConnectionID cid, int* mode);
extern CGError CGSSetGlobalHotKeyOperatingMode(CGSConnectionID cid, int mode);

// Symbolic hot keys: the numbered system-wide shortcuts (Spotlight, Mission Control ...).
// State is kept in the com.apple.symbolichotkeys preference domain; nothing acts on it in
// Darling. A value is the key equivalent character (0xFFFF for none), the virtual key code
// and CGEventFlags modifier bits. Unknown numbers give kCGErrorRangeCheck from the getter.
extern bool CGSIsSymbolicHotKeyEnabled(int number);
extern CGError CGSSetSymbolicHotKeyEnabled(int number, bool enabled);
extern CGError CGSGetSymbolicHotKeyValue(int number, uint16_t* keyEquivalent, uint16_t* keyCode, CGSModifierFlags* modifiers);
extern CGError CGSSetSymbolicHotKeyValue(int number, uint16_t keyEquivalent, uint16_t keyCode, CGSModifierFlags modifiers);


extern CGError CGSNewWindow(CGSConnectionID conn, CFIndex flags, float, float, const CGSRegionRef region, CGSWindowID* windowID);
extern CGError CGSReleaseWindow(CGSConnectionID cid, CGSWindowID wid);

extern CGError CGSSetWindowShape(CGSConnectionID cid, CGSWindowID wid, float x_offset, float y_offset, const CGSRegionRef shape);
extern OSStatus CGSOrderWindow(CGSConnectionID cid, CGSWindowID wid, CGSWindowOrderingMode place, CGSWindowID relativeToWindow);
extern CGError CGSMoveWindow(CGSConnectionID cid, CGSWindowID wid, const CGPoint *window_pos);
// The pixels and the events of a CGS window, for a process that has no UI framework of its own above
// CoreGraphics (the Window Manager of HIToolbox). See -[CGSWindow drawImage:atPoint:].
// Replaces the part of the window's contents the image covers (top left origin, y down) and shows it.
extern CGError _CGSWindowDrawImage(CGSConnectionID cid, CGSWindowID wid, CGImageRef image, CGPoint origin);
// A snapshot of the window's contents, NULL for none.
extern CGImageRef _CGSWindowCopyContents(CGSConnectionID cid, CGSWindowID wid);
// Style bits of a window
enum {
	kCGSWindowStyleFloating = 1 << 0,     // stays above the ordinary windows
	kCGSWindowStyleUtility = 1 << 1,      // a tool window: not in the task lists
	kCGSWindowStyleBorderless = 1 << 2,   // no title bar and frame of the window system
	kCGSWindowStyleIgnoresMouse = 1 << 3, // pointer input goes to the windows below
	kCGSWindowStyleTransparent = 1 << 4,  // the pixels' alpha shows what is below
	kCGSWindowStyleFixedSize = 1 << 5,    // the user cannot resize it
	kCGSWindowStyleNoFocus = 1 << 6,      // never takes the keyboard focus
	kCGSWindowStyleNoClose = 1 << 7,      // the window system offers no close control
	kCGSWindowStyleUnmanaged = 1 << 8,    // the window system neither places nor decorates it
};
extern CGError _CGSWindowSetStyle(CGSConnectionID cid, CGSWindowID wid, uint32_t styleFlags);

// What the window system tells about the windows, on the thread that runs the main run loop.
// kCGSWindowEventBounds: the window's content rectangle in global coordinates (y down) changed.
typedef enum {
	kCGSWindowEventCloseRequested = 1, // the user asked the window system to close the window
	kCGSWindowEventActivated = 2,      // the window got the keyboard focus
	kCGSWindowEventDeactivated = 3,    // the window lost it
	kCGSWindowEventBounds = 4,
} CGSWindowEventKind;
typedef void (*CGSWindowEventProc)(CGSWindowEventKind kind, CGSWindowID window, CGRect rect, void* info);
// Sets the process' one handler of the window events (NULL removes it).
extern void _CGSSetWindowEventProc(CGSWindowEventProc proc, void* info);
// For the backends: reports a window event to that handler.
extern void _CGSPostWindowEvent(CGSWindowEventKind kind, CGSWindowID window, CGRect rect);

// What a toplevel window of an application's UI layer is made with (see
// -[CGSConnection newToplevelWindowWithAttributes:]).
typedef struct {
	// The window's frame in the application's global space: points, the origin at the bottom left of the
	// main display, y up (the space of NSWindow frames).
	CGRect frame;
	// The window system's manager neither places, decorates nor gives the focus to the window (menus,
	// pop-ups, sheets).
	bool unmanaged;
	// What is behind the window shows through the alpha of its pixels. Not every window system can do
	// this (see -[CGSConnection supportsTranslucentToplevels]); then the window is opaque.
	bool translucent;
} CGSToplevelAttributes;

extern CGError CGSSetWindowOpacity(CGSConnectionID cid, CGSWindowID wid, bool isOpaque);
extern CGError CGSSetWindowLevel(CGSConnectionID cid, CGSWindowID wid, CGWindowLevel level);
extern CGError CGSSetWindowTransform(CGSConnectionID cid, CGSWindowID wid, CGAffineTransform transform);
extern CGError CGSSetWindowWarp(CGSConnectionID cid, CGSWindowID wid, int w, int h, float *mesh);
extern CGError CGSSetWindowCaptureExcludeShape(CGSConnectionID cid, CGSWindowID wid, CGRegionRef shape);

// Window transforms. Argument layout as applications call these functions:
// two 32-bit values (a placement selector and a reserved value; both 0 in
// practice) come before the transform, which is passed by value.
extern CGError CGSSetWindowTransformAtPlacement(CGSConnectionID cid, CGSWindowID wid, int32_t placement, int32_t reserved, CGAffineTransform transform);
extern CGError CGSGetWindowTransformAtPlacement(CGSConnectionID cid, CGSWindowID wid, int32_t placement, void *reserved, CGAffineTransform *outTransform);

// Queried window server state; 0 means the server is running normally.
extern int CGSServerOperationState(int state);

// Subwindows (for CGL)
extern CGError CGSAddSurface(CGSConnectionID cid, CGSWindowID wid, CGSSurfaceID *sid);
extern CGError CGSRemoveSurface(CGSConnectionID cid, CGSWindowID wid, CGSSurfaceID sid);
extern CGError CGSSetSurfaceBounds(CGSConnectionID cid, CGSWindowID wid, CGSSurfaceID sid, CGRect rect);
extern CGError CGSGetSurfaceBounds(CGSConnectionID cid, CGSWindowID wid, CGSSurfaceID sid, CGRect *outBounds);
extern CGError CGSGetWindowBounds(CGSConnectionID cid, CGSWindowID wid, CGRect *outBounds);
// Shows the cursor and forgets all pending counted hides. Returns nothing.
extern void CGSForceShowCursor(CGSConnectionID cid);
// The image and hot spot of a registered cursor; NULL when there is none.
extern CGImageRef CGSCreateRegisteredCursorImage(CGSConnectionID cid, const char *cursorName, CGPoint *outHotspot);
extern CGError CGSOrderSurface(CGSConnectionID cid, CGSWindowID wid, CGSSurfaceID sid, int a, int b);
//extern CGLError CGLSetSurface(CGLContextObj gl, CGSConnectionID cid, CGSWindowID wid, CGSSurfaceID sid); // in CGL

//extern CGContextRef CGWindowContextCreate(CGSConnectionID cid, CGSWindowID wid, CFDictionaryRef options); // in CGL

extern CGError CGSSetWindowTags(CGSConnectionID cid, CGSWindowID wid, const int tags[2], size_t tag_size);
extern CGError CGSClearWindowTags(CGSConnectionID cid, CGSWindowID wid, const int tags[2], size_t tag_size);
extern CGError CGSAddActivationRegion(CGSConnectionID cid, CGSWindowID wid, CGSRegionRef region);
extern CGError CGSClearActivationRegion(CGSConnectionID cid, CGSWindowID wid);
extern CGError CGSAddDragRegion(CGSConnectionID cid, CGSWindowID wid, CGSRegionRef region);
extern CGError CGSClearDragRegion(CGSConnectionID cid, CGSWindowID wid);
extern CGError CGSAddTrackingRect(CGSConnectionID cid, CGSWindowID wid, CGRect rect);
extern CGError CGSRemoveAllTrackingAreas(CGSConnectionID cid, CGSWindowID wid);
extern CFStringRef CGSCopyManagedDisplayForWindow(const CGSConnectionID cid, CGSWindowID wid);
extern CGError CGSGetScreenRectForWindow(CGSConnectionID cid, CGSWindowID wid, CGRect *outRect);
// The IOHIDEvent an event was made from; Darling's events have none, so always NULL.
extern CFTypeRef CGEventCopyIOHIDEvent(CGEventRef event);

extern const CFStringRef kCGSWindowTitle;
extern CGError CGSSetWindowTitle(CGSConnectionID cid, CGSWindowID wid, CFStringRef title);
extern CGError CGSGetWindowProperty(CGSConnectionID cid, CGSWindowID wid, CFStringRef key, CFTypeRef *outValue);
extern CGError CGSSetWindowProperty(CGSConnectionID cid, CGSWindowID wid, CFStringRef key, CFTypeRef value);

typedef uint32_t CGSByteCount;
typedef uint16_t CGSEventRecordVersion;
typedef unsigned long CGSEventType;
typedef uint64_t CGSEventRecordTime;  /* nanosecond timer */
typedef unsigned long CGSEventFlag;
typedef NXEventData CGSEventRecordData;

struct _CGSEventRecord
{
	CGSEventRecordVersion major;
	CGSEventRecordVersion minor;
	CGSByteCount length;	/* Length of complete event record */
	CGSEventType type;		/* An event type from above */
	CGPoint location;		/* Base coordinates (global), from upper-left */
	CGPoint windowLocation;	/* Coordinates relative to window */
	CGSEventRecordTime time;	/* nanoseconds since startup */
	CGSEventFlag flags;		/* key state flags */
	CGSWindowID	window;		/* window number of assigned window */
	CGSConnectionID connection;	/* connection the event came from */
	CGSEventRecordData data;	/* type-dependent data: 40 bytes */
};
typedef struct _CGSEventRecord CGSEventRecord;
typedef CGSEventRecord *CGSEventRecordPtr;

typedef void(*CGSNotifyProcPtr)(CGSNotificationType type, void* data, unsigned long dataLength, void* client);

// CGSNotificationType:
// 710 + NX event type from IOLLEvent.h
#define CGSNotificationSingleEventType(event) (701 + event)
#define kCGSNotificationAllEvents 0
extern CGError CGSRegisterNotifyProc(CGSNotifyProcPtr proc, CGSNotificationType notificationType, void* client);
extern CGError CGSRemoveNotifyProc(CGSNotifyProcPtr proc, CGSNotificationType notificationType);

/* Whether font smoothing is disabled for the current user. */
extern bool CGFontRenderingGetFontSmoothingDisabled(void);

// Context state getters and font smoothing style (a graphics state value)
extern bool CGContextGetAllowsAntialiasing(CGContextRef context);
extern bool CGContextGetAllowsFontSmoothing(CGContextRef context);
extern bool CGContextGetShouldSmoothFonts(CGContextRef context);
extern uint32_t CGContextGetFontSmoothingStyle(CGContextRef context);
extern void CGContextSetFontSmoothingStyle(CGContextRef context, uint32_t style);

// Display details beyond the public CGDisplay* API, for the frameworks above CoreGraphics that describe displays
// (AppKit's NSScreen). The display is a CGDirectDisplayID.
// Device pixels per point of the display (at least 1; 1 for a display that does not exist).
extern double _CGSDisplayBackingScaleFactor(CGDirectDisplayID display);
// The display's rectangle in the window system's own pixels (X11: the monitor in root window coordinates), for the
// framework that talks to the window system itself. false (and *frame untouched) when the display does not exist
// or the window system has no such coordinates (Wayland).
extern bool _CGSDisplayNativeFrame(CGDirectDisplayID display, CGRect *frame);
// The EDID the display's output carries, or NULL; the caller releases it.
extern CFDataRef _CGSDisplayCopyEDID(CGDirectDisplayID display);
// The name the window system gives the display's output (a description or a connector name), or NULL; the
// caller releases it.
extern CFStringRef _CGSDisplayCopyOutputName(CGDirectDisplayID display);
// Keys of the dictionary a display's color description uses. Values are CFNumbers. Luminances use
// the color-management protocol's units (minimum luminance is scaled by 10000); absent keys mean
// the compositor did not report them.
extern const CFStringRef kCGSDisplayColorPrimariesKey;
extern const CFStringRef kCGSDisplayColorTransferFunctionKey;
extern const CFStringRef kCGSDisplayColorMinLuminanceKey;
extern const CFStringRef kCGSDisplayColorMaxLuminanceKey;
extern const CFStringRef kCGSDisplayColorReferenceLuminanceKey;
extern const CFStringRef kCGSDisplayColorTargetMinLuminanceKey;
extern const CFStringRef kCGSDisplayColorTargetMaxLuminanceKey;
extern const CFStringRef kCGSDisplayColorICCProfileKey;
// The remaining keys carry the optional parts of a version 3 parametric description. The
// chromaticity keys hold an array of eight CFNumbers in r, g, b, white x/y order. The MaxCLL
// and MaxFALL keys are the values defined by CTA-861-H, in cd/m^2. The transfer-function power
// key is the exponent multiplied by 10000. An absent key means the compositor did not report it.
extern const CFStringRef kCGSDisplayColorPrimariesChromaticityKey;
extern const CFStringRef kCGSDisplayColorTargetPrimariesChromaticityKey;
extern const CFStringRef kCGSDisplayColorTransferFunctionPowerKey;
extern const CFStringRef kCGSDisplayColorTargetMaxCLLKey;
extern const CFStringRef kCGSDisplayColorTargetMaxFALLKey;

// Values of the primaries and transfer-function keys. The numbers are the window system's
// color-management enum values; the names give the frameworks above CoreGraphics a stable
// vocabulary for them.
typedef enum {
    kCGSDisplayColorPrimariesSRGB = 1,
    kCGSDisplayColorPrimariesBT2020 = 6,
    kCGSDisplayColorPrimariesDCIP3 = 8,
    kCGSDisplayColorPrimariesDisplayP3 = 9,
    kCGSDisplayColorPrimariesAdobeRGB = 10,
} CGSDisplayColorPrimaries;

typedef enum {
    kCGSDisplayColorTransferFunctionGamma22 = 2,
    kCGSDisplayColorTransferFunctionExtendedLinear = 5,
    kCGSDisplayColorTransferFunctionSRGB = 9,
    kCGSDisplayColorTransferFunctionExtendedSRGB = 10,
    kCGSDisplayColorTransferFunctionPQ = 11,
    kCGSDisplayColorTransferFunctionHLG = 13,
    kCGSDisplayColorTransferFunctionCompoundPower24 = 14,
} CGSDisplayColorTransferFunction;

// The color description of the display's output, or NULL; the caller releases it. The dictionary
// is in the format described by the keys above.
extern CFDictionaryRef _CGSDisplayCopyColorInfo(CGDirectDisplayID display);

// Darling extras, e.g. for CGL
// Asks the window system to give the windows of a process the input focus and raise them,
// as a pager would (the window manager may still refuse). The pid is a Darling process
// id. With kCGSActivateProcessFrontWindowOnly only the process' frontmost window is
// activated; otherwise all of its windows are raised, keeping their stacking order.
// A process this system has no direct way to activate (Wayland offers none) is asked
// through a per-process Darwin notification that the process' own windowing backend
// answers; so success only means the request was made. Returns kCGErrorIllegalArgument
// for a pid that is not positive, kCGErrorSuccess otherwise, and
// kCGErrorCannotComplete when no request could be made, which includes a process (other than the
// caller) that never connected to the window system, see _CGSProcessHasConnection().
#define kCGSActivateProcessFrontWindowOnly 1
CGError _CGSActivateProcess(pid_t pid, uint32_t options);
// Whether the process with this pid is a live process that has connected to the window system,
// as every process does that creates a connection (CGSNewConnection, CGSMainConnectionID; AppKit
// does so when NSApplication is created). Processes that never did, such as command line tools
// and system daemons, are not applications of the window system.
Boolean _CGSProcessHasConnection(pid_t pid);
#define kCGSProcessConnectionNotificationPrefix "org.darlinghq.process-connection."
// The Darling process that has the input focus: the process that most recently reported (through
// _CGSSetFrontProcess) or was requested (through _CGSRequestFrontProcess) to be the front process,
// as long as it has not resigned since, shared by all Darling processes. When no process is
// in that state, the display server is asked where it can answer (X11: the owner of
// _NET_ACTIVE_WINDOW). Returns kCGErrorSuccess and sets *pid,
// kCGErrorNoneAvailable when no process is known, kCGErrorIllegalArgument for a NULL pid.
CGError _CGSGetFrontProcess(pid_t* pid);
// Reports that the process with this pid got the input focus. A windowing backend calls it
// with its own pid when its windows get the focus on a display server that cannot be asked.
// Every call posts the libnotify name kCGSFrontProcessNotificationName (below), so that processes
// that follow the front process can ask _CGSGetFrontProcess() again.
CGError _CGSSetFrontProcess(pid_t pid);
// Reports that the process with this pid lost the input focus. When it is still the recorded front
// process, no process is known to have the focus until one reports (a window system that cannot be
// asked, such as a Wayland compositor, has focus on a process that is not a Darling process, or on
// none). Posts the same name as _CGSSetFrontProcess().
CGError _CGSResignFrontProcess(pid_t pid);
// Publishes the activation policy of the calling process' application (NSApplicationActivationPolicy:
// 0 regular, 1 accessory, 2 prohibited) for the other processes; AppKit calls it when the application
// object is made and when the policy changes.
void _CGSSetProcessActivationPolicy(int policy);
// The policy the process with this pid published. kCGErrorNoneAvailable for a process that is gone
// or never published one (a program that is not an application of the window system),
// kCGErrorIllegalArgument for a pid that is not positive or a NULL policy.
CGError _CGSGetProcessActivationPolicy(pid_t pid, int* policy);
// Makes the process with this pid the front process: what SetFrontProcess() of the Process Manager
// asks for. The change is visible to every process when the call returns (_CGSGetFrontProcess(),
// and what is built on it), and every process that watches the front process is notified; then
// the window system is asked to give the process' windows the input focus (_CGSActivateProcess()),
// which it may decline. kCGSRequestFrontProcessFrontWindowOnly is passed on to the activation;
// kCGSRequestFrontProcessMenuBarOwner makes the process the menu bar owner too (for a
// regular application; an agent keeps the owner that was). Returns kCGErrorIllegalArgument for a pid
// that is not positive and kCGErrorSuccess otherwise.
#define kCGSRequestFrontProcessFrontWindowOnly 1
#define kCGSRequestFrontProcessMenuBarOwner 2
CGError _CGSRequestFrontProcess(pid_t pid, uint32_t options);
// The request SetFrontProcess() makes for an application: _CGSRequestFrontProcess() with the menu bar
// owner chosen from the activation policy the process published (a regular application becomes the
// owner, an agent does not). kCGErrorInvalidOperation for a process that published the prohibited
// policy (it cannot be the front process, and nothing changes); a process that published none is
// not refused. Only kCGSRequestFrontProcessFrontWindowOnly is accepted in options
// (kCGErrorIllegalArgument otherwise); a pid that is not positive is kCGErrorIllegalArgument too.
CGError _CGSRequestFrontApplication(pid_t pid, uint32_t options);
// The CPS calls, the window system's per-process calls that the Process Manager is built on. A serial
// number is (0, pid); the Process Manager's special values are accepted (1: the system
// process, accepted and left alone by CPSSetFrontProcess; 2: the calling process). They return 0 on
// success and a nonzero error otherwise: 1003 for a NULL serial number, else a CGError.
typedef struct CPSProcessSerNum
{
	uint32_t hi;
	uint32_t lo;
} CPSProcessSerNum;
int CPSGetCurrentProcess(CPSProcessSerNum* psn);
// Makes the calling process a regular application of the window system (it publishes that activation
// policy). kCGErrorCannotComplete for another process, whose policy only it can publish.
int CPSEnableForegroundOperation(CPSProcessSerNum* psn, uint32_t flags1, uint32_t flags2, uint32_t flags3, uint32_t flags4);
// _CGSRequestFrontApplication() for the process: its errors, kCGErrorNoneAvailable for a serial
// number that names no live process.
int CPSSetFrontProcess(CPSProcessSerNum* psn);
// Called in this process when the front process changed (by any process), on the main thread, and
// at once in the thread that reported or requested the change when it was this process. previous
// and current are pids, 0 for none known (the focus is in another client of the window system).
// Not called for a change that is undone before the observers looked. An observer is added once and
// not removed; the first one makes the process watch the front process, and an observer added while
// this process is the front process is called with a previous pid of 0.
typedef void (*CGSFrontProcessObserver)(pid_t previous, pid_t current, void* info);
void _CGSAddFrontProcessObserver(CGSFrontProcessObserver observer, void* info);
// The name of the Darwin notification that asks the process with this pid to activate its
// windows (see above); a windowing backend observes the name of its own process.
#define kCGSProcessActivationNotificationPrefix "org.darlinghq.process-activation."

// Commands for the application of another process: a libnotify notification named after the target
// process, which AppKit's application object answers (hide, unhide, and the quit request, which takes
// the application's normal quit path).
#define kCGSProcessHideNotificationPrefix "org.darlinghq.process-hide."
#define kCGSProcessUnhideNotificationPrefix "org.darlinghq.process-unhide."
#define kCGSProcessQuitNotificationPrefix "org.darlinghq.process-quit."
#define kCGSProcessCommandHide 1
#define kCGSProcessCommandUnhide 2
#define kCGSProcessCommandQuit 3
// Posts the command to the process. Returns kCGErrorIllegalArgument for a pid that is not positive or
// an unknown command, kCGErrorCannotComplete for a process (other than the caller) that is not a
// live application of the window system (see _CGSProcessHasConnection()), kCGErrorSuccess otherwise;
// success means the request was made, not carried out.
CGError _CGSSendProcessCommand(pid_t pid, uint32_t command);
// Publishes the hidden state of the calling process' application for other processes.
void _CGSSetProcessHidden(Boolean hidden);
// Whether the application of the process with this pid is hidden. False for a process that is gone
// or is not an application.
Boolean _CGSProcessIsHidden(pid_t pid);

// The libnotify name whose state holds the pid _CGSSetFrontProcess() stored, and which is posted
// whenever the front process may have changed.
#define kCGSFrontProcessNotificationName "org.darlinghq.front-process"

// The libnotify name whose state holds the pid of the process that owns the menu bar (see
// _CGSSetMenuBarOwnerProcess()).
#define kCGSMenuBarOwnerNotificationName "org.darlinghq.menubar-owner"
// Reports that the process with this pid owns the menu bar from now on. A regular application
// calls it with its own pid when it becomes active; an application that is not regular (an
// agent or background application) never takes the menu bar over when it becomes active, so
// the owner stays the application that had it. Posts kCGSFrontProcessNotificationName.
CGError _CGSSetMenuBarOwnerProcess(pid_t pid);
// The process that owns the menu bar: the last one that reported it, as long as it is alive and a
// Darling process reports to have the input focus (_CGSSetFrontProcess() without a later
// _CGSResignFrontProcess() of the same process). Returns kCGErrorNoneAvailable when there is none (nothing
// was reported, the owner ended, or the focus is in another client of the display server, where
// no Darling process shows a menu bar), kCGErrorIllegalArgument for a NULL pid.
CGError _CGSGetMenuBarOwnerProcess(pid_t* pid);

void* _CGSNativeDisplay(CGSConnectionID connId);
void* _CGSNativeWindowForID(CGSConnectionID connId, CGSWindowID winId);
void* _CGSNativeWindowForSurfaceID(CGSConnectionID connId, CGSWindowID winId, CGSSurfaceID surfaceId);

// Surfaces of application windows. There is no window server to own the drawable of an
// NSOpenGLView, so AppKit records it here: a surface on the AppKit window with this window
// number, backed by `nativeWindow` (the handle a GL surface is made for), with the given size
// in points. The surface can then be looked up by its ids as for a CGS surface:
// CGSGetSurfaceBounds() reports its size, and CGLGetSurface() reports the ids of a context
// that draws to it. Returns the new surface id, never 0.
CGSSurfaceID _CGSAddWindowSurface(CGSWindowID winId, void* nativeWindow, CGSize size);
void _CGSSetWindowSurfaceSize(CGSSurfaceID surfaceId, CGSize size);
void _CGSRemoveWindowSurface(CGSSurfaceID surfaceId);
// The ids of the application window surface backed by `nativeWindow`. False if there is none.
bool _CGSWindowSurfaceForNativeWindow(void* nativeWindow, CGSConnectionID* connId,
                                      CGSWindowID* winId, CGSSurfaceID* surfaceId);

// Creates a window covering `bounds` (global display coordinates), above ordinary
// windows and shown, so that a GL context can fill a display (CGLSetFullScreen).
// The window is not one of the application's own: its keyboard and pointer input
// is the application's, delivered as events that name no window. On X11 it is an
// override-redirect window that takes the keys and the pointer; on Wayland it is a
// fullscreen toplevel without a frame of the compositor, whose input region is its
// whole surface. On both, the connection to the window system decodes the keys and
// the pointer (and the relative mouse grab, which is taken on the overlay) into
// CGEvents with screen coordinates, as it does for any window, and
// _CGSNativeConnectionIsDisplayOverlayWindow() tells the overlay's native window
// from the others. *drawable is the native window handle a GL surface is created
// on. Release it with CGSReleaseWindow.
//
// Once the window is shown, _kCGSDisplayOverlayWindowCreated is posted to the
// default notification center, with the drawable as the NSNumber
// "NativeWindow" in the user info.
#define _kCGSDisplayOverlayWindowCreated CFSTR("_CGSDisplayOverlayWindowCreated")
CGError _CGSCreateDisplayOverlayWindow(CGSConnectionID connId, CGRect bounds,
                                       CGSWindowID* winId, void** drawable);

// Private context functions (see CGContext.m). The composite operation is the
// context's blend mode under a different numbering.
extern size_t CGContextGetLineDashCount(CGContextRef context);
extern void CGContextGetLineDashPattern(CGContextRef context, CGFloat *phase, CGFloat *lengths, size_t capacity);
extern int CGContextGetCompositeOperation(CGContextRef context);
extern void CGContextSetCompositeOperation(CGContextRef context, int operation);
extern void CGContextSetOwnerIdentity(CGContextRef context, task_id_token_t owner);

// Private numeric helpers.
extern bool CGFloatIsValid(CGFloat value);
extern size_t CGBitmapGetAlignedBytesPerRow(size_t bytesPerRow);
COREGRAPHICS_EXPORT bool CGImageGetHeadroom(CGImageRef image, float *headroom);

extern CGEventRef CGEventCreateWithEventRecord(const CGSEventRecordPtr event, uint32_t eventRecordSize);
extern CGError CGEventGetEventRecord(CGEventRef event, CGSEventRecordPtr eventRecord, uint32_t eventRecordSize);
extern CGError CGEventSetEventRecord(CGEventRef event, CGSEventRecordPtr eventRecord, uint32_t eventRecordSize);
extern uint32_t CGEventGetEventRecordSize(CGEventRef event);

// The event stream of the process: the events that are for this process once they have been
// through the event taps (CGEventPost() and friends deliver here), in the order they came, for
// the frameworks above CoreGraphics to read. Thread safe. There is no Mach message, port or
// thread behind it.
//
// The stream keeps events only while a reader is registered with _CGSEventStreamSetReadySource().
// _CGSEventStreamPost() is for the window system: it enters the event at the first tap, as an
// event of the hardware, and retains it until it has been delivered.
extern void _CGSEventStreamPost(CGEventRef event);
// The oldest event, which the caller releases, or NULL once the stream is empty. A reader that was
// woken has to call this until it returns NULL: the source is signalled again only after that.
extern CGEventRef _CGSEventStreamCopyNextEvent(void);
// Registers the run loop source that is signalled, and its run loop woken, when an event arrives
// at an empty stream. For the thread that waits for events: it reads the stream from where it
// waits (before each wait, and after each wake up). A new registration replaces the old one;
// NULL for both stops the stream and drops what is waiting.
extern void _CGSEventStreamSetReadySource(CFRunLoopSourceRef _Nullable source, CFRunLoopRef _Nullable runLoop);

// Fields of our own on the input events the window system backends post, for what a CGEvent has no
// field for. They sit above the highest field CGEvent.h defines and belong to every event type.
enum {
	// The characters of a key event with the modifiers other than Shift ignored: up to four UTF-16
	// units, the first in the lowest 16 bits, and the key code they were made for (they no longer apply
	// when an event tap gives the event another key code).
	kCGSKeyboardEventUnmodifiedUnicode = 180,
	kCGSKeyboardEventUnmodifiedLength = 181,
	kCGSKeyboardEventUnmodifiedKeyCode = 184,
	// The window system handle of the window the event is for (the wl_surface of the keyboard focus
	// on Wayland), compared by value only.
	kCGSEventNativeWindow = 182,
	// The window system serial of the input event (Wayland), 0 when it has none.
	kCGSEventInputSerial = 183,
	// Pointer events: where the pointer was in the window system's window the event is for
	// (kCGSEventNativeWindow), from the window's top-left corner (X11: device pixels; Wayland: 1/1024
	// of a surface-local point), and the global location the event was posted with (in 1/1024 points).
	// The window location only applies while the event's location is still the posted one: an event
	// tap that moves the event invalidates it.
	kCGSEventNativeLocationX = 185,
	kCGSEventNativeLocationY = 186,
	kCGSEventPostedLocationX = 187,
	kCGSEventPostedLocationY = 188,
	// Not 0: the event goes to the event taps only, and not to the process' event stream (a window
	// that has not asked for mouse moved events does not get them).
	kCGSEventTapsOnly = 189,
	// What the framework above the window system knew when a mouse button press arrived: 1 when the
	// window it is for was the key window, 2 when it was not, 0 when nothing was said.
	kCGSMouseEventWindowKeyState = 190,
	// Pinch (magnify) and rotate gesture events: the phase (NSEventPhase bits), the change of the
	// magnification since the previous event of the gesture and the rotation in degrees counter-clockwise
	// since it, both in millionths. CGEvent.h has no field for them.
	kCGSGesturePhase = 191,
	kCGSGestureMagnification = 192,
	kCGSGestureRotation = 193,
	// Touch events: a gesture event (CGEvent type 29, NSEventTypeGesture) with kCGSTouchPhase not 0, one for
	// each change of one finger on a touch screen (a gesture event with phase 0 is an ordinary one, as
	// the touchpad's). Direct touch is not a CGEvent type of its own (CGEvent of type 37 is not valid; the touch
	// events of the application are made from these). The window and the position are given as for pointer
	// events: the window system's window (kCGSEventNativeWindow, with kCGSEventNativeLocationX/Y and
	// kCGSEventPostedLocationX/Y), or, for an event of the application, kCGSTouchWindowNumber
	// with the event's location. The CGEvent location is the global location of the finger. CGEvent.h has no
	// fields for them.
	// The number that names the finger while it is down, and may be used again afterwards. It is unique
	// among the fingers of all touch devices of the event source (0 is a number like any other).
	kCGSTouchIdentifier = 194,
	// The phase as NSTouchPhase bits: began (1), moved (2), ended (8) or cancelled (16); the event is a
	// touch event when this is not 0.
	kCGSTouchPhase = 195,
	// Where the finger is on its device, in millionths of the device's width and height from its bottom left
	// corner (0 to 1000000), and the size of the device in 1/1024 of a point. All four are 0 when the source
	// does not know.
	kCGSTouchNormalizedX = 196,
	kCGSTouchNormalizedY = 197,
	kCGSTouchDeviceWidth = 198,
	kCGSTouchDeviceHeight = 199,
	// Not 0: the source has no position for the finger (the end of a finger that carries none, a cancel): the
	// finger is where its previous event left it, and the location fields of the event are not meaningful.
	kCGSTouchLocationUnknown = 200,
	// The number of the window a touch event of the application is for (the fields of mouse events that name a
	// window do not belong to gesture events), with the event's location. 0 when the event names the window
	// system's window.
	kCGSTouchWindowNumber = 201,
	// Tablet tools: the documented proximity fields belong only to proximity CGEvents, but AppKit gets the
	// tool's identity from the pointer events too. These common fields carry it on both kinds (the
	// documented kCGTabletEventDeviceID/Vendor1/Vendor2/Vendor3 fields carry the ids that have a place in
	// the pointer class). The vendor pointer type is the protocol's raw tool type, the pointer type is
	// Cocoa's NSPointingDeviceType.
	kCGSTabletPointerID = 202,
	kCGSTabletSystemTabletID = 203,
	kCGSTabletCapabilityMask = 204,
	kCGSTabletVendorPointerType = 205,
	kCGSTabletPointerType = 206,
	kCGSTabletVendorPointerSerialNumber = 207,
	// The documented "window under the pointer" fields belong to mouse events, to the exclusion of
	// tablet events. These common fields say which window the tablet tool is over, for both kinds.
	kCGSTabletWindowNumber = 208,
	kCGSTabletWindowNumberThatCanHandleThisEvent = 209,
};

// Tablet tools, for the window system backends: they describe what their window system says about a
// tool, and CoreGraphics makes the tablet CGEvent (kCGEventTabletPointer or kCGEventTabletProximity)
// from it, so that every backend fills the documented kCGTablet* fields and the common fields above
// the same way. Cocoa's NSPointingDeviceType values and the tablet button mask (NSEventButtonMask
// bits) are repeated here because CoreGraphics is below AppKit.
enum {
	kCGSTabletPointingDeviceUnknown = 0,
	kCGSTabletPointingDevicePen = 1,
	kCGSTabletPointingDeviceCursor = 2,
	kCGSTabletPointingDeviceEraser = 3,
};
enum {
	kCGSTabletButtonTip = 1,
	kCGSTabletButtonLowerSide = 2,
	kCGSTabletButtonUpperSide = 4,
};
// The bits of the capability mask: the Wayland tablet protocol's capability numbers.
enum {
	kCGSTabletCapabilityTilt = 1 << 1,
	kCGSTabletCapabilityPressure = 1 << 2,
	kCGSTabletCapabilityDistance = 1 << 3,
	kCGSTabletCapabilityRotation = 1 << 4,
	kCGSTabletCapabilitySlider = 1 << 5,
	kCGSTabletCapabilityWheel = 1 << 6,
};
typedef struct {
	CGEventSourceRef source;      // the event source of the hardware state
	bool proximity;               // a proximity event, not a pointer event
	bool entering;                // the tool enters proximity (proximity events)
	uint64_t flags;               // CGEventFlags: the modifiers of the keyboard
	CGPoint location;             // global (CGEventSetLocation)
	bool hasNativeLocation;       // nativeLocation is known (kCGSEventNativeLocationX/Y)
	CGPoint nativeLocation;       // in the window system window
	double nativeLocationScale;   // what the backend's window system decoder expects it multiplied by (1024 for
	                              // points on Wayland, 1 for the device pixels of X11)
	bool hasPostedLocation;       // location is a real position (kCGSEventPostedLocationX/Y)
	CGPoint axes;                 // the absolute X and Y axes of the tablet (kCGTabletEventPointX/Y)
	uint32_t windowID;            // the CGS window under the tool, 0 when none
	int64_t nativeWindow;         // the window system window
	int64_t inputSerial;          // kCGSEventInputSerial: not 0 only for a press
	double pressure, distance;    // 0 to 1
	double tiltX, tiltY;          // -1 to 1, 1 being a pen parallel to the tablet
	double rotation, tangentialPressure;
	uint32_t buttonMask;          // kCGSTabletButton* bits
	uint32_t vendorID, tabletID;
	uint32_t pointerID;           // the tool's own number (the low half of its serial where it has one)
	uint32_t deviceID;
	uint64_t toolSerial;
	uint32_t vendorPointerType;   // the window system's own number for the kind of tool
	uint32_t pointerType;         // kCGSTabletPointingDevice*
	uint64_t capabilities;        // kCGSTabletCapability* bits
} CGSTabletSample;
// Makes the event for a sample (NULL when none can be made); the caller posts it with
// _CGSEventStreamPost() and releases it.
extern CGEventRef _CGSTabletEventCreate(const CGSTabletSample *sample);
// A stable number for the tool and tablet pair, for the device id of the tablet events. Window
// systems with no such number derive it from the hardware serial and the tablet's ids; extra tells
// apart devices that have neither (the window system's own device number, or 0). Never 0.
extern uint32_t _CGSTabletDeviceID(uint64_t toolSerial, uint32_t vendorID, uint32_t tabletID, uint32_t extra);
// Tilt in degrees from the tablet's normal, as the -1 to 1 the events carry.
extern double _CGSTabletNormalizedTilt(double degrees);

// The CGEvent type of the gesture events (NSEventTypeGesture), and the phases of a touch event
// (NSTouchPhase bits).
enum {
	kCGSEventTypeGesture = 29,
};
enum {
	kCGSTouchPhaseBegan = 1 << 0,
	kCGSTouchPhaseMoved = 1 << 1,
	kCGSTouchPhaseEnded = 1 << 3,
	kCGSTouchPhaseCancelled = 1 << 4,
};

// The double-click interval of the user in seconds: the time within which a second press of a button
// counts as a double click.
extern double _CGSDoubleClickInterval(void);
// The time local mouse motion is dropped after CGWarpMouseCursorPosition() (CGSetLocalEventsSuppressionInterval()).
extern double _CGSLocalEventsSuppressionInterval(void);

// Identity of the object an event stands for: the framework that makes an event from an object of its
// own (AppKit queues the NSEvent an application posted) attaches the object to the event, and the
// framework that reads the event from the stream takes the same object back instead of making a new
// one. The window system's input does not carry one: the backends post plain CGEvents. The object is
// not part of the event: copies of the event do not have it, and an active event tap that changes the
// event or replaces it with another drops it, so the reader then builds the object from the event's
// fields. The event retains the object.
extern void _CGSEventSetClientData(CGEventRef event, CFTypeRef _Nullable data);
extern CFTypeRef _Nullable _CGSEventGetClientData(CGEventRef event);


// What a key code types, from the current keyboard layout and the keys that give the same on every layout.
// kCGKeyCharactersDefault is the Unicode string CGEventCreateKeyboardEvent() gives an event (no modifiers),
// kCGKeyCharactersWithModifiers NSEvent's characters with the flags applied, kCGKeyCharactersIgnoringModifiers
// NSEvent's charactersIgnoringModifiers (Shift still counts). Returns the number of UTF-16 units written
// to out (at most max), 0 for a key without characters.
typedef enum {
	kCGKeyCharactersDefault,
	kCGKeyCharactersWithModifiers,
	kCGKeyCharactersIgnoringModifiers,
} CGKeyCharactersKind;
extern size_t _CGKeyCharacters(CGKeyCode key, CGEventFlags flags, CGKeyCharactersKind kind, UniChar* out, size_t max);

// The characters of a keyboard event as NSEvent reports them (see _CGKeyCharacters). A string set with
// CGEventKeyboardSetUnicodeString() is returned as it is for both; otherwise the characters follow the
// event's key code and flags. Returns the number of UTF-16 units written to out (at most max).
extern size_t _CGEventGetKeyCharacters(CGEventRef event, bool ignoringModifiers, UniChar* out, size_t max);

#ifdef __OBJC__
@class CGSConnection;
CGSConnection* _CGSConnectionForID(CGSConnectionID connId);
CGSConnection* _CGSConnectionFromEventRecord(const CGSEventRecordPtr record);
#endif

// Draws a PDF page like CGContextDrawPDFPage, asking the callback whether to
// draw each of the page's annotations (NULL draws them all).
typedef struct CGPDFAnnotation *CGPDFAnnotationRef;
#if defined(__BLOCKS__)
typedef bool (^CGPDFAnnotationDrawCallbackType)(CGContextRef context, CGPDFPageRef page, CGPDFAnnotationRef annotation);
#else
typedef void *CGPDFAnnotationDrawCallbackType;
#endif
extern void CGContextDrawPDFPageWithAnnotations(CGContextRef context, CGPDFPageRef page, CGPDFAnnotationDrawCallbackType callback);

// More private context functions, as WebKit (BSD licensed,
// Source/WebCore/PAL/pal/spi/cg/CoreGraphicsSPI.h) declares them.
// The base CTM is the transform the CTM started from, kept in the graphics
// state (identity for a new context); setting it leaves the CTM as it is, and
// drawing does not depend on it.
extern CGAffineTransform CGContextGetBaseCTM(CGContextRef context);
extern void CGContextSetBaseCTM(CGContextRef context, CGAffineTransform transform);
// The current fill and stroke colours, owned by the context.
extern CGColorRef CGContextGetFillColorAsColor(CGContextRef context);
extern CGColorRef CGContextGetStrokeColorAsColor(CGContextRef context);
extern bool CGContextGetShouldAntialias(CGContextRef context);
// Kept in the graphics state; Onyx2D antialiases glyphs either way.
extern void CGContextSetShouldAntialiasFonts(CGContextRef context, bool shouldAntialiasFonts);
extern bool CGContextGetShouldAntialiasFonts(CGContextRef context);
// The colour space of the context's destination (a new reference), NULL for a
// NULL context.
extern CGColorSpaceRef CGContextCopyDeviceColorSpace(CGContextRef context);
// Draws path as CGContextDrawPath would, without changing the current path.
// boundingBox, when given, is a hint and is not used.
extern void CGContextDrawPathDirect(CGContextRef context, CGPathDrawingMode mode, CGPathRef path, const CGRect *boundingBox);
// Draws the gradient around center: its start location at angle radians, and
// its locations going counterclockwise in user space (from the positive x axis
// towards the positive y axis) for one full turn.
extern void CGContextDrawConicGradient(CGContextRef context, CGGradientRef gradient, CGPoint center, CGFloat angle);
// A shading that evaluates function as CGContextDrawConicGradient sweeps a
// gradient; it covers the whole clip.
extern CGShadingRef CGShadingCreateConic(CGColorSpaceRef space, CGPoint center, CGFloat angle, CGFunctionRef function);

// Adds a rectangle with elliptical corners of their own sizes. Inferred order
// (WebKit's use): the corners at (minX, maxY), (maxX, maxY), (maxX, minY) and
// (minX, minY), each size the horizontal and vertical radius. NULL corners add
// a plain rectangle.
extern void CGPathAddUnevenCornersRoundedRect(CGMutablePathRef path, const CGAffineTransform *transform, CGRect rect, const CGSize corners[4]);

// A colored pattern that tiles image, one copy every image width and height
// in pattern space; transform maps pattern space to the default user space.
extern CGPatternRef CGPatternCreateWithImage2(CGImageRef image, CGAffineTransform transform, CGPatternTiling tiling);

// Hints on how long an image's decoded data is worth keeping. Inferred values.
// Kept with the image and reported; Onyx2D does not cache by them.
enum {
    kCGImageCachingTransient = 1,
    kCGImageCachingTemporary = 3,
};
typedef uint32_t CGImageCachingFlags;
extern void CGImageSetCachingFlags(CGImageRef image, CGImageCachingFlags flags);
extern CGImageCachingFlags CGImageGetCachingFlags(CGImageRef image);

// Converts colours to the destination colour space it was created with.
typedef const struct CGColorTransform *CGColorTransformRef;
// NULL for a NULL space. The attributes are not used.
extern CGColorTransformRef CGColorTransformCreate(CGColorSpaceRef destination, CFDictionaryRef attributes);
extern CFTypeID CGColorTransformGetTypeID(void);
// Converts the colour components (without alpha) of a colour in source to the
// destination space's components (without alpha). False, and the destination
// left as it was, when the colours cannot be converted.
extern bool CGColorTransformConvertColorComponents(CGColorTransformRef transform, CGColorSpaceRef source, CGColorRenderingIntent intent, const CGFloat sourceComponents[], CGFloat destinationComponents[]);
// The colour in the transform's destination space, alpha kept.
extern CGColorRef CGColorTransformConvertColor(CGColorTransformRef transform, CGColorRef color, CGColorRenderingIntent intent);

// Whether two spaces are the same space: the same object, equal spaces
// (CFEqual), or spaces of one model with the same ICC data. False when only one
// of them is NULL.
extern bool CGColorSpaceEqualToColorSpace(CGColorSpaceRef space1, CGColorSpaceRef space2);
// The description ('desc' tag) of the space's ICC profile, or NULL when it has
// no profile or the profile has no readable description.
extern CFStringRef CGColorSpaceCopyICCProfileDescription(CGColorSpaceRef space);

// Gradient creation with options. With kCGGradientInterpolatesPremultiplied
// true, the colours between the stops are interpolated with their alpha
// premultiplied.
extern const CFStringRef kCGGradientInterpolatesPremultiplied;
extern CGGradientRef CGGradientCreateWithColorComponentsAndOptions(CGColorSpaceRef space, const CGFloat components[], const CGFloat locations[], size_t count, CFDictionaryRef options);

// A provider of a copy of the bytes, made when it is created. NULL for NULL
// data with a size other than 0.
extern CGDataProviderRef CGDataProviderCreateWithCopyOfData(const void *data, size_t size);

// Walks the rectangles of a region. Each CGSNextRect returns the next one
// (owned by the enumerator) and NULL after the last.
typedef struct CGSRegionEnumeratorObject *CGSRegionEnumeratorObj;
extern CGSRegionEnumeratorObj CGSRegionEnumerator(CGSRegionRef region);
extern CGRect *CGSNextRect(const CGSRegionEnumeratorObj enumerator);
extern CGError CGSReleaseRegionEnumerator(const CGSRegionEnumeratorObj enumerator);
extern CGError CGSReleaseRegion(const CGSRegionRef region);

__END_DECLS

#include <CoreGraphics/CGContextDelegatePrivate.h>
#include <CoreGraphics/CGStylePrivate.h>

#endif
