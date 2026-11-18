#import <AppKit/NSRunningApplication.h>
#import <AppKit/NSApplication.h>
#import <AppKit/NSDisplay.h>
#import <CoreGraphics/CoreGraphicsPrivate.h>
#import <AppKit/NSImage.h>
#import <AppKit/NSWorkspace.h>
#import <Foundation/NSBundle.h>
#import <Foundation/NSURL.h>
#import <Foundation/NSProcessInfo.h>
#import <Foundation/NSString.h>
#include <errno.h>
#include <libproc.h>
#include <sys/proc_info.h>
#include <signal.h>
#include <stdlib.h>
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
    // Only processes that connected to the window system are applications; command line tools
    // and daemons are not.
    if (!processExists(pid) || !_CGSProcessHasConnection(pid))
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

// The bundle of the application: the innermost .app directory that the process' executable lives
// in (Name.app/Contents/MacOS/executable). Nil for a process that does not run from an application
// bundle or that has ended.
- (NSBundle *) _applicationBundle {
    char path[PROC_PIDPATHINFO_MAXSIZE];

    if (proc_pidpath(_processIdentifier, path, sizeof(path)) <= 0)
        return nil;

    NSArray<NSString *> *components = [[NSString stringWithUTF8String: path] pathComponents];
    for (NSInteger i = (NSInteger) [components count] - 3; i >= 1; i--) {
        if ([[components objectAtIndex: i] hasSuffix: @".app"] &&
            [[components objectAtIndex: i + 1] isEqualToString: @"Contents"] &&
            [[components objectAtIndex: i + 2] isEqualToString: @"MacOS"]) {
            NSString *bundlePath = [NSString pathWithComponents:
                    [components subarrayWithRange: NSMakeRange(0, i + 1)]];
            return [NSBundle bundleWithPath: bundlePath];
        }
    }
    return nil;
}

- (NSString *) bundleIdentifier {
    if ([self _isCurrent])
        return [[NSBundle mainBundle] bundleIdentifier];
    return [[self _applicationBundle] bundleIdentifier];
}

- (NSURL *) bundleURL {
    return [[self _applicationBundle] bundleURL];
}

- (NSImage *) icon {
    NSString *path = [[self _applicationBundle] bundlePath];

    return path != nil ? [[NSWorkspace sharedWorkspace] iconForFile: path] : nil;
}

// The policy comes from the bundle's declarations (LSUIElement: accessory, LSBackgroundOnly:
// prohibited); an application without a bundle is a regular one.
- (NSApplicationActivationPolicy) activationPolicy {
    NSBundle *bundle = [self _applicationBundle];

    if ([[bundle objectForInfoDictionaryKey: @"LSBackgroundOnly"] boolValue])
        return NSApplicationActivationPolicyProhibited;
    if ([[bundle objectForInfoDictionaryKey: @"LSUIElement"] boolValue])
        return NSApplicationActivationPolicyAccessory;
    return NSApplicationActivationPolicyRegular;
}

- (BOOL) isHidden {
    return _CGSProcessIsHidden(_processIdentifier);
}

// The requests go to the application as a command on the per-process channel (see
// _CGSSendProcessCommand): YES means it was made, not that it was carried out. A process that has
// ended or is not an application gets none.
- (BOOL) _sendCommand: (uint32_t) command {
    if ([self isTerminated])
        return NO;
    return _CGSSendProcessCommand(_processIdentifier, command) == kCGErrorSuccess;
}

- (BOOL) hide {
    return [self _sendCommand: kCGSProcessCommandHide];
}

- (BOOL) unhide {
    return [self _sendCommand: kCGSProcessCommandUnhide];
}

// A quit request, which the application answers like the Quit menu item (it may cancel); it is not
// a signal.
- (BOOL) terminate {
    return [self _sendCommand: kCGSProcessCommandQuit];
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

// The application that has the input focus is the one CoreGraphics reports as the front process. A
// window system that cannot say (no process known) leaves every application inactive.
- (BOOL) isActive {
    pid_t front = 0;
    return _CGSGetFrontProcess(&front) == kCGErrorSuccess && front == _processIdentifier;
}

// There is one menu bar per application, so the application that has the focus owns it.
- (BOOL) ownsMenuBar {
    return [self isActive];
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

// Activation requested on behalf of another application, which has yielded
// activation to this one. The display backends do not arbitrate activation
// between applications, so the request is honoured as an activation that
// overrides other applications; only a missing source application is
// refused.
- (BOOL) activateFromApplication: (NSRunningApplication *) application
                         options: (NSApplicationActivationOptions) options
{
    if (application == nil)
        return NO;
    return [self activateWithOptions:
                         options | NSApplicationActivateIgnoringOtherApps];
}

// The applications are the processes that connected to the window system (the registry), matched by
// the bundle identifier.
+ (NSArray<NSRunningApplication *> *) runningApplicationsWithBundleIdentifier: (NSString *) bundleIdentifier {
    NSMutableArray *result = [NSMutableArray array];

    if (bundleIdentifier == nil)
        return result;

    int count = proc_listallpids(NULL, 0);
    if (count <= 0)
        return result;
    pid_t *pids = calloc((size_t) count + 16, sizeof(pid_t));
    if (pids == NULL)
        return result;
    count = proc_listallpids(pids, (int) (((size_t) count + 16) * sizeof(pid_t)));
    for (int i = 0; i < count; i++) {
        NSRunningApplication *application = [self runningApplicationWithProcessIdentifier: pids[i]];

        if ([[application bundleIdentifier] isEqualToString: bundleIdentifier])
            [result addObject: application];
    }
    free(pids);
    return result;
}

// The applications running from the bundle at the URL, for the launch calls of NSWorkspace.
+ (NSArray<NSRunningApplication *> *) _runningApplicationsWithBundleURL: (NSURL *) bundleURL {
    NSMutableArray *result = [NSMutableArray array];
    NSString *path = [[bundleURL URLByStandardizingPath] path];
    int count = proc_listallpids(NULL, 0);

    if (path == nil || count <= 0)
        return result;
    pid_t *pids = calloc((size_t) count + 16, sizeof(pid_t));
    if (pids == NULL)
        return result;
    count = proc_listallpids(pids, (int) (((size_t) count + 16) * sizeof(pid_t)));
    for (int i = 0; i < count; i++) {
        NSRunningApplication *application = [self runningApplicationWithProcessIdentifier: pids[i]];

        if ([[[[application bundleURL] URLByStandardizingPath] path] isEqualToString: path])
            [result addObject: application];
    }
    free(pids);
    return result;
}

@end
