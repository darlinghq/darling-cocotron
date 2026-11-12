// Copyright (C) 2026 Lubos Dolezel
//
// CAFrameRateRange: the default range, construction and comparison. Expected
// values were observed on macOS 27 (the same file builds and passes there).
#import <QuartzCore/QuartzCore.h>
#include <math.h>
#include <stdio.h>

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL line %d: %s\n", __LINE__, #cond); failures++; } } while (0)

int main(void) {
    CHECK(sizeof(CAFrameRateRange) == 3 * sizeof(float));

    // No preference: all zero.
    CHECK(CAFrameRateRangeDefault.minimum == 0);
    CHECK(CAFrameRateRangeDefault.maximum == 0);
    CHECK(CAFrameRateRangeDefault.preferred == 0);

    CAFrameRateRange r = CAFrameRateRangeMake(10, 60, 30);
    CHECK(r.minimum == 10 && r.maximum == 60 && r.preferred == 30);

    // Values are stored as given: no reordering, clamping or validation.
    CAFrameRateRange odd = CAFrameRateRangeMake(60, 10, 5);
    CHECK(odd.minimum == 60 && odd.maximum == 10 && odd.preferred == 5);
    CAFrameRateRange neg = CAFrameRateRangeMake(-1, -2, -3);
    CHECK(neg.minimum == -1 && neg.maximum == -2 && neg.preferred == -3);
    CAFrameRateRange nanr = CAFrameRateRangeMake(NAN, 1, 2);
    CHECK(isnan(nanr.minimum) && nanr.maximum == 1 && nanr.preferred == 2);

    // Equality compares all three members.
    CHECK(CAFrameRateRangeIsEqualToRange(r, CAFrameRateRangeMake(10, 60, 30)));
    CHECK(!CAFrameRateRangeIsEqualToRange(r, CAFrameRateRangeMake(11, 60, 30)));
    CHECK(!CAFrameRateRangeIsEqualToRange(r, CAFrameRateRangeMake(10, 61, 30)));
    CHECK(!CAFrameRateRangeIsEqualToRange(r, CAFrameRateRangeMake(10, 60, 31)));
    CHECK(CAFrameRateRangeIsEqualToRange(CAFrameRateRangeDefault, CAFrameRateRangeMake(0, 0, 0)));
    CHECK(CAFrameRateRangeIsEqualToRange(CAFrameRateRangeMake(-0.0f, 0, 0), CAFrameRateRangeDefault)); // -0 == 0
    CHECK(!CAFrameRateRangeIsEqualToRange(nanr, nanr)); // NaN never compares equal

    if (failures) { printf("%d failure(s)\n", failures); return 1; }
    printf("PASS: CAFrameRateRange\n");
    return 0;
}
