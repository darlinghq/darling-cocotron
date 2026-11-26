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

static int checkStandard(CFStringRef source, CFStringRef standard, int failure_code) {
    CGColorSpaceRef space = CGColorSpaceCreateWithName(source);
    if (!space)
        return failure_code;
    CGColorSpaceRef copy = CGColorSpaceCreateCopyWithStandardRange(space);
    if (!copy || !CFEqual(CGColorSpaceGetName(copy), standard) ||
        CGColorSpaceUsesExtendedRange(copy))
        return failure_code + 1;
    CGColorSpaceRelease(copy);
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
    if ((r = check(kCGColorSpaceExtendedLinearITUR_2020,
                   kCGColorSpaceExtendedLinearITUR_2020,
                   kCGColorSpaceExtendedLinearITUR_2020, true, 70)))
        return r;

    if ((r = check(kCGColorSpaceITUR_2020, kCGColorSpaceExtendedITUR_2020,
                   kCGColorSpaceExtendedLinearITUR_2020, false, 80)))
        return r;
    if ((r = check(kCGColorSpaceLinearITUR_2020, kCGColorSpaceExtendedLinearITUR_2020,
                   kCGColorSpaceExtendedLinearITUR_2020, false, 90)))
        return r;

    // CGColorSpaceCreateCopyWithStandardRange: an extended space gives its
    // standard-range form; a standard-range space is given back as it is.
    if ((r = checkStandard(kCGColorSpaceExtendedSRGB, kCGColorSpaceSRGB, 100)))
        return r;
    if ((r = checkStandard(kCGColorSpaceExtendedLinearSRGB, kCGColorSpaceLinearSRGB, 110)))
        return r;
    if ((r = checkStandard(kCGColorSpaceExtendedDisplayP3, kCGColorSpaceDisplayP3, 120)))
        return r;
    if ((r = checkStandard(kCGColorSpaceExtendedITUR_2020, kCGColorSpaceITUR_2020, 130)))
        return r;
    if ((r = checkStandard(kCGColorSpaceExtendedLinearITUR_2020, kCGColorSpaceLinearITUR_2020, 140)))
        return r;
    if ((r = checkStandard(kCGColorSpaceSRGB, kCGColorSpaceSRGB, 150)))
        return r;
    if (CGColorSpaceCreateCopyWithStandardRange(NULL) != NULL)
        return 160;

    // Spaces without an extended-range form are rejected, not approximated.
    CGColorSpaceRef device = CGColorSpaceCreateDeviceRGB();
    if (CGColorSpaceUsesExtendedRange(device) ||
        CGColorSpaceCreateExtended(device) ||
        CGColorSpaceCreateExtendedLinearized(device))
        return 60;
    CGColorSpaceRef deviceCopy = CGColorSpaceCreateCopyWithStandardRange(device);
    if (deviceCopy != device)
        return 62;
    CGColorSpaceRelease(deviceCopy);
    CGColorSpaceRelease(device);

    CGColorSpaceRef pq = CGColorSpaceCreateWithName(kCGColorSpaceITUR_2100_PQ);
    if (!pq || CGColorSpaceUsesExtendedRange(pq) || CGColorSpaceCreateExtended(pq))
        return 61;
    CGColorSpaceRelease(pq);
    return 0;
}
