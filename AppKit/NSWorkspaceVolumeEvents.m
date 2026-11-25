// Copyright (C) 2026 Lubos Dolezel
// The mount notifications come from one DiskArbitration session on the main run loop:
// - DidMount when a disk appears with a volume, or its description gains a volume path;
// - WillUnmount when the session is asked to approve an unmount (it always approves);
// - DidUnmount when a description loses its volume path, or a disk with a volume disappears.
// The disks that are already there when the session starts are reported as appearing too; their appearance time,
// earlier than the start, tells them apart, so they give no DidMount (but do give DidUnmount later).
// Every notification has the workspace as its object and the volume's path, URL and name in its userInfo.
#import "NSWorkspaceVolumeEvents.h"
#import <Foundation/Foundation.h>
#include <DiskArbitration/DiskArbitration.h>
#include <dispatch/dispatch.h>

static DASessionRef session;
static NSWorkspace *eventsWorkspace;
static CFAbsoluteTime startTime;
// BSD name -> the userInfo of the volume it has mounted, for every disk with a volume
static NSMutableDictionary *mountedVolumes;

static NSDictionary *volumeInfo(DADiskRef disk)
{
    NSDictionary *description = [(NSDictionary *) DADiskCopyDescription(disk) autorelease];
    NSURL *url = description[(NSString *) kDADiskDescriptionVolumePathKey];
    if (url == nil)
        return nil;
    NSString *path = [url path];
    NSString *name = description[(NSString *) kDADiskDescriptionVolumeNameKey] ?: [path lastPathComponent];
    return @{
        @"NSDevicePath": path,
        NSWorkspaceVolumeURLKey: [NSURL fileURLWithPath: path isDirectory: YES],
        NSWorkspaceVolumeLocalizedNameKey: name,
    };
}

static NSString *diskKey(DADiskRef disk)
{
    const char *name = DADiskGetBSDName(disk);
    return name ? [NSString stringWithUTF8String: name] : nil;
}

static void post(NSNotificationName name, NSDictionary *info)
{
    [[eventsWorkspace notificationCenter] postNotificationName: name object: eventsWorkspace userInfo: info];
}

static void diskMounted(DADiskRef disk, NSDictionary *info, BOOL announce)
{
    NSString *key = diskKey(disk);
    if (key == nil || mountedVolumes[key] != nil)
        return;
    mountedVolumes[key] = info;
    if (announce)
        post(NSWorkspaceDidMountNotification, info);
}

static void diskUnmounted(DADiskRef disk)
{
    NSString *key = diskKey(disk);
    NSDictionary *info = key ? [[mountedVolumes[key] retain] autorelease] : nil;
    if (info == nil)
        return;
    [mountedVolumes removeObjectForKey: key];
    post(NSWorkspaceDidUnmountNotification, info);
}

static void diskAppeared(DADiskRef disk, void *context)
{
    @autoreleasepool {
        NSDictionary *info = volumeInfo(disk);
        if (info == nil)
            return;
        NSDictionary *description = [(NSDictionary *) DADiskCopyDescription(disk) autorelease];
        NSNumber *appeared = description[@"DAAppearanceTime"];
        diskMounted(disk, info, appeared != nil && [appeared doubleValue] >= startTime);
    }
}

static void diskDescriptionChanged(DADiskRef disk, CFArrayRef keys, void *context)
{
    @autoreleasepool {
        NSDictionary *info = volumeInfo(disk);
        if (info != nil)
            diskMounted(disk, info, YES);
        else
            diskUnmounted(disk);
    }
}

static void diskDisappeared(DADiskRef disk, void *context)
{
    @autoreleasepool {
        diskUnmounted(disk);
    }
}

static DADissenterRef unmountApproval(DADiskRef disk, void *context)
{
    @autoreleasepool {
        NSString *key = diskKey(disk);
        NSDictionary *info = (key ? mountedVolumes[key] : nil) ?: volumeInfo(disk);
        if (info != nil)
            post(NSWorkspaceWillUnmountNotification, info);
    }
    return NULL;
}

void NSWorkspaceVolumeEventsStart(NSWorkspace *workspace)
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        session = DASessionCreate(kCFAllocatorDefault);
        if (session == NULL)
            return;
        eventsWorkspace = [workspace retain];
        mountedVolumes = [[NSMutableDictionary alloc] init];
        startTime = CFAbsoluteTimeGetCurrent();

        CFArrayRef watched = CFArrayCreate(kCFAllocatorDefault, (const void **) &kDADiskDescriptionVolumePathKey, 1,
            &kCFTypeArrayCallBacks);
        DARegisterDiskAppearedCallback(session, NULL, diskAppeared, NULL);
        DARegisterDiskDescriptionChangedCallback(session, NULL, watched, diskDescriptionChanged, NULL);
        DARegisterDiskDisappearedCallback(session, NULL, diskDisappeared, NULL);
        DARegisterDiskUnmountApprovalCallback(session, NULL, unmountApproval, NULL);
        CFRelease(watched);
        DASessionScheduleWithRunLoop(session, CFRunLoopGetMain(), kCFRunLoopCommonModes);
    });
}

void NSWorkspaceVolumeEventsSchedule(CFStringRef mode, BOOL schedule)
{
    if (session == NULL)
        return;
    if (schedule)
        DASessionScheduleWithRunLoop(session, CFRunLoopGetMain(), mode);
    else
        DASessionUnscheduleFromRunLoop(session, CFRunLoopGetMain(), mode);
}
