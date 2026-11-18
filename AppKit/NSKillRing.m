/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
#import "NSKillRing-Private.h"
#import <Foundation/NSString.h>
#import <Foundation/NSLock.h>

// QUIRK: the ring behaves as follows, none of it documented. Before
// _NSInitializeKillRing() every function is a no-op and the yank returns nil.
// Afterwards appends accumulate in the current entry until a new sequence
// starts or a yank (or the "yanked" state) happens; a new sequence makes the
// current entry empty; a yank returns the current entry (empty when nothing
// was killed) every time, it does not step to older entries.
// Evidence: black-box observation on macOS 26.7.3 (tier 2), probes calling the
// functions through dlsym. Test: appkit-kill-ring.m (test_quirk_* checks).

static NSLock *killRingLock;
static NSMutableString *currentEntry; // nil until initialised
static BOOL nextAppendStartsNewEntry;

static void lockKillRing(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        killRingLock = [[NSLock alloc] init];
    });
    [killRingLock lock];
}

void _NSInitializeKillRing(void) {
    lockKillRing();
    if (currentEntry == nil)
        currentEntry = [[NSMutableString alloc] init];
    [killRingLock unlock];
}

void _NSAppendToKillRing(NSString *text) {
    lockKillRing();
    if (currentEntry != nil) {
        if (nextAppendStartsNewEntry) {
            [currentEntry setString: @""];
            nextAppendStartsNewEntry = NO;
        }
        [currentEntry appendString: text];
    }
    [killRingLock unlock];
}

void _NSPrependToKillRing(NSString *text) {
    lockKillRing();
    if (currentEntry != nil) {
        if (nextAppendStartsNewEntry) {
            [currentEntry setString: @""];
            nextAppendStartsNewEntry = NO;
        }
        [currentEntry insertString: text atIndex: 0];
    }
    [killRingLock unlock];
}

void _NSNewKillRingSequence(void) {
    lockKillRing();
    if (currentEntry != nil) {
        [currentEntry setString: @""];
        nextAppendStartsNewEntry = NO;
    }
    [killRingLock unlock];
}

void _NSSetKillRingToYankedState(void) {
    lockKillRing();
    nextAppendStartsNewEntry = YES;
    [killRingLock unlock];
}

NSString *_NSYankFromKillRing(void) {
    NSString *result = nil;

    lockKillRing();
    if (currentEntry != nil) {
        result = [[currentEntry copy] autorelease];
        nextAppendStartsNewEntry = YES;
    }
    [killRingLock unlock];
    return result;
}
