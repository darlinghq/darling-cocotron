#include <CoreGraphics/CoreGraphics.h>
#include <CoreGraphics/CGSServerSPI.h>
#include <stdio.h>

// Run with the pointer away from the screen origin (GUESS): a genuine (0,0)
// location would otherwise read as the no-connection result.
int main(void) {
    CGSConnectionID first = CGSMainConnectionID();
    CGSConnectionID second = CGSMainConnectionID();
    printf("connection %u %u\n", first, second);
    if (first == 0)
        return 10;
    if (first != second)
        return 11;

    CGEventRef event = CGEventCreate(NULL);
    if (!event)
        return 20;
    CGPoint location = CGEventGetLocation(event);
    CFRelease(event);
    printf("location %g,%g\n", location.x, location.y);
    if (location.x == 0 && location.y == 0)
        return 21;
    if (location.x == -1 && location.y == -1)
        return 22;
    return 0;
}
