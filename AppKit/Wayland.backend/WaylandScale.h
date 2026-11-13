// Shared geometry for wp_fractional_scale_v1 (scale units are 1/120).
#ifndef WAYLAND_SCALE_H
#define WAYLAND_SCALE_H
#include <stdint.h>
#include <math.h>
#include <limits.h>

// The scale windows render at. NSScreen and NSWindow report whole scale
// factors, so a fractional preference is rounded up to the next whole scale:
// the buffer is drawn at that scale and presented at the logical size through
// the viewport, and the compositor scales it down.
static inline uint32_t WaylandIntegralScale120(uint32_t scale120) {
    uint64_t whole = ((uint64_t)scale120 + 119) / 120;
    if (whole == 0) whole = 1;
    return (uint32_t)(whole * 120);
}

// Round whole integral logical extents once, halfway away from zero. The limit
// belongs to the caller (drawable and SHM allocation limits can differ).
static inline int WaylandScaleExtent(int32_t logical, uint32_t scale120,
                                     int32_t limit, int32_t *pixels) {
    if (!pixels || logical <= 0 || !scale120 || limit <= 0) return 0;
    uint64_t value = ((uint64_t)logical * scale120 + 60) / 120;
    if (!value) value = 1;
    if (value > (uint32_t)limit) return 0;
    *pixels = (int32_t)value;
    return 1;
}

// A fractional surface uses wire buffer_scale=1: viewport source coordinates
// are buffer pixels. Quantize both logical crop endpoints against the actual
// rounded allocation; never separately round a crop width past the buffer.
static inline int WaylandScaleCrop(int32_t logical, int32_t pixels,
                                   int32_t start, int32_t end,
                                   int32_t *offset256, int32_t *extent256) {
    if (!offset256 || !extent256 || logical <= 0 || pixels <= 0 ||
        pixels > INT32_MAX / 256 || start < 0 || end <= start || end > logical)
        return 0;
    uint64_t left = ((uint64_t)start * pixels * 256 + logical / 2) / logical;
    uint64_t right = ((uint64_t)end * pixels * 256 + logical / 2) / logical;
    if (right <= left) return 0;
    *offset256 = (int32_t)left;
    *extent256 = (int32_t)(right - left);
    return 1;
}

// A cursor surface carries its scale only in wl_surface.buffer_scale, which is
// an integer: round the preferred scale up to a whole one (scale units 1/120).
static inline uint32_t WaylandCursorBufferScale120(uint32_t scale120) {
    if (!scale120) return 120;
    uint64_t whole = ((uint64_t)scale120 + 119) / 120;
    return whole > UINT32_MAX / 120 ? 120 : (uint32_t)(whole * 120);
}
// The scale to tag a cursor image of width x height with, at most `scale`: the largest
// whole one that divides both sizes. A buffer that is not a multiple of buffer_scale is an
// invalid_size protocol error, which some compositors answer by disconnecting the client
// (a theme with no image of the requested size returns its nearest one, e.g. 64 for 72).
static inline int32_t WaylandCursorWireScale(int32_t width, int32_t height, int32_t scale) {
    if (width < 1 || height < 1) return 1;
    for (int32_t k = scale; k > 1; k--)
        if (width % k == 0 && height % k == 0) return k;
    return 1;
}
#endif
