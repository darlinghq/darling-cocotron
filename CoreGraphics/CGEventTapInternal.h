/*
 This file is part of Darling.

 Copyright (C) 2020 Lubos Dolezel

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
#ifndef CGEVENTTAP_INTERNAL_H
#define CGEVENTTAP_INTERNAL_H
#include <CoreGraphics/CGEventTypes.h>
#include <CoreGraphics/CGRemoteOperation.h>
#include <mach/message.h>

#ifdef __cplusplus
extern "C" {
#endif

// The keyboard type that a source reports until it is given one, and the one that the events
// made with CGEventCreateKeyboardEvent() carry when their source has not been given one.
#define kCGEventDefaultKeyboardTypeOfSource 40
#define kCGEventCreatedKeyboardType 3

// State tables of event sources (CGEventSource.m). A table is named by an ID: 0 is the combined
// session state, 1 the HID system state, anything else (positive) is the private state of one
// source. Events posted with a source change the table of its state; the HID state also feeds
// the combined one.
#define kCGEventStateTableCombined 0
#define kCGEventStateTableHID 1
extern int32_t _CGEventStateNewPrivateTable(void);
extern void _CGEventStateReleasePrivateTable(int32_t tableId);
// Records an event the system is about to deliver in the table named by the event's state ID
// (and the combined one for the HID state).
extern void _CGEventStateRecordEvent(CGEventRef event);
extern bool _CGEventStateKeyDown(int32_t tableId, CGKeyCode key, bool* known);
extern bool _CGEventStateButtonDown(int32_t tableId, CGMouseButton button, bool* known);
extern bool _CGEventStateFlags(int32_t tableId, CGEventFlags* flags);
extern bool _CGEventStateLastEventTime(int32_t tableId, CGEventType type, uint64_t* time);
extern bool _CGEventStateCounter(int32_t tableId, CGEventType type, uint32_t* count);

// The device independent modifier flag that a modifier key code (54..63) sets while pressed, or 0.
extern uint32_t _CGEventModifierMaskOfKey(CGKeyCode key);

// Posting (CGEventTap.m). The event goes through the taps from `location` on, then to the event
// stream of the process (see CGEventStream.m). `pid` is the destination process, or 0 for every
// process; an event for another process is not delivered by this implementation. With `copy` the
// event is copied (it belongs to the caller), otherwise it is retained until it has been delivered.
extern void _CGEventPostToPipeline(CGEventRef event, CGEventTapLocation location, pid_t pid, bool copy);

// The event stream (CGEventStream.m), called by the end of the pipeline.
extern void _CGEventStreamEnqueue(CGEventRef event);

// What is sent to a tap's port: pointers within this process only.
struct TapMachMessage {
    mach_msg_header_t header;
    void* pass;
    uint32_t listenOnly;
    uint32_t seq;
};

#ifdef __cplusplus
}
#endif

#endif
