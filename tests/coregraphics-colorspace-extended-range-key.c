// Guest test: kCGColorSpaceExtendedRange is exported, and its string is its
// own name. Observed on macOS 26.7.3 (x86_64): CFShow printed
// "kCGColorSpaceExtendedRange".
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>

int main(void)
{
    int ok = kCGColorSpaceExtendedRange != NULL
        && CFEqual(kCGColorSpaceExtendedRange, CFSTR("kCGColorSpaceExtendedRange"));
    printf("%s: kCGColorSpaceExtendedRange\n", ok ? "PASS" : "FAIL");
    return !ok;
}
