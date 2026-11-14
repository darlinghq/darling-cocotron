#ifndef COREGRAPHICSPRIVATE_H
#define COREGRAPHICSPRIVATE_H
#include <CoreGraphics/CoreGraphics.h>
#include <IOKit/hidsystem/IOLLEvent.h>
#include <CoreFoundation/CoreFoundation.h>
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
// location and time are those of the key event. AppKit turns it into an NSEvent of type
// NSSystemDefined, which NSApplication hands to HIToolbox.
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


extern CGError CGSNewWindow(CGSConnectionID conn, CFIndex flags, float, float, const CGSRegionRef region, CGSWindowID* windowID);
extern CGError CGSReleaseWindow(CGSConnectionID cid, CGSWindowID wid);

extern CGError CGSSetWindowShape(CGSConnectionID cid, CGSWindowID wid, float x_offset, float y_offset, const CGSRegionRef shape);
extern OSStatus CGSOrderWindow(CGSConnectionID cid, CGSWindowID wid, CGSWindowOrderingMode place, CGSWindowID relativeToWindow);
extern CGError CGSMoveWindow(CGSConnectionID cid, CGSWindowID wid, const CGPoint *window_pos);
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

// Darling extras, e.g. for CGL
void* _CGSNativeDisplay(CGSConnectionID connId);
void* _CGSNativeWindowForID(CGSConnectionID connId, CGSWindowID winId);
void* _CGSNativeWindowForSurfaceID(CGSConnectionID connId, CGSWindowID winId, CGSSurfaceID surfaceId);

extern CGEventRef CGEventCreateWithEventRecord(const CGSEventRecordPtr event, uint32_t eventRecordSize);
extern CGError CGEventGetEventRecord(CGEventRef event, CGSEventRecordPtr eventRecord, uint32_t eventRecordSize);
extern CGError CGEventSetEventRecord(CGEventRef event, CGSEventRecordPtr eventRecord, uint32_t eventRecordSize);
extern uint32_t CGEventGetEventRecordSize(CGEventRef event);

#ifdef __OBJC__
@class CGSConnection;
CGSConnection* _CGSConnectionForID(CGSConnectionID connId);
CGSConnection* _CGSConnectionFromEventRecord(const CGSEventRecordPtr record);
#endif

__END_DECLS

#endif
