/* AppKit's Pocket backend: sending on the host's socket.

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

// Sending on the Pocket socket: the one routine the backend and a host share, in plain C with POSIX
// calls only. See PocketProtocol.h.

#ifndef POCKET_SOCKET_H
#define POCKET_SOCKET_H

#include "PocketProtocol.h"

#include <errno.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/uio.h>

// Sends a whole message, with the descriptor `fd` (when it is not negative) attached to its first
// byte (SCM_RIGHTS). The socket may be non-blocking: a full socket is waited for, one second at a
// time. Returns 0, or -1 with errno set when the message is too long or the peer is gone.
static inline int pocket_send(int sock, uint32_t type, const void *payload, size_t size, int fd) {
    uint8_t message[sizeof(struct pocket_header) + POCKET_MAX_MESSAGE];
    size_t total = pocket_pack(message, type, payload, size);
    size_t sent = 0;
    if (total == 0) {
        errno = EMSGSIZE;
        return -1;
    }

    if (fd >= 0) {
        union {
            struct cmsghdr header;
            char space[CMSG_SPACE(sizeof(int))];
        } control;
        memset(&control, 0, sizeof(control));
        struct iovec iov = {.iov_base = message, .iov_len = total};
        struct msghdr msg = {
            .msg_iov = &iov,
            .msg_iovlen = 1,
            .msg_control = control.space,
            .msg_controllen = sizeof(control.space),
        };
        struct cmsghdr *cmsg = CMSG_FIRSTHDR(&msg);
        cmsg->cmsg_level = SOL_SOCKET;
        cmsg->cmsg_type = SCM_RIGHTS;
        cmsg->cmsg_len = CMSG_LEN(sizeof(int));
        memcpy(CMSG_DATA(cmsg), &fd, sizeof(int));

        ssize_t written;
        for (;;) {
            written = sendmsg(sock, &msg, 0);
            if (written >= 0 || (errno != EAGAIN && errno != EINTR))
                break;
            struct pollfd pfd = {.fd = sock, .events = POLLOUT};
            poll(&pfd, 1, 1000);
        }
        if (written <= 0)
            return -1;
        sent = (size_t) written;
    }

    while (sent < total) {
        ssize_t written = send(sock, message + sent, total - sent, 0);
        if (written < 0 && (errno == EAGAIN || errno == EINTR)) {
            struct pollfd pfd = {.fd = sock, .events = POLLOUT};
            poll(&pfd, 1, 1000);
            continue;
        }
        if (written <= 0)
            return -1;
        sent += (size_t) written;
    }
    return 0;
}

#endif
