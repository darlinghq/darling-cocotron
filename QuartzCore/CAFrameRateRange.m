// Copyright (C) 2026 Lubos Dolezel
// This file is part of Darling; see the license of the repository.

#import <QuartzCore/CAFrameRateRange.h>

const CAFrameRateRange CAFrameRateRangeDefault = {0, 0, 0};

CAFrameRateRange CAFrameRateRangeMake(float minimum, float maximum, float preferred) {
    // The values are stored as given; no ordering or range is enforced.
    CAFrameRateRange range = {minimum, maximum, preferred};
    return range;
}

bool CAFrameRateRangeIsEqualToRange(CAFrameRateRange range, CAFrameRateRange other) {
    return range.minimum == other.minimum && range.maximum == other.maximum && range.preferred == other.preferred;
}
