// SPDX-License-Identifier: MIT
//
// The Pocket backend's wire protocol (AppKit/Pocket.backend/PocketProtocol.h and PocketSocket.h): the
// layout of the messages, their framing and sending, the way a host receives them. The header is plain C, so this
// builds and runs on any Linux or macOS host, 32-bit or 64-bit, without Darling:
//   cc -I AppKit/Pocket.backend tests/appkit-pocket-protocol.c -o /tmp/pocket-protocol && /tmp/pocket-protocol
#include "PocketSocket.h"

#include <fcntl.h>
#include <pthread.h>
#include <stdio.h>
#include <sys/mman.h>
#include <unistd.h>

static int failures;
#define CHECK(cond, ...) do { if (!(cond)) { failures++; fprintf(stderr, "FAIL line %d: ", __LINE__); fprintf(stderr, __VA_ARGS__); fputc('\n', stderr); } } while (0)

static void testLayout(void) {
    // A host built for another ABI (32-bit, 64-bit) must see the same bytes.
    struct pocket_touch touch;
    CHECK(offsetof(struct pocket_touch, phase) == 0, "touch.phase offset");
    CHECK(offsetof(struct pocket_touch, finger) == 4, "touch.finger offset");
    CHECK(offsetof(struct pocket_touch, x) == 8, "touch.x offset");
    CHECK(offsetof(struct pocket_touch, y) == 12, "touch.y offset");
    CHECK(offsetof(struct pocket_touch, time) == 16, "touch.time offset");
    CHECK(sizeof(touch) == 24, "touch size %zu", sizeof(touch));
    CHECK(offsetof(struct pocket_window, level) == 24, "window.level offset");
    CHECK(offsetof(struct pocket_screen, inset_right) == 24, "screen.inset_right offset");
    CHECK(offsetof(struct pocket_keyboard, flags) == 20, "keyboard.flags offset");
    CHECK(offsetof(struct pocket_key, length) == 12, "key.length offset");
    // Phases are UITouch.Phase's (stationary is 2 and never sent).
    CHECK(POCKET_TOUCH_BEGAN == 0 && POCKET_TOUCH_MOVED == 1 && POCKET_TOUCH_ENDED == 3 &&
          POCKET_TOUCH_CANCELLED == 4, "touch phases");
}

static void testPack(void) {
    uint8_t out[sizeof(struct pocket_header) + POCKET_MAX_MESSAGE];
    struct pocket_screen screen = {1080, 2400, 2625, 90, 0, 48, 0};
    size_t length = pocket_pack(out, POCKET_SCREEN, &screen, sizeof(screen));
    CHECK(length == sizeof(struct pocket_header) + sizeof(screen), "pack length %zu", length);

    struct pocket_header header;
    CHECK(pocket_unpack(out, length, &header) == 1, "a whole message unpacks");
    CHECK(header.type == POCKET_SCREEN && header.size == sizeof(screen), "header fields");
    struct pocket_screen back;
    memcpy(&back, out + sizeof(header), sizeof(back));
    CHECK(memcmp(&back, &screen, sizeof(back)) == 0, "payload survives");

    for (size_t cut = 0; cut < length; cut++)
        CHECK(pocket_unpack(out, cut, &header) == 0, "%zu of %zu bytes is not a message", cut, length);

    CHECK(pocket_pack(out, POCKET_ORDER, NULL, 0) == sizeof(struct pocket_header), "an empty payload");
    CHECK(pocket_unpack(out, sizeof(struct pocket_header), &header) == 1 && header.size == 0, "empty message");

    uint8_t big[POCKET_MAX_MESSAGE + 1] = {0};
    CHECK(pocket_pack(out, POCKET_TEXT, big, POCKET_MAX_MESSAGE) == sizeof(header) + POCKET_MAX_MESSAGE,
          "the longest message is packed");
    CHECK(pocket_pack(out, POCKET_TEXT, big, POCKET_MAX_MESSAGE + 1) == 0, "a longer one is refused");

    // A peer that announces more than the limit is broken, even before the payload is there.
    struct pocket_header lie = {POCKET_TEXT, POCKET_MAX_MESSAGE + 1};
    memcpy(out, &lie, sizeof(lie));
    CHECK(pocket_unpack(out, sizeof(lie), &header) == -1, "an oversized message is broken");
    lie.size = POCKET_MAX_MESSAGE;
    memcpy(out, &lie, sizeof(lie));
    CHECK(pocket_unpack(out, sizeof(lie), &header) == 0, "a message of the limit's size is waited for");
}

// What a host's reader does: take bytes as they arrive, pull out whole messages.
struct reader {
    uint8_t buffer[POCKET_MAX_MESSAGE * 2];
    size_t have;
    int count;
    int broken;
    int fd; // for a reader thread
    uint32_t types[4];
};

static void feed(struct reader *reader, const uint8_t *bytes, size_t length) {
    if (reader->broken || length > sizeof(reader->buffer) - reader->have) {
        reader->broken = 1;
        return;
    }
    memcpy(reader->buffer + reader->have, bytes, length);
    reader->have += length;
    struct pocket_header header;
    int status;
    size_t offset = 0;
    while ((status = pocket_unpack(reader->buffer + offset, reader->have - offset, &header)) == 1) {
        if (reader->count < 4)
            reader->types[reader->count] = header.type;
        reader->count++;
        offset += sizeof(header) + header.size;
    }
    if (status < 0)
        reader->broken = 1;
    memmove(reader->buffer, reader->buffer + offset, reader->have - offset);
    reader->have -= offset;
}

static void testStream(void) {
    // The same messages arrive however the stream is cut into reads.
    uint8_t stream[3 * (sizeof(struct pocket_header) + POCKET_MAX_MESSAGE)];
    struct pocket_touch touch = {POCKET_TOUCH_MOVED, 2, 10.5f, 20.5f, 3.25};
    struct pocket_present present = {7, 0, 0, 100, 50};
    uint8_t text[300];
    memset(text, 'a', sizeof(text));
    size_t length = pocket_pack(stream, POCKET_TOUCH, &touch, sizeof(touch));
    length += pocket_pack(stream + length, POCKET_PRESENT, &present, sizeof(present));
    length += pocket_pack(stream + length, POCKET_TEXT, text, sizeof(text));

    for (size_t chunk = 1; chunk <= length; chunk++) {
        struct reader reader = {.count = 0};
        for (size_t sent = 0; sent < length; sent += chunk)
            feed(&reader, stream + sent, length - sent < chunk ? length - sent : chunk);
        CHECK(!reader.broken && reader.count == 3 && reader.have == 0, "chunk size %zu: %d messages, %zu left",
              chunk, reader.count, reader.have);
        CHECK(reader.types[0] == POCKET_TOUCH && reader.types[1] == POCKET_PRESENT && reader.types[2] == POCKET_TEXT,
              "chunk size %zu: message order", chunk);
    }

    // A stream that ends in the middle of a message leaves bytes behind.
    struct reader cut = {.count = 0};
    feed(&cut, stream, length - 1);
    CHECK(cut.count == 2 && cut.have > 0, "a truncated last message stays pending");

    // A peer that announces a message over the limit is broken.
    struct reader bad = {.count = 0};
    struct pocket_header lie = {POCKET_TEXT, POCKET_MAX_MESSAGE + 1};
    feed(&bad, (const uint8_t *) &lie, sizeof(lie));
    CHECK(bad.broken, "an oversized message breaks the reader");

    // The same bytes through a real stream socket.
    int sockets[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) != 0) {
        perror("socketpair");
        failures++;
        return;
    }
    CHECK(write(sockets[0], stream, length) == (ssize_t) length, "write to the socket");
    close(sockets[0]);
    struct reader reader = {.count = 0};
    uint8_t received[64];
    ssize_t got;
    while ((got = read(sockets[1], received, sizeof(received))) > 0)
        feed(&reader, received, (size_t) got);
    close(sockets[1]);
    CHECK(!reader.broken && reader.count == 3 && reader.have == 0, "socket: %d messages", reader.count);
}

// A host receiving one message and the descriptor that came with it.
static int receiveWithFd(int sock, struct pocket_header *header, uint8_t *payload, int *fd) {
    uint8_t message[sizeof(struct pocket_header) + POCKET_MAX_MESSAGE];
    union {
        struct cmsghdr header;
        char space[CMSG_SPACE(sizeof(int))];
    } control;
    struct iovec iov = {.iov_base = message, .iov_len = sizeof(message)};
    struct msghdr msg = {.msg_iov = &iov, .msg_iovlen = 1, .msg_control = control.space,
                         .msg_controllen = sizeof(control.space)};
    ssize_t got = recvmsg(sock, &msg, 0);
    *fd = -1;
    for (struct cmsghdr *cmsg = CMSG_FIRSTHDR(&msg); cmsg != NULL; cmsg = CMSG_NXTHDR(&msg, cmsg))
        if (cmsg->cmsg_level == SOL_SOCKET && cmsg->cmsg_type == SCM_RIGHTS)
            memcpy(fd, CMSG_DATA(cmsg), sizeof(int));
    if (got < (ssize_t) sizeof(*header) || pocket_unpack(message, (size_t) got, header) != 1)
        return -1;
    memcpy(payload, message + sizeof(*header), header->size);
    return 0;
}

// The buffer of a window: shared memory the host maps and reads what the application wrote.
static void testBufferDescriptor(void) {
    int sockets[2];
    FILE *file = tmpfile();
    if (file == NULL || socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) != 0) {
        perror("setup");
        failures++;
        return;
    }
    struct timeval timeout = {5, 0}; // a message that never comes fails the test instead of hanging it
    setsockopt(sockets[1], SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    int fd = fileno(file);
    size_t size = 64 * 4 * 16;
    CHECK(ftruncate(fd, (off_t) size) == 0, "size the buffer");
    uint8_t *pixels = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    CHECK(pixels != MAP_FAILED, "map the buffer");
    if (pixels == MAP_FAILED)
        return;
    memset(pixels, 0x7f, size);

    struct pocket_buffer buffer = {5, 64, 16, 64 * 4, POCKET_FORMAT_BGRA};
    CHECK(pocket_send(sockets[0], POCKET_BUFFER, &buffer, sizeof(buffer), fd) == 0, "send with a descriptor");
    pixels[100] = 0x11; // written after the send: the host maps the same memory
    CHECK(pocket_send(sockets[0], POCKET_PRESENT, &(struct pocket_present){5, 0, 0, 64, 16},
                      sizeof(struct pocket_present), -1) == 0, "send without one");

    struct pocket_header header;
    uint8_t payload[POCKET_MAX_MESSAGE];
    int received;
    CHECK(receiveWithFd(sockets[1], &header, payload, &received) == 0, "receive the buffer message");
    CHECK(header.type == POCKET_BUFFER && header.size == sizeof(buffer), "the buffer message");
    CHECK(received >= 0 && received != fd, "a new descriptor arrives with it");
    if (received >= 0) {
        const uint8_t *mapped = mmap(NULL, size, PROT_READ, MAP_SHARED, received, 0);
        CHECK(mapped != MAP_FAILED && mapped[0] == 0x7f && mapped[100] == 0x11 && mapped[size - 1] == 0x7f,
              "the host sees the application's pixels");
        close(received);
    }
    CHECK(receiveWithFd(sockets[1], &header, payload, &received) == 0 && header.type == POCKET_PRESENT &&
          received == -1, "the next message has no descriptor");
    close(sockets[0]);
    close(sockets[1]);
    fclose(file);
}

static void *slowReader(void *argument) {
    struct reader *reader = argument;
    uint8_t chunk[1000];
    ssize_t got;
    while ((got = read(reader->fd, chunk, sizeof(chunk))) > 0) {
        feed(reader, chunk, (size_t) got);
        usleep(200);
    }
    return NULL;
}

// A non-blocking socket that fills up: the sender waits for the host and loses nothing.
static void testFullSocket(void) {
    int sockets[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) != 0) {
        failures++;
        return;
    }
    int small = 4096;
    setsockopt(sockets[0], SOL_SOCKET, SO_SNDBUF, &small, sizeof(small));
    fcntl(sockets[0], F_SETFL, fcntl(sockets[0], F_GETFL) | O_NONBLOCK);
    static struct reader reader;
    reader.fd = sockets[1];
    pthread_t thread;
    pthread_create(&thread, NULL, slowReader, &reader);
    uint8_t text[POCKET_MAX_MESSAGE];
    memset(text, 'x', sizeof(text));
    int sent = 0;
    for (; sent < 40; sent++)
        if (pocket_send(sockets[0], POCKET_TEXT, text, sizeof(text), -1) != 0)
            break;
    CHECK(sent == 40, "all messages were sent (%d)", sent);
    CHECK(pocket_send(sockets[0], POCKET_TEXT, text, sizeof(text) + 1, -1) == -1 && errno == EMSGSIZE,
          "a message over the limit is refused");
    close(sockets[0]);
    pthread_join(thread, NULL);
    close(sockets[1]);
    CHECK(!reader.broken && reader.count == 40, "the host got %d of 40 messages", reader.count);
}

static size_t packTouch(uint8_t *out, uint32_t phase, uint32_t finger) {
    struct pocket_touch touch = {phase, finger, 1.0f, 2.0f, 0.5};
    return pocket_pack(out, POCKET_TOUCH, &touch, sizeof(touch));
}

static void testStaleTouchMoves(void) {
    uint8_t in[400];
    size_t length;
    // A move followed by another move of the same finger is stale, even with another finger's in between.
    length = packTouch(in, POCKET_TOUCH_MOVED, 1);
    length += packTouch(in + length, POCKET_TOUCH_MOVED, 2);
    length += packTouch(in + length, POCKET_TOUCH_MOVED, 1);
    CHECK(pocket_touch_move_is_stale(in, length), "a move superseded by a later move of the finger");
    // The later move itself, and a move of a finger that does not move again, are not.
    size_t second = sizeof(struct pocket_header) + sizeof(struct pocket_touch);
    CHECK(!pocket_touch_move_is_stale(in + second, length - second), "the move of finger 2 has no later one");
    CHECK(!pocket_touch_move_is_stale(in + 2 * second, length - 2 * second), "the last move is current");
    // An end or a begin in between keeps the order: nothing is skipped across it.
    length = packTouch(in, POCKET_TOUCH_MOVED, 1);
    length += packTouch(in + length, POCKET_TOUCH_ENDED, 1);
    length += packTouch(in + length, POCKET_TOUCH_MOVED, 1);
    CHECK(!pocket_touch_move_is_stale(in, length), "a move before an end is not stale");
    length = packTouch(in, POCKET_TOUCH_MOVED, 1);
    length += pocket_pack(in + length, POCKET_TEXT, "a", 1);
    length += packTouch(in + length, POCKET_TOUCH_MOVED, 1);
    CHECK(!pocket_touch_move_is_stale(in, length), "another kind of message in between keeps the move");
    // Only whole messages decide; a later move that has not arrived yet does not.
    length = packTouch(in, POCKET_TOUCH_MOVED, 1);
    length += packTouch(in + length, POCKET_TOUCH_MOVED, 1);
    CHECK(!pocket_touch_move_is_stale(in, length - 1), "a partial later message is not seen");
    CHECK(!pocket_touch_move_is_stale(in, 3), "a partial header is not a message");
}

int main(void) {
    testLayout();
    testPack();
    testStream();
    testBufferDescriptor();
    testFullSocket();
    testStaleTouchMoves();
    if (failures != 0) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    puts("ok");
    return 0;
}
