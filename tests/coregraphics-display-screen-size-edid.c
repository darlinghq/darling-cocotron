// Host test for screenSizeFromEDID() in CoreGraphics/CGDirectDisplay.m. The script
// coregraphics-display-screen-size-edid.sh extracts that function and compiles it
// with this file; no Darling, X server or Objective-C runtime is needed.
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "screen-size-edid-extract.inc"

static int failures;
#define CHECK(c, msg) do { if (!(c)) { failures++; printf("FAIL line %d: %s\n", __LINE__, msg); } } while (0)

static void base(uint8_t *e) {
    memset(e, 0, 128);
    e[21] = 60; e[22] = 34; /* 600 x 340 mm from the basic parameters */
}

static void timing(uint8_t *e, int w, int h) {
    e[54] = 0x01; e[55] = 0x1d; /* non-zero pixel clock: a detailed timing */
    e[66] = w & 0xff; e[67] = h & 0xff;
    e[68] = (uint8_t) (((w >> 8) << 4) | (h >> 8));
}

int main(void) {
    uint8_t e[128];
    double w = 0, h = 0;

    base(e); timing(e, 598, 336);
    CHECK(screenSizeFromEDID(e, 128, &w, &h) && w == 598 && h == 336, "detailed timing size");

    /* The reviewed bug: a display descriptor first (pixel clock 0) holds text, and
     * bytes 66-68 of it must not be read as a size. */
    base(e); e[54] = 0; e[55] = 0; e[66] = 'A'; e[67] = 'B'; e[68] = 'C';
    CHECK(screenSizeFromEDID(e, 128, &w, &h) && w == 600 && h == 340, "display descriptor falls back to cm size");

    base(e); timing(e, 16, 9);
    CHECK(screenSizeFromEDID(e, 128, &w, &h) && w == 600 && h == 340, "16:9 aspect-only falls back");
    base(e); timing(e, 4, 3);
    CHECK(screenSizeFromEDID(e, 128, &w, &h) && w == 600 && h == 340, "4:3 aspect-only falls back");

    base(e); e[21] = 0; e[22] = 0;
    CHECK(!screenSizeFromEDID(e, 128, &w, &h), "no size anywhere");
    base(e);
    CHECK(!screenSizeFromEDID(e, 127, &w, &h), "short EDID");

    if (failures) return 1;
    printf("PASS\n");
    return 0;
}
