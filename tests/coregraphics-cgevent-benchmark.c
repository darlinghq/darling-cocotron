// Cost of the CGEvent operations the input path is made of, in nanoseconds per operation. Not a pass or
// fail test beyond a generous bound: it prints the numbers so that two builds can be compared.
// The posting rows need Darling's private event stream (they are skipped with -DNO_STREAM).
//
// Copyright (C) 2026 Lubos Dolezel
#include <ApplicationServices/ApplicationServices.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

#ifndef NO_STREAM
extern CGEventRef _CGSEventStreamCopyNextEvent(void);
extern void _CGSEventStreamSetReadySource(CFRunLoopSourceRef source, CFRunLoopRef runLoop);
#endif

static double nowNs(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1e9 + ts.tv_nsec;
}

static volatile long g_sink;
static long g_drained;

static void perform(void* info)
{
#ifndef NO_STREAM
    CGEventRef e;

    while ((e = _CGSEventStreamCopyNextEvent()) != NULL)
    {
        g_drained++;
        CFRelease(e);
    }
#endif
}

static CGEventRef passTap(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void* info)
{
    return event;
}

#define N 200000

static void report(const char* what, double start, long n)
{
    printf("%-52s %8.0f ns\n", what, (nowNs() - start) / n);
}

int main(void)
{
    double t;

    t = nowNs();
    for (long i = 0; i < N; i++)
    {
        CGEventRef e = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, CGPointMake(i, i), 0);
        CFRelease(e);
    }
    report("create + release a mouse moved event", t, N);

    CGEventRef e = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, CGPointMake(1, 2), 0);

    t = nowNs();
    for (long i = 0; i < N; i++)
    {
        CGEventSetIntegerValueField(e, kCGMouseEventClickState, (int) (i & 7));
        g_sink += CGEventGetIntegerValueField(e, kCGMouseEventClickState);
    }
    report("set + get an integer field", t, N);

    t = nowNs();
    for (long i = 0; i < N; i++)
    {
        CGEventRef c = CGEventCreateCopy(e);
        CFRelease(c);
    }
    report("copy + release an event", t, N);

    t = nowNs();
    for (long i = 0; i < N; i++)
    {
        CGEventSetLocation(e, CGPointMake(i, i));
        g_sink += (long) CGEventGetLocation(e).x + (long) CGEventGetFlags(e) + (long) CGEventGetTimestamp(e);
    }
    report("set location, get location, flags and time", t, N);

#ifndef NO_STREAM
    CFRunLoopSourceContext ctx;

    memset(&ctx, 0, sizeof ctx);
    ctx.perform = perform;

    CFRunLoopSourceRef source = CFRunLoopSourceCreate(NULL, 0, &ctx);

    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
    _CGSEventStreamSetReadySource(source, CFRunLoopGetCurrent());

    // Batches of 100 events, as a busy pointer makes them, drained by the waiting thread.
    t = nowNs();
    for (long i = 0; i < N / 100; i++)
    {
        for (int j = 0; j < 100; j++)
            CGEventPost(kCGHIDEventTap, e);
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, true);
    }
    report("post (no taps) + drain, 100 events per wake", t, N);
    printf("  events drained: %ld of %d\n", g_drained, N);

    CFMachPortRef tap = CGEventTapCreate(kCGHIDEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly, kCGEventMaskForAllEvents, passTap, NULL);

    if (tap)
    {
        CFRunLoopSourceRef tapSource = CFMachPortCreateRunLoopSource(NULL, tap, 0);

        CFRunLoopAddSource(CFRunLoopGetCurrent(), tapSource, kCFRunLoopDefaultMode);
        g_drained = 0;
        t = nowNs();
        for (long i = 0; i < N / 10 / 100; i++)
        {
            for (int j = 0; j < 100; j++)
                CGEventPost(kCGHIDEventTap, e);
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, true);
        }
        report("post + drain with one listen-only tap", t, N / 10);
        CFMachPortInvalidate(tap);
        CFRelease(tapSource);
        CFRelease(tap);
    }
    _CGSEventStreamSetReadySource(NULL, NULL);
    CFRelease(source);
#endif

    CFRelease(e);
    return 0;
}
