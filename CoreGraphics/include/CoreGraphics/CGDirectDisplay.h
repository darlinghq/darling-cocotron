
#import <CoreGraphics/CGError.h>
#import <CoreGraphics/CGGeometry.h>
#import <CoreGraphics/CoreGraphicsExport.h>
#import <mach/boolean.h>

typedef uint32_t CGDirectDisplayID;
typedef uint32_t CGOpenGLDisplayMask;
typedef double CGRefreshRate;

#define kCGDirectMainDisplay 69989856
#define kCGDisplayBitsPerPixel 8200
#define kCGDisplayBlendNormal 0
#define kCGDisplayBlendSolidColor 1
#define kCGDisplayRefreshRate 8200
#define kCGDisplayHeight 8200
#define kCGDisplayWidth 8200
#define kCGMaxDisplayReservationInterval 15
#define kCGNullDirectDisplay 0

typedef CFTypeRef CGDisplayModeRef;

COREGRAPHICS_EXPORT CGError CGCaptureAllDisplays(void);
COREGRAPHICS_EXPORT CGError CGReleaseAllDisplays(void);

COREGRAPHICS_EXPORT CGDirectDisplayID CGMainDisplayID(void);

COREGRAPHICS_EXPORT CGError
CGGetOnlineDisplayList(uint32_t maxDisplays, CGDirectDisplayID *onlineDisplays,
                       uint32_t *displayCount);

COREGRAPHICS_EXPORT CGError
CGGetActiveDisplayList(uint32_t maxDisplays, CGDirectDisplayID *activeDisplays,
                       uint32_t *displayCount);

COREGRAPHICS_EXPORT CGError CGGetDisplaysWithOpenGLDisplayMask(
        CGOpenGLDisplayMask mask, uint32_t maxDisplays,
        CGDirectDisplayID *displays, uint32_t *matchingDisplayCount);

COREGRAPHICS_EXPORT CGDirectDisplayID
CGOpenGLDisplayMaskToDisplayID(CGOpenGLDisplayMask mask);

COREGRAPHICS_EXPORT CGError CGGetDisplaysWithPoint(
        CGPoint point, uint32_t maxDisplays, CGDirectDisplayID *displays,
        uint32_t *matchingDisplayCount);

COREGRAPHICS_EXPORT CGError CGGetDisplaysWithRect(
        CGRect rect, uint32_t maxDisplays, CGDirectDisplayID *displays,
        uint32_t *matchingDisplayCount);

COREGRAPHICS_EXPORT size_t CGDisplayPixelsHigh(CGDirectDisplayID display);
COREGRAPHICS_EXPORT size_t CGDisplayPixelsWide(CGDirectDisplayID display);

COREGRAPHICS_EXPORT boolean_t CGDisplayIsInMirrorSet(CGDirectDisplayID display);
COREGRAPHICS_EXPORT Boolean CGDisplayIsMain(CGDirectDisplayID display);
COREGRAPHICS_EXPORT CGDirectDisplayID
CGDisplayMirrorsDisplay(CGDirectDisplayID display);

COREGRAPHICS_EXPORT CFDictionaryRef
CGDisplayBestModeForParametersAndRefreshRate(CGDirectDisplayID display,
                                             size_t bitsPerPixel, size_t width,
                                             size_t height,
                                             CGRefreshRate refreshRate,
                                             boolean_t *exactMatch);
COREGRAPHICS_EXPORT CGDisplayModeRef
CGDisplayCopyDisplayMode(CGDirectDisplayID displayId);
COREGRAPHICS_EXPORT CFDictionaryRef
CGDisplayCurrentMode(CGDirectDisplayID display);
COREGRAPHICS_EXPORT void CGDisplayModeRelease(CGDisplayModeRef mode);
COREGRAPHICS_EXPORT CGDisplayModeRef CGDisplayModeRetain(CGDisplayModeRef mode);
COREGRAPHICS_EXPORT boolean_t CGDisplayIsCaptured(CGDirectDisplayID display);
COREGRAPHICS_EXPORT double CGDisplayModeGetRefreshRate(CGDisplayModeRef mode);
COREGRAPHICS_EXPORT CGError CGDisplaySwitchToMode(CGDirectDisplayID display,
                                                  CFDictionaryRef mode);
COREGRAPHICS_EXPORT size_t CGDisplayModeGetPixelWidth(CGDisplayModeRef mode);
COREGRAPHICS_EXPORT CGSize CGDisplayScreenSize(CGDirectDisplayID display);
