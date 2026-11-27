// Copyright (C) 2026 Darling Developers
//
// Contract checks for CGDisplayStream properties, update rects, IOSurface
// ownership and the Stopped callback. Backend-dependent checks are skipped
// when a capture backend is unavailable.

#include <CoreGraphics/CGDisplayStream.h>
#include <IOSurface/IOSurfaceRef.h>
#include <dispatch/dispatch.h>
#include <stdio.h>
#include <time.h>
#include <string.h>

#define HELD_SURFACES 3

static int failures;
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static void check_string(CFStringRef value, const char *expected)
{
    char buffer[128] = "";
    CHECK(value != NULL);
    if (value == NULL)
        return;
    CHECK(CFStringGetCString(value, buffer, sizeof(buffer), kCFStringEncodingUTF8));
    CHECK(strcmp(buffer, expected) == 0);
}

int main(void)
{
    CHECK(kCGDisplayStreamFrameStatusFrameComplete == 0);
    CHECK(kCGDisplayStreamFrameStatusFrameIdle == 1);
    CHECK(kCGDisplayStreamFrameStatusFrameBlank == 2);
    CHECK(kCGDisplayStreamFrameStatusStopped == 3);
    CHECK(kCGDisplayStreamUpdateRefreshedRects == 0);
    CHECK(kCGDisplayStreamUpdateMovedRects == 1);
    CHECK(kCGDisplayStreamUpdateDirtyRects == 2);
    CHECK(kCGDisplayStreamUpdateReducedDirtyRects == 3);

    check_string(kCGDisplayStreamSourceRect, "kCGDisplayStreamSourceRect");
    check_string(kCGDisplayStreamDestinationRect, "kCGDisplayStreamDestinationRect");
    check_string(kCGDisplayStreamPreserveAspectRatio, "kCGDisplayStreamPreserveAspectRatio");
    check_string(kCGDisplayStreamColorSpace, "kCGDisplayStreamColorSpace");
    check_string(kCGDisplayStreamMinimumFrameTime, "kCGDisplayStreamMinimumFrameTime");
    check_string(kCGDisplayStreamShowCursor, "kCGDisplayStreamShowCursor");
    check_string(kCGDisplayStreamQueueDepth, "kCGDisplayStreamQueueDepth");

    CHECK(CGDisplayStreamUpdateGetDropCount(NULL) == 0);
    size_t count = 99;
    CHECK(CGDisplayStreamUpdateGetRects(NULL, kCGDisplayStreamUpdateRefreshedRects, &count) == NULL);
    CHECK(count == 0);
    count = 99;
    CHECK(CGDisplayStreamUpdateGetRects(NULL, (CGDisplayStreamUpdateRectType) 100, &count) == NULL);
    CHECK(count == 0);

    CHECK(CGDisplayStreamStart(NULL) == kCGErrorIllegalArgument);
    CHECK(CGDisplayStreamStop(NULL) == kCGErrorIllegalArgument);
    CHECK(CGDisplayStreamCreateWithDispatchQueue(CGMainDisplayID(), 16, 16, 'BGRA', NULL, NULL,
        ^(CGDisplayStreamFrameStatus status, uint64_t time, IOSurfaceRef surface,
          CGDisplayStreamUpdateRef update) { (void) status; (void) time; (void) surface; (void) update; }) == NULL);

    dispatch_queue_t queue = dispatch_queue_create("cg-display-stream-contract", NULL);
    __block int stopCount = 0;
    __block int duplicateSurface = 0;
    __block size_t heldCount = 0;
    __block IOSurfaceRef *held = (IOSurfaceRef *) calloc(HELD_SURFACES, sizeof(IOSurfaceRef));
    dispatch_semaphore_t stopped = dispatch_semaphore_create(0);
    dispatch_semaphore_t frames = dispatch_semaphore_create(0);
    CHECK(held != NULL);
    CGDisplayStreamRef stream = CGDisplayStreamCreateWithDispatchQueue(CGMainDisplayID(), 16, 16,
        'BGRA', NULL, queue, ^(CGDisplayStreamFrameStatus status, uint64_t time,
                              IOSurfaceRef surface, CGDisplayStreamUpdateRef update) {
            (void) time; (void) update;
            if (status == kCGDisplayStreamFrameStatusStopped) {
                stopCount++;
                dispatch_semaphore_signal(stopped);
                return;
            }
            if (status != kCGDisplayStreamFrameStatusFrameComplete || surface == NULL)
                return;
            CHECK(IOSurfaceGetUseCount(surface) >= 1);
            for (size_t i = 0; i < heldCount; i++) {
                if (held[i] == surface)
                    duplicateSurface = 1;
            }
            if (!duplicateSurface && heldCount < HELD_SURFACES) {
                held[heldCount] = (IOSurfaceRef) CFRetain(surface);
                IOSurfaceIncrementUseCount(held[heldCount]);
                heldCount++;
            }
            if (heldCount == HELD_SURFACES)
                dispatch_semaphore_signal(frames);
        });
    CHECK(stream != NULL);
    if (stream != NULL) {
        if (CGDisplayStreamStart(stream) == kCGErrorSuccess) {
            dispatch_semaphore_wait(frames,
                dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
            CHECK(!duplicateSurface);
            for (size_t i = 0; i < heldCount; i++) {
                IOSurfaceDecrementUseCount(held[i]);
                CFRelease(held[i]);
            }
            heldCount = 0;
            CHECK(CGDisplayStreamStop(stream) == kCGErrorSuccess);
            CHECK(dispatch_semaphore_wait(stopped,
                dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
            CHECK(stopCount == 1);
            CHECK(CGDisplayStreamStop(stream) == kCGErrorSuccess);
            CHECK(dispatch_semaphore_wait(stopped,
                dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 10)) != 0);
            CHECK(stopCount == 1);
        }
        CFRelease(stream);
    }

    /* kCGDisplayStreamMinimumFrameTime limits how often frames are delivered, and the display
     * times of delivered frames increase. */
    {
        __block int throttled = 0;
        __block uint64_t previous = 0;
        __block int decreasing = 0;
        dispatch_queue_t tq = dispatch_queue_create("cg-display-stream-throttle", NULL);
        double minimum = 0.5;
        CFNumberRef number = CFNumberCreate(NULL, kCFNumberDoubleType, &minimum);
        CFMutableDictionaryRef properties = CFDictionaryCreateMutable(NULL, 0,
            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CFDictionarySetValue(properties, kCGDisplayStreamMinimumFrameTime, number);
        CGDisplayStreamRef slow = CGDisplayStreamCreateWithDispatchQueue(CGMainDisplayID(), 16, 16,
            'BGRA', properties, tq, ^(CGDisplayStreamFrameStatus status, uint64_t time,
                                     IOSurfaceRef surface, CGDisplayStreamUpdateRef update) {
                (void) surface; (void) update;
                if (status != kCGDisplayStreamFrameStatusFrameComplete)
                    return;
                if (time <= previous)
                    decreasing = 1;
                previous = time;
                throttled++;
            });
        CHECK(slow != NULL);
        if (slow != NULL) {
            if (CGDisplayStreamStart(slow) == kCGErrorSuccess) {
                struct timespec pause = { 3, 0 };
                nanosleep(&pause, NULL);
                CGDisplayStreamStop(slow);
                CHECK(throttled >= 2);
                CHECK(throttled <= 7);
                CHECK(!decreasing);
            }
            CFRelease(slow);
        }
        CFRelease(properties);
        CFRelease(number);
        dispatch_release(tq);
    }
    free(held);
    dispatch_release(queue);

    printf(failures ? "FAILED\n" : "PASSED\n");
    return failures != 0;
}
