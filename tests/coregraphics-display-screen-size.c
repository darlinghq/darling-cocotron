#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>

// Needs a display (or the 1920 x 1080 default the backend reports without one).
int main(void) {
    CGDirectDisplayID main_display = CGMainDisplayID();
    CGSize size = CGDisplayScreenSize(main_display);
    printf("main display %u: %g x %g mm\n", main_display, size.width, size.height);

    // A zero size makes callers' aspect ratio divide by zero.
    if (size.width <= 0 || size.height <= 0)
        return 10;

    // An EDID detailed timing that holds only an aspect ratio (16 x 9) is not a size.
    if (size.width < 100 || size.height < 50)
        return 11;

    // An off-screen window reports display 0; it must answer for the main display.
    CGSize unknown = CGDisplayScreenSize(0);
    if (unknown.width != size.width || unknown.height != size.height)
        return 12;

    return 0;
}
