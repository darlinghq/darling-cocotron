#import <CoreGraphics/CGDisplayFade.h>
#import <CoreGraphics/CGDirectDisplay.h>
#import <CoreGraphics/CGError.h>
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <pthread.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

// The display fade reservation is system-wide: observed on macOS 26.7.3 that a second acquire, also from
// another process, reports kCGErrorNoneAvailable while one is held, and that a token stops being valid when it
// is released or when its interval has passed (releasing or fading with such a token, or with a token that was
// never issued, reports kCGErrorIllegalArgument). Test: coregraphics-display-fade-reservation, which acquires
// in a child process as well.
// The one reservation is a small record in a file all processes of the system share, changed under an
// exclusive flock. A reservation whose owner process has died ends too, so a crashed client does not block
// the hardware until the interval is up.
typedef struct {
    uint32_t magic;
    uint32_t lastIssued;   // the last token handed out, never 0
    uint32_t heldToken;    // the reservation in effect, 0 if none
    int32_t owner;         // pid of the process that holds it
    int64_t expiry;        // CLOCK_REALTIME nanoseconds; INT64_MAX when the interval is not bounded
} FadeRecord;

#define FADE_MAGIC 0x43474644u
#define FADE_PATH "/var/tmp/.CGDisplayFadeReservation"

static int64_t nowNanoseconds(void) {
    struct timespec now;
    clock_gettime(CLOCK_REALTIME, &now);
    return (int64_t) now.tv_sec * 1000000000LL + now.tv_nsec;
}

// Opens and locks the record, reads it into `record` (a fresh one when the file is new or damaged) and drops a
// reservation that has ended. Returns the descriptor holding the lock, or -1.
static int lockRecord(FadeRecord *record) {
    int fd = open(FADE_PATH, O_RDWR | O_CREAT | O_CLOEXEC, 0666);
    if (fd < 0)
        return -1;
    // The file is shared by every user of the system.
    fchmod(fd, 0666);
    if (flock(fd, LOCK_EX) != 0) {
        close(fd);
        return -1;
    }
    if (pread(fd, record, sizeof *record, 0) != (ssize_t) sizeof *record || record->magic != FADE_MAGIC) {
        memset(record, 0, sizeof *record);
        record->magic = FADE_MAGIC;
    }
    if (record->heldToken != 0 &&
        (nowNanoseconds() >= record->expiry || (kill(record->owner, 0) != 0 && errno == ESRCH)))
        record->heldToken = 0;
    return fd;
}

static void unlockRecord(int fd, const FadeRecord *record) {
    pwrite(fd, record, sizeof *record, 0);
    flock(fd, LOCK_UN);
    close(fd);
}

// A token is valid while it is the reservation in effect.
static bool tokenInEffect(const FadeRecord *record, CGDisplayFadeReservationToken token) {
    return token != kCGDisplayFadeReservationInvalidToken && record->heldToken == token;
}

// Unchanged: nothing is faded. The token must be a reservation in effect, else the call fails with
// kCGErrorIllegalArgument (observed on macOS 26.7.3, also for a released, a zero and a never-issued token).
CGError CGDisplayFade(CGDisplayFadeReservationToken token,
                      CGDisplayFadeInterval duration,
                      CGDisplayBlendFraction startBlend,
                      CGDisplayBlendFraction endBlend, float redBlend,
                      float greenBlend, float blueBlend, boolean_t synchronous)
{
    FadeRecord record;
    int fd = lockRecord(&record);
    if (fd < 0)
        return kCGErrorFailure;
    bool valid = tokenInEffect(&record, token);
    unlockRecord(fd, &record);
    return valid ? kCGErrorSuccess : kCGErrorIllegalArgument;
}

CGError CGAcquireDisplayFadeReservation(CGDisplayReservationInterval seconds,
                                        CGDisplayFadeReservationToken *token)
{
    // Observed on macOS 26.7.3: an interval of 0, a negative one and minus infinity, and a NULL token pointer,
    // are illegal arguments; any positive interval is accepted, also one above kCGMaxDisplayReservationInterval
    // (15.001, 100, infinity, 1e30) and NaN.
    if (token == NULL || seconds <= 0)
        return kCGErrorIllegalArgument;

    FadeRecord record;
    int fd = lockRecord(&record);
    if (fd < 0)
        return kCGErrorFailure;
    CGError result = kCGErrorSuccess;
    if (record.heldToken != 0) {
        result = kCGErrorNoneAvailable;
    } else {
        // GUESS: the interval is used as given, however long; one that is NaN or too large to count is
        // unbounded and ends only with a release or with the death of the process (not observed).
        int64_t now = nowNanoseconds();
        int64_t expiry = INT64_MAX;
        if (seconds < 9e9f)
            expiry = now + (int64_t) ((double) seconds * 1e9);
        // A token is never 0, so a zeroed token can be told from a live one.
        if (++record.lastIssued == 0)
            record.lastIssued = 1;
        record.heldToken = record.lastIssued;
        record.owner = getpid();
        record.expiry = expiry;
        *token = record.heldToken;
    }
    unlockRecord(fd, &record);
    return result;
}

// The documentation says releasing also unfades the display if needed; nothing is faded here, so there is
// nothing to undo. A token that is not the reservation in effect (already released, expired, zero or never
// issued) is an illegal argument (observed on macOS 26.7.3).
CGError CGReleaseDisplayFadeReservation(CGDisplayFadeReservationToken token) {
    FadeRecord record;
    int fd = lockRecord(&record);
    if (fd < 0)
        return kCGErrorFailure;
    CGError result = kCGErrorIllegalArgument;
    if (tokenInEffect(&record, token)) {
        record.heldToken = 0;
        result = kCGErrorSuccess;
    }
    unlockRecord(fd, &record);
    return result;
}
