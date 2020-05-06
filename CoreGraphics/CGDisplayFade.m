#import <CoreGraphics/CGDisplayFade.h>

CGError CGDisplayFade(CGDisplayFadeReservationToken token,
                      CGDisplayFadeInterval duration,
                      CGDisplayBlendFraction startBlend,
                      CGDisplayBlendFraction endBlend, float redBlend,
                      float greenBlend, float blueBlend,
                      boolean_t synchronous) {
    return 0;
}

CGError CGAcquireDisplayFadeReservation(CGDisplayReservationInterval seconds,
                                        CGDisplayFadeReservationToken *token) {
    return 0;
}

CGError CGReleaseDisplayFadeReservation(CGDisplayFadeReservationToken token) {
    return 0;
}
