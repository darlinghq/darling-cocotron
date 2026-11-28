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

#ifndef CGS_WAYLAND_PING_RESPONDER_H
#define CGS_WAYLAND_PING_RESPONDER_H

#include <CoreFoundation/CoreFoundation.h>
#include <stdbool.h>

struct wl_display;
struct wl_proxy;

// Answers xdg_wm_base.ping (see xdg-shell) from a thread of its own, so that a compositor that tests
// whether the client is responsive gets its pong even while the main thread is busy and not running
// the run loop that serves the connection.
//
// The xdg_wm_base proxy is moved to a private wl_event_queue that only this thread dispatches. The
// requests of that object (get_xdg_surface, create_positioner) are made on a wrapper that stays on the
// default queue, so the objects they create deliver their events on the default queue, to the main
// thread, as every other object of the connection does.
//
// The thread reads the socket with libwayland's multi-reader protocol, so it can share the descriptor
// with the main thread's reader, but it does so only when the main thread has not read what arrived within
// a short grace period. What it reads for the default queue it leaves there and wakes the main run loop,
// which dispatches it.
typedef struct CGSWaylandPingResponder CGSWaylandPingResponder;

// `perform` runs on the main run loop after the thread has read events that belong to the default queue.
CGSWaylandPingResponder *CGSWaylandPingResponderCreate(struct wl_display *display,
                                                       void (*perform)(void *info), void *info);

// Takes over `wmBase`, a just bound xdg_wm_base that has had no event yet: it answers its pings from now
// on. Returns the proxy to make the requests of the object on (from the main thread; NULL on failure).
struct wl_proxy *CGSWaylandPingResponderAdopt(CGSWaylandPingResponder *responder, struct wl_proxy *wmBase);

// Starts the thread, once the first object is adopted. Returns false when it cannot be started.
bool CGSWaylandPingResponderStart(CGSWaylandPingResponder *responder);

// Tells the thread that the main thread is serving the socket (call it on every pass of the main thread's reader). The
// thread reads the socket itself only when the main thread has left it unread for a short while.
void CGSWaylandPingResponderHeartbeat(CGSWaylandPingResponder *responder);

// Dispatches what the main thread's own reads left on the private queue.
void CGSWaylandPingResponderDispatchPending(CGSWaylandPingResponder *responder);

// Stops and joins the thread, destroys the proxies it adopted (the request wrapper first) and the queue.
// Call it with no xdg_surface or positioner left, before the display is disconnected.
void CGSWaylandPingResponderDestroy(CGSWaylandPingResponder *responder);

#endif
