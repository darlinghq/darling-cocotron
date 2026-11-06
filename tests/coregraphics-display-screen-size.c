#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>

// Needs a display (or the 1920 x 1080 default the backend reports without one).
// The EDID parsing is covered on the host by coregraphics-display-screen-size-edid.sh.
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

    // Apple documents 0 for a display that is not valid, so an off-screen window's
    // display 0 and an id no screen owns must not borrow the main display's size.
    CGSize unknown = CGDisplayScreenSize(0);
    if (unknown.width != 0 || unknown.height != 0)
        return 12;
    CGSize missing = CGDisplayScreenSize(0x7fff);
    if (missing.width != 0 || missing.height != 0)
        return 13;

    return 0;
}
