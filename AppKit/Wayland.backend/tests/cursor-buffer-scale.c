// Host check (plain cc, no Wayland needed): the buffer scale the backend gives a
// cursor surface. A compositor shows a cursor at buffer size / buffer scale and
// ignores any wp_viewport destination, so the raster must be made at the whole
// scale the surface is tagged with, whatever the output scale is.
//   cc -I.. -o /tmp/cursor-buffer-scale cursor-buffer-scale.c && /tmp/cursor-buffer-scale
#include "WaylandScale.h"
#include <stdio.h>

static int failures;
static void expect(int ok, const char *what, unsigned a, unsigned b) {
    if (!ok) { failures++; printf("FAIL %s (%u, %u)\n", what, a, b); }
}

int main(void) {
    static const struct { uint32_t in, whole; } cases[] = {
        {0, 120}, {1, 120}, {120, 120}, {121, 240}, {150, 240}, {180, 240}, {210, 240},
        {240, 240}, {241, 360}, {300, 360}, {360, 360}, {UINT32_MAX, 120},
    };
    for (unsigned i = 0; i < sizeof cases / sizeof cases[0]; i++)
        expect(WaylandCursorBufferScale120(cases[i].in) == cases[i].whole, "whole scale", cases[i].in, cases[i].whole);

    // What the compositor shows: the theme is loaded at nominal * whole scale and the
    // surface tagged with the whole scale, so the logical size is the nominal 24.
    for (uint32_t output = 120; output <= 480; output += 30) {
        uint32_t whole = WaylandCursorBufferScale120(output);
        int32_t pixels;
        expect(WaylandScaleExtent(24, whole, INT32_MAX, &pixels), "extent", output, whole);
        expect(pixels / (int32_t)(whole / 120) == 24, "logical cursor size", output, pixels);
        expect(whole >= output, "never below the output scale", output, whole);
    }
    // The scale a theme image is tagged with: it must divide the image exactly. 72 and 48 are the
    // requested sizes (24 at 3x and 2x); 64 is what a theme without a 72 hands back.
    static const struct { int32_t w, h, scale, wire; } wire[] = {
        {72, 72, 3, 3}, {64, 64, 3, 2}, {48, 48, 2, 2}, {25, 25, 2, 1}, {24, 25, 2, 1}, {32, 24, 2, 2},
        {24, 24, 1, 1}, {64, 63, 3, 1}, {96, 96, 4, 4}, {90, 60, 4, 3}, {0, 24, 2, 1}, {24, 24, 0, 1},
    };
    for (unsigned i = 0; i < sizeof wire / sizeof wire[0]; i++) {
        int32_t got = WaylandCursorWireScale(wire[i].w, wire[i].h, wire[i].scale);
        expect(got == wire[i].wire, "wire scale", wire[i].w * 1000 + wire[i].scale, got);
        expect(wire[i].w < 1 || wire[i].w % got == 0, "buffer is a multiple of the scale", wire[i].w, got);
    }
    printf(failures ? "RESULT failures=%d\n" : "PASS cursor buffer scale\n", failures);
    return failures != 0;
}
