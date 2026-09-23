#include <CoreGraphics/CGColorSpace.h>
#include <CoreFoundation/CoreFoundation.h>

static int check(CFStringRef source, CFStringRef extended,
                 CFStringRef extendedLinear, bool sourceIsExtended,
                 int failure_code) {
    CGColorSpaceRef space = CGColorSpaceCreateWithName(source);
    if (!space)
        return failure_code;
    if (CGColorSpaceUsesExtendedRange(space) != sourceIsExtended)
        return failure_code + 1;

    CGColorSpaceRef ext = CGColorSpaceCreateExtended(space);
    if (!ext || !CFEqual(CGColorSpaceGetName(ext), extended) ||
        !CGColorSpaceUsesExtendedRange(ext))
        return failure_code + 2;

    CGColorSpaceRef lin = CGColorSpaceCreateExtendedLinearized(space);
    if (!lin || !CFEqual(CGColorSpaceGetName(lin), extendedLinear) ||
        !CGColorSpaceUsesExtendedRange(lin))
        return failure_code + 3;

    CGColorSpaceRelease(lin);
    CGColorSpaceRelease(ext);
    CGColorSpaceRelease(space);
    return 0;
}

int main(void) {
    int r;
    if ((r = check(kCGColorSpaceSRGB, kCGColorSpaceExtendedSRGB,
                   kCGColorSpaceExtendedLinearSRGB, false, 10)))
        return r;
    if ((r = check(kCGColorSpaceLinearSRGB, kCGColorSpaceExtendedLinearSRGB,
                   kCGColorSpaceExtendedLinearSRGB, false, 20)))
        return r;
    if ((r = check(kCGColorSpaceExtendedSRGB, kCGColorSpaceExtendedSRGB,
                   kCGColorSpaceExtendedLinearSRGB, true, 30)))
        return r;
    if ((r = check(kCGColorSpaceDisplayP3, kCGColorSpaceExtendedDisplayP3,
                   kCGColorSpaceExtendedLinearDisplayP3, false, 40)))
        return r;
    if ((r = check(kCGColorSpaceExtendedLinearDisplayP3,
                   kCGColorSpaceExtendedLinearDisplayP3,
                   kCGColorSpaceExtendedLinearDisplayP3, true, 50)))
        return r;

    // Spaces without an extended-range form are rejected, not approximated.
    CGColorSpaceRef device = CGColorSpaceCreateDeviceRGB();
    if (CGColorSpaceUsesExtendedRange(device) ||
        CGColorSpaceCreateExtended(device) ||
        CGColorSpaceCreateExtendedLinearized(device))
        return 60;
    CGColorSpaceRelease(device);

    CGColorSpaceRef pq = CGColorSpaceCreateWithName(kCGColorSpaceITUR_2100_PQ);
    if (!pq || CGColorSpaceUsesExtendedRange(pq) || CGColorSpaceCreateExtended(pq))
        return 61;
    CGColorSpaceRelease(pq);
    return 0;
}
