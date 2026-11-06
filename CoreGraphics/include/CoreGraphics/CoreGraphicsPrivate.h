#ifndef COREGRAPHICSPRIVATE_H
#define COREGRAPHICSPRIVATE_H
#include <CoreGraphics/CoreGraphics.h>
#include <IOKit/hidsystem/IOLLEvent.h>
#include <CoreFoundation/CoreFoundation.h>

__BEGIN_DECLS

// References:
// https://github.com/koekeishiya/cglwindow/blob/master/src/cgl_window.c
// https://sourceforge.net/p/xnntp/SVN_Xnntp/1/tree/CGSPrivate.h

typedef int CGSConnectionID;
typedef int CGSWindowID;
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
extern CGSConnectionID CGSMainConnectionID(void);
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

extern CGError CGSNewWindow(CGSConnectionID conn, CFIndex flags, float, float, const CGSRegionRef region, CGSWindowID* windowID);
extern CGError CGSReleaseWindow(CGSConnectionID cid, CGSWindowID wid);

extern CGError CGSSetWindowShape(CGSConnectionID cid, CGSWindowID wid, float x_offset, float y_offset, const CGSRegionRef shape);
extern OSStatus CGSOrderWindow(CGSConnectionID cid, CGSWindowID wid, CGSWindowOrderingMode place, CGSWindowID relativeToWindow);
extern CGError CGSMoveWindow(CGSConnectionID cid, CGSWindowID wid, const CGPoint *window_pos);
extern CGError CGSSetWindowOpacity(CGSConnectionID cid, CGSWindowID wid, bool isOpaque);
extern CGError CGSSetWindowAlpha(CGSConnectionID cid, CGSWindowID wid, float alpha);
extern CGError CGSSetWindowLevel(CGSConnectionID cid, CGSWindowID wid, CGWindowLevel level);
extern CGError CGSSetWindowTransform(CGSConnectionID cid, CGSWindowID wid, CGAffineTransform transform);
extern CGError CGSSetWindowWarp(CGSConnectionID cid, CGSWindowID wid, int w, int h, float *mesh);
extern CGError CGSSetWindowCaptureExcludeShape(CGSConnectionID cid, CGSWindowID wid, CGRegionRef shape);

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
