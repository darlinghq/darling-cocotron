/*
 * Display fade reservations (CGAcquireDisplayFadeReservation, CGReleaseDisplayFadeReservation,
 * CGDisplayFade, CGDisplayFadeReservationToken):
 * https://developer.apple.com/documentation/coregraphics/cgacquiredisplayfadereservation(_:_:)
 * https://developer.apple.com/documentation/coregraphics/cgreleasedisplayfadereservation(_:)
 * https://developer.apple.com/documentation/coregraphics/cgdisplayfadereservationtoken
 * Acquire stores a new token in the caller's storage; while a reservation is in effect another acquire reports
 * kCGErrorNoneAvailable; the token stops being valid when the interval ends or when it is released.
 * Undocumented details pinned to what was observed on macOS 26.7.3 (black-box, through the public API):
 *  - the reservation is system-wide: a second acquire from another process fails while one is held;
 *  - an interval of 0, a negative one, minus infinity and a NULL token pointer are kCGErrorIllegalArgument; any
 *    positive interval is accepted, also above kCGMaxDisplayReservationInterval (15.001, 100, infinity, 1e30), and NaN;
 *  - releasing, or fading with, a token that is released, expired, zero or never issued is
 *    kCGErrorIllegalArgument; fading with the token in effect succeeds.
 * Exit code 0 is success, otherwise the number of the failed check.
 */
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdio.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define CHECK(n, cond) do { if (!(cond)) { printf("FAIL check %d: %s\n", n, #cond); return n; } } while (0)

// Child: acquiring must report none available while the parent holds the reservation (exit 0), and succeed
// when the parent holds none (exit 1 after releasing it again).
static int acquireInChild(void) {
    pid_t pid = fork();
    if (pid == 0) {
        CGDisplayFadeReservationToken token = 0;
        CGError err = CGAcquireDisplayFadeReservation(2, &token);
        if (err == kCGErrorSuccess)
            CGReleaseDisplayFadeReservation(token);
        _exit(err == kCGErrorNoneAvailable ? 0 : err == kCGErrorSuccess ? 1 : 2);
    }
    int status = 0;
    waitpid(pid, &status, 0);
    return WIFEXITED(status) ? WEXITSTATUS(status) : 3;
}

int main(void) {
    // The token is written: a caller that starts from a recognisable value gets another one back.
    CGDisplayFadeReservationToken token = 0xdeadbeef;
    CHECK(1, CGAcquireDisplayFadeReservation(2, &token) == kCGErrorSuccess);
    CHECK(2, token != 0xdeadbeef && token != kCGDisplayFadeReservationInvalidToken);

    // The token is the one the other fade functions take.
    CHECK(3, CGDisplayFade(token, 0, 0, 0, 0, 0, 0, 1) == kCGErrorSuccess);

    // One reservation is in effect, so a second one is refused and leaves the caller's token alone.
    CGDisplayFadeReservationToken second = 0xdeadbeef;
    CHECK(4, CGAcquireDisplayFadeReservation(2, &second) == kCGErrorNoneAvailable);
    CHECK(5, second == 0xdeadbeef);
    // System-wide: another process is refused too.
    CHECK(6, acquireInChild() == 0);

    // Releasing ends it, so the hardware can be reserved again, with a new token, also by another process.
    CHECK(7, CGReleaseDisplayFadeReservation(token) == kCGErrorSuccess);
    CHECK(8, acquireInChild() == 1);
    CHECK(9, CGAcquireDisplayFadeReservation(2, &second) == kCGErrorSuccess);
    CHECK(10, second != token);
    // The old token is no reservation any more.
    CHECK(11, CGReleaseDisplayFadeReservation(token) == kCGErrorIllegalArgument);
    CHECK(12, CGDisplayFade(token, 0, 0, 0, 0, 0, 0, 1) == kCGErrorIllegalArgument);
    CHECK(13, CGReleaseDisplayFadeReservation(second) == kCGErrorSuccess);
    CHECK(14, CGReleaseDisplayFadeReservation(second) == kCGErrorIllegalArgument);

    // Zero and never-issued tokens.
    const CGDisplayFadeReservationToken bad[] = { 0, 1, 2, 12345, 0xFFFFFFFF };
    for (unsigned i = 0; i < sizeof bad / sizeof bad[0]; i++) {
        CHECK(20 + i, CGReleaseDisplayFadeReservation(bad[i]) == kCGErrorIllegalArgument);
        CHECK(30 + i, CGDisplayFade(bad[i], 0, 0, 0, 0, 0, 0, 1) == kCGErrorIllegalArgument);
    }

    // A reservation ends by itself when its interval has passed; releasing or fading with it is then illegal.
    CHECK(40, CGAcquireDisplayFadeReservation(0.05f, &token) == kCGErrorSuccess);
    struct timespec pause = {0, 200 * 1000 * 1000};
    nanosleep(&pause, NULL);
    CHECK(41, CGDisplayFade(token, 0, 0, 0, 0, 0, 0, 1) == kCGErrorIllegalArgument);
    CHECK(42, CGAcquireDisplayFadeReservation(2, &second) == kCGErrorSuccess);
    CHECK(43, CGReleaseDisplayFadeReservation(token) == kCGErrorIllegalArgument);
    // The old token does not release the reservation in effect now.
    CGDisplayFadeReservationToken third = 0xdeadbeef;
    CHECK(44, CGAcquireDisplayFadeReservation(2, &third) == kCGErrorNoneAvailable);
    CHECK(45, CGReleaseDisplayFadeReservation(second) == kCGErrorSuccess);

    // Intervals: invalid ones.
    const float invalid[] = { 0, -1, -INFINITY, -1e-6f };
    for (unsigned i = 0; i < sizeof invalid / sizeof invalid[0]; i++)
        CHECK(50 + i, CGAcquireDisplayFadeReservation(invalid[i], &third) == kCGErrorIllegalArgument);
    CHECK(55, CGAcquireDisplayFadeReservation(2, NULL) == kCGErrorIllegalArgument);
    // Valid ones, also beyond the documented maximum, and NaN.
    const float valid[] = { 1e-6f, 15, 15.001f, 16, 100, INFINITY, 1e30f, NAN };
    for (unsigned i = 0; i < sizeof valid / sizeof valid[0]; i++) {
        CHECK(60 + i, CGAcquireDisplayFadeReservation(valid[i], &third) == kCGErrorSuccess);
        // (the 1e-6 s reservation may already be over)
        if (valid[i] >= 15 || valid[i] != valid[i])
            CHECK(70 + i, CGReleaseDisplayFadeReservation(third) == kCGErrorSuccess);
        else
            CGReleaseDisplayFadeReservation(third);
    }

    puts("PASS: display fade reservations");
    return 0;
}
