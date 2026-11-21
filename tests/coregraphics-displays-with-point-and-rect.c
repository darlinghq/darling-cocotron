// CGGetDisplaysWithPoint and CGGetDisplaysWithRect, as documented
// (https://developer.apple.com/documentation/coregraphics/cggetdisplayswithpoint(_:_:_:_:)):
// the displays array may be NULL, and then the count is of all the displays that
// match; with an array the count is of the IDs written, at most maxDisplays.
// Needs a display (X11 or Wayland session).
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

int main(void)
{
    CGDirectDisplayID main = CGMainDisplayID();
    CGRect bounds = CGDisplayBounds(main);
    CGPoint inside = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    CGPoint nowhere = CGPointMake(-100000, -100000);
    CGRect nowhereRect = CGRectMake(-100000, -100000, 10, 10);
    CGDirectDisplayID ids[MAX];
    uint32_t count = 99, total = 0;

    // A point on the main display: the display is listed.
    CHECK(CGGetDisplaysWithPoint(inside, MAX, ids, &count) == kCGErrorSuccess);
    CHECK(count >= 1 && count <= MAX && contains(ids, count, main));
    uint32_t written = count;

    // No array: the count is of all that match, the same as when there is room for them.
    CHECK(CGGetDisplaysWithPoint(inside, MAX, NULL, &total) == kCGErrorSuccess);
    CHECK(total == written);
    CHECK(CGGetDisplaysWithPoint(inside, 0, NULL, &total) == kCGErrorSuccess && total == written);

    // An array with no room is not written to; the count is of all that match.
    memset(ids, 0xAB, sizeof ids);
    CHECK(CGGetDisplaysWithPoint(inside, 0, ids, &total) == kCGErrorSuccess && total == written);
    CHECK(ids[0] == 0xABABABAB);

    // Room for one: at most one ID is written and counted.
    CHECK(CGGetDisplaysWithPoint(inside, 1, ids, &count) == kCGErrorSuccess && count == 1);

    // The count is optional.
    CHECK(CGGetDisplaysWithPoint(inside, MAX, ids, NULL) == kCGErrorSuccess);

    // A point on no display.
    count = 99;
    CHECK(CGGetDisplaysWithPoint(nowhere, MAX, ids, &count) == kCGErrorSuccess && count == 0);

    // The same for a rectangle.
    CHECK(CGGetDisplaysWithRect(bounds, MAX, ids, &count) == kCGErrorSuccess);
    CHECK(count >= 1 && count <= MAX && contains(ids, count, main));
    written = count;
    CHECK(CGGetDisplaysWithRect(bounds, MAX, NULL, &total) == kCGErrorSuccess && total == written);
    memset(ids, 0xAB, sizeof ids);
    CHECK(CGGetDisplaysWithRect(bounds, 0, ids, &total) == kCGErrorSuccess && total == written);
    CHECK(ids[0] == 0xABABABAB);
    CHECK(CGGetDisplaysWithRect(bounds, 1, ids, &count) == kCGErrorSuccess && count == 1);
    CHECK(CGGetDisplaysWithRect(bounds, MAX, ids, NULL) == kCGErrorSuccess);
    count = 99;
    CHECK(CGGetDisplaysWithRect(nowhereRect, MAX, ids, &count) == kCGErrorSuccess && count == 0);

    printf(failures ? "FAILED\n" : "PASSED\n");
    return failures != 0;
}
