#include <CoreGraphics/CoreGraphics.h>
#include <CoreGraphics/CGSServerSPI.h>
#include <stdio.h>

int main(void) {
    if (CGDisplayIsAsleep(CGMainDisplayID()))
        return 10;

    // Without a backend connection both queries below would trivially agree.
    if (CGSMainConnectionID() <= 0)
        return 11;

    CGEventRef event = CGEventCreate(NULL);
    if (!event)
        return 20;
    CGPoint expected = CGEventGetLocation(event);
    CFRelease(event);

    CGPoint pointer = CGSCurrentInputPointerPosition();
    printf("pointer %g,%g event %g,%g\n", pointer.x, pointer.y, expected.x, expected.y);
    if (pointer.x != expected.x || pointer.y != expected.y)
        return 21;
    return 0;
}
