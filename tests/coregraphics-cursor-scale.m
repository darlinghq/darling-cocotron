// Copyright (C) 2026 Lubos Dolezel
//
// The private cursor-scale SPI behaves as observed on macOS 26.7.3 (QUIRK, see CGSCursor.m): the getter writes a
// 4-byte float and starts at 1; the setter stores a value from 0.5 up to 16 exactly; a smaller value fails with
// kCGErrorFailure and a value of 16 or more, +infinity or NaN succeeds, both changing nothing; the value is
// system-wide, so a second process reads what the first set. The test restores 1 at the end.
// Build: clang -framework CoreGraphics <private include dir> coregraphics-cursor-scale.m
#import <CoreGraphics/CGSCursorPrivate.h>
#include <math.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <sys/wait.h>

extern char **environ;
static int failures;
#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static float Get(void)
{
    float scale = -7;
    CHECK(CGSGetCursorScale(0, &scale) == kCGErrorSuccess);
    return scale;
}

// Sets a value and checks the result and the value afterwards.
static void Set(float value, CGError expected, float after)
{
    CGError error = CGSSetCursorScale(0, value);
    if (error != expected || Get() != after)
        fprintf(stderr, "FAIL: set %g gave %d (want %d), reads %g (want %g)\n", value, error, expected, Get(), after);
    if (error != expected || Get() != after)
        failures++;
}

// A second process reads the value: its output is the value as text.
static float OtherProcessReads(const char *self)
{
    int fds[2];
    if (pipe(fds) != 0)
        return -1;
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, fds[1], 1);
    posix_spawn_file_actions_addclose(&actions, fds[0]);
    char *argv[] = { (char *) self, "get", NULL };
    pid_t pid;
    if (posix_spawn(&pid, self, &actions, NULL, argv, environ) != 0)
        return -1;
    close(fds[1]);
    char text[64] = "";
    ssize_t n = read(fds[0], text, sizeof(text) - 1);
    close(fds[0]);
    int status;
    waitpid(pid, &status, 0);
    return n > 0 ? strtof(text, NULL) : -1;
}

int main(int argc, char **argv)
{
    if (argc > 1 && !strcmp(argv[1], "get")) {
        float scale = 0;
        if (CGSGetCursorScale(0, &scale) != kCGErrorSuccess)
            return 1;
        printf("%.6f\n", scale);
        return 0;
    }

    // Four bytes only: the byte after the float stays as it was.
    unsigned char buffer[8];
    memset(buffer, 0xAB, sizeof(buffer));
    CHECK(CGSGetCursorScale(0, (float *) buffer) == kCGErrorSuccess);
    CHECK(buffer[4] == 0xAB && buffer[7] == 0xAB);
    CHECK(CGSGetCursorScale(0, NULL) == kCGErrorIllegalArgument);

    CHECK(Get() == 1.0f);
    float accepted[] = { 0.5f, 2.0f, 3.99f, 4.5f, 8.01f, 12.0f, 15.999f, 1.0f };
    for (size_t i = 0; i < sizeof(accepted) / sizeof(accepted[0]); i++)
        Set(accepted[i], kCGErrorSuccess, accepted[i]);

    Set(3.0f, kCGErrorSuccess, 3.0f);
    float tooSmall[] = { 0.49f, 0.1f, 0.001f, 0.0f, -1.0f, -INFINITY };
    for (size_t i = 0; i < sizeof(tooSmall) / sizeof(tooSmall[0]); i++)
        Set(tooSmall[i], kCGErrorFailure, 3.0f);
    float tooLarge[] = { 16.0f, 16.01f, 64.0f, 100.0f, INFINITY, NAN };
    for (size_t i = 0; i < sizeof(tooLarge) / sizeof(tooLarge[0]); i++)
        Set(tooLarge[i], kCGErrorSuccess, 3.0f);

    // System-wide: another process sees the value, and the restore.
    Set(2.0f, kCGErrorSuccess, 2.0f);
    CHECK(OtherProcessReads(argv[0]) == 2.0f);
    Set(1.0f, kCGErrorSuccess, 1.0f);
    CHECK(OtherProcessReads(argv[0]) == 1.0f);

    if (failures == 0)
        printf("PASS: cursor scale SPI\n");
    return failures ? 1 : 0;
}
