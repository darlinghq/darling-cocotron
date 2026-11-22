#ifndef CGDISPLAYFADE_H
#define CGDISPLAYFADE_H

#import <CoreGraphics/CGDirectDisplay.h>
#import <CoreGraphics/CoreGraphicsExport.h>

typedef uint32_t CGDisplayFadeReservationToken;
typedef float CGDisplayBlendFraction;
typedef float CGDisplayFadeInterval;
typedef float CGDisplayReservationInterval;

enum { kCGDisplayFadeReservationInvalidToken = 0 };

COREGRAPHICS_EXPORT CGError CGDisplayFade(CGDisplayFadeReservationToken token, CGDisplayFadeInterval duration, CGDisplayBlendFraction startBlend, CGDisplayBlendFraction endBlend, float redBlend, float greenBlend, float blueBlend, boolean_t synchronous);

COREGRAPHICS_EXPORT CGError CGAcquireDisplayFadeReservation(CGDisplayReservationInterval seconds, CGDisplayFadeReservationToken *token);
COREGRAPHICS_EXPORT CGError CGReleaseDisplayFadeReservation(CGDisplayFadeReservationToken token);

#endif /* CGDISPLAYFADE_H */
