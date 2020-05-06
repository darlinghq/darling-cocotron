#import <CoreGraphics/CGDirectDisplay.h>
#import <CoreGraphics/CoreGraphicsExport.h>

typedef uint32_t CGDisplayFadeReservationToken;
typedef float CGDisplayBlendFraction;
typedef float CGDisplayFadeInterval;
typedef float CGDisplayReservationInterval;

COREGRAPHICS_EXPORT CGError CGDisplayFade(CGDisplayFadeReservationToken token, CGDisplayFadeInterval duration, CGDisplayBlendFraction startBlend, CGDisplayBlendFraction endBlend, float redBlend, float greenBlend, float blueBlend, boolean_t synchronous);
