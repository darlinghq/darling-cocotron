/*
 This file is part of Darling.

 Copyright (C) 2026 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

// The messages between a remote CAContext (the client, which renders) and a
// CALayerHost (the host, which shows the client's frames). Private to
// QuartzCore; both ends are always the same QuartzCore build, but the version
// field lets either end refuse a peer it does not understand.
//
// - The client registers a receive right in its bootstrap namespace under
//   CARemoteContextServiceName(contextId).
// - The host looks that name up and sends CARemoteSubscribeMessage to it, with
//   a send right to its own receive port as the reply port.
// - The client sends CARemoteFrameMessage to every subscriber after each
//   frame, and once to a new subscriber if it already has a frame.
// - The host learns that the client has gone from a dead-name notification on
//   the send right it looked up; the client learns that a host has gone when
//   a send to it fails.

#ifndef CAREMOTECONTEXTPROTOCOL_H
#define CAREMOTECONTEXTPROTOCOL_H

#include <mach/mach.h>
#include <stdint.h>
#include <stdio.h>

#define CA_REMOTE_PROTOCOL_VERSION 1

enum {
    kCARemoteSubscribeMessageID = 0x43417331, // 'CAs1'
    kCARemoteFrameMessageID = 0x43416631,     // 'CAf1'
};

// The largest frame either end accepts, in pixels per side.
#define CA_REMOTE_MAX_FRAME_SIDE 16384

typedef struct {
    mach_msg_header_t header;
    uint32_t version;
} CARemoteSubscribeMessage;

// One surface per message, as a send right to its IOSurface Mach port, or
// MACH_PORT_NULL when the context has nothing to show (no layer, or a layer of
// zero size). The surface's top-left pixel is the top-left of the context's
// coordinate space, and its size is the frame's size in points.
typedef struct {
    mach_msg_header_t header;
    mach_msg_body_t body;
    mach_msg_port_descriptor_t surface;
    uint32_t version;
} CARemoteFrameMessage;

// Room for any message either end receives, with an audit trailer.
typedef union {
    mach_msg_header_t header;
    struct {
        CARemoteFrameMessage message;
        mach_msg_audit_trailer_t trailer;
    } frame;
    struct {
        CARemoteSubscribeMessage message;
        mach_msg_audit_trailer_t trailer;
    } subscribe;
    // Its SDK struct already ends in a (shorter) trailer; the padding below
    // leaves room for the audit trailer that replaces it.
    mach_dead_name_notification_t deadName;
    uint8_t padding[512];
} CARemoteReceiveBuffer;

#define CA_REMOTE_RECEIVE_OPTIONS                                             \
    (MACH_RCV_MSG | MACH_RCV_TIMEOUT |                                        \
     MACH_RCV_TRAILER_TYPE(MACH_MSG_TRAILER_FORMAT_0) |                       \
     MACH_RCV_TRAILER_ELEMENTS(MACH_RCV_TRAILER_AUDIT))

static inline void CARemoteContextServiceName(uint32_t contextId,
                                              char name[128])
{
    snprintf(name, 128, "org.darlinghq.QuartzCore.context.%08x", contextId);
}

#endif
