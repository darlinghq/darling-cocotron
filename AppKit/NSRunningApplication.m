#import <AppKit/NSRunningApplication.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSDisplay.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSProcessInfo.h>
#import <Foundation/NSString.h>
#include <errno.h>
#include <libproc.h>
#include <signal.h>
#include <sys/param.h>
#include <unistd.h>

// Implementation notes:
// _LSCopyApplicationInformationItem(-2, ...) is used to fetch properties, such
// as _kLSExecutablePathKey Applications (processes) are referred to by an
// opaque void* asn (application serial number). ASNs can be compared with
// _LSCompareASNs().
//
// lsd provides notifications when processes change. This is registered via:
// _LSScheduleNotificationFunction(-2, callback, eventMask, context,
// CFRunLoopRef, kCFRunLoopCommonModes) and _LSModifyNotification(). The
// properties are updated via KVO.
//
// Current application is also observed via LS - _LSGetCurrentApplicationASN().
// All apps: _LSCopyRunningApplicationArray() - returns an array of ASNs.
// Running apps: _LSCopyRunningApplicationArray() - ditto.

@implementation NSRunningApplication

static BOOL processExists(pid_t pid) {
    return pid > 0 && (kill(pid, 0) == 0 || errno == EPERM);
}

- (instancetype) _initWithProcessIdentifier: (pid_t) pid {
    self = [super init];
    if (self != nil)
        _processIdentifier = pid;
    return self;
}

+ (NSRunningApplication *) currentApplication {
    static NSRunningApplication *current;

    @synchronized(self) {
        if (current == nil || current->_processIdentifier != getpid()) {
            [current release];
            current = [[NSRunningApplication alloc]
                    _initWithProcessIdentifier: getpid()];
        }
        return current;
    }
}

+ (instancetype) runningApplicationWithProcessIdentifier: (pid_t) pid {
    if (pid == getpid())
        return [self currentApplication];
    if (!processExists(pid))
        return nil;
    return [[[self alloc] _initWithProcessIdentifier: pid] autorelease];
}

- (BOOL) isEqual: (id) other {
    return [other isKindOfClass: [NSRunningApplication class]] &&
           ((NSRunningApplication *) other)->_processIdentifier ==
                   _processIdentifier;
}

- (NSUInteger) hash {
    return (NSUInteger) _processIdentifier;
}

- (pid_t) processIdentifier {
    return _processIdentifier;
}

- (BOOL) _isCurrent {
    return _processIdentifier == getpid();
}

// Only the current process's bundle is known here.
- (NSString *) bundleIdentifier {
    return [self _isCurrent] ? [[NSBundle mainBundle] bundleIdentifier] : nil;
}

- (NSString *) localizedName {
    if ([self _isCurrent]) {
        NSBundle *bundle = [NSBundle mainBundle];
        NSString *name =
                [bundle objectForInfoDictionaryKey: @"CFBundleDisplayName"];
        if (name == nil)
            name = [bundle objectForInfoDictionaryKey: @"CFBundleName"];
        return name ? name : [[NSProcessInfo processInfo] processName];
    }

    char name[2 * MAXCOMLEN + 1];
    if (proc_name(_processIdentifier, name, sizeof(name)) <= 0)
        return nil;
    return [NSString stringWithUTF8String: name];
}

- (BOOL) isTerminated {
    return !processExists(_processIdentifier);
}

- (BOOL) activateWithOptions: (NSApplicationActivationOptions) options {
    if ([self isTerminated])
        return NO;

    if ([self _isCurrent]) {
        if (NSApp == nil)
            return NO;
        [NSApp activateIgnoringOtherApps:
                       (options & NSApplicationActivateIgnoringOtherApps) != 0];
        return YES;
    }

    return [[NSDisplay currentDisplay]
            activateProcessIdentifier: _processIdentifier];
}

+ (NSArray<NSRunningApplication *> *) runningApplicationsWithBundleIdentifier: (NSString *) bundleIdentifier {
    printf("STUB %s\n", __PRETTY_FUNCTION__);
    return [NSArray array];
}

@end
