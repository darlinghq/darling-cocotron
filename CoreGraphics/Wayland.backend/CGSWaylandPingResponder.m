/* Copyright (C) 2026 Lubos Dolezel

 Permission is hereby granted, free of charge, to any person obtaining a copy of
 this software and associated documentation files (the "Software"), to deal in
 the Software without restriction, including without limitation the rights to
 use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
 of the Software, and to permit persons to whom the Software is furnished to do
 so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE. */

#import "CGSWaylandPingResponder.h"
#import "WaylandLibrary.h"
#import "WaylandProtocol.h"
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <stdlib.h>
#include <unistd.h>

// How long the thread leaves what arrived on the socket to the main thread before it reads it itself.
#define kMainThreadGraceMs 50

struct CGSWaylandPingResponder {
    struct wl_display *display;
    struct wl_event_queue *queue;
    struct wl_proxy *wmBase;
    struct wl_proxy *wmBaseRequests;
    CFRunLoopSourceRef mainWake;
    pthread_t thread;
    bool running;
    // Counts the main thread's own passes over the socket (see CGSWaylandPingResponderHeartbeat).
    uint32_t heartbeat;
    // Written to stop the thread; the thread polls the read end.
    int stopPipe[2];
};

// The one responder of the process (CoreGraphics has one connection), for the fork handlers.
static pthread_mutex_t gActiveLock = PTHREAD_MUTEX_INITIALIZER;
static CGSWaylandPingResponder *gActive;
static bool gForkRestart;
static pthread_once_t gForkHandlersOnce = PTHREAD_ONCE_INIT;

static void mainWakePerform(void *info) {
    void **context = info;
    ((void (*)(void *)) context[0])(context[1]);
}

// The dispatcher of the xdg_wm_base proxy. It runs on whichever thread dispatches the private queue and
// only marshals a request, which libwayland allows from any thread.
static int pingDispatch(const void *data, void *proxy, uint32_t opcode,
                        const struct wl_message *message, union wl_argument *args)
{
    (void) message;
    if (opcode == WP_WM_BASE_EV_PING) {
        const CGSWaylandPingResponder *responder = data;
        union wl_argument pong[1] = {{.u = args[0].u}};
        WaylandMarshal((struct wl_proxy *) proxy, WP_WM_BASE_PONG, NULL, 0, pong);
        WL.wl_display_flush(responder->display);
    }
    return 0;
}

static void *pingThreadMain(void *arg) {
    CGSWaylandPingResponder *responder = arg;
    struct wl_display *display = responder->display;
    struct wl_event_queue *queue = responder->queue;
    int socketFd = WL.wl_display_get_fd(display);

    // Anything that arrived before the thread started.
    if (WL.wl_display_dispatch_queue_pending(display, queue) < 0)
        return NULL;

    for (;;) {
        struct pollfd fds[2] = {
            {.fd = socketFd, .events = POLLIN},
            {.fd = responder->stopPipe[0], .events = POLLIN},
        };
        if (poll(fds, 2, -1) < 0) {
            if (errno == EINTR)
                continue;
            break;
        }
        // A broken connection is reported by the main thread's reader.
        if (fds[1].revents != 0 || (fds[0].revents & (POLLERR | POLLHUP | POLLNVAL)))
            break;
        if (!(fds[0].revents & POLLIN))
            continue;

        // The main thread serves the socket when it can, as it does without this thread: events keep
        // reaching it in the same batches, in its own run loop passes. The thread reads only what the
        // main thread leaves unread for a while, which is when it is too busy to answer the compositor.
        uint32_t heartbeat = __atomic_load_n(&responder->heartbeat, __ATOMIC_RELAXED);
        struct pollfd stop = {.fd = responder->stopPipe[0], .events = POLLIN};
        int stopped = poll(&stop, 1, kMainThreadGraceMs);
        if (stopped > 0)
            break;
        if (stopped < 0 && errno != EINTR)
            break;
        if (__atomic_load_n(&responder->heartbeat, __ATOMIC_RELAXED) != heartbeat)
            continue;

        while (WL.wl_display_prepare_read_queue(display, queue) != 0) {
            if (WL.wl_display_dispatch_queue_pending(display, queue) < 0)
                return NULL;
        }
        WL.wl_display_flush(display);

        // The main thread may have read what the poll saw.
        bool didRead = false;
        struct pollfd again = {.fd = socketFd, .events = POLLIN};
        if (poll(&again, 1, 0) > 0 && (again.revents & POLLIN)) {
            if (WL.wl_display_read_events(display) < 0)
                return NULL;
            didRead = true;
        } else {
            WL.wl_display_cancel_read(display);
        }

        if (WL.wl_display_dispatch_queue_pending(display, queue) < 0)
            return NULL;

        // The read also queued the events of the default queue, which the main thread alone dispatches:
        // it may be asleep in the run loop and would not see the socket readable any more.
        if (didRead && responder->mainWake != NULL) {
            CFRunLoopSourceSignal(responder->mainWake);
            CFRunLoopWakeUp(CFRunLoopGetMain());
        }
    }
    return NULL;
}

static void drainStopPipe(CGSWaylandPingResponder *responder) {
    char buffer[16];
    int flags = fcntl(responder->stopPipe[0], F_GETFL);
    fcntl(responder->stopPipe[0], F_SETFL, flags | O_NONBLOCK);
    while (read(responder->stopPipe[0], buffer, sizeof(buffer)) > 0)
        ;
    fcntl(responder->stopPipe[0], F_SETFL, flags);
}

static void stopThread(CGSWaylandPingResponder *responder) {
    if (!responder->running)
        return;
    char byte = 0;
    ssize_t written;
    do {
        written = write(responder->stopPipe[1], &byte, 1);
    } while (written < 0 && errno == EINTR);
    pthread_join(responder->thread, NULL);
    responder->running = false;
    drainStopPipe(responder);
}

static bool startThread(CGSWaylandPingResponder *responder) {
    if (responder->running)
        return true;
    if (pthread_create(&responder->thread, NULL, pingThreadMain, responder) != 0)
        return false;
    responder->running = true;
    return true;
}

// A fork must not copy a thread that holds one of libwayland's locks, so the thread is joined for the
// duration of the fork. The parent runs it again. The child gets none: it shares the connection's
// socket with the parent, so it is not the one to answer the compositor on it (a child that goes on
// to use the connection is on its own, as for every other framework; one that execs is unaffected).
static void forkPrepare(void) {
    pthread_mutex_lock(&gActiveLock);
    gForkRestart = false;
    if (gActive != NULL && gActive->running) {
        stopThread(gActive);
        gForkRestart = true;
    }
}

static void forkParent(void) {
    if (gActive != NULL && gForkRestart)
        startThread(gActive);
    pthread_mutex_unlock(&gActiveLock);
}

static void forkChild(void) {
    pthread_mutex_unlock(&gActiveLock);
}

static void installForkHandlers(void) {
    pthread_atfork(forkPrepare, forkParent, forkChild);
}

CGSWaylandPingResponder *CGSWaylandPingResponderCreate(struct wl_display *display,
                                                       void (*perform)(void *info), void *info)
{
    CGSWaylandPingResponder *responder = calloc(1, sizeof(*responder));
    if (responder == NULL)
        return NULL;
    responder->display = display;
    responder->stopPipe[0] = responder->stopPipe[1] = -1;
    responder->queue = WL.wl_display_create_queue(display);
    if (responder->queue == NULL || pipe(responder->stopPipe) != 0) {
        CGSWaylandPingResponderDestroy(responder);
        return NULL;
    }
    fcntl(responder->stopPipe[0], F_SETFD, FD_CLOEXEC);
    fcntl(responder->stopPipe[1], F_SETFD, FD_CLOEXEC);

    // The perform function and its argument live as long as the source.
    void **context = malloc(2 * sizeof(void *));
    if (context == NULL) {
        CGSWaylandPingResponderDestroy(responder);
        return NULL;
    }
    context[0] = (void *) perform;
    context[1] = info;
    CFRunLoopSourceContext sourceContext = {
        .version = 0,
        .info = context,
        .perform = mainWakePerform,
    };
    responder->mainWake = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &sourceContext);
    if (responder->mainWake == NULL) {
        free(context);
        CGSWaylandPingResponderDestroy(responder);
        return NULL;
    }
    CFRunLoopAddSource(CFRunLoopGetMain(), responder->mainWake, kCFRunLoopCommonModes);

    pthread_once(&gForkHandlersOnce, installForkHandlers);
    pthread_mutex_lock(&gActiveLock);
    gActive = responder;
    pthread_mutex_unlock(&gActiveLock);
    return responder;
}

struct wl_proxy *CGSWaylandPingResponderAdopt(CGSWaylandPingResponder *responder, struct wl_proxy *wmBase) {
    if (responder == NULL || responder->wmBase != NULL || wmBase == NULL)
        return NULL;
    // The wrapper takes the queue the proxy is on now, the default one: made before the proxy moves.
    struct wl_proxy *requests = WL.wl_proxy_create_wrapper(wmBase);
    if (requests == NULL)
        return NULL;
    WL.wl_proxy_add_dispatcher(wmBase, pingDispatch, responder, NULL);
    WL.wl_proxy_set_queue(wmBase, responder->queue);
    responder->wmBase = wmBase;
    responder->wmBaseRequests = requests;
    return requests;
}

bool CGSWaylandPingResponderStart(CGSWaylandPingResponder *responder) {
    if (responder == NULL || responder->wmBase == NULL)
        return false;
    pthread_mutex_lock(&gActiveLock);
    bool started = startThread(responder);
    pthread_mutex_unlock(&gActiveLock);
    return started;
}

void CGSWaylandPingResponderHeartbeat(CGSWaylandPingResponder *responder) {
    if (responder != NULL)
        __atomic_add_fetch(&responder->heartbeat, 1, __ATOMIC_RELAXED);
}

void CGSWaylandPingResponderDispatchPending(CGSWaylandPingResponder *responder) {
    if (responder != NULL)
        WL.wl_display_dispatch_queue_pending(responder->display, responder->queue);
}

void CGSWaylandPingResponderDestroy(CGSWaylandPingResponder *responder) {
    if (responder == NULL)
        return;
    pthread_mutex_lock(&gActiveLock);
    if (gActive == responder)
        gActive = NULL;
    stopThread(responder);
    pthread_mutex_unlock(&gActiveLock);

    if (responder->wmBaseRequests != NULL)
        WL.wl_proxy_wrapper_destroy(responder->wmBaseRequests);
    if (responder->wmBase != NULL)
        WL.wl_proxy_destroy(responder->wmBase);
    if (responder->queue != NULL)
        WL.wl_event_queue_destroy(responder->queue);
    if (responder->mainWake != NULL) {
        CFRunLoopSourceContext context;
        CFRunLoopSourceGetContext(responder->mainWake, &context);
        CFRunLoopSourceInvalidate(responder->mainWake);
        CFRelease(responder->mainWake);
        free(context.info);
    }
    if (responder->stopPipe[0] >= 0)
        close(responder->stopPipe[0]);
    if (responder->stopPipe[1] >= 0)
        close(responder->stopPipe[1]);
    free(responder);
}
