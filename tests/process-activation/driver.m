/*
 Copyright (C) 2026 Lubos Dolezel

 Licensed under the MIT license, the same as the rest of this project.
*/
// SetFrontProcess() must activate the windows of the process it names. Starts two windowed
// helper processes (helper.m), calls SetFrontProcess on each in turn and checks that the
// named one reports -[NSApplication isActive] and the other one does not.
//   driver <helper> x11       checks the helpers' state (needs a window manager)
//   driver <helper> wayland   only makes the requests and holds the windows for 8 seconds so that the
//                             harness (run-wayland.sh) can ask the compositor; a compositor may grant
//                             focus only for requests tied to input, so it may mark the window urgent.
// Also checks the Process Manager's answers for a process that does not exist.
#include <ApplicationServices/ApplicationServices.h>
#include <errno.h>
#include <poll.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifndef kSetFrontProcessFrontWindowOnly
#define kSetFrontProcessFrontWindowOnly 1 /* public constant, absent from older installed headers */
#endif

extern char **environ;
static int failures;

static void expect(int condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", what);
        failures++;
    }
}

struct Helper {
    pid_t pid;
    int fd;
    int state;
    char buffer[256];
    size_t used;
};

static int startHelper(struct Helper *h, const char *path, const char *title, const char *x) {
    int fds[2];
    if (pipe(fds) != 0)
        return -1;
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, fds[1], 1);
    posix_spawn_file_actions_addclose(&actions, fds[0]);
    char *args[] = {(char *) path, (char *) title, (char *) x, NULL};
    int rc = posix_spawn(&h->pid, path, &actions, NULL, args, environ);
    posix_spawn_file_actions_destroy(&actions);
    close(fds[1]);
    h->fd = fds[0];
    h->state = -1;
    h->used = 0;
    return rc;
}

// Reads what the helper has printed so far (waiting at most timeoutMs for more), updating
// state from the STATE lines. Returns 1 when a READY line was seen.
static int pump(struct Helper *h, int timeoutMs) {
    int ready = 0;
    struct pollfd pfd = {h->fd, POLLIN, 0};
    while (poll(&pfd, 1, timeoutMs) > 0) {
        ssize_t n = read(h->fd, h->buffer + h->used, sizeof(h->buffer) - 1 - h->used);
        if (n <= 0)
            break;
        h->used += n;
        h->buffer[h->used] = 0;
        char *line = h->buffer, *end;
        while ((end = strchr(line, '\n')) != NULL) {
            *end = 0;
            int value;
            if (sscanf(line, "STATE %d", &value) == 1)
                h->state = value;
            else if (strncmp(line, "READY", 5) == 0)
                ready = 1;
            line = end + 1;
        }
        h->used = strlen(line);
        memmove(h->buffer, line, h->used + 1);
        timeoutMs = 0;
    }
    return ready;
}

static int waitReady(struct Helper *h) {
    for (int i = 0; i < 100; i++)
        if (pump(h, 100))
            return 1;
    return 0;
}

// Waits until the helper's state is wanted, pumping both helpers.
static int waitState(struct Helper *h, struct Helper *other, int wanted, int seconds) {
    for (int i = 0; i < seconds * 10; i++) {
        pump(h, 50);
        pump(other, 50);
        if (h->state == wanted)
            return 1;
    }
    return 0;
}

static OSErr front(pid_t pid, OptionBits options) {
    ProcessSerialNumber psn;
    OSErr err = GetProcessForPID(pid, &psn);
    if (err != noErr)
        return err;
    return SetFrontProcessWithOptions(&psn, options);
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: driver <helper> x11|wayland\n");
        return 2;
    }
    int wayland = strcmp(argv[2], "wayland") == 0;
    struct Helper a, b;
    if (startHelper(&a, argv[1], "process-activation-A", "100") != 0 ||
        startHelper(&b, argv[1], "process-activation-B", "400") != 0) {
        fprintf(stderr, "FAIL: cannot start the helpers\n");
        return 1;
    }
    expect(waitReady(&a), "helper A is on screen");
    expect(waitReady(&b), "helper B is on screen");

    // No such process.
    ProcessSerialNumber none = {0, 0x7ffffff0};
    expect(SetFrontProcess(&none) == procNotFound, "SetFrontProcess of a missing process is procNotFound");

    if (wayland) {
        expect(front(a.pid, 0) == noErr, "SetFrontProcess(A) succeeds");
        printf("REQUESTED A\n");
        sleep(8);
    } else {
        // B was created last and is expected to hold the focus; take it to A, and back.
        expect(front(a.pid, kSetFrontProcessFrontWindowOnly) == noErr, "SetFrontProcess(A) succeeds");
        expect(waitState(&a, &b, 1, 5), "A is active after SetFrontProcess(A)");
        expect(waitState(&b, &a, 0, 5), "B is inactive after SetFrontProcess(A)");
        expect(front(b.pid, 0) == noErr, "SetFrontProcess(B) succeeds");
        expect(waitState(&b, &a, 1, 5), "B is active after SetFrontProcess(B)");
        expect(waitState(&a, &b, 0, 5), "A is inactive after SetFrontProcess(B)");
    }

    kill(a.pid, SIGKILL);
    kill(b.pid, SIGKILL);
    printf(failures == 0 ? "PASS\n" : "FAIL\n");
    return failures != 0;
}
