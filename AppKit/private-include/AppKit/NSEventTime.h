/* Copyright (C) 2026 Lubos Dolezel
 *
 * Licensed under the MIT license, the same as the rest of this project.
 *
 * The time an NSEvent gets when nothing gives it one: seconds since the system started, on the
 * mach_absolute_time clock that -[NSProcessInfo systemUptime] is documented to count (neither counts
 * the time the system slept). */
#ifndef NSEVENTTIME_H
#define NSEVENTTIME_H

#include <mach/mach_time.h>
#import <Foundation/NSDate.h>

static inline NSTimeInterval NSEventCurrentTime(void) {
    static mach_timebase_info_data_t timebase;
    if (timebase.denom == 0)
        mach_timebase_info(&timebase);
    return (double) mach_absolute_time() * timebase.numer / timebase.denom / 1e9;
}

#endif
