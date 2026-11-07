#include <CoreGraphics/CGColorSpace.h>
#include <CoreFoundation/CoreFoundation.h>

static int check_name(CFStringRef name, int failure_code) {
    CGColorSpaceRef space = CGColorSpaceCreateWithName(name);
    if (!space)
        return failure_code;

    CFStringRef borrowed = CGColorSpaceGetName(space);
    if (!borrowed || !CFEqual(borrowed, name))
        return failure_code + 1;

    CFStringRef copied = CGColorSpaceCopyName(space);
    if (!copied || !CFEqual(copied, name))
        return failure_code + 2;
    CFRelease(copied);

    if (CGColorSpaceGetModel(space) != kCGColorSpaceModelRGB)
        return failure_code + 3;

    CGColorSpaceRelease(space);
    return 0;
}

int main(void) {
    const CFStringRef names[] = {
        kCGColorSpaceSRGB,
        kCGColorSpaceDisplayP3,
        kCGColorSpaceExtendedDisplayP3,
        kCGColorSpaceLinearDisplayP3,
        kCGColorSpaceExtendedLinearDisplayP3,
        kCGColorSpaceITUR_2100_PQ,
    };
    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
        int result = check_name(names[i], 10 + i * 4);
        if (result)
            return result;
    }

    CFStringRef dynamic = CFStringCreateWithCString(NULL,
        "kCGColorSpaceLinearDisplayP3", kCFStringEncodingUTF8);
    CGColorSpaceRef retained = CGColorSpaceCreateWithName(dynamic);
    CFRelease(dynamic);
    if (!retained || !CFEqual(CGColorSpaceGetName(retained),
                              kCGColorSpaceLinearDisplayP3))
        return 40;
    CGColorSpaceRelease(retained);

    if (CGColorSpaceCreateWithName(CFSTR("unknown-color-space")))
        return 41;

    CGColorSpaceRef device = CGColorSpaceCreateDeviceRGB();
    if (!device || CGColorSpaceGetName(device) || CGColorSpaceCopyName(device))
        return 42;
    CGColorSpaceRelease(device);
    return 0;
}
