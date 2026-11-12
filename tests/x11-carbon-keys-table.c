/* Copyright (C) 2026 Lubos Dolezel
 *
 * Checks the X11 keycode <-> Carbon virtual key code tables of the X11
 * backend: the keys a PC keyboard has beyond the first sixty-odd map to the
 * documented kVK_* codes, and the two tables agree with each other.
 *
 * Host build (no X11 or Darling needed): CarbonKeys.h only needs the kVK_*
 * constants of <HIToolbox/Events.h>, so give it a stub header made of the
 * constant lines of the real one:
 *   mkdir -p stub/HIToolbox
 *   (echo 'enum {'; grep -E '^ *kVK_[A-Za-z0-9_]+ += 0x[0-9A-Fa-f]+' \
 *        <darling>/src/frameworks/Carbon/HIToolbox/include/HIToolbox/Events.h \
 *        | sed 's/,*$/,/'; echo '};') > stub/HIToolbox/Events.h
 *   cc -Istub -I<cocotron>/AppKit/X11.backend -o carbon-keys-table carbon-keys-table.c
 */
#include <stdio.h>
#include "CarbonKeys.h"

static int failures;
#define CHECK(c, ...) do { if (!(c)) { printf("FAIL: " __VA_ARGS__); printf("\n"); failures++; } } while (0)

int main(void) {
    static const struct { int x11; int carbon; const char *name; } want[] = {
        { 94,  0x0A, "ISO key left of Z -> kVK_ISO_Section" },
        { 118, kVK_Help, "Insert -> kVK_Help" },
        { 125, kVK_ANSI_KeypadEquals, "KP_Equal -> kVK_ANSI_KeypadEquals" },
        { 194, kVK_F16, "F16" },
        { 195, kVK_F17, "F17" },
        { 196, kVK_F18, "F18" },
        { 197, kVK_F19, "F19" },
        { 198, kVK_F20, "F20" },
    };
    for (unsigned i = 0; i < sizeof(want) / sizeof(want[0]); i++) {
        CHECK(x11ToCarbon[want[i].x11] == want[i].carbon, "x11ToCarbon[%d]: %s", want[i].x11, want[i].name);
        CHECK(carbonToX11[want[i].carbon] == want[i].x11, "carbonToX11[0x%x]: %s", want[i].carbon, want[i].name);
    }
    /* the Menu key has no kVK_ constant: it stays unmapped */
    CHECK(x11ToCarbon[135] == 0, "Menu (135) must stay unmapped");

    /* every mapped X keycode round-trips, and no Carbon code is the target
       of two X keycodes (kVK_ANSI_A is 0, so the unmapped value is ambiguous
       only for it) */
    static const int mappedA = 38;
    int seen[256] = {0};
    for (int x = 0; x < 256; x++) {
        if (x11ToCarbon[x] == 0 && x != mappedA)
            continue;
        int c = x11ToCarbon[x];
        CHECK(!seen[c], "carbon 0x%x is the target of two X keycodes (second: %d)", c, x);
        seen[c] = 1;
        CHECK(carbonToX11[c] == x, "round trip x11 %d -> 0x%x -> %d", x, c, carbonToX11[c]);
    }
    if (!failures)
        puts("PASS: X11/Carbon key tables");
    return failures ? 1 : 0;
}
