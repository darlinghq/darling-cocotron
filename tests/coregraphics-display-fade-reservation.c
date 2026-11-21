/*
 * Display fade reservations, as described in the documentation of
 * CGAcquireDisplayFadeReservation, CGReleaseDisplayFadeReservation and
 * CGDisplayFadeReservationToken:
 * https://developer.apple.com/documentation/coregraphics/cgacquiredisplayfadereservation(_:_:)
 * https://developer.apple.com/documentation/coregraphics/cgreleasedisplayfadereservation(_:)
 * https://developer.apple.com/documentation/coregraphics/cgdisplayfadereservationtoken
 * Acquire stores a new token in the caller's storage; while a reservation is
 * in effect another acquire reports kCGErrorNoneAvailable; the token stops
 * being valid when the interval ends or when it is released, and releasing an
 * expired token is safe. Exit code 0 is success, otherwise the number of the
 * failed check.
 */
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <time.h>

#define CHECK(n, cond) do { if (!(cond)) { printf("FAIL check %d: %s\n", n, #cond); return n; } } while (0)

int main(void) {
    // The token is written: a caller that starts from a recognisable value gets another one back.
    CGDisplayFadeReservationToken token = 0xdeadbeef;
    CHECK(1, CGAcquireDisplayFadeReservation(2, &token) == kCGErrorSuccess);
    CHECK(2, token != 0xdeadbeef);

    // The token is the one the other fade functions take.
    CHECK(3, CGDisplayFade(token, 0, 0, 1, 0, 0, 0, 1) == kCGErrorSuccess);

    // One reservation is in effect, so a second one is refused and leaves the caller's token alone.
    CGDisplayFadeReservationToken second = 0xdeadbeef;
    CHECK(4, CGAcquireDisplayFadeReservation(2, &second) == kCGErrorNoneAvailable);
    CHECK(5, second == 0xdeadbeef);

    // Releasing ends it, so the hardware can be reserved again, with a new token.
    CHECK(6, CGReleaseDisplayFadeReservation(token) == kCGErrorSuccess);
    CHECK(7, CGAcquireDisplayFadeReservation(2, &second) == kCGErrorSuccess);
    CHECK(8, second != token);
    CHECK(9, CGReleaseDisplayFadeReservation(second) == kCGErrorSuccess);

    // A reservation ends by itself when its interval has passed; releasing it is still safe.
    CHECK(10, CGAcquireDisplayFadeReservation(0.05f, &token) == kCGErrorSuccess);
    struct timespec pause = {0, 200 * 1000 * 1000};
    nanosleep(&pause, NULL);
    CHECK(11, CGAcquireDisplayFadeReservation(2, &second) == kCGErrorSuccess);
    CHECK(12, CGReleaseDisplayFadeReservation(token) == kCGErrorSuccess);
    // The old token does not release the reservation in effect now.
    CGDisplayFadeReservationToken third = 0xdeadbeef;
    CHECK(13, CGAcquireDisplayFadeReservation(2, &third) == kCGErrorNoneAvailable);
    CHECK(14, CGReleaseDisplayFadeReservation(second) == kCGErrorSuccess);

    puts("PASS: display fade reservations");
    return 0;
}
