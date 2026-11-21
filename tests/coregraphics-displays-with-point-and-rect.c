// The display list functions count as documented
// (https://developer.apple.com/documentation/coregraphics/cggetdisplayswithpoint(_:_:_:_:),
// .../cggetdisplayswithrect(_:_:_:_:), .../cggetactivedisplaylist(_:_:_:) and
// .../cggetonlinedisplaylist(_:_:_:)): the displays array may be NULL, and
// then the count is of all the displays; with an array the count is of the IDs
// written, at most maxDisplays. Not pinned, because the pages leave it open: the
// count when maxDisplays is 0, and a NULL count pointer (the rect page requires a
// non-NULL one).
// Needs a display (X11 or Wayland session). The over-count that the "room
// for one" checks catch needs two or more displays; on one display they still
// check that at most one ID is written and counted.
#include <ApplicationServices/ApplicationServices.h>
#include <stdio.h>
#include <string.h>

static int failures;
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

enum { MAX = 32 };

static int contains(const CGDirectDisplayID *ids, uint32_t count, CGDirectDisplayID wanted)
{
    for (uint32_t i = 0; i < count; i++)
        if (ids[i] == wanted)
            return 1;
    return 0;
}

typedef CGError (*ListFn)(uint32_t, CGDirectDisplayID *, uint32_t *);

// A list function that takes no query: all, through a NULL array, and with room.
static void checkList(const char *name, ListFn list, CGDirectDisplayID main, int mainFirst)
{
    CGDirectDisplayID ids[MAX];
    uint32_t total = 0, count = 99;

    // NULL array with room claimed: nothing is written (this crashed) and the count is of all.
    if (list(MAX, NULL, &total) != kCGErrorSuccess || total < 1 || total > MAX) {
        printf("FAIL %s: count through a NULL array (%u)\n", name, total);
        failures++;
        return;
    }
    if (list(MAX, ids, &count) != kCGErrorSuccess || count != total || !contains(ids, count, main)) {
        printf("FAIL %s: all displays with room (%u of %u)\n", name, count, total);
        failures++;
    }
    if (mainFirst && ids[0] != main) {
        printf("FAIL %s: main display first\n", name);
        failures++;
    }
    // Room for one: one ID is written and counted, however many displays there are.
    memset(ids, 0xAB, sizeof ids);
    count = 99;
    if (list(1, ids, &count) != kCGErrorSuccess || count != 1 || ids[1] != 0xABABABAB) {
        printf("FAIL %s: room for one (count %u)\n", name, count);
        failures++;
    }
}

static CGError online(uint32_t max, CGDirectDisplayID *ids, uint32_t *count)
{
    return CGGetOnlineDisplayList(max, ids, count);
}

static CGError active(uint32_t max, CGDirectDisplayID *ids, uint32_t *count)
{
    return CGGetActiveDisplayList(max, ids, count);
}

static CGDirectDisplayID glMask;

static CGError withMask(uint32_t max, CGDirectDisplayID *ids, uint32_t *count)
{
    return CGGetDisplaysWithOpenGLDisplayMask(glMask, max, ids, count);
}

int main(void)
{
    CGDirectDisplayID main = CGMainDisplayID();
    CGRect bounds = CGDisplayBounds(main);
    CGPoint inside = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    CGPoint nowhere = CGPointMake(-100000, -100000);
    CGRect nowhereRect = CGRectMake(-100000, -100000, 10, 10);
    CGDirectDisplayID ids[MAX];
    uint32_t count = 99, total = 0;

    glMask = CGDisplayIDToOpenGLDisplayMask(main);
    checkList("CGGetOnlineDisplayList", online, main, 1);
    checkList("CGGetActiveDisplayList", active, main, 0);
    checkList("CGGetDisplaysWithOpenGLDisplayMask", withMask, main, 1);

    // A point on the main display: the display is listed.
    CHECK(CGGetDisplaysWithPoint(inside, MAX, ids, &count) == kCGErrorSuccess);
    CHECK(count >= 1 && count <= MAX && contains(ids, count, main));
    uint32_t written = count;

    // No array: the count is of all that match, the same as when there is room for them.
    CHECK(CGGetDisplaysWithPoint(inside, MAX, NULL, &total) == kCGErrorSuccess);
    CHECK(total == written);

    // An array with no room is not written to.
    memset(ids, 0xAB, sizeof ids);
    CHECK(CGGetDisplaysWithPoint(inside, 0, ids, &total) == kCGErrorSuccess);
    CHECK(ids[0] == 0xABABABAB);

    // Room for one: at most one ID is written and counted.
    memset(ids, 0xAB, sizeof ids);
    CHECK(CGGetDisplaysWithPoint(inside, 1, ids, &count) == kCGErrorSuccess && count == 1 && ids[1] == 0xABABABAB);

    // A point on no display.
    count = 99;
    CHECK(CGGetDisplaysWithPoint(nowhere, MAX, ids, &count) == kCGErrorSuccess && count == 0);

    // The same for a rectangle.
    CHECK(CGGetDisplaysWithRect(bounds, MAX, ids, &count) == kCGErrorSuccess);
    CHECK(count >= 1 && count <= MAX && contains(ids, count, main));
    written = count;
    CHECK(CGGetDisplaysWithRect(bounds, MAX, NULL, &total) == kCGErrorSuccess && total == written);
    memset(ids, 0xAB, sizeof ids);
    CHECK(CGGetDisplaysWithRect(bounds, 0, ids, &total) == kCGErrorSuccess);
    CHECK(ids[0] == 0xABABABAB);
    memset(ids, 0xAB, sizeof ids);
    CHECK(CGGetDisplaysWithRect(bounds, 1, ids, &count) == kCGErrorSuccess && count == 1 && ids[1] == 0xABABABAB);
    count = 99;
    CHECK(CGGetDisplaysWithRect(nowhereRect, MAX, ids, &count) == kCGErrorSuccess && count == 0);

    printf(failures ? "FAILED\n" : "PASSED\n");
    return failures != 0;
}
