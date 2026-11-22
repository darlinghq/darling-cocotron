#import <CoreGraphics/CGDisplayFade.h>
#import <CoreGraphics/CGDirectDisplay.h>
#import <CoreGraphics/CGError.h>
#include <pthread.h>
#include <stdbool.h>
#include <time.h>

// One fade reservation at a time, kept per process. GUESS: the documentation
// speaks of "another fade reservation" without saying whose; the fade
// hardware is not modelled here, so the process is the scope.
static pthread_mutex_t fadeLock = PTHREAD_MUTEX_INITIALIZER;
static bool fadeHeld;
static CGDisplayFadeReservationToken fadeLastIssued;
static struct timespec fadeExpiry;

static bool fadeExpired(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return now.tv_sec > fadeExpiry.tv_sec ||
           (now.tv_sec == fadeExpiry.tv_sec && now.tv_nsec >= fadeExpiry.tv_nsec);
}

// Unchanged: nothing is faded. GUESS: it does not look at the token, so it returns success for an
// expired or never-issued one, while -CGReleaseDisplayFadeReservation rejects a never-issued token
// (the documentation names no result code for either).
CGError CGDisplayFade(CGDisplayFadeReservationToken token,
                      CGDisplayFadeInterval duration,
                      CGDisplayBlendFraction startBlend,
                      CGDisplayBlendFraction endBlend, float redBlend,
                      float greenBlend, float blueBlend, boolean_t synchronous)
{
    return 0;
}

CGError CGAcquireDisplayFadeReservation(CGDisplayReservationInterval seconds,
                                        CGDisplayFadeReservationToken *token)
{
    // GUESS: the documentation of this function gives (0, kCGMaxDisplayReservationInterval] as the
    // valid interval, while the page of CGDisplayReservationInterval says 1 to the maximum; the
    // function's own page is followed. Neither it nor a NULL token pointer (which cannot be written)
    // has a documented error, so both are reported as illegal arguments.
    if (token == NULL || !(seconds > 0 && seconds <= kCGMaxDisplayReservationInterval))
        return kCGErrorIllegalArgument;

    CGError result = kCGErrorSuccess;
    pthread_mutex_lock(&fadeLock);
    // A reservation that ran out its interval is no longer in effect.
    if (fadeHeld && fadeExpired())
        fadeHeld = false;
    if (fadeHeld) {
        result = kCGErrorNoneAvailable;
    } else {
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        time_t whole = (time_t) seconds;
        fadeExpiry.tv_sec = now.tv_sec + whole;
        fadeExpiry.tv_nsec = now.tv_nsec + (long) ((seconds - whole) * 1e9);
        if (fadeExpiry.tv_nsec >= 1000000000L) {
            fadeExpiry.tv_sec++;
            fadeExpiry.tv_nsec -= 1000000000L;
        }
        // A token is never 0, so a zeroed token can be told from a live one.
        if (++fadeLastIssued == 0)
            fadeLastIssued = 1;
        fadeHeld = true;
        *token = fadeLastIssued;
    }
    pthread_mutex_unlock(&fadeLock);
    return result;
}

// The documentation says releasing also unfades the display if needed; nothing is faded here, so
// there is nothing to undo.
CGError CGReleaseDisplayFadeReservation(CGDisplayFadeReservationToken token) {
    // Tokens are issued in increasing order. Releasing one that already ended
    // (expired, or released before) is safe and leaves the reservation in
    // effect now alone. GUESS: a token that was never issued has no documented
    // result code.
    CGError result = kCGErrorSuccess;
    pthread_mutex_lock(&fadeLock);
    if (token != 0 && token <= fadeLastIssued) {
        if (token == fadeLastIssued)
            fadeHeld = false;
    } else {
        result = kCGErrorIllegalArgument;
    }
    pthread_mutex_unlock(&fadeLock);
    return result;
}
