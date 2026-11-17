// Copyright (C) 2026 Lubos Dolezel
// NSWorkspace's mount notifications (NSWorkspaceDidMountNotification, NSWorkspaceWillUnmountNotification and
// NSWorkspaceDidUnmountNotification), made from DiskArbitration's disk callbacks.
#import <AppKit/NSWorkspace.h>
#include <CoreFoundation/CoreFoundation.h>

// Starts posting the notifications to the workspace's notification centre, on the main thread. Only the first call
// does anything; any thread may make it.
void NSWorkspaceVolumeEventsStart(NSWorkspace *workspace);

// Adds the session behind the notifications to the main run loop in another mode, or removes it again. A caller that
// waits on the main thread in a private mode for a DiskArbitration request uses it, so that its own process answers
// the request's approval (and posts WillUnmount) at once. Does nothing before NSWorkspaceVolumeEventsStart.
void NSWorkspaceVolumeEventsSchedule(CFStringRef mode, BOOL schedule);
