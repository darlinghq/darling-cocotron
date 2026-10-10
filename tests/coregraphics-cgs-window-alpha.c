#include <CoreGraphics/CoreGraphics.h>
#include <CoreGraphics/CGSServerSPI.h>
#include <stdint.h>
#include <stdio.h>

int main(void) {
    CGSConnectionID first = CGSMainConnectionID();
    CGSConnectionID second = CGSMainConnectionID();
    printf("connection %u %u\n", first, second);
    if (first != second)
        return 11;

    // No window exists in this process, so the identifier cannot name one.
    CGError error = CGSSetWindowAlpha(first, UINT32_MAX, 0.5f);
    printf("alpha error %d\n", (int) error);
    if (error != kCGErrorIllegalArgument && error != kCGErrorNotImplemented)
        return 20;
    return 0;
}
