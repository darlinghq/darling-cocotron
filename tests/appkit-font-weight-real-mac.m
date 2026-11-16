// Copyright (C) 2026 Lubos Dolezel
// The NSFontWeight constants hold the single-precision values macOS 26.7.3 (and macOS 10.14, where CGFloat is a float on i386)
// holds, widened to CGFloat: compared bit for bit, so integer-literal initialisers (numbers near 1e19) or double-precision decimals
// (-0.8 instead of -0.800000011920929) fail. Not run in Darling (prepared only).
#import <AppKit/AppKit.h>
#include <stdlib.h>
#include <string.h>

static void expect(BOOL condition, NSString *message)
{
    if (!condition)
    {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

#define CHECK(name, literal) do { \
    float single = literal; \
    CGFloat want = single; \
    CGFloat got = name; \
    expect(memcmp(&got, &want, sizeof got) == 0, [NSString stringWithFormat:@"%s is %.17g, expected %.17g", #name, (double)got, (double)want]); \
} while (0)

int main(void)
{
    @autoreleasepool
    {
        CHECK(NSFontWeightUltraLight, -0.8f);
        CHECK(NSFontWeightThin, -0.6f);
        CHECK(NSFontWeightLight, -0.4f);
        CHECK(NSFontWeightRegular, 0.0f);
        CHECK(NSFontWeightMedium, 0.23f);
        CHECK(NSFontWeightSemibold, 0.3f);
        CHECK(NSFontWeightBold, 0.4f);
        CHECK(NSFontWeightHeavy, 0.56f);
        CHECK(NSFontWeightBlack, 0.62f);
        NSLog(@"appkit-font-weight-real-mac: ok");
    }
    return 0;
}
