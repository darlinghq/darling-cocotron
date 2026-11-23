// Copyright (C) 2026 Lubos Dolezel
// nsworkspace-mount-notifications <image> <mount point> [<da-ops>]: NSWorkspace's DidMount, WillUnmount and
// DidUnmount notifications. For each one it prints "<DidMount|WillUnmount|DidUnmount> <NSDevicePath> <localized
// name> url=<0|1> object=<0|1> main=<0|1>", url and object telling whether NSWorkspaceVolumeURLKey is the mount point
// and the object is the shared workspace. It first prints "same workspace on another thread=<0|1>" (whether
// sharedWorkspace is one object for the process), then goes through these steps, printing "step <n>" before each:
//  1. attaches the image with hdiutil and runs the main run loop for 3 s;
//  2. detaches it, 3 s;
// and, with da-ops (darling's tests/da-ops.c) given:
//  3. attaches it, then ejects it with unmountAndEjectDeviceAtURL:error: on the main thread and prints
//     "eject: <result> elapsed=<seconds> posted-before-return=<0|1>" (whether DidUnmount came before the call
//     returned), 3 s;
//  4. attaches it, runs "da-ops deny 15", ejects it ("dissented eject: <result>"), 3 s; stops da-ops and ejects it
//     again ("eject: <result>"), 3 s.
// Link with -framework AppKit. Also builds on macOS; the values macOS gives are in darling's tests/volumes.md.
#import <AppKit/AppKit.h>
#include <pthread.h>

static NSString *mountPoint;
static BOOL didUnmountSeen;

static void *sharedWorkspaceOnThread(void *result)
{
    @autoreleasepool
    {
        *(NSWorkspace **)result = [NSWorkspace sharedWorkspace];
    }
    return NULL;
}

static void runFor(NSTimeInterval seconds)
{
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

static int hdiutil(NSArray *arguments)
{
    NSTask *task = [NSTask launchedTaskWithLaunchPath:@"/usr/bin/hdiutil" arguments:arguments];
    [task waitUntilExit];
    return [task terminationStatus];
}

static void eject(NSString *label)
{
    NSError *error = nil;
    didUnmountSeen = NO;
    NSDate *start = [NSDate date];
    BOOL result = [[NSWorkspace sharedWorkspace] unmountAndEjectDeviceAtURL:[NSURL fileURLWithPath:mountPoint] error:&error];
    printf("%s: %d elapsed=%.1f posted-before-return=%d\n", [label UTF8String], result,
        -[start timeIntervalSinceNow], didUnmountSeen);
    fflush(stdout);
}

int main(int argc, char **argv)
{
    if (argc < 3)
    {
        fprintf(stderr, "usage: nsworkspace-mount-notifications <image> <mount point> [<da-ops>]\n");
        return 2;
    }
    @autoreleasepool
    {
        NSString *image = [NSString stringWithUTF8String:argv[1]];
        mountPoint = [NSString stringWithUTF8String:argv[2]];
        NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
        NSNotificationCenter *center = [workspace notificationCenter];
        pthread_t thread;
        NSWorkspace *other = nil;
        pthread_create(&thread, NULL, sharedWorkspaceOnThread, &other);
        pthread_join(thread, NULL);
        printf("same workspace on another thread=%d\n", other == workspace);

        for (NSString *name in @[ NSWorkspaceDidMountNotification, NSWorkspaceWillUnmountNotification,
                                  NSWorkspaceDidUnmountNotification ])
        {
            [center addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
                NSString *path = note.userInfo[@"NSDevicePath"];
                NSURL *url = note.userInfo[NSWorkspaceVolumeURLKey];
                NSString *shortName = [[note.name substringFromIndex:[@"NSWorkspace" length]]
                    stringByReplacingOccurrencesOfString:@"Notification" withString:@""];
                if ([note.name isEqual:NSWorkspaceDidUnmountNotification])
                    didUnmountSeen = YES;
                printf("%s %s %s url=%d object=%d main=%d\n", [shortName UTF8String], [path UTF8String],
                    [note.userInfo[NSWorkspaceVolumeLocalizedNameKey] UTF8String],
                    [[url path] isEqual:path] && [url hasDirectoryPath], note.object == workspace, [NSThread isMainThread]);
                fflush(stdout);
            }];
        }

        printf("step 1\n");
        fflush(stdout);
        hdiutil(@[ @"attach", @"-quiet", image ]);
        runFor(3);
        printf("step 2\n");
        fflush(stdout);
        hdiutil(@[ @"detach", @"-quiet", mountPoint ]);
        runFor(3);
        if (argc < 4)
            return 0;

        printf("step 3\n");
        fflush(stdout);
        hdiutil(@[ @"attach", @"-quiet", image ]);
        runFor(3);
        eject(@"eject");
        runFor(3);

        printf("step 4\n");
        fflush(stdout);
        hdiutil(@[ @"attach", @"-quiet", image ]);
        runFor(3);
        NSTask *deny = [[NSTask alloc] init];
        NSPipe *pipe = [NSPipe pipe];
        [deny setLaunchPath:[NSString stringWithUTF8String:argv[3]]];
        [deny setArguments:@[ @"deny", @"15" ]];
        [deny setStandardOutput:pipe];
        [deny launch];
        NSData *ready = [[pipe fileHandleForReading] availableData]; // "ready" once its approvals are registered
        (void)ready;
        eject(@"dissented eject");
        runFor(3);
        [deny terminate];
        [deny waitUntilExit];
        eject(@"eject");
        runFor(3);
    }
    return 0;
}
