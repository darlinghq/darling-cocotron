// SPDX-License-Identifier: MIT
// Copyright (C) 2026 Lubos Dolezel
//
// CGDataProviderCreateSequential: a provider that reads through getBytes, skipForward and rewind callbacks.
// Behaviour observed on macOS 26.7.3 and Mac OS X 10.14.4 (probe: mac-probes/gog-blockers/cgdataprovider-sequential.c;
// the program builds and runs there too): CGDataProviderCopyData rewinds, reads until getBytes returns 0 and rewinds
// again, on every call; releaseInfo runs once when the provider goes away; NULL callbacks, a NULL getBytes and a
// version other than 0 give NULL; skipForward, rewind and releaseInfo may be NULL.
#include <CoreGraphics/CoreGraphics.h>
#include <stdio.h>
#include <string.h>

static int failures;

static void expect(int ok, const char *what)
{
    printf("%s %s\n", ok ? "PASS" : "FAIL", what);
    if (!ok)
        failures++;
}

struct state {
    const char *data;
    size_t length, position;
    int rewinds, gets, released;
};

static size_t getBytes(void *info, void *buffer, size_t count)
{
    struct state *s = info;
    s->gets++;
    size_t n = s->length - s->position;
    if (n > count)
        n = count;
    memcpy(buffer, s->data + s->position, n);
    s->position += n;
    return n;
}

static off_t skipForward(void *info, off_t count)
{
    struct state *s = info;
    size_t n = s->length - s->position;
    if ((size_t)count < n)
        n = (size_t)count;
    s->position += n;
    return (off_t)n;
}

static void rewindState(void *info)
{
    struct state *s = info;
    s->rewinds++;
    s->position = 0;
}

static void releaseState(void *info)
{
    struct state *s = info;
    s->released++;
}

int main(void)
{
    struct state s = {"0123456789abcdef", 16, 0, 0, 0, 0};
    CGDataProviderSequentialCallbacks callbacks = {0, getBytes, skipForward, rewindState, releaseState};
    CGDataProviderRef provider = CGDataProviderCreateSequential(&s, &callbacks);
    expect(provider != NULL, "a sequential provider is made");
    if (provider == NULL)
        return 1;
    expect(s.gets == 0 && s.rewinds == 0, "nothing is read when the provider is made");

    CFDataRef data = CGDataProviderCopyData(provider);
    expect(data != NULL && CFDataGetLength(data) == 16 && memcmp(CFDataGetBytePtr(data), "0123456789abcdef", 16) == 0,
           "the copy of the data is everything the callbacks give");
    expect(s.rewinds == 2, "the copy rewinds before and after reading");
    if (data != NULL)
        CFRelease(data);

    s.position = 9;
    data = CGDataProviderCopyData(provider);
    expect(data != NULL && CFDataGetLength(data) == 16, "a copy starts from the beginning wherever the stream was");
    expect(s.rewinds == 4, "every copy is a new pass over the callbacks");
    if (data != NULL)
        CFRelease(data);

    CGDataProviderRetain(provider);
    CGDataProviderRelease(provider);
    expect(s.released == 0, "the info stays while the provider is retained");
    CGDataProviderRelease(provider);
    expect(s.released == 1, "releaseInfo runs once when the provider is gone");

    expect(CGDataProviderCreateSequential(&s, NULL) == NULL, "NULL callbacks give NULL");
    CGDataProviderSequentialCallbacks noGet = {0, NULL, skipForward, rewindState, releaseState};
    expect(CGDataProviderCreateSequential(&s, &noGet) == NULL, "a NULL getBytes gives NULL");
    CGDataProviderSequentialCallbacks versioned = {1, getBytes, skipForward, rewindState, releaseState};
    expect(CGDataProviderCreateSequential(&s, &versioned) == NULL, "a version other than 0 gives NULL");

    CGDataProviderSequentialCallbacks minimal = {0, getBytes, NULL, NULL, NULL};
    s.position = 0;
    CGDataProviderRef bare = CGDataProviderCreateSequential(&s, &minimal);
    expect(bare != NULL, "only getBytes is required");
    if (bare != NULL) {
        data = CGDataProviderCopyData(bare);
        expect(data != NULL && CFDataGetLength(data) == 16, "a provider with only getBytes copies its data");
        if (data != NULL)
            CFRelease(data);
        CGDataProviderRelease(bare);
    }

    printf(failures ? "FAILED %d\n" : "ALL PASSED\n", failures);
    return failures ? 1 : 0;
}
