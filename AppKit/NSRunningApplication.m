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
#import <Foundation/NSDate.h>
#import <Foundation/NSBundle.h>
#include <errno.h>
#include <fcntl.h>
#include <mach-o/fat.h>
#include <mach-o/loader.h>
#include <mach/machine.h>
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

@interface NSApplication (NSRunningApplicationLaunchState)
- (BOOL) _isFinishedLaunching;
@end

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

    // An application bundle is recognised by its contents, not by its name: the executable lies in
    // Contents/MacOS next to an Info.plist that does not declare another package type. On macOS 26.7.3
    // an application whose bundle directory has no .app extension, started through its executable,
    // has the same main bundle, bundle URL and activation policy as the same bundle named .app.
    // Tests: the policy and noext cases of tests/appkit-global-menu/run-bar-tracking.py.
    NSArray<NSString *> *components = [[NSString stringWithUTF8String: path] pathComponents];
    NSInteger count = (NSInteger) [components count];
    if (count < 4 || ![[components objectAtIndex: count - 2] isEqualToString: @"MacOS"] ||
        ![[components objectAtIndex: count - 3] isEqualToString: @"Contents"])
        return nil;

    NSString *bundlePath = [NSString pathWithComponents:
            [components subarrayWithRange: NSMakeRange(0, count - 3)]];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
            [bundlePath stringByAppendingPathComponent: @"Contents/Info.plist"]];
    if (info == nil)
        return nil;
    NSString *type = [info objectForKey: @"CFBundlePackageType"];
    if (type != nil && ![type isEqual: @"APPL"])
        return nil;
    return [NSBundle bundleWithPath: bundlePath];
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
// prohibited). A program that is not in an application bundle is prohibited until it sets another
// policy: it cannot become the front application or own the menu bar, however it activates itself.
// Evidence: black-box observation on macOS 10.14.4 and 26.7.3 (tier 2): an AppKit executable outside
// a bundle, run from Terminal and started by a regular application, has policy 2, and neither
// activateIgnoringOtherApps: nor the other activation call made it active, the front application
// or the menu bar owner; the regular application that started it stayed all three.
// Test: tests/appkit-global-menu/run-bar-tracking.py (the parent case).
- (NSApplicationActivationPolicy) activationPolicy {
    NSBundle *bundle = [self _applicationBundle];

    if (bundle == nil)
        return NSApplicationActivationPolicyProhibited;
    if ([[bundle objectForInfoDictionaryKey: @"LSBackgroundOnly"] boolValue])
        return NSApplicationActivationPolicyProhibited;
    if ([[bundle objectForInfoDictionaryKey: @"LSUIElement"] boolValue])
        return NSApplicationActivationPolicyAccessory;
    return NSApplicationActivationPolicyRegular;
}

- (BOOL) _isOutsideApplicationBundle {
    return [self _applicationBundle] == nil;
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

- (NSURL *) executableURL {
    char path[PROC_PIDPATHINFO_MAXSIZE];

    if (proc_pidpath(_processIdentifier, path, sizeof(path)) <= 0)
        return nil;
    return [NSURL fileURLWithPath: [NSString stringWithUTF8String: path] isDirectory: NO];
}

// The architecture the process runs. For another process it is read from its executable: a thin
// one has a single CPU type, and of a universal one the 64-bit Intel slice is the one run by default.
static NSInteger executableArchitectureAtPath(const char *path) {
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        return 0;

    union {
        uint32_t magic;
        struct mach_header header;
        struct {
            struct fat_header header;
            struct fat_arch archs[16];
        } fat;
    } buffer;
    ssize_t length = read(fd, &buffer, sizeof(buffer));
    close(fd);
    if (length < (ssize_t) sizeof(uint32_t))
        return 0;

    if ((buffer.magic == MH_MAGIC || buffer.magic == MH_MAGIC_64) &&
        length >= (ssize_t) sizeof(struct mach_header))
        return buffer.header.cputype;

    if (buffer.magic == FAT_CIGAM && length >= (ssize_t) sizeof(struct fat_header)) {
        uint32_t count = OSSwapBigToHostInt32(buffer.fat.header.nfat_arch);
        NSInteger first = 0;
        for (uint32_t i = 0; i < count && i < 16 &&
                             (ssize_t) (sizeof(struct fat_header) + (i + 1) * sizeof(struct fat_arch)) <= length; i++) {
            cpu_type_t type = OSSwapBigToHostInt32(buffer.fat.archs[i].cputype);
            if (type == CPU_TYPE_X86_64)
                return type;
            if (first == 0)
                first = type;
        }
        return first;
    }
    return 0;
}

- (NSInteger) executableArchitecture {
    if ([self _isCurrent]) {
#if defined(__x86_64__)
        return NSBundleExecutableArchitectureX86_64;
#elif defined(__i386__)
        return NSBundleExecutableArchitectureI386;
#endif
    }

    char path[PROC_PIDPATHINFO_MAXSIZE];
    if (proc_pidpath(_processIdentifier, path, sizeof(path)) <= 0)
        return 0;
    return executableArchitectureAtPath(path);
}

- (NSDate *) launchDate {
    struct proc_bsdinfo info;

    if (proc_pidinfo(_processIdentifier, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) != sizeof(info))
        return nil;
    return [NSDate dateWithTimeIntervalSince1970:
                           (NSTimeInterval) info.pbi_start_tvsec + info.pbi_start_tvusec / 1e6];
}

// An application has finished launching once its -finishLaunching ran. Other processes are only known
// once they connected to the window system, which an application does while it launches.
- (BOOL) isFinishedLaunching {
    if ([self _isCurrent])
        return NSApp != nil && [NSApp _isFinishedLaunching];
    return ![self isTerminated];
}

// Unlike -terminate, which asks the application to quit, this ends the process at once.
- (BOOL) forceTerminate {
    if ([self isTerminated])
        return NO;
    return kill(_processIdentifier, SIGKILL) == 0;
}

// No application here opts into automatic termination, so there is nothing to end.
+ (void) terminateAutomaticallyTerminableApplications {
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

// The application that owns the menu bar (see -[NSWorkspace menuBarOwningApplication]).
- (BOOL) ownsMenuBar {
    pid_t owner = 0;
    return _CGSGetMenuBarOwnerProcess(&owner) == kCGErrorSuccess && owner == _processIdentifier;
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

    // Another process: the window system layer asks the window manager or the compositor to focus its windows, which may
    // refuse (see _CGSActivateProcess).
    if (_processIdentifier <= 0 || _processIdentifier == getpid())
        return NO;
    return _CGSActivateProcess(_processIdentifier, kCGSActivateProcessFrontWindowOnly) == kCGErrorSuccess;
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
